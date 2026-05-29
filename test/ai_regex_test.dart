import 'dart:io';

import 'package:final_project/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIService bank SMS regex parser', () {
    late AIService service;

    setUp(() {
      service = AIService();
    });

    test('matches provider-aware FinancialMind SMS patterns', () {
      for (final sample in _samples) {
        final parsed = service.parseBankSmsLocally(
          sample.sms,
          sender: sample.sender,
        );

        if (sample.ignored) {
          expect(parsed, isNull, reason: sample.name);
          continue;
        }

        expect(parsed, isNotNull, reason: sample.name);
        final data = parsed!;
        expect(data['type'], sample.type, reason: sample.name);
        expect(data['sms_kind'], sample.smsKind, reason: sample.name);
        expect(data['category_hint'], sample.categoryHint, reason: sample.name);
        expect(
          data['amount'],
          closeTo(sample.amount!, 0.000001),
          reason: sample.name,
        );
        expect(data['is_cliq'], sample.isCliq, reason: sample.name);

        if (sample.balanceAfter == null) {
          expect(data['available_balance'], isNull, reason: sample.name);
        } else {
          expect(
            data['available_balance'],
            closeTo(sample.balanceAfter!, 0.000001),
            reason: sample.name,
          );
        }

        expect(data['merchant_name'], sample.merchantName, reason: sample.name);
        expect(data['counterparty'], sample.counterparty, reason: sample.name);
      }
    });

    test('validates all fixture messages are covered by parser tests', () {
      final fixtureFile = File('test/fixtures/bank_sms_samples.txt');
      final lines = fixtureFile
          .readAsLinesSync()
          .where((line) => line.trim().isNotEmpty && !line.startsWith('#'))
          .toList();

      expect(lines.length, _samples.length);

      for (var i = 0; i < lines.length; i++) {
        final parts = lines[i].split('\t');
        expect(parts.length, 2, reason: 'Fixture line ${i + 1}');
        expect(parts[0], _samples[i].sender, reason: _samples[i].name);
        expect(parts[1], _samples[i].sms, reason: _samples[i].name);
      }
    });

    test('extracts supported standalone balance formats', () {
      expect(service.extractBalanceLocally('Available balance 5.000 JOD'), 5.0);
      expect(
        service.extractBalanceLocally('Available balance JOD 18.136'),
        18.136,
      );
      expect(
        service.extractBalanceLocally('Available balance: 20.008 JOD'),
        20.008,
      );
      expect(service.extractBalanceLocally('الرصيد المتوفر 0.000 JOD'), 0.0);
      expect(
        service.extractBalanceLocally('رصيد المحفظة المتاح هو 29 دينار أردني'),
        29.0,
      );
    });
  });
}

class SmsSample {
  final String name;
  final String sender;
  final String sms;
  final bool ignored;
  final double? amount;
  final String? type;
  final double? balanceAfter;
  final String? smsKind;
  final String? categoryHint;
  final String? merchantName;
  final String? counterparty;
  final bool isCliq;

  const SmsSample({
    required this.name,
    required this.sender,
    required this.sms,
    this.ignored = false,
    this.amount,
    this.type,
    this.balanceAfter,
    this.smsKind,
    this.categoryHint,
    this.merchantName,
    this.counterparty,
    this.isCliq = false,
  });
}

