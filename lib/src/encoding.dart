import 'dart:convert';

/// Percent-encodes [value] for a query string, matching WHATWG
/// `application/x-www-form-urlencoded` serialisation.
///
/// Dart's [Uri.encodeQueryComponent] differs from that spec in two characters —
/// it escapes `*` and leaves `~` — which would make GROQ queries diverge from
/// what other Sanity clients send.
String formUrlEncode(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if (_isUnreserved(byte)) {
      buffer.writeCharCode(byte);
    } else if (byte == 0x20) {
      buffer.write('+');
    } else {
      buffer
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

bool _isUnreserved(int byte) =>
    (byte >= 0x30 && byte <= 0x39) ||
    (byte >= 0x41 && byte <= 0x5A) ||
    (byte >= 0x61 && byte <= 0x7A) ||
    byte == 0x2A ||
    byte == 0x2D ||
    byte == 0x2E ||
    byte == 0x5F;
