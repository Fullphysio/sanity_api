/// How an image is fitted to the requested dimensions.
enum SanityImageFit {
  /// Scale down to fit inside the box, preserving aspect ratio.
  clip,

  /// Crop to fill the box exactly.
  crop,

  /// Fill the box, padding with the background colour.
  fill,

  /// Like [fill], but never scales up.
  fillmax,

  /// Scale to fill the box, cropping the overflow.
  max,

  /// Scale down only, preserving aspect ratio.
  min,

  /// Stretch to the box, ignoring aspect ratio.
  scale,
}

/// Output format for an image transform.
enum SanityImageFormat {
  /// Let the CDN negotiate the best format for the client.
  auto,

  /// JPEG.
  jpg,

  /// PNG.
  png,

  /// WebP.
  webp,
}

/// A parsed Sanity asset reference such as `image-abc123-800x600-jpg`.
class SanityAssetRef {
  /// Wraps a raw asset reference string.
  const SanityAssetRef(this.ref);

  /// The reference exactly as stored in the document.
  final String ref;

  /// The file extension, lowercased.
  String get extension {
    final parts = ref.split('-');
    return parts.isEmpty ? '' : parts.last.toLowerCase();
  }

  /// Whether the asset is an animated GIF, which must not be transcoded.
  bool get isGif => extension == 'gif';

  /// The CDN filename for an image reference, `<hash>-<dimensions>.<ext>`.
  String get imageFilename {
    final parts = ref.split('-');
    if (parts.length < 4) {
      throw ArgumentError('Not a valid Sanity image reference: $ref');
    }
    return '${parts[1]}-${parts[2]}.${parts[3]}';
  }

  /// The CDN filename for a file reference, `<hash>.<ext>`.
  String get fileFilename {
    final parts = ref.split('-');
    if (parts.length < 3) {
      throw ArgumentError('Not a valid Sanity file reference: $ref');
    }
    return '${parts.skip(1).take(parts.length - 2).join('-')}.${parts.last}';
  }
}

/// Builds a `cdn.sanity.io` image URL with transform parameters.
///
/// Transform parameters are skipped for GIFs, which the CDN cannot transcode
/// without losing animation.
class SanityImageUrlBuilder {
  /// Creates a builder for [ref] within the given project and dataset.
  SanityImageUrlBuilder({
    required this.projectId,
    required this.dataset,
    required this.ref,
  });

  /// The Sanity project id.
  final String projectId;

  /// The dataset holding the asset.
  final String dataset;

  /// The image being addressed.
  final SanityAssetRef ref;

  final Map<String, String> _params = {};

  /// Sets the target width in pixels.
  SanityImageUrlBuilder width(int value) => _set('w', '$value');

  /// Sets the target height in pixels.
  SanityImageUrlBuilder height(int value) => _set('h', '$value');

  /// Sets JPEG/WebP quality, 0–100.
  SanityImageUrlBuilder quality(int value) => _set('q', '$value');

  /// Sets the device pixel ratio multiplier.
  SanityImageUrlBuilder dpr(num value) => _set('dpr', '$value');

  /// Applies a gaussian blur, 0–2000.
  SanityImageUrlBuilder blur(int value) => _set('blur', '$value');

  /// Sets how the image is fitted to the requested box.
  SanityImageUrlBuilder fit(SanityImageFit value) => _set('fit', value.name);

  /// Sets the output format. [SanityImageFormat.auto] emits `auto=format`.
  SanityImageUrlBuilder format(SanityImageFormat value) =>
      value == SanityImageFormat.auto
          ? _set('auto', 'format')
          : _set('fm', value.name);

  /// Sets an arbitrary transform parameter not covered by the typed methods.
  SanityImageUrlBuilder param(String name, String value) => _set(name, value);

  SanityImageUrlBuilder _set(String key, String value) {
    if (!ref.isGif) _params[key] = value;
    return this;
  }

  /// Builds the final CDN URL.
  Uri build() => Uri(
        scheme: 'https',
        host: 'cdn.sanity.io',
        path: 'images/$projectId/$dataset/${ref.imageFilename}',
        queryParameters: _params.isEmpty ? null : _params,
      );
}

/// Builds a `cdn.sanity.io` file URL.
class SanityFileUrlBuilder {
  /// Creates a builder for [ref] within the given project and dataset.
  const SanityFileUrlBuilder({
    required this.projectId,
    required this.dataset,
    required this.ref,
  });

  /// The Sanity project id.
  final String projectId;

  /// The dataset holding the asset.
  final String dataset;

  /// The file being addressed.
  final SanityAssetRef ref;

  /// Builds the final CDN URL.
  Uri build() => Uri(
        scheme: 'https',
        host: 'cdn.sanity.io',
        path: 'files/$projectId/$dataset/${ref.fileFilename}',
      );
}