const _samples = [
  SmsSample(
    name: 'INCOME-01 Reflect credited',
    sender: 'Reflect',
    sms:
        'JOD 5.000 has been credited to your Reflect account on 30/04 17:03. Available balance 5.000 JOD. More details under "Transactions"',
    amount: 5.0,
    type: 'Income',
    balanceAfter: 5.0,
    smsKind: 'Bank Credit',
    categoryHint: 'Bank Credit',
    merchantName: 'reflect',
  ),
  SmsSample(
    name: 'INCOME-02 Reflect purchase reversal',
    sender: 'Reflect',
    sms:
        'A purchase transaction has been reversed to your Reflect card from GOOGLETEMPORARY HOLD amount 5.000 JOD on 04-11-2025 as a reversal. Available balance 5.000 JOD.',
    amount: 5.0,
    type: 'Income',
    balanceAfter: 5.0,
    smsKind: 'Refund/Reversal',
    categoryHint: 'Refund',
    merchantName: 'googletemporary hold',
  ),
  SmsSample(
    name: 'INCOME-03 Reflect CliQ reversal',
    sender: 'Reflect',
    sms:
        'JOD 5.000 Cliq Payment from your Reflect account on 02/05 14:19 as a reversal.',
    amount: 5.0,
    type: 'Income',
    smsKind: 'Refund/Reversal',
    categoryHint: 'Refund',
    merchantName: 'reflect',
    counterparty: 'reflect account',
    isCliq: true,
  ),
  SmsSample(
    name: 'INCOME-04 Orange Money received transfer',
    sender: 'OrangeMoney',
    sms:
        'تم استقبال حوالة مالية من 00962788625307 من مزود الخدمة: Orange Money إلى محفظتك بمبلغ 9 دينار بتاريخ 06/05/2026 الساعة 10:51:54 PM رصيد المحفظة المتاح هو 29 دينار أردني',
    amount: 9.0,
    type: 'Income',
    balanceAfter: 29.0,
    smsKind: 'Mobile Wallet Transfer',
    categoryHint: 'Wallet Transfer In',
    counterparty: '00962788625307',
  ),
  SmsSample(
    name: 'INCOME-05 HousingBank CliQ transfer to account',
    sender: 'HousingBank',
    sms:
        'JOD 7.000 has been transferred by CliQ to account XXXXXX6800110001 on 10/05/2026 06:27 PM from JO29ARAB9000030025369444874500. Available balance JOD 40.000',
    amount: 7.0,
    type: 'Income',
    balanceAfter: 40.0,
    smsKind: 'CliQ Transfer',
    categoryHint: 'CliQ Transfer In',
    counterparty: 'jo29arab9000030025369444874500',
    isCliq: true,
  ),
  SmsSample(
    name: 'INCOME-06 HousingBank ATM deposit',
    sender: 'HousingBank',
    sms:
        'JOD 50.000 has been deposited to account XXXXXX6800110001 on 07/05/2026 11:55 AM from ATM JUWAIDA with authorization number 441177. Available balance JOD 50.000',
    amount: 50.0,
    type: 'Income',
    balanceAfter: 50.0,
    smsKind: 'ATM Deposit',
    categoryHint: 'ATM Deposit',
    merchantName: 'atm juwaida',
  ),
  SmsSample(
    name: 'INCOME-07 Union style CliQ transfer from person',
    sender: 'ArabBank',
    sms:
        '100.000 JOD CliQ transfer from ABDALKAREEM YOUSEF SALEH ALARJAN. Available balance: 138.158 JOD.',
    amount: 100.0,
    type: 'Income',
    balanceAfter: 138.158,
    smsKind: 'CliQ Transfer',
    categoryHint: 'CliQ Transfer In',
    counterparty: 'abdalkareem yousef saleh alarjan',
    isCliq: true,
  ),
  SmsSample(
    name: 'INCOME-08 Refund at merchant with comma amount',
    sender: 'ArabBank',
    sms:
        'Refund of 2,400.000 JOD at PAYPAL ALE. Available balance: 1,561.350 JOD.',
    amount: 2400.0,
    type: 'Income',
    balanceAfter: 1561.35,
    smsKind: 'Refund/Reversal',
    categoryHint: 'Refund',
    merchantName: 'paypal ale',
  ),
  SmsSample(
    name: 'EXPENSE-01 Reflect Arabic outgoing transfer',
    sender: 'Reflect',
    sms:
        'تم قيد حوالة بمبلغ 221.698 JOD من حسابك على ريفلكت بتاريخ 01/05 14:37. الرصيد المتوفر 0.000 JOD',
    amount: 221.698,
    type: 'Expense',
    balanceAfter: 0.0,
    smsKind: 'CliQ Transfer',
    categoryHint: 'CliQ Transfer Out',
    counterparty: 'Reflect Account',
    isCliq: true,
  ),
  SmsSample(
    name: 'EXPENSE-02 Orange Money transfer to wallet',
    sender: 'OrangeMoney',
    sms:
        'تمت عملية التحويل المالي الى المحفظة 00962772432565 بمبلغ 5 دينار بتاريخ 10/05/2026 الساعة 09:31:44 PM رصيد المحفظة المتاح هو 29 دينار أردني',
    amount: 5.0,
    type: 'Expense',
    balanceAfter: 29.0,
    smsKind: 'Mobile Wallet Transfer',
    categoryHint: 'Wallet Transfer Out',
    counterparty: '00962772432565',
  ),
  SmsSample(
    name: 'EXPENSE-03 HousingBank CliQ transfer from account',
    sender: 'HousingBank',
    sms:
        'JOD 7.000 has been transferred by CliQ from account XXXXXX6800110001 on 09/05/2026 11:17 AM to ABDARABIC. Available balance JOD 30.000',
    amount: 7.0,
    type: 'Expense',
    balanceAfter: 30.0,
    smsKind: 'CliQ Transfer',
    categoryHint: 'CliQ Transfer Out',
    counterparty: 'abdarabic',
    isCliq: true,
  ),
  SmsSample(
    name: 'EXPENSE-04 HousingBank ATM withdrawal',
    sender: 'HousingBank',
    sms:
        'JOD 20.000 has been withdrawn from account XXXXXX6800110001 on 01/05/2026 05:15 PM from ATM JUWAIDA with authorization number 449535. Available balance JOD 98.423',
    amount: 20.0,
    type: 'Expense',
    balanceAfter: 98.423,
    smsKind: 'ATM Withdrawal',
    categoryHint: 'ATM Withdrawal',
    merchantName: 'atm juwaida',
  ),
  SmsSample(
    name: 'EXPENSE-05 HousingBank fees',
    sender: 'HousingBank',
    sms:
        'JOD 0.500 has been debited as digital banking services fee from account XXXXXX6800110001 on 28/04/2026 05:13 AM',
    amount: 0.5,
    type: 'Expense',
    smsKind: 'Bank Fee',
    categoryHint: 'Bank Fees',
    merchantName: 'digital banking services fee',
  ),
  SmsSample(
    name: 'EXPENSE-06 HousingBank Arabic bill payment',
    sender: 'HousingBank',
    sms:
        'تم دفع فاتورة Umniah رقم 962110213214 بقيمة 50.000 دينار و عمولة بقيمة 0.000 دينار بتاريخ 20:45:7 05/05/2026.',
    amount: 50.0,
    type: 'Expense',
    smsKind: 'Bill Payment',
    categoryHint: 'Bills - Telecom',
    merchantName: 'umniah',
  ),
  SmsSample(
    name: 'EXPENSE-07 Union style CliQ transfer to person',
    sender: 'ArabBank',
    sms:
        '2.600 JOD CliQ transfer to Abdalkareem Alarjan. Available balance: 20.008 JOD.',
    amount: 2.6,
    type: 'Expense',
    balanceAfter: 20.008,
    smsKind: 'CliQ Transfer',
    categoryHint: 'CliQ Transfer Out',
    counterparty: 'abdalkareem alarjan',
    isCliq: true,
  ),
  SmsSample(
    name: 'EXPENSE-08 Card merchant Umniah',
    sender: 'ArabBank',
    sms: '11.600 JOD at Umniah. Card 786. Available balance: 22.608 JOD.',
    amount: 11.6,
    type: 'Expense',
    balanceAfter: 22.608,
    smsKind: 'Card Payment',
    categoryHint: 'Bills - Telecom',
    merchantName: 'umniah',
  ),
  SmsSample(
    name: 'EXPENSE-08 Card merchant TALABAT',
    sender: 'ArabBank',
    sms: '8.250 JOD at TALABAT. Card 786. Available balance: 12.000 JOD.',
    amount: 8.25,
    type: 'Expense',
    balanceAfter: 12.0,
    smsKind: 'Card Payment',
    categoryHint: 'Food & Delivery',
    merchantName: 'talabat',
  ),
  SmsSample(
    name: 'EXPENSE-08 Card merchant GOOGLE',
    sender: 'ArabBank',
    sms: '1.990 JOD at GOOGLE PLAY. Card 786. Available balance: 10.010 JOD.',
    amount: 1.99,
    type: 'Expense',
    balanceAfter: 10.01,
    smsKind: 'Card Payment',
    categoryHint: 'Online Services',
    merchantName: 'google play',
  ),
  SmsSample(
    name: 'EXPENSE-09 eFAWATEERCOM bill Zain',
    sender: 'ArabBank',
    sms:
        'Bill no. 00294617 of 45.24 JOD has been paid to Zain. Ref no. 399BPDP261460197. Available balance: 41.408 JOD.',
    amount: 45.24,
    type: 'Expense',
    balanceAfter: 41.408,
    smsKind: 'Bill Payment',
    categoryHint: 'Bills - Telecom',
    merchantName: 'zain',
  ),
  SmsSample(
    name: 'EXPENSE-09 eFAWATEERCOM bill Electricity',
    sender: 'ArabBank',
    sms:
        'Bill no. 123 of 29.000 JOD has been paid to Jordan Electricity. Ref no. REF123. Available balance: 100.000 JOD.',
    amount: 29.0,
    type: 'Expense',
    balanceAfter: 100.0,
    smsKind: 'Bill Payment',
    categoryHint: 'Bills - Electricity',
    merchantName: 'jordan electricity',
  ),
  SmsSample(
    name: 'EXPENSE-09 eFAWATEERCOM bill Water',
    sender: 'ArabBank',
    sms:
        'Bill no. 124 of 12.500 JOD has been paid to Water_Miyahuna Amman. Ref no. REF124. Available balance: 87.500 JOD.',
    amount: 12.5,
    type: 'Expense',
    balanceAfter: 87.5,
    smsKind: 'Bill Payment',
    categoryHint: 'Bills - Water',
    merchantName: 'water_miyahuna amman',
  ),
  SmsSample(
    name: 'EXPENSE-09 eFAWATEERCOM Ministry of Health',
    sender: 'ArabBank',
    sms:
        'Bill no. 125 of 6.000 JOD has been paid to Ministry of Health Patients eServices. Ref no. REF125. Available balance: 81.500 JOD.',
    amount: 6.0,
    type: 'Expense',
    balanceAfter: 81.5,
    smsKind: 'Bill Payment',
    categoryHint: 'Healthcare',
    merchantName: 'ministry of health patients eservices',
  ),
  SmsSample(
    name: 'EXPENSE-09 eFAWATEERCOM Education',
    sender: 'ArabBank',
    sms:
        'Bill no. 126 of 100.000 JOD has been paid to World Islamic Sciences And Education University. Ref no. REF126. Available balance: 50.000 JOD.',
    amount: 100.0,
    type: 'Expense',
    balanceAfter: 50.0,
    smsKind: 'Bill Payment',
    categoryHint: 'Education',
    merchantName: 'world islamic sciences and education university',
  ),
  SmsSample(
    name: 'EXPENSE-09 eFAWATEERCOM DAMAMAX',
    sender: 'ArabBank',
    sms:
        'Bill no. 127 of 22.000 JOD has been paid to DAMAMAX. Ref no. REF127. Available balance: 28.000 JOD.',
    amount: 22.0,
    type: 'Expense',
    balanceAfter: 28.0,
    smsKind: 'Bill Payment',
    categoryHint: 'Bills - Internet',
    merchantName: 'damamax',
  ),
  SmsSample(
    name: 'EXPENSE-10 Voucher purchase',
    sender: 'ArabBank',
    sms:
        'You successfully purchased a voucher from FreeFire for 0.710JOD on 11/09/2025. Amount has been debited to your Saving - Regular-01. Current balance: 1004.442 JOD Available balance: 1,004.442 JOD',
    amount: 0.71,
    type: 'Expense',
    balanceAfter: 1004.442,
    smsKind: 'Voucher Purchase',
    categoryHint: 'Gaming / Vouchers',
    merchantName: 'freefire',
  ),
  SmsSample(
    name: 'IGNORE-01 Reflect CliQ OTP',
    sender: 'Reflect',
    sms:
        '740585 هو رمز التحقق لدفعة كليك بقيمة 5.000 JOD. يرجى عدم مشاركته مع أي شخص.',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-02 eFAWATEERCOM OTP',
    sender: 'ArabBank',
    sms:
        'OTP for eFAWATEERCOM Direct Pay is 83084, it will be used to debit your account with 45.240 JOD, so please do not share this OTP with any person',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-03 Arabic card purchase OTP',
    sender: 'ArabBank',
    sms:
        '203980 هو رمز التأكيد OTP لتنفيذ حركة شراء بقيمة JOD 6.550 من ZAIN WEBSITE لبطاقتك المنتهية بالأرقام 7786. لا تشارك هذا الرمز مع أحد',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-04 Arabic bank transfer OTP',
    sender: 'ArabBank',
    sms:
        'بنك الإتحاد الرقم السري لعملية التحويل: 402470 سوف يتم استخدام هذا الرمز لعملية تحويل من حسابك بمبلغ JOD 100',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-05 Security/scam warning',
    sender: 'HousingBank',
    sms:
        'Beware of SMS or WhatsApp messages claiming to be from Jordan Post. Avoid opening any links or sharing your banking information.',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-06 Service maintenance/update',
    sender: 'HousingBank',
    sms:
        'Please note that all digital banking services will be suspended due to system updates.',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-07 Declined card transaction',
    sender: 'ArabBank',
    sms:
        'Your transaction on debit card ending with 786 for JOD 15.07 at ZAIN WEBSITE has been declined due to Exceeds Withdrawal Amount Limit',
    ignored: true,
  ),
  SmsSample(
    name: 'IGNORE-08 Voucher OTP',
    sender: 'ArabBank',
    sms: 'رمز التحقق لإستكمال شراء القسيمة: 578115',
    ignored: true,
  ),
];
