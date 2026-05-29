// lib/services/ai_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIService {
  SupabaseClient get _client => Supabase.instance.client;

  static const String _numberPattern = r'[0-9][0-9,]*(?:\.[0-9]+)?';

  // Parses a bank SMS locally without calling Gemini.
  // This is used for SMS automation to avoid API quota and improve reliability.
  Map<String, dynamic>? parseBankSmsLocally(String smsBody, {String? sender}) {
    final String text = _normalizeSms(smsBody);
    final String senderText = _normalizeSender(sender);

    if (text.isEmpty || _isIgnorableSms(text)) {
      debugPrint("SMS ignored: OTP/security/service message.");
      return null;
    }

    final _ParsedSms? parsed =
        _matchProviderSpecific(text, senderText) ??
        _matchGeneric(text) ??
        _matchFallback(text);

    if (parsed == null || parsed.amount <= 0) {
      debugPrint("SMS ignored: transaction pattern not detected.");
      return null;
    }

    return {
      'amount': parsed.amount,
      'type': parsed.type,
      'bank': sender ?? 'Unknown Bank',
      'status': 'Final',
      'available_balance': parsed.balanceAfter,
      'balance_after': parsed.balanceAfter,
      'counterparty': parsed.counterparty,
      'is_cliq': parsed.isCliq,
      'sms_kind': parsed.smsKind,
      'merchant_name': parsed.merchantName,
      'category_hint': parsed.categoryHint,
    };
  }

  // Detects a simple transaction type from a raw SMS.
  // This is kept as a lightweight helper for older code compatibility.
  String detectTypeLocally(String smsBody) {
    final parsed = parseBankSmsLocally(smsBody);
    return parsed?['type']?.toString() ?? 'Unknown';
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

  String _normalizeSender(String? sender) {
    return (sender ?? '').toLowerCase().trim();
  }

  RegExp _amountRx(String pattern, {bool caseSensitive = false}) {
    return RegExp(
      pattern.replaceAll('{{amount}}', _numberPattern),
      caseSensitive: caseSensitive,
    );
  }

  bool _isIgnorableSms(String text) {
    final ignorePatterns = [
      RegExp(
        r'(?:\botp\b|one time password|verification|verify|auth code|authorization code|please enter the following code|please do not share|do not share|do not share this otp)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:رمز\s+التحقق|رمز\s+التاكيد\s+otp|رمز\s+التأكيد\s+otp|يرجى\s+عدم\s+مشاركته|لا\s+تشارك\s+هذا\s+الرمز|الرقم\s+السري\s+لعمليه?\s+التحويل|سوف\s+يتم\s+استخدام\s+هذا\s+الرمز|رمز\s+التحقق\s+لاستكمال\s+شراء\s+القسيمه)',
      ),
      RegExp(
        r'(?:beware\s+of\s+sms|scam\s+messages|avoid\s+opening\s+any\s+links|sharing\s+your\s+banking\s+information)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:digital\s+banking\s+services\s+will\s+be\s+suspended|system\s+updates)',
        caseSensitive: false,
      ),
      RegExp(
        r'transaction\s+on\s+debit\s+card.*?has\s+been\s+declined',
        caseSensitive: false,
      ),
    ];

    return ignorePatterns.any((pattern) => pattern.hasMatch(text));
  }

  _ParsedSms? _matchProviderSpecific(String text, String sender) {
    if (_isReflectMessage(text, sender)) {
      final parsed = _matchReflect(text);
      if (parsed != null) return parsed;
    }

    if (_isOrangeMoneyMessage(text, sender)) {
      final parsed = _matchOrangeMoney(text);
      if (parsed != null) return parsed;
    }

    return _matchHousingBank(text);
  }

  bool _isReflectMessage(String text, String sender) {
    return sender.contains('reflect') ||
        text.contains('reflect') ||
        text.contains('ريفلكت');
  }

  bool _isOrangeMoneyMessage(String text, String sender) {
    return sender.contains('orange') ||
        text.contains('orange money') ||
        text.contains('orange');
  }

  _ParsedSms? _matchReflect(String text) {
    final reflectedCredit = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+credited\s+to\s+your\s+reflect\s+account\b',
        caseSensitive: false,
      ),
    );
    if (reflectedCredit != null) {
      return _ParsedSms(
        amount: reflectedCredit.amount,
        type: 'Income',
        balanceAfter: reflectedCredit.balance ?? extractBalanceLocally(text),
        smsKind: 'Bank Credit',
        categoryHint: 'Bank Credit',
        merchantName: 'reflect',
      );
    }

    final purchaseReversal = _match(
      text,
      _amountRx(
        r'purchase\s+transaction\s+has\s+been\s+reversed\s+to\s+your\s+reflect\s+card\s+from\s+(?<merchant>.+?)\s+amount\s+(?<amount>{{amount}})\s*jod',
        caseSensitive: false,
      ),
    );
    if (purchaseReversal != null) {
      return _ParsedSms(
        amount: purchaseReversal.amount,
        type: 'Income',
        balanceAfter: purchaseReversal.balance ?? extractBalanceLocally(text),
        smsKind: 'Refund/Reversal',
        categoryHint: 'Refund',
        merchantName: _cleanParty(purchaseReversal.merchant),
      );
    }

    final cliqReversal = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+cliq\s+payment\s+from\s+your\s+reflect\s+account\b.*?as\s+a\s+reversal',
        caseSensitive: false,
      ),
    );
    if (cliqReversal != null) {
      return _ParsedSms(
        amount: cliqReversal.amount,
        type: 'Income',
        balanceAfter: cliqReversal.balance ?? extractBalanceLocally(text),
        smsKind: 'Refund/Reversal',
        categoryHint: 'Refund',
        merchantName: 'reflect',
        counterparty: 'reflect account',
        isCliq: true,
      );
    }

    final outgoing = _match(
      text,
      _amountRx(
        r'تم\s+قيد\s+حواله?\s+بمبلغ\s+(?<amount>{{amount}})\s*jod\s+من\s+حسابك\s+عل[ىي]\s+ريفلكت',
      ),
    );
    if (outgoing != null) {
      return _ParsedSms(
        amount: outgoing.amount,
        type: 'Expense',
        balanceAfter: outgoing.balance ?? extractBalanceLocally(text),
        smsKind: 'CliQ Transfer',
        categoryHint: 'CliQ Transfer Out',
        counterparty: 'Reflect Account',
        isCliq: true,
      );
    }

    return null;
  }

  _ParsedSms? _matchOrangeMoney(String text) {
    final incoming = _match(
      text,
      _amountRx(
        r'تم\s+استقبال\s+حواله?\s+ماليه?\s+من\s+(?<counterparty>\S+).*?(?:الى|الي)\s+محفظتك\s+بمبلغ\s+(?<amount>{{amount}})\s*دينار',
      ),
    );
    if (incoming != null) {
      return _ParsedSms(
        amount: incoming.amount,
        type: 'Income',
        balanceAfter: incoming.balance ?? extractBalanceLocally(text),
        smsKind: 'Mobile Wallet Transfer',
        categoryHint: 'Wallet Transfer In',
        counterparty: _cleanParty(incoming.counterparty),
      );
    }

    final outgoing = _match(
      text,
      _amountRx(
        r'تمت\s+عمليه?\s+التحويل\s+المالي\s+(?:الى|الي)\s+المحفظه?\s+(?<counterparty>\S+)\s+بمبلغ\s+(?<amount>{{amount}})\s*دينار',
      ),
    );
    if (outgoing != null) {
      return _ParsedSms(
        amount: outgoing.amount,
        type: 'Expense',
        balanceAfter: outgoing.balance ?? extractBalanceLocally(text),
        smsKind: 'Mobile Wallet Transfer',
        categoryHint: 'Wallet Transfer Out',
        counterparty: _cleanParty(outgoing.counterparty),
      );
    }

    return null;
  }

  _ParsedSms? _matchHousingBank(String text) {
    final cliqIn = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+transferred\s+by\s+cliq\s+to\s+account\s+(?<account>\S+).*?\s+from\s+(?<counterparty>.+?)\.\s+available\s+balance',
        caseSensitive: false,
      ),
    );
    if (cliqIn != null) {
      return _ParsedSms(
        amount: cliqIn.amount,
        type: 'Income',
        balanceAfter: cliqIn.balance ?? extractBalanceLocally(text),
        smsKind: 'CliQ Transfer',
        categoryHint: 'CliQ Transfer In',
        counterparty: _cleanParty(cliqIn.counterparty),
        isCliq: true,
      );
    }

    final cliqOut = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+transferred\s+by\s+cliq\s+from\s+account\s+(?<account>\S+).*?\s+to\s+(?<counterparty>.+?)\.\s+available\s+balance',
        caseSensitive: false,
      ),
    );
    if (cliqOut != null) {
      return _ParsedSms(
        amount: cliqOut.amount,
        type: 'Expense',
        balanceAfter: cliqOut.balance ?? extractBalanceLocally(text),
        smsKind: 'CliQ Transfer',
        categoryHint: 'CliQ Transfer Out',
        counterparty: _cleanParty(cliqOut.counterparty),
        isCliq: true,
      );
    }

    final atmDeposit = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+deposited\s+to\s+account\s+(?<account>\S+).*?\s+from\s+atm\s+(?<merchant>.+?)\s+with\s+authorization\s+number',
        caseSensitive: false,
      ),
    );
    if (atmDeposit != null) {
      return _ParsedSms(
        amount: atmDeposit.amount,
        type: 'Income',
        balanceAfter: atmDeposit.balance ?? extractBalanceLocally(text),
        smsKind: 'ATM Deposit',
        categoryHint: 'ATM Deposit',
        merchantName: _prefixAtm(atmDeposit.merchant),
      );
    }

    final atmWithdrawal = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+withdrawn\s+from\s+account\s+(?<account>\S+).*?\s+from\s+atm\s+(?<merchant>.+?)\s+with\s+authorization\s+number',
        caseSensitive: false,
      ),
    );
    if (atmWithdrawal != null) {
      return _ParsedSms(
        amount: atmWithdrawal.amount,
        type: 'Expense',
        balanceAfter: atmWithdrawal.balance ?? extractBalanceLocally(text),
        smsKind: 'ATM Withdrawal',
        categoryHint: 'ATM Withdrawal',
        merchantName: _prefixAtm(atmWithdrawal.merchant),
      );
    }

    final fee = _match(
      text,
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s+has\s+been\s+debited\s+as\s+(?<merchant>.+?)\s+from\s+account\s+(?<account>\S+)\s+on\b',
        caseSensitive: false,
      ),
    );
    if (fee != null) {
      return _ParsedSms(
        amount: fee.amount,
        type: 'Expense',
        balanceAfter: fee.balance ?? extractBalanceLocally(text),
        smsKind: 'Bank Fee',
        categoryHint: 'Bank Fees',
        merchantName: _cleanParty(fee.merchant),
      );
    }

    final bill = _match(
      text,
      _amountRx(
        r'تم\s+دفع\s+فاتوره?\s+(?<merchant>.+?)\s+رقم\s+(?<billNo>\S+)\s+بقيمه?\s+(?<amount>{{amount}})\s*دينار',
      ),
    );
    if (bill != null) {
      final biller = _cleanParty(bill.merchant);
      return _ParsedSms(
        amount: bill.amount,
        type: 'Expense',
        balanceAfter: bill.balance ?? extractBalanceLocally(text),
        smsKind: 'Bill Payment',
        categoryHint: _categoryForBiller(biller),
        merchantName: biller,
      );
    }

    return null;
  }

  _ParsedSms? _matchGeneric(String text) {
    final cliqFrom = _match(
      text,
      _amountRx(
        r'(?<amount>{{amount}})\s*jod\s+cliq\s+transfer\s+from\s+(?<counterparty>.+?)\.\s+available\s+balance',
        caseSensitive: false,
      ),
    );
    if (cliqFrom != null) {
      return _ParsedSms(
        amount: cliqFrom.amount,
        type: 'Income',
        balanceAfter: cliqFrom.balance ?? extractBalanceLocally(text),
        smsKind: 'CliQ Transfer',
        categoryHint: 'CliQ Transfer In',
        counterparty: _cleanParty(cliqFrom.counterparty),
        isCliq: true,
      );
    }

    final cliqTo = _match(
      text,
      _amountRx(
        r'(?<amount>{{amount}})\s*jod\s+cliq\s+transfer\s+to\s+(?<counterparty>.+?)\.\s+available\s+balance',
        caseSensitive: false,
      ),
    );
    if (cliqTo != null) {
      return _ParsedSms(
        amount: cliqTo.amount,
        type: 'Expense',
        balanceAfter: cliqTo.balance ?? extractBalanceLocally(text),
        smsKind: 'CliQ Transfer',
        categoryHint: 'CliQ Transfer Out',
        counterparty: _cleanParty(cliqTo.counterparty),
        isCliq: true,
      );
    }

    final cardPayment = _match(
      text,
      _amountRx(
        r'(?<amount>{{amount}})\s*jod\s+at\s+(?<merchant>.+?)\.\s+card\s+(?<card>\d+)\.\s+available\s+balance',
        caseSensitive: false,
      ),
    );
    if (cardPayment != null) {
      final merchant = _cleanParty(cardPayment.merchant);
      return _ParsedSms(
        amount: cardPayment.amount,
        type: 'Expense',
        balanceAfter: cardPayment.balance ?? extractBalanceLocally(text),
        smsKind: 'Card Payment',
        categoryHint: _categoryForMerchant(merchant, isCardPayment: true),
        merchantName: merchant,
      );
    }

    final billPayment = _match(
      text,
      _amountRx(
        r'bill\s+no\.\s+(?<billNo>\S+)\s+of\s+(?<amount>{{amount}})\s*jod\s+has\s+been\s+paid\s+to\s+(?<merchant>.+?)\.\s+ref\s+no\.',
        caseSensitive: false,
      ),
    );
    if (billPayment != null) {
      final biller = _cleanParty(billPayment.merchant);
      return _ParsedSms(
        amount: billPayment.amount,
        type: 'Expense',
        balanceAfter: billPayment.balance ?? extractBalanceLocally(text),
        smsKind: 'Bill Payment',
        categoryHint: _categoryForBiller(biller),
        merchantName: biller,
      );
    }

    final refund = _match(
      text,
      _amountRx(
        r'refund\s+of\s+(?<amount>{{amount}})\s*jod\s+at\s+(?<merchant>.+?)\.\s+available\s+balance',
        caseSensitive: false,
      ),
    );
    if (refund != null) {
      return _ParsedSms(
        amount: refund.amount,
        type: 'Income',
        balanceAfter: refund.balance ?? extractBalanceLocally(text),
        smsKind: 'Refund/Reversal',
        categoryHint: 'Refund',
        merchantName: _cleanParty(refund.merchant),
      );
    }

    final voucher = _match(
      text,
      _amountRx(
        r'successfully\s+purchased\s+a\s+voucher\s+from\s+(?<merchant>.+?)\s+for\s+(?<amount>{{amount}})\s*jod\b',
        caseSensitive: false,
      ),
    );
    if (voucher != null) {
      return _ParsedSms(
        amount: voucher.amount,
        type: 'Expense',
        balanceAfter: voucher.balance ?? extractBalanceLocally(text),
        smsKind: 'Voucher Purchase',
        categoryHint: _categoryForMerchant(voucher.merchant, isVoucher: true),
        merchantName: _cleanParty(voucher.merchant),
      );
    }

    return null;
  }

  _ParsedSms? _matchFallback(String text) {
    final type = _detectFallbackType(text);
    if (type == null || !_hasStrongTransactionKeyword(text)) return null;

    final amount = _extractTransactionAmount(text);
    if (amount == null || amount <= 0) return null;

    final merchantName = _extractMerchantName(text);
    final smsKind = _detectFallbackSmsKind(text);
    return _ParsedSms(
      amount: amount,
      type: type,
      balanceAfter: extractBalanceLocally(text),
      smsKind: smsKind,
      categoryHint: _categoryForKind(
        smsKind: smsKind,
        type: type,
        merchantName: merchantName,
      ),
      merchantName: merchantName,
      isCliq: text.contains('cliq') || text.contains('كليك'),
    );
  }

  bool _hasStrongTransactionKeyword(String text) {
    return RegExp(
      r'(?:credited|debited|deposited|withdrawn|transferred|refund|reversal|paid|payment|purchase|bill\s+no\.|available\s+balance|current\s+balance|تم\s+قيد|تمت\s+عمليه\s+التحويل|تم\s+استقبال|تم\s+دفع|الرصيد\s+المتوفر|رصيد\s+المحفظه\s+المتاح)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  String? _detectFallbackType(String text) {
    if (RegExp(
      r'(?:credited|credit|deposit|deposited|received|salary|refund|cashback|reversal|reversed|ايداع|وارد|استلام|استقبال)',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'Income';
    }

    if (RegExp(
      r'(?:debited|debit|withdrawn|withdrawal|paid|payment|purchase|pos|visa|card|bill|biller|efawateercom|atm|fee|fees|خصم|سحب|شراء|دفع|فاتوره|فواتير|عموله|رسوم)',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'Expense';
    }

    return null;
  }

  double? _extractTransactionAmount(String text) {
    final double? filsAmount = _extractFilsAmount(text);
    if (filsAmount != null) return filsAmount;

    final amountPatterns = [
      _amountRx(r'\bjod\s*(?<amount>{{amount}})\s+has\s+been'),
      _amountRx(r'(?<amount>{{amount}})\s*jod\s+has\s+been'),
      _amountRx(r'(?:amount|of|for)\s+(?<amount>{{amount}})\s*jod'),
      _amountRx(
        r'(?:بمبلغ|بقيمة|بقيمه)\s*(?<amount>{{amount}})\s*(?:jod|دينار)',
      ),
      _amountRx(
        r'\bjod\s*(?<amount>{{amount}})\s*(?:credited|debited|withdrawn|transferred|payment|purchase|paid|deposit|deposited)',
        caseSensitive: false,
      ),
      _amountRx(r'(?<amount>{{amount}})\s*jod\b'),
      _amountRx(r'\bjod\s*(?<amount>{{amount}})\b'),
      _amountRx(r'(?<amount>{{amount}})\s*دينار\b'),
    ];

    return _firstNumber(text, amountPatterns);
  }

  double? _extractFilsAmount(String text) {
    if (!text.contains('فلس') && !text.contains('fils')) return null;

    final value = _firstNumber(text, [
      _amountRx(
        r'(?:amount|بمبلغ|بقيمة|بقيمه|مبلغ)\s*(?<amount>{{amount}})\s*(?:fils|فلس)',
        caseSensitive: false,
      ),
      _amountRx(r'(?<amount>{{amount}})\s*(?:fils|فلس)', caseSensitive: false),
    ]);
    if (value == null || value <= 0) return null;

    return value / 1000;
  }

  double? extractBalanceLocally(String smsBody) {
    final String text = _normalizeSms(smsBody);
    return _firstNumber(text, [
      _amountRx(
        r'available\s+balance:?\s*(?:jod\s*)?(?<amount>{{amount}})\s*jod',
        caseSensitive: false,
      ),
      _amountRx(
        r'available\s+balance\s+jod\s*(?<amount>{{amount}})',
        caseSensitive: false,
      ),
      _amountRx(
        r'current\s+balance:?\s*(?:jod\s*)?(?<amount>{{amount}})\s*jod',
        caseSensitive: false,
      ),
      _amountRx(r'الرصيد\s+المتوفر\s*(?<amount>{{amount}})\s*jod'),
      _amountRx(
        r'رصيد\s+المحفظه?\s+المتاح\s+هو\s+(?<amount>{{amount}})\s*دينار(?:\s+اردني)?',
      ),
      _amountRx(
        r'الرصيد\s*(?:الحالي|المتاح|المتوفر)?\s*(?<amount>{{amount}})\s*(?:jod|دينار)?',
      ),
    ], allowZero: true);
  }

  _PatternMatch? _match(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;

    final amount = _namedNumber(match, 'amount');
    if (amount == null) return null;

    return _PatternMatch(
      amount: amount,
      balance: _namedNumber(match, 'balance'),
      merchant: _namedString(match, 'merchant'),
      counterparty: _namedString(match, 'counterparty'),
    );
  }

  double? _namedNumber(RegExpMatch match, String name) {
    final value = _namedString(match, name);
    if (value == null) return null;

    return double.tryParse(value.replaceAll(',', ''));
  }

  String? _namedString(RegExpMatch match, String name) {
    try {
      final value = match.namedGroup(name)?.trim();
      return value == null || value.isEmpty ? null : value;
    } on ArgumentError {
      return null;
    }
  }

  double? _firstNumber(
    String text,
    List<RegExp> patterns, {
    bool allowZero = false,
  }) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final raw = _namedString(match, 'amount') ?? match.group(1);
      final value = double.tryParse((raw ?? '').replaceAll(',', ''));
      if (value != null && (allowZero ? value >= 0 : value > 0)) return value;
    }

    return null;
  }

  String _detectFallbackSmsKind(String text) {
    if (text.contains('cliq') || text.contains('كليك')) return 'CliQ Transfer';
    if (text.contains('voucher')) return 'Voucher Purchase';
    if (text.contains('refund') ||
        text.contains('reversal') ||
        text.contains('reversed')) {
      return 'Refund/Reversal';
    }
    if (text.contains('atm') && RegExp(r'deposit|deposited').hasMatch(text)) {
      return 'ATM Deposit';
    }
    if (text.contains('atm') && RegExp(r'withdraw|withdrawn').hasMatch(text)) {
      return 'ATM Withdrawal';
    }
    if (RegExp(r'bill|biller|efawateercom|فاتوره').hasMatch(text)) {
      return 'Bill Payment';
    }
    if (RegExp(r'fee|fees|عموله|رسوم').hasMatch(text)) return 'Bank Fee';
    if (RegExp(r'purchase|pos|card|visa|شراء').hasMatch(text)) {
      return 'Card Payment';
    }
    if (RegExp(r'credited|credit').hasMatch(text)) return 'Bank Credit';

    return 'Bank Transaction';
  }

  String _categoryForKind({
    required String smsKind,
    required String type,
    String? merchantName,
  }) {
    switch (smsKind) {
      case 'Bank Credit':
        return 'Bank Credit';
      case 'CliQ Transfer':
        return type == 'Income' ? 'CliQ Transfer In' : 'CliQ Transfer Out';
      case 'Mobile Wallet Transfer':
        return type == 'Income' ? 'Wallet Transfer In' : 'Wallet Transfer Out';
      case 'ATM Deposit':
        return 'ATM Deposit';
      case 'ATM Withdrawal':
        return 'ATM Withdrawal';
      case 'Bank Fee':
        return 'Bank Fees';
      case 'Bill Payment':
        return _categoryForBiller(merchantName);
      case 'Card Payment':
        return _categoryForMerchant(merchantName, isCardPayment: true);
      case 'Voucher Purchase':
        return _categoryForMerchant(merchantName, isVoucher: true);
      case 'Refund/Reversal':
        return 'Refund';
      default:
        return type == 'Income' ? 'Income' : 'General Expense';
    }
  }

  String _categoryForBiller(String? biller) {
    final value = (biller ?? '').toLowerCase();

    if (_containsAny(value, ['zain', 'umniah', 'orange mobile', 'orange'])) {
      return 'Bills - Telecom';
    }
    if (_containsAny(value, [
      'jordan electricity',
      'electricity distribution co',
    ])) {
      return 'Bills - Electricity';
    }
    if (_containsAny(value, ['water_miyahuna', 'miyahuna'])) {
      return 'Bills - Water';
    }
    if (value.contains('ministry of health')) return 'Healthcare';
    if (value.contains('world islamic sciences and education university')) {
      return 'Education';
    }
    if (value.contains('damamax')) return 'Bills - Internet';
    if (value.contains('sadad logistics')) return 'Services';
    if (_containsAny(value, ['al tas heelat', 'tasheelat'])) {
      return 'Financing / Installments';
    }

    return 'General Expense';
  }

  String _categoryForMerchant(
    String? merchant, {
    bool isCardPayment = false,
    bool isVoucher = false,
  }) {
    final value = (merchant ?? '').toLowerCase();

    if (isVoucher || value.contains('freefire')) return 'Gaming / Vouchers';
    if (_containsAny(value, ['zain', 'umniah', 'orange'])) {
      return 'Bills - Telecom';
    }
    if (value.contains('talabat')) return 'Food & Delivery';
    if (_containsAny(value, ['paypal', 'google'])) return 'Online Services';

    return isCardPayment ? 'Shopping' : 'General Expense';
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  String? _extractMerchantName(String text) {
    final patterns = [
      RegExp(
        r'from\s+(?<merchant>atm\s+[a-z0-9\u0600-\u06FF\s\-_]+?)\s+with\s+authorization',
        caseSensitive: false,
      ),
      RegExp(
        r'from\s+(?<merchant>[a-z0-9\u0600-\u06FF\s\-_]+?)\s+amount',
        caseSensitive: false,
      ),
      RegExp(r'paid\s+to\s+(?<merchant>.+?)(?:\.|$)', caseSensitive: false),
      RegExp(
        r'at\s+(?<merchant>.+?)(?:\.|,| on | available|$)',
        caseSensitive: false,
      ),
      RegExp(r'لدى\s+(?<merchant>.+?)(?:\.|،| بتاريخ| الرصيد|$)'),
      RegExp(r'لدي\s+(?<merchant>.+?)(?:\.|،| بتاريخ| الرصيد|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;

      final value = _cleanParty(_namedString(match, 'merchant'));
      if (value == null || _isBadMerchantValue(value)) continue;
      return value;
    }

    return null;
  }

  bool _isBadMerchantValue(String value) {
    final normalizedValue = value.toLowerCase();

    return normalizedValue.contains('account') ||
        normalizedValue.contains('balance') ||
        normalizedValue.contains('authorization') ||
        normalizedValue.contains('available') ||
        normalizedValue.length < 2;
  }

  String? _cleanParty(String? value) {
    final cleaned = value
        ?.trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.,]+$'), '');
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  String? _prefixAtm(String? location) {
    final cleaned = _cleanParty(location);
    if (cleaned == null) return null;
    return cleaned.startsWith('atm ') ? cleaned : 'atm $cleaned';
  }

  // Generates professional financial advice through the backend AI function.
  Future<String> getFinancialAdvice(
    String userMessage, [
    String? financialContext,
  ]) async {
    const int maxRetries = 2;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _client.functions
            .invoke('financial_ai_assistant', body: {'message': userMessage})
            .timeout(const Duration(seconds: 25));

        final data = response.data;
        if (data is Map && data['response'] != null) {
          return data['response'].toString();
        }

        return "I could not generate a response right now.";
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

class _ParsedSms {
  final double amount;
  final String type;
  final double? balanceAfter;
  final String smsKind;
  final String categoryHint;
  final String? merchantName;
  final String? counterparty;
  final bool isCliq;

  const _ParsedSms({
    required this.amount,
    required this.type,
    required this.balanceAfter,
    required this.smsKind,
    required this.categoryHint,
    this.merchantName,
    this.counterparty,
    this.isCliq = false,
  });
}

class _PatternMatch {
  final double amount;
  final double? balance;
  final String? merchant;
  final String? counterparty;

  const _PatternMatch({
    required this.amount,
    required this.balance,
    this.merchant,
    this.counterparty,
  });
}
