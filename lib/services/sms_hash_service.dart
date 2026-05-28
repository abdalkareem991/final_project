class SmsHashService {
  const SmsHashService._();

  static String normalizeSender(String sender) {
    return sender.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  static String normalizeBody(String body) {
    return body.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  static bool senderMatches(String savedSender, String incomingSender) {
    final saved = normalizeSender(savedSender);
    final incoming = normalizeSender(incomingSender);
    return saved.isNotEmpty && saved == incoming;
  }

  static String stableSmsHash({
    required String sender,
    required String body,
    required int smsDate,
  }) {
    final normalizedSender = normalizeSender(sender);
    final normalizedBody = normalizeBody(body);
    return '${normalizedSender}_${smsDate}_${_jenkinsHash(normalizedBody)}';
  }

  static int _jenkinsHash(String value) {
    var hash = 0;

    for (var i = 0; i < value.length; i++) {
      hash = 0x1fffffff & (hash + value.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash = hash ^ (hash >> 6);
    }

    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash = hash ^ (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));

    return hash;
  }
}
