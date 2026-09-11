import 'dart:convert';

import 'encoding.dart';

/// Encodes a GROQ [query] and its [params] into a query string, leading `?`
/// included.
///
/// Parameter names are prefixed with `$` and their values JSON-encoded, matching
/// the Content Lake wire format. A null value is sent as JSON `null`; omit the
/// key entirely to leave the parameter unbound.
String encodeQueryString(String query, Map<String, Object?> params) {
  final buffer = StringBuffer('?query=${formUrlEncode(query)}');
  params.forEach((key, value) {
    buffer
      ..write('&')
      ..write(formUrlEncode('\$$key'))
      ..write('=')
      ..write(formUrlEncode(jsonEncode(value)));
  });
  return buffer.toString();
}
