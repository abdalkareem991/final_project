// lib/services/sms_listener_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';

import 'ai_service.dart';
import 'supabase_service.dart';

// ===========================================================================
// BACKGROUND ENTRY POINT
// ===========================================================================

/// This function handles SMS messages when the app is terminated or in the background.
/// It must remain at the top level and be annotated with @pragma('vm:entry-point').
/*@pragma('vm:entry-point')
void backGroundMessageHandler(SmsMessage message) async {
  final AIService aiService = AIService();
  final SupabaseService supabaseService = SupabaseService();

  if (message.body == null || message.address == null) return;

  final String sender = message.address!;
  debugPrint("🚨 Background SMS received from: $sender");

  try {
    // 1. Identify the linked automated wallet for this specific sender
    final String? walletId = await supabaseService.findWalletBySmsSender(
      sender,
    );

    if (walletId != null) {
      // 2. Analyze the SMS body using Gemini AI to extract transaction details[cite: 6]
      final data = await aiService.parseBankSMS(message.body!);

      if (data != null) {
        // 3. Log the transaction and update the cloud database balance
        await supabaseService.processAutomatedTransaction(data, sender);
        debugPrint("✅ Background: Automated transaction logged for $sender");
      }
    } else {
      debugPrint(
        "⚠️ Background: No automated wallet linked for sender '$sender'.",
      );
    }
  } catch (e) {
    debugPrint("❌ Background Process Error: $e");
  }
}
*/
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

    _smsSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
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

        if (messages.isEmpty) continue;

        final latest = messages.first;
        final body = latest.body?.trim();
        final date = latest.date?.toString() ?? '';

        if (body == null || body.isEmpty) continue;

        final smsHash = "$sender-$date-$body";

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

        final data = await _aiService.parseBankSMS(body);

        if (data == null) {
          debugPrint("AI could not parse SMS from $sender");
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
