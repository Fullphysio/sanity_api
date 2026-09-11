import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

/// Every request target here is compared against `test/fixtures/url_golden.json`,
/// captured from the reference JavaScript client (@sanity/client 7.20.0) driving
/// a live HTTP server.
void main() {
  setUpAll(() => sanityWarn = (_) {});

  final golden = jsonDecode(
    File('test/fixtures/url_golden.json').readAsStringSync(),
  ) as Map<String, Object?>;

  late List<http.Request> captured;

  SanityClient makeClient(Object? Function() body) {
    captured = [];
    return SanityClient(
      SanityConfig(
        projectId: 'abc123',
        dataset: 'production',
        apiVersion: '2024-05-03',
        useProjectHostname: false,
        useCdn: false,
        apiHost: 'http://127.0.0.1:1',
        maxRetries: 0,
      ),
      httpClient: MockClient((request) async {
        captured.add(request);
        return http.Response(
          jsonEncode(body()),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
  }

  void conforms(
    String name,
    Future<void> Function(SanityClient client) exercise, {
    Object? Function()? body,
  }) {
    test(name, () async {
      final client = makeClient(
        body ?? () => {'result': null, 'ms': 1},
      );
      await exercise(client);
      final expected = golden[name]! as Map<String, Object?>;
      final request = captured.single;
      final target = '${request.url.path}'
          '${request.url.query.isEmpty ? '' : '?${request.url.query}'}';
      expect(request.method, expected['method']);
      expect(target, expected['target'], reason: 'diverges from JS client');
    });
  }

  conforms('plain', (c) => c.fetch<Object?>('*[_type == "exercise"]'));
  conforms(
    'params',
    (c) => c.fetch<Object?>(
      r'*[_type == $t && n == $n]',
      params: {'t': 'exercise', 'n': 3},
    ),
  );
  conforms(
    'listParam',
    (c) => c.fetch<Object?>(r'*[_id in $ids]', params: {
      'ids': ['a', 'b'],
    }),
  );
  conforms(
    'specialChars',
    (c) =>
        c.fetch<Object?>(r'*[title == $q]', params: {'q': 'a b&c=d+e/f?g#h'}),
  );
  conforms(
    'unicodeParam',
    (c) => c.fetch<Object?>(r'*[t == $t]', params: {'t': 'éàü 中文'}),
  );
  conforms(
    'nullParam',
    (c) =>
        c.fetch<Object?>(r'*[a == $a && b == $b]', params: {'a': null, 'b': 1}),
  );
  conforms(
    'nestedParam',
    (c) => c.fetch<Object?>(r'*[a == $o]', params: {
      'o': {
        'x': [
          1,
          {'y': 'z'},
        ],
      },
    }),
  );
  conforms(
    'boolParam',
    (c) => c.fetch<Object?>(r'*[a == $b]', params: {'b': true}),
  );
  conforms(
    'perspectivePublished',
    (c) => c.fetch<Object?>('*', perspective: SanityPerspective.published),
  );
  conforms(
    'perspectiveDrafts',
    (c) => c.fetch<Object?>('*', perspective: SanityPerspective.drafts),
  );
  conforms(
    'perspectiveStack',
    (c) => c.fetch<Object?>(
      '*',
      perspective: SanityPerspective.stack(['r1', 'drafts']),
    ),
  );
  conforms('tagged', (c) => c.fetch<Object?>('*', tag: 'my-tag'));
  conforms(
    'getDocument',
    (c) => c.getDocument('doc1'),
    body: () => {'documents': <Object?>[]},
  );
  conforms(
    'getDocuments',
    (c) => c.getDocuments(['doc1', 'doc2']),
    body: () => {'documents': <Object?>[]},
  );
  conforms(
    'mutateCreate',
    (c) => c.create({'_type': 'x', 'title': 'T'}),
    body: () => {'transactionId': 't', 'results': <Object?>[]},
  );
  conforms(
    'mutateDelete',
    (c) => c.deleteById('doc1'),
    body: () => {'transactionId': 't', 'results': <Object?>[]},
  );
  conforms(
    'mutateTransaction',
    (c) => c.transaction().create({'_type': 'x'}).delete('d2').commit(),
    body: () => {'transactionId': 't', 'results': <Object?>[]},
  );
  conforms(
    'mutateDryRun',
    (c) => c.mutate(
      [
        {
          'create': <String, Object?>{'_type': 'x'}
        },
      ],
      options: const MutationOptions(
        dryRun: true,
        visibility: SanityVisibility.async,
        autoGenerateArrayKeys: true,
      ),
    ),
    body: () => {'transactionId': 't', 'results': <Object?>[]},
  );
}
