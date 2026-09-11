import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => sanityWarn = (_) {});

  group('apiVersion', () {
    test('accepts 1, X and dates, stripping a leading v', () {
      expect(SanityConfig(projectId: 'p', apiVersion: '1').apiVersion, '1');
      expect(SanityConfig(projectId: 'p', apiVersion: 'vX').apiVersion, 'X');
      expect(
        SanityConfig(projectId: 'p', apiVersion: 'v2024-05-03').apiVersion,
        '2024-05-03',
      );
    });

    test('rejects anything else', () {
      for (final bad in ['2024-5-3', '2024-13-01', 'latest', '2']) {
        expect(
          () => SanityConfig(projectId: 'p', apiVersion: bad),
          throwsA(isA<ArgumentError>()),
          reason: bad,
        );
      }
    });
  });

  group('url construction', () {
    test('uses the project hostname and swaps in the CDN host', () {
      final config = SanityConfig(
        projectId: 'abc123',
        dataset: 'production',
        apiVersion: '2024-05-03',
      );
      expect(config.url, 'https://abc123.api.sanity.io/v2024-05-03');
      expect(config.cdnUrl, 'https://abc123.apicdn.sanity.io/v2024-05-03');
    });

    test('keeps a custom apiHost off the CDN host', () {
      final config = SanityConfig(
        projectId: 'abc123',
        apiVersion: '2024-05-03',
        apiHost: 'https://api.eu.sanity.io',
      );
      expect(config.url, 'https://abc123.api.eu.sanity.io/v2024-05-03');
      expect(config.cdnUrl, 'https://abc123.api.eu.sanity.io/v2024-05-03');
    });

    test('falls back to a path form without the project hostname', () {
      final config = SanityConfig(
        projectId: 'abc123',
        apiVersion: '2024-05-03',
        useProjectHostname: false,
      );
      expect(config.url, 'https://api.sanity.io/v2024-05-03');
      expect(config.cdnUrl, config.url);
    });
  });

  group('requestTagPrefix', () {
    test('strips trailing dots', () {
      final config = SanityConfig(projectId: 'p', apiVersion: '1', requestTagPrefix: 'app...');
      expect(config.requestTagPrefix, 'app');
    });

    test('rejects an invalid prefix', () {
      expect(
        () => SanityConfig(projectId: 'p', apiVersion: '1', requestTagPrefix: 'a b'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('dataset and projectId are validated', () {
    expect(
      () => SanityConfig(projectId: 'p', dataset: 'Not Valid'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => SanityConfig(projectId: 'has space'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('requireDataset throws when no dataset is configured', () {
    expect(
      () => SanityConfig(projectId: 'p', apiVersion: '1').requireDataset(),
      throwsA(isA<StateError>()),
    );
  });
}
