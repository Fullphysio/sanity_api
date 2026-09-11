/// The perspective a query is evaluated against.
///
/// Use the constants for the single-value perspectives, or [SanityPerspective.stack]
/// to layer releases on top of one another. A stack always bypasses the CDN, as
/// does [drafts], because the API rejects those combinations on the CDN host.
class SanityPerspective {
  const SanityPerspective._(this._values, {required this.isStack});

  /// Every document, drafts and published alike, exactly as stored.
  static const SanityPerspective raw =
      SanityPerspective._(['raw'], isStack: false);

  /// Only published documents.
  static const SanityPerspective published =
      SanityPerspective._(['published'], isStack: false);

  /// Drafts overlaid on published documents.
  static const SanityPerspective drafts =
      SanityPerspective._(['drafts'], isStack: false);

  /// Former name of [drafts].
  @Deprecated('Renamed to `drafts`; will be removed in a future API version')
  static const SanityPerspective previewDrafts =
      SanityPerspective._(['previewDrafts'], isStack: false);

  /// Layers [perspectives] — release ids, `drafts` and `published` — highest
  /// precedence first.
  ///
  /// Throws [ArgumentError] if `raw` appears alongside anything else, which the
  /// API does not accept.
  factory SanityPerspective.stack(List<String> perspectives) {
    if (perspectives.length > 1 && perspectives.contains('raw')) {
      throw ArgumentError(
        'Invalid API perspective value: "raw". The raw-perspective can not be '
        'combined with other perspectives',
      );
    }
    return SanityPerspective._(List.unmodifiable(perspectives), isStack: true);
  }

  final List<String> _values;

  /// Whether this perspective was built with [SanityPerspective.stack].
  final bool isStack;

  /// The wire value, comma-joined for a stack.
  String get value => _values.join(',');

  /// Whether using this perspective forces a request off the CDN.
  bool get forcesCdnOff =>
      (isStack && _values.isNotEmpty) ||
      _values.first == 'drafts' ||
      _values.first == 'previewDrafts';

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is SanityPerspective &&
      other.isStack == isStack &&
      other.value == value;

  @override
  int get hashCode => Object.hash(value, isStack);
}
