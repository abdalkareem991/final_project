// lib/services/ai_service.dart

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  // IMPORTANT: Ensure this API Key is active in Google AI Studio
  final String _apiKey = "AIzaSyB3o37ExwfLr8dcI-KeJzU007-3h1IkBOE";
  late GenerativeModel _model;

  AIService() {
    // FIXED: Using 'gemini-1.5-flash' without the 'models/' prefix
    // to match standard API implementation for generateContent
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
  }

  String detectTypeLocally(String smsBody) {
    final text = smsBody.toLowerCase();

    final incomeWords = [
      'credited',
      'deposit',
      'received',
      'transferred to',
      'to account',
      'ايداع',
      'إيداع',
      'وارد',
      'استلام',
    ];

    final expenseWords = [
      'debited',
      'withdrawn',
      'paid',
      'purchase',
      'transferred from',
      'from account',
      'خصم',
      'سحب',
      'شراء',
      'دفع',
    ];

    for (final word in expenseWords) {
      if (text.contains(word)) return 'Expense';
    }

    for (final word in incomeWords) {
      if (text.contains(word)) return 'Income';
    }

    return 'Unknown';
  }

  Map<String, dynamic>? parseBankSmsLocally(String smsBody, {String? sender}) {
    final text = smsBody.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    final amountRegex = RegExp(
      r'(?:jod|jd)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:jod|jd)?',
    );
    final matches = amountRegex.allMatches(text).toList();

    if (matches.isEmpty) return null;

    final type = detectTypeLocally(text);

    if (type == 'Unknown') return null;

    final amount = double.tryParse(matches.first.group(1) ?? '');

    if (amount == null || amount <= 0) return null;

    return {
      'amount': amount,
      'type': type,
      'bank': sender ?? 'Unknown Bank',
      'status': 'Final',
    };
  }

  double? extractBalanceLocally(String smsBody) {
    final String text = smsBody
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final balancePatterns = [
      RegExp(r'available balance\s*jod\s*(\d+(?:\.\d+)?)'),
      RegExp(r'available balance\s*(\d+(?:\.\d+)?)\s*jod'),
      RegExp(r'available balance\s*(\d+(?:\.\d+)?)'),
      RegExp(r'رصيدك المتاح\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'الرصيد المتاح\s*(\d+(?:\.\d+)?)\s*دينار'),
    ];

    for (final pattern in balancePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
    }

    return null;
  }

  /// Generates professional financial advice based on user context
  Future<String> getFinancialAdvice(
    String userMessage,
    String financialContext,
  ) async {
    try {
      final prompt = [
        Content.text("""
          You are 'FinMind AI', a professional financial assistant for Abdulkareem.
          Context: $financialContext
          Question: $userMessage
          Provide professional, concise, and actionable advice.
        """),
      ];

      final response = await _model.generateContent(prompt);
      return response.text ??
          "I'm having trouble analyzing your request right now.";
    } catch (e) {
      debugPrint("❌ FinMind AI Advice Error: $e");
      return "Connection error. Please check your internet or API key.";
    }
  }
}
