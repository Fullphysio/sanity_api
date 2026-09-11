import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => sanityWarn = (_) {});

  SanityClient clientFor(
    List<int> statuses, {
    int maxRetries = 5,
    List<http.Request>? log,
  }) {
    var call = 0;
    return SanityClient(
      SanityConfig(
        projectId: 'abc123',
        dataset: 'production',
        apiVersion: '2024-05-03',
        maxRetries: maxRetries,
        retryDelay: (_) => Duration.zero,
      ),
      httpClient: MockClient((request) async {
        log?.add(request);
        final status =
            statuses[call < statuses.length ? call : statuses.length - 1];
        call++;
        return http.Response(
          jsonEncode({'result': null}),
          status,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
  }

  test('retries 429, 502 and 503 on queries', () async {
    for (final status in [429, 502, 503]) {
      final log = <http.Request>[];
      final client = clientFor([status, status, 200], log: log);
      await client.fetch<Object?>('*');
      expect(log, hasLength(3), reason: 'status $status should be retried');
    }
  });

  test('does not retry 400, 401, 404 or 500', () async {
    for (final status in [400, 401, 404, 500]) {
      final log = <http.Request>[];
      final client = clientFor([status], log: log);
      await expectLater(
        client.fetch<Object?>('*'),
        throwsA(isA<SanityRequestException>()),
      );
      expect(log, hasLength(1), reason: 'status $status should not be retried');
    }
  });

  test('gives up after maxRetries and throws the last error', () async {
    final log = <http.Request>[];
    final client = clientFor([503], maxRetries: 2, log: log);
    await expectLater(
      client.fetch<Object?>('*'),
      throwsA(isA<SanityServerException>()
          .having((error) => error.statusCode, 'statusCode', 503)),
    );
    expect(log, hasLength(3));
  });

  test('maxRetries: 0 disables retrying entirely', () async {
    final log = <http.Request>[];
    final client = clientFor([503], maxRetries: 0, log: log);
    await expectLater(
      client.fetch<Object?>('*'),
      throwsA(isA<SanityServerException>()),
    );
    expect(log, hasLength(1));
  });

  test('retries a POST fallback query, but not a mutation', () async {
    final queryLog = <http.Request>[];
    final queryClient = clientFor([503, 200], log: queryLog);
    await queryClient.fetch<Object?>('a' * 12000);
    expect(queryLog.first.method, 'POST');
    expect(queryLog, hasLength(2));

    final mutationLog = <http.Request>[];
    final mutationClient = clientFor([503], log: mutationLog);
    await expectLater(
      mutationClient.create({'_type': 'x'}),
      throwsA(isA<SanityServerException>()),
    );
    expect(mutationLog, hasLength(1));
  });

  test('a transport failure surfaces as SanityTransportException', () async {
    final client = SanityClient(
      SanityConfig(
        projectId: 'abc123',
        dataset: 'production',
        apiVersion: '2024-05-03',
        maxRetries: 0,
      ),
      httpClient: MockClient((_) async => throw const SocketishError()),
    );
    await expectLater(
      client.fetch<Object?>('*'),
      throwsA(isA<SanityTransportException>()),
    );
  });
}

class SocketishError implements Exception {
  const SocketishError();
  @override
  String toString() => 'connection refused';
}
