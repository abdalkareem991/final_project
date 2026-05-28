import 'package:final_project/services/sms_hash_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable SMS hash ignores sender spacing and body whitespace', () {
    final first = SmsHashService.stableSmsHash(
      sender: 'Orange Money',
      body: 'JOD 5.000   has been paid',
      smsDate: 1779980000000,
    );

    final second = SmsHashService.stableSmsHash(
      sender: ' orangemoney ',
      body: 'JOD 5.000 has been paid',
      smsDate: 1779980000000,
    );

    expect(first, second);
  });

  test('sender match normalizes case and spaces', () {
    expect(SmsHashService.senderMatches('Housing Bank', 'housingbank'), isTrue);
  });
}
