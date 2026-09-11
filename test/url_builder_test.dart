import 'package:sanity_api/sanity_api.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() => sanityWarn = (_) {});

  final client = SanityClient(
    SanityConfig(
      projectId: 'abc123',
      dataset: 'production',
      apiVersion: '2024-05-03',
    ),
  );

  test('parses an image reference into a CDN filename', () {
    const ref = SanityAssetRef('image-Tb9Ew8CXIwaY6R1kjMvI0uRR-2000x3000-jpg');
    expect(ref.imageFilename, 'Tb9Ew8CXIwaY6R1kjMvI0uRR-2000x3000.jpg');
    expect(ref.extension, 'jpg');
    expect(ref.isGif, isFalse);
  });

  test('parses a file reference into a CDN filename', () {
    const ref =
        SanityAssetRef('file-2a29e0f3f4b4c1e0d1a2b3c4d5e6f7a8b9c0d1e2-pdf');
    expect(ref.fileFilename, '2a29e0f3f4b4c1e0d1a2b3c4d5e6f7a8b9c0d1e2.pdf');
  });

  test('builds an image URL with transform parameters', () {
    final url = client
        .image(const SanityAssetRef('image-abc-800x600-jpg'))
        .width(400)
        .height(300)
        .quality(90)
        .fit(SanityImageFit.clip)
        .format(SanityImageFormat.webp)
        .build();

    expect(url.host, 'cdn.sanity.io');
    expect(url.path, '/images/abc123/production/abc-800x600.jpg');
    expect(url.queryParameters, {
      'w': '400',
      'h': '300',
      'q': '90',
      'fit': 'clip',
      'fm': 'webp',
    });
  });

  test('auto format emits auto=format rather than fm', () {
    final url = client
        .image(const SanityAssetRef('image-abc-800x600-jpg'))
        .format(SanityImageFormat.auto)
        .build();
    expect(url.queryParameters, {'auto': 'format'});
  });

  test('GIFs are never given transform parameters', () {
    final url = client
        .image(const SanityAssetRef('image-abc-800x600-gif'))
        .width(400)
        .quality(90)
        .format(SanityImageFormat.webp)
        .build();
    expect(url.hasQuery, isFalse);
    expect(url.path, '/images/abc123/production/abc-800x600.gif');
  });

  test('builds a file URL', () {
    final url = client.file(const SanityAssetRef('file-abc-pdf')).build();
    expect(url.toString(),
        'https://cdn.sanity.io/files/abc123/production/abc.pdf');
  });

  test('rejects a malformed image reference', () {
    expect(
      () => const SanityAssetRef('image-abc').imageFilename,
      throwsA(isA<ArgumentError>()),
    );
  });
}
