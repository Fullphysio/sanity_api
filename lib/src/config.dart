import 'perspective.dart';
import 'validators.dart';
import 'warnings.dart';

const String _defaultCdnHost = 'apicdn.sanity.io';
const String _defaultApiHost = 'https://api.sanity.io';

final RegExp _apiVersionDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _trailingDots = RegExp(r'\.+$');

/// Immutable configuration for a [SanityClient].
///
/// Validation runs in the constructor, so an invalid configuration throws
/// immediately rather than on first request.
class SanityConfig {
  /// Creates and validates a configuration.
  ///
  /// [apiVersion] must be `1`, `X` (experimental), or a `YYYY-MM-DD` date; a
  /// leading `v` is stripped. Pinning a date is strongly recommended.
  ///
  /// [useCdn] defaults to true. Use `false` for any client that writes, so reads
  /// are not served a stale cached copy of what it just committed.
  factory SanityConfig({
    required String projectId,
    String? dataset,
    String apiVersion = '1',
    bool useCdn = true,
    String? token,
    SanityPerspective? perspective,
    String apiHost = _defaultApiHost,
    String? requestTagPrefix,
    Duration timeout = const Duration(minutes: 5),
    int maxRetries = 5,
    Duration Function(int attempt)? retryDelay,
    Map<String, String> headers = const {},
    List<Pattern> ignoreWarnings = const [],
    bool useProjectHostname = true,
  }) {
    if (useProjectHostname) {
      if (projectId.isEmpty) {
        throw ArgumentError('Configuration must contain `projectId`');
      }
      validateProjectId(projectId);
    }
    if (dataset != null) validateDataset(dataset);

    final normalizedPrefix = (requestTagPrefix == null ||
            requestTagPrefix.isEmpty)
        ? null
        : validateRequestTag(requestTagPrefix).replaceAll(_trailingDots, '');

    final normalizedApiVersion =
        apiVersion.startsWith('v') ? apiVersion.substring(1) : apiVersion;
    _validateApiVersion(normalizedApiVersion);

    if (apiVersion == '1') {
      sanityWarn(
        'Using the Sanity client without specifying an API version is deprecated. '
        'Pin an apiVersion such as `2024-05-03`.',
      );
    }

    return SanityConfig._(
      projectId: projectId,
      dataset: dataset,
      apiVersion: normalizedApiVersion,
      useCdn: useCdn,
      token: token,
      perspective: perspective,
      apiHost: apiHost,
      requestTagPrefix: normalizedPrefix,
      timeout: timeout,
      maxRetries: maxRetries,
      retryDelay: retryDelay ?? _defaultRetryDelay,
      headers: Map.unmodifiable(headers),
      ignoreWarnings: List.unmodifiable(ignoreWarnings),
      useProjectHostname: useProjectHostname,
    );
  }

  SanityConfig._({
    required this.projectId,
    required this.dataset,
    required this.apiVersion,
    required this.useCdn,
    required this.token,
    required this.perspective,
    required this.apiHost,
    required this.requestTagPrefix,
    required this.timeout,
    required this.maxRetries,
    required this.retryDelay,
    required this.headers,
    required this.ignoreWarnings,
    required this.useProjectHostname,
  });

  /// The Sanity project id.
  final String projectId;

  /// The dataset queries and mutations target. Required for all content operations.
  final String? dataset;

  /// The pinned API version, without its leading `v`.
  final String apiVersion;

  /// Whether reads may be served from the CDN. Always false for mutations.
  final bool useCdn;

  /// Bearer token. Required for drafts and for every write.
  final String? token;

  /// Default perspective applied to queries that do not override it.
  final SanityPerspective? perspective;

  /// API host, without a trailing slash.
  final String apiHost;

  /// Prefix joined to every per-request tag with a `.`.
  final String? requestTagPrefix;

  /// Per-request timeout.
  final Duration timeout;

  /// Maximum retry attempts. Zero disables retries entirely.
  final int maxRetries;

  /// Backoff before the given retry attempt, one-based.
  final Duration Function(int attempt) retryDelay;

  /// Headers merged into every request, lowest precedence.
  final Map<String, String> headers;

  /// Warnings from the `x-sanity-warning` response header matching any of these
  /// are suppressed.
  final List<Pattern> ignoreWarnings;

  /// Whether to address the project by hostname rather than by path.
  final bool useProjectHostname;

  /// Whether [apiHost] is still the stock host, which is what makes a CDN host
  /// available.
  bool get isDefaultApi => apiHost == _defaultApiHost;

  /// Base URL for requests that must reach the origin API.
  String get url {
    if (!useProjectHostname) return '$apiHost/v$apiVersion';
    final parts = apiHost.split('://');
    return '${parts[0]}://$projectId.${parts[1]}/v$apiVersion';
  }

  /// Base URL for requests that may be served by the CDN.
  String get cdnUrl {
    if (!useProjectHostname) return url;
    final parts = apiHost.split('://');
    final host = isDefaultApi ? _defaultCdnHost : parts[1];
    return '${parts[0]}://$projectId.$host/v$apiVersion';
  }

  /// The dataset, or a thrown [StateError] when none is configured.
  String requireDataset() {
    final value = dataset;
    if (value == null) {
      throw StateError('`dataset` must be provided to perform queries');
    }
    return value;
  }

  /// A copy of this configuration with the given fields replaced.
  SanityConfig copyWith({
    String? projectId,
    String? dataset,
    String? apiVersion,
    bool? useCdn,
    String? token,
    SanityPerspective? perspective,
    String? apiHost,
    String? requestTagPrefix,
    Duration? timeout,
    int? maxRetries,
    Duration Function(int attempt)? retryDelay,
    Map<String, String>? headers,
    List<Pattern>? ignoreWarnings,
    bool? useProjectHostname,
  }) {
    return SanityConfig(
      projectId: projectId ?? this.projectId,
      dataset: dataset ?? this.dataset,
      apiVersion: apiVersion ?? this.apiVersion,
      useCdn: useCdn ?? this.useCdn,
      token: token ?? this.token,
      perspective: perspective ?? this.perspective,
      apiHost: apiHost ?? this.apiHost,
      requestTagPrefix: requestTagPrefix ?? this.requestTagPrefix,
      timeout: timeout ?? this.timeout,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      headers: headers ?? this.headers,
      ignoreWarnings: ignoreWarnings ?? this.ignoreWarnings,
      useProjectHostname: useProjectHostname ?? this.useProjectHostname,
    );
  }
}

void _validateApiVersion(String apiVersion) {
  if (apiVersion == '1' || apiVersion == 'X') return;
  if (!_apiVersionDatePattern.hasMatch(apiVersion) ||
      !_isRealDate(apiVersion)) {
    throw ArgumentError(
      'Invalid API version string, expected `1` or date in format `YYYY-MM-DD`',
    );
  }
}

bool _isRealDate(String value) {
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null) return false;
  if (!parsed.toIso8601String().startsWith(value)) return false;
  return parsed.millisecondsSinceEpoch > 0;
}

Duration _defaultRetryDelay(int attempt) =>
    Duration(milliseconds: 100 * (1 << attempt));
