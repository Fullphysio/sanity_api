import 'dart:convert';
import 'dart:io';

import 'package:sanity_api/src/exceptions.dart';
import 'package:test/test.dart';

/// Compared against `test/fixtures/error_golden.json`, produced by the reference
/// JavaScript client (@sanity/client 7.20.0).
void main() {
  final golden = jsonDecode(
    File('test/fixtures/error_golden.json').readAsStringSync(),
  ) as Map<String, Object?>;

  const url = 'https://abc123.api.sanity.io/v2024-05-03/data/query/production';

  SanityRequestException build(
    int statusCode,
    Object body, {
    String contentType = 'application/json',
    String? statusMessage,
  }) =>
      buildRequestException(
        statusCode: statusCode,
        method: 'GET',
        url: url,
        statusMessage: statusMessage,
        contentType: contentType,
        rawBody: body is String ? body : jsonEncode(body),
        tag: 'fullphysio.test',
      );

  void matches(String name, SanityRequestException exception) {
    test(name, () {
      final expected = golden[name]! as Map<String, Object?>;
      expect(exception.message, expected['message'], reason: 'message diverges from JS client');
      expect(exception.statusCode, expected['statusCode']);
    });
  }

  matches(
    'boomStyle',
    build(401, {
      'statusCode': 401,
      'error': 'Unauthorized',
      'message': 'Session not found',
    }),
  );
  matches('errorStringOnly', build(400, {'error': 'Some plain error'}));
  matches('messageOnly', build(400, {'message': 'Just a message'}));
  matches(
    'mutationError',
    build(409, {
      'error': {
        'type': 'mutationError',
        'description': 'Mutation failed',
        'items': [
          {
            'error': {
              'type': 'documentNotFound',
              'description': 'Document a not found',
            },
          },
          {
            'error': {
              'type': 'documentNotFound',
              'description': 'Document b not found',
            },
          },
        ],
      },
    }),
  );
  matches(
    'mutationErrorTruncated',
    build(409, {
      'error': {
        'type': 'mutationError',
        'description': 'Mutation failed',
        'items': [
          for (var i = 0; i < 8; i++)
            {
              'error': {'type': 'x', 'description': 'item $i'},
            },
        ],
      },
    }),
  );
  matches(
    'queryParseError',
    build(400, {
      'error': {
        'type': 'queryParseError',
        'description': 'unexpected token',
        'query': '*[_type == "exercise"\n  && bad]',
        'start': 21,
        'end': 24,
      },
    }),
  );
  matches(
    'descriptionOnly',
    build(400, {
      'error': {'description': 'Dataset not found', 'other': 'x'},
    }),
  );
  matches(
    'nonJsonBody',
    build(502, 'gateway blew up', contentType: 'text/plain', statusMessage: 'Bad Gateway'),
  );
  matches(
    'emptyObject',
    build(418, <String, Object?>{}, statusMessage: "I'm a teapot"),
  );
  matches(
    'serverError',
    build(500, {
      'error': {'description': 'Internal error'},
    }),
  );

  test('4xx and 5xx map to distinct types', () {
    expect(build(404, <String, Object?>{}), isA<SanityClientException>());
    expect(build(503, <String, Object?>{}), isA<SanityServerException>());
  });

  test('the response body is retained, pretty-printed when JSON', () {
    final exception = build(400, {'error': 'nope'});
    expect(exception.responseBody, '{\n  "error": "nope"\n}');
  });
}
