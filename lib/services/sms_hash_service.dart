class SmsHashService {
  const SmsHashService._();

  static String normalizeSender(String sender) {
    var normalized = sender.trim().toLowerCase();
    normalized = normalized.replaceAll(
      RegExp(r'[\u200B-\u200F\uFEFF\u2060-\u2064]'),
      '',
    );
    normalized = normalized.replaceAll(RegExp(r'\s+'), '');

    if (normalized.startsWith('sms:')) {
      normalized = normalized.substring(4);
    }

    if (normalized.startsWith('+')) {
      normalized = normalized.substring(1);
    } else if (normalized.startsWith('00')) {
      normalized = normalized.substring(2);
    }

    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]'), '');
    return normalized;
  }

  static String normalizeBody(String body) {
    return body.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  static bool senderMatches(String savedSender, String incomingSender) {
    final saved = normalizeSender(savedSender);
    final incoming = normalizeSender(incomingSender);
    if (saved.isEmpty || incoming.isEmpty) return false;
    return saved == incoming ||
        incoming.contains(saved) ||
        saved.contains(incoming);
  }

  static String stableSmsHash({required String sender, required String body}) {
    final normalizedSender = normalizeSender(sender);
    final normalizedBody = normalizeBody(body);
    return '${normalizedSender}_${_jenkinsHash(normalizedBody)}';
  }

  // Lookup only: recognizes hashes produced before timestamp-free hashes.
  static String legacyTimestampedSmsHashForLookup({
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
