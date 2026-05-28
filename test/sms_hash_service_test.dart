import 'package:final_project/services/sms_hash_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable SMS hash ignores sender spacing and body whitespace', () {
    final first = SmsHashService.stableSmsHash(
      sender: 'Orange Money',
      body: 'JOD 5.000   has been paid',
    );

    final second = SmsHashService.stableSmsHash(
      sender: ' orangemoney ',
      body: 'JOD 5.000 has been paid',
    );

    expect(first, second);
  });

  test('stable SMS hash ignores unstable SMS timestamps', () {
    const reflectMessage =
        'JOD 2.000 has been credited to your Reflect account on 28/05 17:12. Available balance 5.793 JOD. More details under "Transactions"';

    final incomingHash = SmsHashService.stableSmsHash(
      sender: 'Reflect',
      body: reflectMessage,
    );

    final inboxHash = SmsHashService.stableSmsHash(
      sender: ' reflect ',
      body: reflectMessage,
    );

    expect(incomingHash, inboxHash);
  });

  test('legacy timestamped hash is separate from new stable hash', () {
    const body =
        'JOD 2.000 has been credited to your Reflect account on 28/05 17:12. Available balance 5.793 JOD. More details under "Transactions"';

    final stableHash = SmsHashService.stableSmsHash(
      sender: 'Reflect',
      body: body,
    );
    final legacyHash = SmsHashService.legacyTimestampedSmsHashForLookup(
      sender: 'Reflect',
      body: body,
      smsDate: 1779980000000,
    );

    expect(legacyHash, isNot(stableHash));
  });

  test('sender match normalizes case and spaces', () {
    expect(SmsHashService.senderMatches('Housing Bank', 'housingbank'), isTrue);
  });
}
