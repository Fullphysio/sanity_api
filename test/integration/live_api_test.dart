@Tags(['integration'])
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

/// Exercises the real Content Lake over HTTP.
///
/// Reads its target from `SANITY_TEST_PROJECT_ID` and `SANITY_TEST_DATASET` and
/// skips itself when they are unset, so a checkout without configuration still
/// passes. Every assertion is structural: nothing here depends on how much
/// content the dataset happens to hold.
void main() {
  // GitHub Actions supplies an empty string for a variable that is not defined,
  // so absence has to be treated the same as blank.
  final projectId = Platform.environment['SANITY_TEST_PROJECT_ID'] ?? '';
  final dataset = Platform.environment['SANITY_TEST_DATASET'] ?? '';

  if (projectId.isEmpty || dataset.isEmpty) {
    test('live API', () {}, skip: 'SANITY_TEST_PROJECT_ID/DATASET not set');
    return;
  }

  late SanityClient client;

  setUpAll(() {
    sanityWarn = (_) {};
    client = SanityClient(
      SanityConfig(
        projectId: projectId,
        dataset: dataset,
        apiVersion: '2024-05-03',
      ),
    );
  });

  tearDownAll(() => client.close());

  test('runs a GROQ query over GET', () async {
    final count = await client.fetch<int>('count(*[])');
    expect(count, isA<int>());
    expect(count, greaterThanOrEqualTo(0));
  });

  test('binds parameters and applies a projection', () async {
    final docs = await client.fetch<List<Object?>>(
      r'*[_type == $type][0...1]{_id, _type}',
      params: {'type': 'sanity.imageAsset'},
    );
    for (final doc in docs) {
      expect(doc, isA<Map<String, Object?>>());
      expect((doc! as Map<String, Object?>)['_id'], isA<String>());
    }
  });

  test(
      'falls back to POST for a query over the size limit, with the same '
      'result as GET', () async {
    // The padding sits in a GROQ comment so it lengthens the request without
    // costing the server anything: a filter against it scans every document.
    final padding = 'x' * 12000;
    final long = 'count(*[]) // $padding';
    expect(long.length, greaterThan(getQuerySizeLimit));

    final viaPost = await client.fetch<int>(long);
    final viaGet = await client.fetch<int>('count(*[])');
    expect(viaPost, viaGet);
  });

  test('exposes server timing and echoes the query on a full fetch', () async {
    final response = await client.fetchFull<int>('count(*[])');
    expect(response.result, isA<int>());
    expect(response.ms, isA<int>());
    expect(response.query, isNotNull);
  });

  test('fetches documents by id and reports missing ones as null', () async {
    final docs = await client.fetch<List<Object?>>('*[0...1]{_id}');
    if (docs.isEmpty) return;
    final id = (docs.first! as Map<String, Object?>)['_id']! as String;

    final found = await client.getDocument(id);
    expect(found?['_id'], id);

    final missing = await client.getDocuments([id, 'definitely-not-a-real-id']);
    expect(missing, hasLength(2));
    expect(missing[0]?['_id'], id);
    expect(missing[1], isNull);
  });

  test('builds an image URL the CDN actually serves', () async {
    final refs = await client.fetch<List<Object?>>(
      '*[_type == "sanity.imageAsset"][0...1]._id',
    );
    if (refs.isEmpty) return;

    final url = client
        .image(SanityAssetRef(refs.first! as String))
        .width(64)
        .quality(70)
        .build();

    final response = await http.head(url);
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('image/'));
  });

  test('reports a GROQ syntax error with a code frame', () async {
    await expectLater(
      client.fetch<Object?>('*[_type == "x"'),
      throwsA(
        isA<SanityClientException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('^')),
      ),
    );
  });

  test('rejects an unauthenticated write', () async {
    await expectLater(
      client.createOrReplace({
        '_id': 'sanity-api-integration-should-never-persist',
        '_type': 'sanityApiIntegrationProbe',
      }),
      throwsA(
        isA<SanityClientException>()
            .having((e) => e.statusCode, 'statusCode', anyOf(401, 403)),
      ),
    );
  });
}
