// lib/services/sms_listener_service.dart

import 'package:flutter/foundation.dart'; // Required for debugPrint
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Required for SharedPreferences
import 'ai_service.dart';
import 'supabase_service.dart';

class SMSListenerService {
  final Telephony telephony = Telephony.instance;
  final AIService _aiService = AIService();
  final SupabaseService _supabaseService = SupabaseService();

  /// Starts listening for incoming SMS messages in both foreground and background
  void startListening() {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        final String? body = message.body;
        final String? sender = message.address;

        if (body != null && sender != null) {
          // 1. Privacy Check: Process only if the sender is an authorized bank
          if (await isBankAuthorized(sender)) {
            
            // 2. AI Analysis: Extracting data from the SMS body using Gemini
            final data = await _aiService.parseBankSMS(body);
            
            // Check if the AI extraction was successful and the transaction is final
            if (data != null && data['status'] == 'Final') {
              
              debugPrint("Automated Transaction Detected: ${data['amount']} from ${data['bank']}");
              
              // TODO: Implementation logic to map 'bank' name to a 'walletId' in Supabase
              // Example: await _handleAutomatedTransaction(data);
            } else if (data != null && data['status'] == 'Pending') {
              debugPrint("Hold transaction detected. Ignoring to avoid duplicate balance deduction.");
            }
          }
        }
      },
      listenInBackground: true, // Vital for background processing on Android
    );
  }

  /// Verifies if the SMS sender is in the user's authorized bank list
  Future<bool> isBankAuthorized(String senderAddress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Retrieve the list of banks the user has opted to monitor
      List<String> authorizedBanks = prefs.getStringList('authorized_banks') ?? [];
      
      // Returns true if the sender's address contains any of the authorized keywords
      return authorizedBanks.any((bank) => 
        senderAddress.toLowerCase().contains(bank.toLowerCase()));
    } catch (e) {
      debugPrint("Authorization Check Error: $e");
      return false;
    }
  }
}