// lib/services/ai_service.dart

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  // Stores the Gemini API key used for the AI assistant only.
  // Keep your real key here or move it later to a secure environment/config file.
  final String _apiKey = "AIzaSyB3o37ExwfLr8dcI-KeJzU007-3h1IkBOE";

  late final GenerativeModel _model;

  // Initializes the Gemini model once when the service is created.
  AIService() {
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
  }

  // Parses a bank SMS locally without calling Gemini.
  // This is used for SMS automation to avoid API quota and improve reliability.
  Map<String, dynamic>? parseBankSmsLocally(String smsBody, {String? sender}) {
    final String text = _normalizeSms(smsBody);
    final String senderText = _normalizeSender(sender);

    if (_isIgnorableSms(text)) {
      debugPrint("SMS ignored: OTP/security/service message.");
      return null;
    }

    final String? type = _detectTransactionType(text, senderText);
    if (type == null) {
      debugPrint("SMS ignored: transaction type not detected.");
      return null;
    }

    final double? amount = _extractTransactionAmount(text);
    if (amount == null || amount <= 0) {
      debugPrint("SMS ignored: amount not detected.");
      return null;
    }
    // Extracts available balance, counterparty, and merchant name if possible.
    final double? availableBalance = extractBalanceLocally(text);
    final String smsKind = _detectSmsKind(text, senderText);
    final String? counterparty = _extractCounterparty(text, type, senderText);
    final String? merchantName = counterparty ?? _extractMerchantName(text);
    // The returned map can be used directly for creating transactions or further processing.
    return {
      'amount': amount,
      'type': type,
      'bank': sender ?? 'Unknown Bank',
      'status': 'Final',
      'available_balance': availableBalance,
      'counterparty': counterparty,
      'is_cliq': text.contains('cliq') || text.contains('كليك'),
      'sms_kind': smsKind,
      'merchant_name': merchantName,
    };
  }

  // Detects a simple transaction type from a raw SMS.
  // This is kept as a lightweight helper for older code compatibility.
  String detectTypeLocally(String smsBody) {
    final String text = _normalizeSms(smsBody);
    final String? type = _detectTransactionType(text, '');
    return type ?? 'Unknown';
  }

  // Normalizes SMS text to make Arabic and English matching more reliable.
  String _normalizeSms(String smsBody) {
    return smsBody
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('إ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ً', '')
        .replaceAll('ٌ', '')
        .replaceAll('ٍ', '')
        .replaceAll('َ', '')
        .replaceAll('ُ', '')
        .replaceAll('ِ', '')
        .replaceAll('ّ', '')
        .replaceAll('ْ', '')
        .trim();
  }

  // Normalizes the SMS sender name for easier bank detection.
  String _normalizeSender(String? sender) {
    return (sender ?? '').toLowerCase().trim();
  }

  // Checks whether the SMS should be ignored, such as OTP, scam, or service messages.
  bool _isIgnorableSms(String text) {
    return RegExp(
      r'(otp|one time password|verification|verify|authorization|auth code|please enter the following code|please do not share|do not share|beware|scam|system updates|digital banking services will be suspended|رمز التحقق|رمز|كود|تحقق|توثيق|تفعيل|يرجى عدم مشاركته|عدم مشاركته)',
    ).hasMatch(text);
  }

  // Detects whether the SMS is Income or Expense based on bank-specific rules first,
  // then falls back to general financial keywords.
  String? _detectTransactionType(String text, String sender) {
    if (_isReflectMessage(text, sender)) {
      return _detectReflectType(text);
    }

    if (_isOrangeMoneyMessage(text, sender)) {
      return _detectOrangeMoneyType(text);
    }

    final String? housingType = _detectHousingBankType(text);
    if (housingType != null) {
      return housingType;
    }

    return _detectGeneralType(text);
  }

  // Checks if the SMS belongs to Reflect.
  bool _isReflectMessage(String text, String sender) {
    return sender.contains('reflect') ||
        text.contains('reflect') ||
        text.contains('ريفلكت');
  }

  // Checks if the SMS belongs to Orange Money.
  bool _isOrangeMoneyMessage(String text, String sender) {
    return sender.contains('orange') ||
        text.contains('orange money') ||
        text.contains('orange');
  }

  // Detects Reflect transaction type.
  String? _detectReflectType(String text) {
    if (text.contains('من حسابك على ريفلكت') ||
        text.contains('من حسابك علي ريفلكت')) {
      return 'Expense';
    }

    if (text.contains('reversal') || text.contains('reversed')) {
      return 'Income';
    }

    if (RegExp(
      r'jod\s*\d+(?:\.\d+)?\s*has been credited to your reflect account',
    ).hasMatch(text)) {
      return 'Income';
    }

    if (RegExp(r'(credited|received)').hasMatch(text)) {
      return 'Income';
    }

    if (RegExp(
      r'(cliq payment from your reflect account|debited|paid|خصم|دفع)',
    ).hasMatch(text)) {
      return 'Expense';
    }

    return null;
  }

  // Detects Orange Money transaction type.
  String? _detectOrangeMoneyType(String text) {
    if (text.contains('تم استقبال حواله ماليه') ||
        text.contains('الى محفظتك')) {
      return 'Income';
    }

    if (text.contains('تمت عمليه التحويل المالي الى المحفظه') ||
        text.contains('الى المحفظه')) {
      return 'Expense';
    }

    return null;
  }

  // Detects HousingBank, CliQ, ATM, bill, and fee transaction types.
  String? _detectHousingBankType(String text) {
    if (text.contains('transferred by cliq to account')) {
      return 'Income';
    }

    if (text.contains('transferred by cliq from account')) {
      return 'Expense';
    }

    if (text.contains('has been deposited to account')) {
      return 'Income';
    }

    if (text.contains('has been withdrawn from account')) {
      return 'Expense';
    }

    if (text.contains('has been debited as')) {
      return 'Expense';
    }

    if (text.contains('تم دفع فاتوره') || text.contains('تم دفع فاتورة')) {
      return 'Expense';
    }

    return null;
  }

  // Detects transaction type using general fallback keywords.
  String? _detectGeneralType(String text) {
    if (RegExp(
      r'(credited|credit|deposit|deposited|received|salary|refund|cashback|ايداع|تم ايداع|وارد|استلام|تم استقبال حواله|تم استقبال حوالة)',
    ).hasMatch(text)) {
      return 'Income';
    }

    if (RegExp(
      r'(debited|debit|withdrawn|withdrawal|paid|payment|purchase|pos|visa|card|bill|biller|efawateercom|atm|fee|fees|خصم|سحب|شراء|دفع|فاتوره|فاتورة|فواتير|عموله|عمولة|رسوم)',
    ).hasMatch(text)) {
      return 'Expense';
    }

    return null;
  }

  // Extracts the transaction amount from Reflect, Orange Money, HousingBank,
  // ATM, bill payment, reversal, and fee messages.
  double? _extractTransactionAmount(String text) {
    final double? filsAmount = _extractFilsAmount(text);
    if (filsAmount != null) return filsAmount;

    final patterns = [
      RegExp(r'jod\s*(\d+(?:\.\d+)?)\s*has been'),
      RegExp(r'(\d+(?:\.\d+)?)\s*jod\s*has been'),
      RegExp(r'بمبلغ\s*(\d+(?:\.\d+)?)\s*jod'),
      RegExp(r'بمبلغ\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'بقيمة\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'بقيمه\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'amount\s*(\d+(?:\.\d+)?)\s*jod'),
      RegExp(
        r'jod\s*(\d+(?:\.\d+)?)\s*(?:credited|debited|withdrawn|transferred|payment|purchase|paid|deposit|deposited)',
      ),
      RegExp(
        r'(?:credited|debited|withdrawn|transferred|payment|purchase|paid|deposit|deposited).*?jod\s*(\d+(?:\.\d+)?)',
      ),
      RegExp(r'(\d+(?:\.\d+)?)\s*jod'),
      RegExp(r'jod\s*(\d+(?:\.\d+)?)'),
    ];

    return _firstDoubleMatch(text, patterns);
  }

  // Extracts fils values and converts them to JOD.
  double? _extractFilsAmount(String text) {
    if (!text.contains('فلس')) return null;

    final patterns = [
      RegExp(r'(?:بقيمة|بقيمه|مبلغ|بمبلغ)\s*(\d+(?:\.\d+)?)\s*فلس'),
      RegExp(r'(\d+(?:\.\d+)?)\s*فلس'),
    ];

    final double? value = _firstDoubleMatch(text, patterns);
    if (value == null || value <= 0) return null;

    return value / 1000;
  }

  // Extracts the remaining balance from the SMS if available.
  double? extractBalanceLocally(String smsBody) {
    final String text = _normalizeSms(smsBody);

    final balancePatterns = [
      RegExp(r'available balance\s*(\d+(?:\.\d+)?)\s*jod'),
      RegExp(r'available balance\s*jod\s*(\d+(?:\.\d+)?)'),
      RegExp(r'الرصيد المتوفر\s*(\d+(?:\.\d+)?)\s*jod'),
      RegExp(r'رصيد المحفظه المتاح هو\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'رصيد المحفظة المتاح هو\s*(\d+(?:\.\d+)?)\s*دينار'),
      RegExp(r'الرصيد\s*(?:الحالي|المتاح|المتوفر)?\s*(\d+(?:\.\d+)?)'),
    ];

    return _firstDoubleMatch(text, balancePatterns);
  }

  // Detects the SMS category/kind used later for automatic categorization.
  String _detectSmsKind(String text, String sender) {
    if (_isReflectMessage(text, sender)) {
      return _detectReflectSmsKind(text);
    }

    if (_isOrangeMoneyMessage(text, sender)) {
      return _detectOrangeMoneySmsKind(text);
    }

    return _detectGeneralSmsKind(text);
  }

  // Detects Reflect-specific SMS kind.
  String _detectReflectSmsKind(String text) {
    if (text.contains('reversal') || text.contains('reversed')) {
      return 'Reflect Reversal';
    }

    if (text.contains('من حسابك على ريفلكت') ||
        text.contains('من حسابك علي ريفلكت') ||
        text.contains('cliq payment from your reflect account')) {
      return 'Reflect CliQ Payment';
    }

    if (text.contains('credited to your reflect account')) {
      return 'Reflect Credit';
    }

    return 'Reflect Transaction';
  }

  // Detects Orange Money-specific SMS kind.
  String _detectOrangeMoneySmsKind(String text) {
    if (text.contains('تم استقبال حواله ماليه')) {
      return 'Orange Money Transfer In';
    }

    if (text.contains('تمت عمليه التحويل المالي الى المحفظه') ||
        text.contains('الى المحفظه')) {
      return 'Orange Money Transfer Out';
    }

    return 'Orange Money Transaction';
  }

  // Detects general SMS kind for HousingBank, CliQ, ATM, bills, fees, and cards.
  String _detectGeneralSmsKind(String text) {
    if (text.contains('transferred by cliq')) {
      return 'CliQ Transfer';
    }

    if (text.contains('has been deposited to account') &&
        text.contains('atm')) {
      return 'ATM Deposit';
    }

    if (text.contains('has been withdrawn from account') &&
        text.contains('atm')) {
      return 'ATM Withdrawal';
    }

    if (text.contains('تم دفع فاتوره') || text.contains('تم دفع فاتورة')) {
      return 'Bill Payment';
    }

    if (text.contains('debited as') ||
        text.contains('fee') ||
        text.contains('fees') ||
        text.contains('عموله') ||
        text.contains('عمولة') ||
        text.contains('رسوم')) {
      return 'Bank Fee';
    }

    if (text.contains('purchase') ||
        text.contains('pos') ||
        text.contains('card')) {
      return 'Card Payment';
    }

    return 'Bank Transaction';
  }

  // Extracts the other party involved in the transaction, such as CliQ alias,
  // IBAN, phone number, Orange wallet number, or Reflect account marker.
  String? _extractCounterparty(String text, String type, String sender) {
    final String? housingCounterparty = _extractHousingBankCounterparty(
      text,
      type,
    );
    if (housingCounterparty != null) return housingCounterparty;

    final String? orangeCounterparty = _extractOrangeMoneyCounterparty(
      text,
      type,
      sender,
    );
    if (orangeCounterparty != null) return orangeCounterparty;

    final String? reflectCounterparty = _extractReflectCounterparty(
      text,
      sender,
    );
    if (reflectCounterparty != null) return reflectCounterparty;

    return null;
  }

  // Extracts CliQ sender or receiver for HousingBank messages.
  String? _extractHousingBankCounterparty(String text, String type) {
    if (text.contains('transferred by cliq to account') && type == 'Income') {
      final match = RegExp(
        r'\sfrom\s+([a-z0-9]+)(?:\.| available|$)',
        caseSensitive: false,
      ).firstMatch(text);

      return match?.group(1)?.trim();
    }

    if (text.contains('transferred by cliq from account') &&
        type == 'Expense') {
      final match = RegExp(
        r'\sto\s+([a-z0-9]+)(?:\.| available|$)',
        caseSensitive: false,
      ).firstMatch(text);

      return match?.group(1)?.trim();
    }

    return null;
  }

  // Extracts sender or destination wallet for Orange Money messages.
  String? _extractOrangeMoneyCounterparty(
    String text,
    String type,
    String sender,
  ) {
    if (!_isOrangeMoneyMessage(text, sender)) return null;

    if (type == 'Income') {
      final patterns = [
        RegExp(r'تم استقبال حواله ماليه من\s+([a-z0-9]+)'),
        RegExp(r'تم استقبال حوالة مالية من\s+([a-z0-9]+)'),
      ];

      return _firstStringMatch(text, patterns);
    }

    if (type == 'Expense') {
      final patterns = [
        RegExp(r'الى المحفظه\s+([a-z0-9]+)'),
        RegExp(r'الى المحفظة\s+([a-z0-9]+)'),
      ];

      return _firstStringMatch(text, patterns);
    }

    return null;
  }

  // Extracts Reflect-specific counterparty marker.
  String? _extractReflectCounterparty(String text, String sender) {
    if (!_isReflectMessage(text, sender)) return null;

    if (text.contains('من حسابك على ريفلكت') ||
        text.contains('من حسابك علي ريفلكت')) {
      return 'Reflect Account';
    }

    return null;
  }

  // Extracts merchant/source names such as ATM location, biller name, or card merchant.
  String? _extractMerchantName(String text) {
    final patterns = [
      RegExp(
        r'from\s+(atm\s+[a-z0-9\u0600-\u06FF\s\-_]+?)\s+with authorization',
        caseSensitive: false,
      ),
      RegExp(
        r'from\s+([a-z0-9\u0600-\u06FF\s\-_]+?)\s+amount',
        caseSensitive: false,
      ),
      RegExp(
        r'تم دفع فاتوره\s+([a-z0-9\u0600-\u06FF\s\-_]+?)\s+رقم',
        caseSensitive: false,
      ),
      RegExp(
        r'تم دفع فاتورة\s+([a-z0-9\u0600-\u06FF\s\-_]+?)\s+رقم',
        caseSensitive: false,
      ),
      RegExp(
        r'at\s+([a-z0-9\u0600-\u06FF\s\-_]+?)(?:\.|,| on | available|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'لدى\s+([a-z0-9\u0600-\u06FF\s\-_]+?)(?:\.|،| بتاريخ| الرصيد|$)',
        caseSensitive: false,
      ),
    ];

    final String? value = _firstStringMatch(text, patterns);
    if (value == null) return null;

    if (_isBadMerchantValue(value)) return null;

    return value;
  }

  // Prevents invalid merchant values from being saved.
  bool _isBadMerchantValue(String value) {
    final String normalizedValue = value.toLowerCase();

    return normalizedValue.contains('account') ||
        normalizedValue.contains('balance') ||
        normalizedValue.contains('authorization') ||
        normalizedValue.contains('available') ||
        normalizedValue.length < 2;
  }

  // Returns the first valid double captured by the provided patterns.
  double? _firstDoubleMatch(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final value = double.tryParse(match.group(1)!);
      if (value != null && value > 0) return value;
    }

    return null;
  }

  // Returns the first non-empty string captured by the provided patterns.
  String? _firstStringMatch(String text, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final value = match.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }

    return null;
  }

  // Generates professional financial advice using Gemini and real app context.
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
