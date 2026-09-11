import 'dart:convert';
import 'dart:typed_data';

import 'config.dart';
import 'transport.dart';
import 'validators.dart';

/// The kind of asset being uploaded.
enum SanityAssetType {
  /// An image, which the CDN can transform.
  image,

  /// Any other file.
  file,
}

/// Where an asset originally came from, recorded on the asset document.
class SanityAssetSource {
  /// Describes an upstream source.
  const SanityAssetSource({required this.id, required this.name, this.url});

  /// Identifier of the asset in the source system.
  final String id;

  /// Name of the source system.
  final String name;

  /// Link back to the asset in the source system.
  final String? url;
}

/// Uploads assets into a dataset.
class SanityAssets {
  /// Creates an asset client over [transport].
  const SanityAssets(this._transport, this._config);

  final SanityTransport _transport;
  final SanityConfig _config;

  /// Uploads [data] as an asset of [type] and returns the asset document.
  ///
  /// [extract] names the metadata Sanity should derive (`blurhash`, `exif`,
  /// `location`, `lqip`, `palette`); an empty list disables extraction entirely.
  /// [timeout] defaults to [Duration.zero], meaning no deadline, since uploads
  /// can be large.
  Future<Map<String, Object?>> upload(
    SanityAssetType type,
    Uint8List data, {
    String? filename,
    String? contentType,
    String? label,
    String? title,
    String? description,
    String? creditLine,
    SanityAssetSource? source,
    List<String>? extract,
    String? tag,
    String? token,
    Duration timeout = Duration.zero,
  }) async {
    validateAssetType(type.name);
    final dataset = _config.requireDataset();
    final meta = extract == null ? null : (extract.isEmpty ? const ['none'] : extract);

    final query = <String, String>{
      if (label != null) 'label': label,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (filename != null) 'filename': filename,
      if (meta != null) 'meta': meta.join(','),
      if (creditLine != null) 'creditLine': creditLine,
      if (source != null) 'sourceId': source.id,
      if (source != null) 'sourceName': source.name,
      if (source?.url != null) 'sourceUrl': source!.url!,
    };

    final endpoint = type == SanityAssetType.image ? 'images' : 'files';
    final response = await _transport.send(
      method: 'POST',
      path: 'assets/$endpoint/$dataset',
      query: query,
      bodyBytes: data,
      contentType: contentType,
      tag: tag,
      token: token,
      timeout: timeout,
    );

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw StateError('Unexpected asset upload response: ${response.body}');
    }
    final document = decoded['document'];
    if (document is! Map<String, Object?>) {
      throw StateError(
        'Asset upload response contained no document: ${response.body}',
      );
    }
    return document;
  }
}
