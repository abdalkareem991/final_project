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

        final latest = messages.first;

        final body = latest.body
            ?.replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toLowerCase();

        final date = latest.date ?? 0;

        if (body == null || body.isEmpty) continue;

        final smsHash = "${sender}_${date}_${body.hashCode}";

        _processedInMemory.add(
          smsHash,
        ); // Mark as processed in memory to avoid duplicates within the same session

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
      }
    } catch (e, stackTrace) {
      debugPrint("SMS auto sync error: $e");
      debugPrint("StackTrace: $stackTrace");
    }
  }

  /// Stops the SMS listener service manually
  void stopListening() {
    _smsSyncTimer?.cancel();
    _smsSyncTimer = null;
    debugPrint("SMS Auto Sync stopped.");
  }
}
