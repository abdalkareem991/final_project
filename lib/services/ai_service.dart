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

    if (RegExp(
      r'(otp|code|verification|password|authorization|رمز|كود|تحقق)',
    ).hasMatch(text)) {
      return null;
    }

    String type = 'Unknown';

    if (text.contains('transferred by cliq from account')) {
      type = 'Expense';
    } else if (text.contains('transferred by cliq to account')) {
      type = 'Income';
    } else if (RegExp(
      r'(credited|deposit|deposited|received|salary|refund|إيداع|ايداع|وارد|استلام|تم استقبال حوالة|تم شحن|تم ايداع|تم إيداع)',
    ).hasMatch(text)) {
      type = 'Income';
    } else if (RegExp(
      r'(debited|withdrawn|paid|payment|purchase|pos|visa|card|bill|biller|efawateercom|atm|atv|خصم|سحب|شراء|دفع|فاتورة|فواتير|إلى المحفظة)',
    ).hasMatch(text)) {
      type = 'Expense';
    }

    if (type == 'Unknown') return null;

    final double? amount = _extractTransactionAmount(text);
    if (amount == null || amount <= 0) return null;

    final double? availableBalance = extractBalanceLocally(text);
    final String smsKind = _detectSmsKind(text);
    final String? counterparty = _extractCliqCounterparty(text, type);
    final String? merchantName = counterparty ?? _extractMerchantName(text);

    return {
      'amount': amount,
      'type': type,
      'bank': sender ?? 'Unknown Bank',
      'status': 'Final',
      'available_balance': availableBalance,
      'counterparty': counterparty,
      'is_cliq': text.contains('cliq'),
      'sms_kind': smsKind,
      'merchant_name': merchantName,
    };
  }

  double? _extractTransactionAmount(String text) {
    if (text.contains('فلس')) {
      final filsRegex = RegExp(r'(?:بقيمة|مبلغ)\s*(\d+(?:\.\d+)?)\s*فلس');
      final match = filsRegex.firstMatch(text);
      if (match != null) {
        return (double.tryParse(match.group(1)!) ?? 0) / 1000;
      }
    }

    final patterns = [
      RegExp(r'jod\s*(\d+(?:\.\d+)?)\s*has been'),
      RegExp(r'(\d+(?:\.\d+)?)\s*jod\s*has been'),
      RegExp(
        r'jod\s*(\d+(?:\.\d+)?)\s*(?:credited|debited|withdrawn|transferred|payment|purchase|paid)',
      ),
      RegExp(
        r'(?:credited|debited|withdrawn|transferred|payment|purchase|paid).*?jod\s*(\d+(?:\.\d+)?)',
      ),
      RegExp(r'(?:بقيمة|مبلغ)\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'(\d+(?:\.\d+)?)\s*دينار'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final value = double.tryParse(match.group(1)!);
        if (value != null && value > 0) return value;
      }
    }

    return null;
  }

  String? _extractCliqCounterparty(String text, String type) {
    if (!text.contains('cliq')) return null;

    if (type == 'Income') {
      final match = RegExp(
        r'\sfrom\s+([a-z0-9]+)',
        caseSensitive: false,
      ).firstMatch(text);

      return match?.group(1);
    }

    if (type == 'Expense') {
      final match = RegExp(
        r'\sto\s+([a-z0-9\u0600-\u06FF\s\-_]+?)(?:\.| available|$)',
        caseSensitive: false,
      ).firstMatch(text);

      return match?.group(1)?.trim();
    }

    return null;
  }

  String? _extractMerchantName(String text) {
    final patterns = [
      RegExp(r'at\s+([a-z0-9\u0600-\u06FF\s\-_]+?)(?:\.|,| on | available|$)'),
      RegExp(r'لدى\s+([a-z0-9\u0600-\u06FF\s\-_]+?)(?:\.|،| بتاريخ| الرصيد|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final value = match.group(1)?.trim();
        if (value != null && value.length >= 2) return value;
      }
    }

    return null;
  }

  String _detectSmsKind(String text) {
    if (text.contains('cliq')) return 'CliQ Transfer';

    if (RegExp(r'(visa|card|pos|purchase)').hasMatch(text)) {
      return 'Card Payment';
    }

    if (RegExp(r'(bill|biller|efawateercom|فاتورة|فواتير)').hasMatch(text)) {
      return 'Bill Payment';
    }

    if (RegExp(r'(atm|withdrawn|سحب)').hasMatch(text)) {
      return 'ATM Withdrawal';
    }

    if (RegExp(
      r'(credited|deposit|deposited|إيداع|ايداع|تم ايداع|تم إيداع)',
    ).hasMatch(text)) {
      return 'Deposit';
    }

    return 'Bank Transaction';
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
    const int maxRetries = 2;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final prompt = [
          Content.text("""
You are FinMind AI, a financial assistant inside a personal finance app.

Use the user's real financial data below:
$financialContext

User question:
$userMessage

Rules:
- Use only the available financial data.
- Do not invent numbers.
- Mention if data is missing.
- Keep the answer practical, short, and clear.
- Give advice based on balances, income, expenses, wallets, and recent transactions.
"""),
        ];

        final response = await _model
            .generateContent(prompt)
            .timeout(const Duration(seconds: 25));

        return response.text ?? "I could not generate a response right now.";
      } catch (e) {
        debugPrint("FinMind AI attempt $attempt failed: $e");

        if (attempt == maxRetries) {
          return "AI connection is temporarily unstable. Please try again shortly.";
        }

        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }

    return "AI connection is temporarily unstable.";
  }
}
