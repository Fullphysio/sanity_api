import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

late List<http.Request> captured;

SanityClient clientFor(
  Object? Function() body, {
  SanityConfig? config,
  int status = 200,
  Map<String, String> headers = const {'content-type': 'application/json'},
}) {
  captured = [];
  final mock = MockClient((request) async {
    captured.add(request);
    final payload = body();
    return http.Response(
      payload is String ? payload : jsonEncode(payload),
      status,
      headers: headers,
    );
  });
  return SanityClient(
    config ??
        SanityConfig(
          projectId: 'abc123',
          dataset: 'production',
          apiVersion: '2024-05-03',
        ),
    httpClient: mock,
  );
}

Uri get lastUri => captured.single.url;

void main() {
  setUpAll(() => sanityWarn = (_) {});

  group('query transport', () {
    test('short queries go out as GET with the query embedded', () async {
      final client = clientFor(() => {'result': <Object?>[], 'ms': 3});
      await client.fetch<List<Object?>>(
        '*[_type == \$type]',
        params: {'type': 'exercise'},
      );

      final request = captured.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/v2024-05-03/data/query/production');
      expect(request.url.host, 'abc123.apicdn.sanity.io');
      expect(request.url.queryParameters['query'], '*[_type == \$type]');
      expect(request.url.queryParameters[r'$type'], '"exercise"');
      expect(request.body, isEmpty);
    });

    test('queries at or over 11264 encoded chars switch to POST', () async {
      final client = clientFor(() => {'result': <Object?>[]});
      final long = '*[_type == "x" && title == "${'a' * 11300}"]';
      await client.fetch<List<Object?>>(long);

      final request = captured.single;
      expect(request.method, 'POST');
      expect(request.url.queryParameters.containsKey('query'), isFalse);
      expect(jsonDecode(request.body), {'query': long, 'params': <String, Object?>{}});
    });

    test('the GET/POST boundary is strictly less-than', () async {
      // encodeQueryString yields '?query=' (7 chars) + the encoded query.
      final justUnder = 'a' * (11264 - 8);
      var client = clientFor(() => {'result': null});
      await client.fetch<Object?>(justUnder);
      expect(captured.single.method, 'GET');

      client = clientFor(() => {'result': null});
      await client.fetch<Object?>('a' * (11264 - 7));
      expect(captured.single.method, 'POST');
    });
  });

  group('perspective', () {
    test('published stays on the CDN', () async {
      final client = clientFor(() => {'result': null});
      await client.fetch<Object?>('*', perspective: SanityPerspective.published);
      expect(lastUri.host, 'abc123.apicdn.sanity.io');
      expect(lastUri.queryParameters['perspective'], 'published');
    });

    test('drafts forces the request off the CDN', () async {
      final client = clientFor(() => {'result': null});
      await client.fetch<Object?>('*', perspective: SanityPerspective.drafts);
      expect(lastUri.host, 'abc123.api.sanity.io');
      expect(lastUri.queryParameters['perspective'], 'drafts');
    });

    test('raw stays on the CDN', () async {
      final client = clientFor(() => {'result': null});
      await client.fetch<Object?>('*', perspective: SanityPerspective.raw);
      expect(lastUri.host, 'abc123.apicdn.sanity.io');
    });

    test('a stack is comma-joined and bypasses the CDN', () async {
      final client = clientFor(() => {'result': null});
      await client.fetch<Object?>(
        '*',
        perspective: SanityPerspective.stack(['summer-drop', 'drafts', 'published']),
      );
      expect(lastUri.queryParameters['perspective'], 'summer-drop,drafts,published');
      expect(lastUri.host, 'abc123.api.sanity.io');
    });

    test('raw cannot be stacked with anything else', () {
      expect(
        () => SanityPerspective.stack(['raw', 'drafts']),
        throwsA(isA<ArgumentError>()),
      );
      expect(SanityPerspective.stack(['raw']).value, 'raw');
    });
  });

  group('tagging', () {
    test('prefix and tag are joined with a dot', () async {
      final client = clientFor(
        () => {'result': null},
        config: SanityConfig(
          projectId: 'abc123',
          dataset: 'production',
          apiVersion: '2024-05-03',
          requestTagPrefix: 'fullphysio',
        ),
      );
      await client.fetch<Object?>('*', tag: 'exercises');
      expect(lastUri.queryParameters['tag'], 'fullphysio.exercises');
    });

    test('the joined tag is revalidated', () async {
      final client = clientFor(
        () => {'result': null},
        config: SanityConfig(
          projectId: 'abc123',
          dataset: 'production',
          apiVersion: '2024-05-03',
          requestTagPrefix: 'p' * 40,
        ),
      );
      await expectLater(
        client.fetch<Object?>('*', tag: 'q' * 40),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the prefix alone is sent when no per-call tag is given', () async {
      final client = clientFor(
        () => {'result': null},
        config: SanityConfig(
          projectId: 'abc123',
          dataset: 'production',
          apiVersion: '2024-05-03',
          requestTagPrefix: 'fullphysio',
        ),
      );
      await client.fetch<Object?>('*');
      expect(lastUri.queryParameters['tag'], 'fullphysio');
    });
  });

  group('mutations', () {
    test('always POST to the origin API, never the CDN', () async {
      final client = clientFor(() => {'transactionId': 't1', 'results': <Object?>[]});
      await client.createOrReplace({'_id': 'foo', '_type': 'bar'});

      final request = captured.single;
      expect(request.method, 'POST');
      expect(request.url.host, 'abc123.api.sanity.io');
      expect(request.url.path, '/v2024-05-03/data/mutate/production');
    });

    test('send the documented query parameters', () async {
      final client = clientFor(() => {'transactionId': 't1', 'results': <Object?>[]});
      await client.mutate(
        [
          {
            'create': <String, Object?>{'_type': 'x'}
          },
        ],
        options: const MutationOptions(
          dryRun: true,
          autoGenerateArrayKeys: true,
          visibility: SanityVisibility.deferred,
        ),
      );

      final query = lastUri.queryParameters;
      expect(query['returnIds'], 'true');
      expect(query['returnDocuments'], 'true');
      expect(query['visibility'], 'deferred');
      expect(query['dryRun'], 'true');
      expect(query['autoGenerateArrayKeys'], 'true');
    });

    test('returnDocuments:false omits the parameter entirely', () async {
      final client = clientFor(() => {'transactionId': 't1', 'results': <Object?>[]});
      await client.mutate(
        [
          {
            'create': <String, Object?>{'_type': 'x'}
          },
        ],
        options: const MutationOptions(returnDocuments: false),
      );
      expect(lastUri.queryParameters.containsKey('returnDocuments'), isFalse);
    });

    test('a transaction defaults to not returning documents', () async {
      final client = clientFor(() => {'transactionId': 't1', 'results': <Object?>[]});
      await client.transaction().create({'_type': 'x'}).delete('old-doc').commit();

      expect(lastUri.queryParameters.containsKey('returnDocuments'), isFalse);
      expect(jsonDecode(captured.single.body), {
        'mutations': [
          {
            'create': {'_type': 'x'},
          },
          {
            'delete': {'id': 'old-doc'},
          },
        ],
      });
    });

    test('a transaction id rides in the body', () async {
      final client = clientFor(() => {'transactionId': 'tx-1', 'results': <Object?>[]});
      await client.transaction().setTransactionId('tx-1').create({'_type': 'x'}).commit();

      final body = jsonDecode(captured.single.body) as Map<String, Object?>;
      expect(body['transactionId'], 'tx-1');
    });

    test('results expose ids and documents together', () async {
      final client = clientFor(() => {
            'transactionId': 'tx-9',
            'results': [
              {
                'id': 'a',
                'operation': 'update',
                'document': {'_id': 'a', 'title': 'A'},
              },
              {'id': 'b', 'operation': 'create'},
            ],
          });
      final result = await client.patchId('a').set({'title': 'A'}).commit();

      expect(result.transactionId, 'tx-9');
      expect(result.documentIds, ['a', 'b']);
      expect(result.documentId, 'a');
      expect(result.document, {'_id': 'a', 'title': 'A'});
      expect(result.results.first.operation, MutationOperation.update);
    });
  });

  group('assets', () {
    test('map options onto the documented query parameters', () async {
      final client = clientFor(() => {
            'document': {'_id': 'image-1', '_type': 'sanity.imageAsset'},
          });
      await client.assets.upload(
        SanityAssetType.image,
        Uint8List.fromList([1, 2, 3]),
        filename: 'slide.png',
        contentType: 'image/png',
        title: 'Slide',
        label: 'deck',
        creditLine: 'Fullphysio',
        extract: ['blurhash', 'palette'],
        source: const SanityAssetSource(
          id: 'gs-1',
          name: 'google-slides',
          url: 'https://example.com/1',
        ),
      );

      final request = captured.single;
      expect(request.url.path, '/v2024-05-03/assets/images/production');
      expect(request.method, 'POST');
      expect(request.headers['Content-Type'], 'image/png');
      final query = request.url.queryParameters;
      expect(query['filename'], 'slide.png');
      expect(query['title'], 'Slide');
      expect(query['label'], 'deck');
      expect(query['creditLine'], 'Fullphysio');
      expect(query['meta'], 'blurhash,palette');
      expect(query['sourceId'], 'gs-1');
      expect(query['sourceName'], 'google-slides');
      expect(query['sourceUrl'], 'https://example.com/1');
    });

    test('an empty extract list disables extraction', () async {
      final client = clientFor(() => {
            'document': {'_id': 'file-1'},
          });
      await client.assets.upload(SanityAssetType.file, Uint8List.fromList([1]), extract: []);
      expect(lastUri.queryParameters['meta'], 'none');
      expect(lastUri.path, '/v2024-05-03/assets/files/production');
    });

    test('omitting extract sends no meta parameter', () async {
      final client = clientFor(() => {
            'document': {'_id': 'file-1'},
          });
      await client.assets.upload(SanityAssetType.file, Uint8List.fromList([1]));
      expect(lastUri.queryParameters.containsKey('meta'), isFalse);
    });

    test('unwraps the document from the response envelope', () async {
      final client = clientFor(() => {
            'document': {'_id': 'image-1', 'url': 'https://cdn'},
          });
      final document = await client.assets.upload(SanityAssetType.image, Uint8List.fromList([1]));
      expect(document, {'_id': 'image-1', 'url': 'https://cdn'});
    });
  });
}
