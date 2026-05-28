import 'package:final_project/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AIService bank SMS regex parser', () {
    late AIService service;

    setUp(() {
      service = AIService();
    });

    test('parses Reflect credit messages', () {
      final parsed = service.parseBankSmsLocally(
        'JOD 124.072 has been credited to your Reflect account on 01/05 14:31. Available balance 129.072 JOD. More details under "Transactions"',
        sender: 'Reflect',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Income');
      expect(parsed['amount'], 124.072);
      expect(parsed['available_balance'], 129.072);
      expect(parsed['sms_kind'], 'Bank Transaction');
    });

    test('parses Reflect Arabic outgoing transfer messages', () {
      final parsed = service.parseBankSmsLocally(
        'تم قيد حوالة بمبلغ 221.698 JOD من حسابك على ريفلكت بتاريخ 01/05 14:37. الرصيد المتوفر 0.000 JOD',
        sender: 'Reflect',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Expense');
      expect(parsed['amount'], 221.698);
      expect(parsed['available_balance'], 0.0);
      expect(parsed['counterparty'], 'Reflect Account');
      expect(parsed['sms_kind'], 'Reflect CliQ Payment');
    });

    test('parses Reflect reversal messages as income', () {
      final parsed = service.parseBankSmsLocally(
        'A purchase transaction has been reversed to your Reflect card from GOOGLETEMPORARY HOLD amount 5.000 JOD on 04-11-2025 as a reversal. Available balance 5.000 JOD. More details under "Transactions"',
        sender: 'Reflect',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Income');
      expect(parsed['amount'], 5.0);
      expect(parsed['available_balance'], 5.0);
      expect(parsed['sms_kind'], 'Reflect Reversal');
      expect(parsed['merchant_name'], 'googletemporary hold');
    });

    test('ignores OTP messages', () {
      final parsed = service.parseBankSmsLocally(
        '740585 هو رمز التحقق لدفعة كليك بقيمة 5.000 JOD. يرجى عدم مشاركته مع أي شخص.',
        sender: 'Reflect',
      );

      expect(parsed, isNull);
    });

    test('parses Orange Money outgoing transfers', () {
      final parsed = service.parseBankSmsLocally(
        'تمت عملية التحويل المالي الى المحفظة 00962772432565 بمبلغ 5 دينار بتاريخ 10/05/2026 الساعة 09:31:44 PM بالرقم المرجعي OJM-PAY رصيد المحفظة المتاح هو 29 دينار أردني شكراً لاستخدامك Orange Money',
        sender: 'OrangeMoney',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Expense');
      expect(parsed['amount'], 5.0);
      expect(parsed['available_balance'], 29.0);
      expect(parsed['counterparty'], '00962772432565');
      expect(parsed['sms_kind'], 'Orange Money Transfer Out');
    });

    test('parses Orange Money incoming transfers', () {
      final parsed = service.parseBankSmsLocally(
        'تم استقبال حوالة مالية من 00962788625307  من مزود الخدمة:  Orange Money إلى محفظتك بمبلغ 20  دينار بتاريخ 06/05/2026 الساعة 10:51:54 PM بالرقم المرجعي OJM-PAY رصيد المحفظة المتاح هو 20 دينار أردني شكراً لاستخدامك Orange Money',
        sender: 'OrangeMoney',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Income');
      expect(parsed['amount'], 20.0);
      expect(parsed['available_balance'], 20.0);
      expect(parsed['counterparty'], '00962788625307');
      expect(parsed['sms_kind'], 'Orange Money Transfer In');
    });

    test('parses CliQ incoming transfers to bank account', () {
      final parsed = service.parseBankSmsLocally(
        'JOD 7.000 has been transferred by CliQ to account XXXXXX6800110001 on 10/05/2026 06:27 PM from JO29ARAB9000030025369444874500. Available balance JOD 40.000',
        sender: 'HousingBank',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Income');
      expect(parsed['amount'], 7.0);
      expect(parsed['available_balance'], 40.0);
      expect(parsed['counterparty'], 'jo29arab9000030025369444874500');
      expect(parsed['is_cliq'], true);
      expect(parsed['sms_kind'], 'CliQ Transfer');
    });

    test('parses CliQ outgoing transfers from bank account', () {
      final parsed = service.parseBankSmsLocally(
        'JOD 63.000 has been transferred by CliQ from account XXXXXX6800110001 on 08/05/2026 01:11 AM to 00962792386665. Available balance JOD 37.000',
        sender: 'HousingBank',
      );

      expect(parsed, isNotNull);
      expect(parsed!['type'], 'Expense');
      expect(parsed['amount'], 63.0);
      expect(parsed['available_balance'], 37.0);
      expect(parsed['counterparty'], '00962792386665');
      expect(parsed['is_cliq'], true);
      expect(parsed['sms_kind'], 'CliQ Transfer');
    });

    test('parses exact Reflect and HousingBank transfer pair messages', () {
      final reflect = service.parseBankSmsLocally(
        'JOD 2.000 has been credited to your Reflect account on 28/05 17:12. Available balance 5.793 JOD. More details under "Transactions"',
        sender: 'Reflect',
      );

      final housing = service.parseBankSmsLocally(
        'JOD 2.000 has been transferred by CliQ from account XXXXX6800110001 on 28/05/2026 05:12 PM to AB-DARABIC. Available balance JOD 18.136',
        sender: 'HousingBank',
      );

      expect(reflect, isNotNull);
      expect(reflect!['amount'], 2.0);
      expect(reflect['type'], 'Income');
      expect(reflect['sms_kind'], 'Bank Transaction');
      expect(reflect['available_balance'], 5.793);

      expect(housing, isNotNull);
      expect(housing!['amount'], 2.0);
      expect(housing['type'], 'Expense');
      expect(housing['sms_kind'], 'CliQ Transfer');
      expect(housing['is_cliq'], true);
      expect(housing['available_balance'], 18.136);
      expect(housing['counterparty'], 'ab-darabic');
    });

    test('parses ATM deposits and withdrawals', () {
      final deposit = service.parseBankSmsLocally(
        'JOD 50.000 has been deposited to account XXXXXX6800110001 on 07/05/2026 11:55 AM from ATM JUWAIDA with authorization number 441177. Available balance JOD 50.000',
        sender: 'HousingBank',
      );
      final withdrawal = service.parseBankSmsLocally(
        'JOD 20.000 has been withdrawn from account XXXXXX6800110001 on 01/05/2026 05:15 PM from ATM JUWAIDA with authorization number 449535. Available balance JOD 98.423',
        sender: 'HousingBank',
      );

      expect(deposit, isNotNull);
      expect(deposit!['type'], 'Income');
      expect(deposit['amount'], 50.0);
      expect(deposit['available_balance'], 50.0);
      expect(deposit['merchant_name'], 'atm juwaida');
      expect(deposit['sms_kind'], 'ATM Deposit');

      expect(withdrawal, isNotNull);
      expect(withdrawal!['type'], 'Expense');
      expect(withdrawal['amount'], 20.0);
      expect(withdrawal['available_balance'], 98.423);
      expect(withdrawal['merchant_name'], 'atm juwaida');
      expect(withdrawal['sms_kind'], 'ATM Withdrawal');
    });

    test('parses bill payments and bank fees', () {
      final bill = service.parseBankSmsLocally(
        'تم دفع فاتورة Umniah رقم 962110213214 بقيمة 50.000 دينار و عمولة بقيمة 0.000 دينار بتاريخ 20:45:7 05/05/2026.',
        sender: 'HousingBank',
      );
      final fee = service.parseBankSmsLocally(
        'JOD 0.500 has been debited as digital banking services fee from account XXXXXX6800110001 on 28/04/2026 05:13 AM',
        sender: 'HousingBank',
      );

      expect(bill, isNotNull);
      expect(bill!['type'], 'Expense');
      expect(bill['amount'], 50.0);
      expect(bill['merchant_name'], 'umniah');
      expect(bill['sms_kind'], 'Bill Payment');

      expect(fee, isNotNull);
      expect(fee!['type'], 'Expense');
      expect(fee['amount'], 0.5);
      expect(fee['sms_kind'], 'Bank Fee');
    });

    test('ignores scam and service outage messages', () {
      final scam = service.parseBankSmsLocally(
        'Beware of SMS or WhatsApp messages claiming to be from Jordan Post regarding shipments or information updates, as these may be scam messages.',
        sender: 'HousingBank',
      );
      final serviceOutage = service.parseBankSmsLocally(
        'Please note that all digital banking services will be suspended on Friday from 2 AM to 7 AM due to system updates.',
        sender: 'HousingBank',
      );

      expect(scam, isNull);
      expect(serviceOutage, isNull);
    });
  });
}
