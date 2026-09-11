import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

void main() {
  test('classifies ids', () {
    expect(isDraftId('drafts.foo'), isTrue);
    expect(isVersionId('versions.summer.foo'), isTrue);
    expect(isPublishedId('foo'), isTrue);
    expect(isPublishedId('drafts.foo'), isFalse);
  });

  test('derives published ids', () {
    expect(getPublishedId('foo'), 'foo');
    expect(getPublishedId('drafts.foo'), 'foo');
    expect(getPublishedId('versions.summer.foo'), 'foo');
    expect(getPublishedId('versions.summer.foo.bar'), 'foo.bar');
  });

  test('derives draft ids from any form', () {
    expect(getDraftId('foo'), 'drafts.foo');
    expect(getDraftId('drafts.foo'), 'drafts.foo');
    expect(getDraftId('versions.summer.foo'), 'drafts.foo');
  });

  test('derives version ids and rejects reserved names', () {
    expect(getVersionId('foo', 'summer'), 'versions.summer.foo');
    expect(getVersionId('drafts.foo', 'summer'), 'versions.summer.foo');
    expect(() => getVersionId('foo', 'drafts'), throwsA(isA<ArgumentError>()));
    expect(
        () => getVersionId('foo', 'published'), throwsA(isA<ArgumentError>()));
  });

  test('extracts the release name', () {
    expect(getVersionFromId('versions.summer-drop.foo'), 'summer-drop');
    expect(getVersionFromId('drafts.foo'), isNull);
    expect(getVersionFromId('foo'), isNull);
  });
}
