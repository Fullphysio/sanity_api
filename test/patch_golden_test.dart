import 'dart:convert';
import 'dart:io';

import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

/// Every case here is compared against `test/fixtures/patch_golden.json`, which
/// was produced by the reference JavaScript client (@sanity/client 7.20.0).
void main() {
  final golden = jsonDecode(
    File('test/fixtures/patch_golden.json').readAsStringSync(),
  ) as Map<String, Object?>;

  void matches(String name, SanityPatch patch) {
    test(name, () {
      expect(patch.serialize(), golden[name],
          reason: 'diverges from JS client');
    });
  }

  const doc = DocumentIdSelection('doc1');

  matches('set', SanityPatch(doc).set({'title': 'A', 'nested.prop': 1}));
  matches('setThenSet', SanityPatch(doc).set({'a': 1}).set({'b': 2}));
  matches('setIfMissing', SanityPatch(doc).setIfMissing({'a': 1}));
  matches('unsetTwice', SanityPatch(doc).unset(['a']).unset(['b', 'c']));
  matches('incDec', SanityPatch(doc).inc({'n': 1}).dec({'m': 2}));
  matches('ifRev', SanityPatch(doc).set({'a': 1}).ifRevisionId('rev1'));
  matches(
      'append',
      SanityPatch(doc).append('comments', [
        {'x': 1},
      ]));
  matches(
      'prepend',
      SanityPatch(doc).prepend('comments', [
        {'x': 1},
      ]));
  matches(
    'insertDouble',
    SanityPatch(doc).insert(InsertLocation.before, 'a[0]', [1]).insert(
        InsertLocation.after, 'a[-1]', [2]),
  );
  matches('spliceNoCount', SanityPatch(doc).splice('a', 2));
  matches(
    'spliceCount',
    SanityPatch(doc).splice('a', 2, deleteCount: 3, items: [9]),
  );
  matches(
    'spliceNegStart',
    SanityPatch(doc).splice('a', -2, deleteCount: 1, items: [9]),
  );
  matches('spliceNegStartAll', SanityPatch(doc).splice('a', -2));
  matches(
    'spliceZero',
    SanityPatch(doc).splice('a', 0, deleteCount: 0, items: [9]),
  );
  matches(
    'spliceMinusOne',
    SanityPatch(doc).splice('a', 1, deleteCount: -1, items: [9]),
  );
  matches(
    'idsSelection',
    SanityPatch(const DocumentIdsSelection(['d1', 'd2'])).set({'a': 1}),
  );
  matches(
    'querySelection',
    SanityPatch(const QuerySelection('*[_type=="x"]', params: {'t': 'x'}))
        .set({'a': 1}),
  );
  matches(
    'queryNoParams',
    SanityPatch(const QuerySelection('*[_type=="x"]')).set({'a': 1}),
  );

  test('key order matches the JS client for the insert merge quirk', () {
    final serialized = (SanityPatch(doc)
            .insert(InsertLocation.before, 'a[0]', [1]).insert(
                InsertLocation.after, 'a[-1]', [2]).serialize()['insert']!
        as Map<String, Object?>);
    expect(serialized.keys.toList(), ['before', 'items', 'after']);
  });
}
