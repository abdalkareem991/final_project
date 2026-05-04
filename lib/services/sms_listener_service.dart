// lib/services/sms_listener_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';

import 'ai_service.dart';
import 'supabase_service.dart';

// ===========================================================================
// SERVICE CLASS
// ===========================================================================

class SMSListenerService {
  final Telephony telephony = Telephony.instance;
  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();
  Timer? _smsSyncTimer;
  final Set<String> _processedInMemory = {};
  static DateTime? lastSyncTime;
  static int lastProcessedCount = 0;
  static String lastSyncStatus = "Not started";

  /// Starts the SMS listener for both foreground and background states[cite: 8]
  Future<void> startListening() async {
    debugPrint("SMS Auto Sync STARTED");

    final bool? permission = await telephony.requestPhoneAndSmsPermissions;
    debugPrint("SMS permission: $permission");

    if (permission != true) {
      debugPrint("SMS sync stopped: permission denied");
      return;
    }

    _smsSyncTimer?.cancel();

    _smsSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _syncLatestBankSms();
    });

    await _syncLatestBankSms();
  }

  Future<void> _syncLatestBankSms() async {
    try {
      final wallets = await _supabaseService.getWallets();
      lastSyncStatus = "Syncing";
      int processedCount = 0;

      final automatedWallets = wallets.where((wallet) {
        return wallet.accountMode == 'AUTOMATED' &&
            wallet.isActiveMonitoring == true &&
            wallet.smsSenderId != null &&
            wallet.smsSenderId!.trim().isNotEmpty;
      }).toList();

      for (final wallet in automatedWallets) {
        final sender = wallet.smsSenderId!.trim();

        final messages = await telephony.getInboxSms(
          columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
          filter: SmsFilter.where(SmsColumn.ADDRESS).equals(sender),
          sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
        );

        if (messages.isEmpty) {
          debugPrint("No SMS messages found for sender: $sender");
          continue;
        }

        final recentMessages = messages.take(5).toList().reversed;

        for (final message in recentMessages) {
          final body = message.body
              ?.replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .toLowerCase();

          final date = message.date ?? 0;

          if (body == null || body.isEmpty) continue;

          final smsHash = "${sender}_${date}_${body.hashCode}";

          if (_processedInMemory.contains(smsHash)) {
            continue;
          }

          final alreadyProcessed = await _supabaseService.isSmsAlreadyProcessed(
            smsHash,
          );

          if (alreadyProcessed) {
            _processedInMemory.add(smsHash);
            continue;
          }

          debugPrint("New bank SMS detected from $sender");
          debugPrint("SMS body: $body");

          final Map<String, dynamic>? data = _aiService.parseBankSmsLocally(
            body,
            sender: sender,
          );

          debugPrint("Local parser result: $data");

          if (data == null) {
            debugPrint(
              "Local parser could not parse SMS from $sender. Skipping.",
            );
            _processedInMemory.add(smsHash);
            continue;
          }

          await _supabaseService.processAutomatedTransaction(
            data,
            sender,
            smsHash: smsHash,
          );

          _processedInMemory.add(smsHash);

          debugPrint("SMS synced into dashboard.");
          processedCount++;
        } // End of messages loop
      } // Update sync status

      lastSyncTime = DateTime.now();
      lastProcessedCount = processedCount;
      lastSyncStatus = "Active";
    } catch (e, stackTrace) {
      lastSyncStatus = "Error"; // Update sync status on error
      debugPrint("SMS auto sync error: $e"); // Log the error
      debugPrint(
        "StackTrace: $stackTrace",
      ); // Log the stack trace for debugging
    } // End of sync method
  } // End of class

  /// Stops the SMS listener service manually
  void stopListening() {
    // Cancel the periodic timer
    _smsSyncTimer?.cancel();
    _smsSyncTimer = null;
    debugPrint("SMS Auto Sync stopped.");
  }
}
