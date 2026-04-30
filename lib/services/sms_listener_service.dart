// lib/services/sms_listener_service.dart

import 'package:flutter/foundation.dart';
import 'package:telephony/telephony.dart';

import 'ai_service.dart';
import 'supabase_service.dart';

// ===========================================================================
// BACKGROUND ENTRY POINT
// ===========================================================================

/// This function MUST be at the top level (outside any class).
/// It handles SMS messages when the app is terminated or in the background.
@pragma('vm:entry-point')
void backGroundMessageHandler(SmsMessage message) async {
  // Re-initialize services for the separate background isolate
  final AIService aiService = AIService();
  final SupabaseService supabaseService = SupabaseService();

  if (message.body == null || message.address == null) return;

  // Convert sender address to lowercase for flexible matching
  final String sender = message.address!.toLowerCase();

  debugPrint("🚨 Background SMS received from: $sender");

  // Check if the sender is an authorized bank (JIB or Arab Bank)
  if (sender.contains("jib") || sender.contains("arabbank")) {
    try {
      // 1. Analyze SMS body using Gemini AI
      final data = await aiService.parseBankSMS(message.body!);

      // 2. Log to database if AI successfully extracted the transaction data
      if (data != null) {
        await supabaseService.processAutomatedTransaction(data);
        debugPrint("✅ Background: Transaction logged for $sender");
      }
    } catch (e) {
      debugPrint("Background Process Error: $e");
    }
  }
}

// ===========================================================================
// SERVICE CLASS
// ===========================================================================

class SMSListenerService {
  final Telephony telephony = Telephony.instance;
  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();

  /// Initializes the SMS listener for both foreground and background states
  void startListening() {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        // Log the raw SMS data for debugging purposes
        debugPrint(
          "📩 Foreground SMS | From: ${message.address} | Body: ${message.body}",
        );

        if (message.body == null || message.address == null) return;

        final String sender = message.address!.toLowerCase();

        // Validate if the sender matches JIB or Arab Bank identifiers
        if (sender.contains("jib") || sender.contains("arabbank")) {
          debugPrint("🎯 Authorized Bank Match Detected: $sender");
          try {
            // Process the message through the AI service
            final data = await _aiService.parseBankSMS(message.body!);

            if (data != null) {
              // Execute the automated transaction logic in Supabase
              await _supabaseService.processAutomatedTransaction(data);
              debugPrint(
                "✅ Foreground: Transaction logged successfully for $sender",
              );
            }
          } catch (e) {
            debugPrint("Foreground AI Processing Error: $e");
          }
        } else {
          // Log a warning if the bank is not in the authorized list
          debugPrint("⚠️ SMS Filtered: Sender '$sender' is not authorized.");
        }
      },
      // Essential for background automation:
      listenInBackground: true,
      onBackgroundMessage: backGroundMessageHandler,
    );
  }

  /// Optional: Method to stop the SMS listener manually
  void stopListening() {
    debugPrint("SMS Listener Service Stopped.");
  }
}
