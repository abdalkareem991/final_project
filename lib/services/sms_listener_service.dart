// lib/services/sms_listener_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';

import 'ai_service.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

class SMSListenerService {
  static final SMSListenerService _instance = SMSListenerService._internal();

  factory SMSListenerService() => _instance;

  SMSListenerService._internal();

  final Telephony telephony = Telephony.instance;
  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();

  Timer? _smsSyncTimer;

  final Set<String> _processedInMemory = {};
  final Set<String> _ignoredInMemory = {};

  bool _isSyncing = false;
  DateTime? _lastNetworkErrorAt;

  static DateTime? lastSyncTime;
  static int lastProcessedCount = 0;
  static String lastSyncStatus = "Not started";

  static const Duration _syncInterval = Duration(minutes: 2);
  static const Duration _networkCooldown = Duration(minutes: 2);
  static const int _recentMessagesLimit = 10;

  Future<void> startListening() async {
    debugPrint("SMS Auto Sync STARTED");

    final bool? permission = await telephony.requestPhoneAndSmsPermissions;
    debugPrint("SMS permission: $permission");

    if (permission != true) {
      lastSyncStatus = "Permission denied";

      await NotificationService().showSyncErrorNotification(
        "SMS permission is required to automate bank transactions.",
      );

      return;
    }

    _smsSyncTimer?.cancel();

    await syncNow();

    _smsSyncTimer = Timer.periodic(_syncInterval, (_) async {
      await syncNow();
    });
  }

  Future<void> syncNow() async {
    await _syncLatestBankSms();
  }

  Future<void> _syncLatestBankSms() async {
    if (_isSyncing) {
      debugPrint("SMS sync skipped: previous sync still running.");
      return;
    }

    if (_lastNetworkErrorAt != null) {
      final diff = DateTime.now().difference(_lastNetworkErrorAt!);
      if (diff < _networkCooldown) {
        lastSyncStatus = "Offline";
        return;
      }
    }

    _isSyncing = true;
    lastSyncStatus = "Syncing";

    int processedCount = 0;

    try {
      debugPrint("SMS SYNC TICK STARTED");

      final wallets = await _supabaseService.getWallets();

      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      }).toList();

      debugPrint("Automated wallets count: ${automatedWallets.length}");

      for (final wallet in automatedWallets) {
        final String sender = wallet.smsSenderId!.trim();

        try {
          debugPrint("Checking SMS sender: $sender");

          final messages = await telephony.getInboxSms(
            columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
            filter: SmsFilter.where(SmsColumn.ADDRESS).equals(sender),
            sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
          );

          debugPrint("Messages found for $sender: ${messages.length}");

          if (messages.isEmpty) continue;

          final recentMessages = messages
              .take(_recentMessagesLimit)
              .toList()
              .reversed;

          for (final message in recentMessages) {
            final String? normalizedBody = message.body
                ?.replaceAll(RegExp(r'\s+'), ' ')
                .trim()
                .toLowerCase();

            final int smsDate = message.date ?? 0;

            if (normalizedBody == null || normalizedBody.isEmpty) {
              continue;
            }

            final String smsHash =
                "${sender}_${smsDate}_${normalizedBody.hashCode}";

            if (_processedInMemory.contains(smsHash) ||
                _ignoredInMemory.contains(smsHash)) {
              continue;
            }

            final bool alreadyProcessed = await _supabaseService
                .isSmsAlreadyProcessed(smsHash);

            if (alreadyProcessed) {
              _processedInMemory.add(smsHash);
              continue;
            }

            final Map<String, dynamic>? parsedData = _aiService
                .parseBankSmsLocally(normalizedBody, sender: sender);

            debugPrint("Local parser result for $sender: $parsedData");

            if (parsedData == null) {
              _ignoredInMemory.add(smsHash);
              continue;
            }

            parsedData['sms_timestamp'] = smsDate;

            await _supabaseService.processAutomatedTransaction(
              parsedData,
              sender,
              smsHash: smsHash,
            );

            _processedInMemory.add(smsHash);
            processedCount++;

            debugPrint("SMS synced into dashboard.");
          }
        } catch (walletError) {
          debugPrint("SMS sync error for sender $sender: $walletError");
          continue;
        }
      }

      lastSyncTime = DateTime.now();
      lastProcessedCount = processedCount;
      lastSyncStatus = "Active";

      debugPrint("SMS SYNC FINISHED. Processed: $processedCount");
    } catch (e) {
      final errorText = e.toString();

      if (errorText.contains("Failed host lookup") ||
          errorText.contains("SocketException") ||
          errorText.contains("Connection timed out")) {
        _lastNetworkErrorAt = DateTime.now();
        lastSyncStatus = "Offline";

        await NotificationService().showSyncErrorNotification(
          "Could not sync bank SMS. Check your internet connection.",
        );
      } else {
        lastSyncStatus = "Error";

        await NotificationService().showSyncErrorNotification(
          "SMS automation failed. Please try again.",
        );
      }

      debugPrint("SMS auto sync error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  void stopListening() {
    _smsSyncTimer?.cancel();
    _smsSyncTimer = null;
    _isSyncing = false;
    lastSyncStatus = "Stopped";
    debugPrint("SMS Auto Sync stopped.");
  }
}
