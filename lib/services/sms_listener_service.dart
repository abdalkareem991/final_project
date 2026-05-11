// lib/services/sms_listener_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';

import 'ai_service.dart';
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

  bool _isStarted = false;
  bool _isSyncing = false;
  DateTime? _lastNetworkErrorAt;

  static DateTime? lastSyncTime;
  static int lastProcessedCount = 0;
  static String lastSyncStatus = "Not started";

  static const Duration _syncInterval = Duration(minutes: 2);
  static const Duration _networkCooldown = Duration(minutes: 2);
  static const int _recentMessagesLimit = 10;

  Future<void> startListening() async {
    if (_isStarted && _smsSyncTimer != null) {
      return;
    }
    _isStarted = true;

    final bool? permission = await telephony.requestPhoneAndSmsPermissions;
    // debugPrint("SMS permission: $permission");

    if (permission != true) {
      _isStarted = false;
      lastSyncStatus = "Permission denied";
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

  String _stableSmsHash({
    required String sender,
    required int smsDate,
    required String body,
  }) {
    int hash = 0;

    for (int i = 0; i < body.length; i++) {
      hash = 0x1fffffff & (hash + body.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash = hash ^ (hash >> 6);
    }

    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash = hash ^ (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));

    return "${sender.trim().toLowerCase()}_${smsDate}_$hash";
  }

  List<String> _senderCandidates(String sender) {
    final trimmed = sender.trim();
    final noSpaces = trimmed.replaceAll(' ', '');

    return {
      trimmed,
      noSpaces,
      trimmed.toLowerCase(),
      noSpaces.toLowerCase(),
      trimmed.toUpperCase(),
      noSpaces.toUpperCase(),
    }.where((value) => value.isNotEmpty).toList();
  }

  Future<List<SmsMessage>> _getMessagesForSender(String sender) async {
    final Map<String, SmsMessage> uniqueMessages = {};

    for (final candidate in _senderCandidates(sender)) {
      try {
        final messages = await telephony.getInboxSms(
          columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
          filter: SmsFilter.where(SmsColumn.ADDRESS).equals(candidate),
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
        );

        for (final message in messages) {
          final key =
              "${message.address}_${message.date}_${message.body?.hashCode}";
          uniqueMessages[key] = message;
        }

        if (messages.isNotEmpty) {
          debugPrint("Messages found using sender candidate: $candidate");
        }
      } catch (e) {
        debugPrint("Sender candidate failed: $candidate => $e");
      }
    }

    final result = uniqueMessages.values.toList();

    result.sort((a, b) {
      final aDate = a.date ?? 0;
      final bDate = b.date ?? 0;
      return bDate.compareTo(aDate);
    });

    return result;
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
      // debugPrint("SMS SYNC TICK STARTED");

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

          final messages = await _getMessagesForSender(
            sender,
          ); // This method now handles multiple sender candidates and deduplicates messages

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

            final String smsHash = _stableSmsHash(
              sender: sender,
              smsDate: smsDate,
              body: normalizedBody,
            );

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

        debugPrint("SMS sync offline: $e");
      } else {
        lastSyncStatus = "Error";

        debugPrint("SMS auto sync error: $e");
      }
    } finally {
      _isSyncing = false;
    }
  }

  void stopListening() {
    // Call this method when the app is closing or when you want to stop the service
    _smsSyncTimer?.cancel();
    _smsSyncTimer = null;
    _isStarted = false;
    _isSyncing = false;
    lastSyncStatus = "Stopped";
    // debugPrint("SMS Auto Sync stopped.");
  }
}
