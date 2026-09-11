import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'encoding.dart';
import 'exceptions.dart';
import 'validators.dart';
import 'warnings.dart';

const Set<int> _retriableStatusCodes = {429, 502, 503};

/// Carries out HTTP requests against the Content Lake, applying the client's
/// auth, tagging, retry and error-mapping rules.
class SanityTransport {
  /// Creates a transport bound to [config], optionally reusing [httpClient].
  SanityTransport(this.config, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// The configuration these requests are issued under.
  final SanityConfig config;

  final http.Client _httpClient;
  final bool _ownsClient;
  final Set<String> _seenWarnings = {};

  /// Releases the underlying HTTP client when this transport created it.
  void close() {
    if (_ownsClient) _httpClient.close();
  }

  /// Issues a request and decodes its JSON body.
  Future<Object?> requestJson({
    required String method,
    required String path,
    String? embeddedQueryString,
    Map<String, String> query = const {},
    Object? body,
    Map<String, String> headers = const {},
    String? tag,
    String? token,
    Duration? timeout,
    bool useCdn = false,
  }) async {
    final response = await send(
      method: method,
      path: path,
      embeddedQueryString: embeddedQueryString,
      query: query,
      bodyBytes: body == null ? null : utf8.encode(jsonEncode(body)),
      contentType: body == null ? null : 'application/json',
      headers: headers,
      tag: tag,
      token: token,
      timeout: timeout,
      useCdn: useCdn,
    );
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Issues a request, returning the raw response.
  ///
  /// A [timeout] of [Duration.zero] disables the deadline entirely, which is
  /// what asset uploads use. Throws [SanityRequestException] on any non-2xx
  /// status and [SanityTransportException] when no response was produced.
  Future<http.Response> send({
    required String method,
    required String path,
    String? embeddedQueryString,
    Map<String, String> query = const {},
    List<int>? bodyBytes,
    String? contentType,
    Map<String, String> headers = const {},
    String? tag,
    String? token,
    Duration? timeout,
    bool useCdn = false,
  }) async {
    final resolvedTag = _resolveTag(tag);
    final effectiveQuery = {
      ...query,
      if (resolvedTag != null) 'tag': resolvedTag,
    };
    final url = _buildUrl(
      path: path,
      embeddedQueryString: embeddedQueryString,
      query: effectiveQuery,
      useCdn: useCdn,
    );
    final requestHeaders = _buildHeaders(
      token: token,
      contentType: contentType,
      overrides: headers,
    );
    final deadline = timeout ?? config.timeout;
    final isRetriablePath =
        method == 'GET' || method == 'HEAD' || path.startsWith('data/query');

    var attempt = 0;
    while (true) {
      http.Response response;
      try {
        final request = http.Request(method, Uri.parse(url))
          ..headers.addAll(requestHeaders);
        if (bodyBytes != null) request.bodyBytes = bodyBytes;
        final sent = _httpClient.send(request);
        final streamed = deadline == Duration.zero
            ? await sent
            : await sent.timeout(deadline);
        response = await http.Response.fromStream(streamed);
      } on TimeoutException catch (error) {
        if (_shouldRetry(attempt, isRetriablePath, null)) {
          await Future<void>.delayed(config.retryDelay(++attempt));
          continue;
        }
        throw SanityTransportException(
          '$method-request to $url timed out after ${deadline.inMilliseconds}ms',
          cause: error,
        );
      } on Object catch (error) {
        if (_shouldRetry(attempt, isRetriablePath, null)) {
          await Future<void>.delayed(config.retryDelay(++attempt));
          continue;
        }
        throw SanityTransportException(
          '$method-request to $url failed: $error',
          cause: error,
        );
      }

      _printWarnings(response);

      if (response.statusCode >= 400) {
        if (_shouldRetry(attempt, isRetriablePath, response.statusCode)) {
          await Future<void>.delayed(config.retryDelay(++attempt));
          continue;
        }
        throw buildRequestException(
          statusCode: response.statusCode,
          method: method,
          url: url,
          statusMessage: response.reasonPhrase,
          contentType: response.headers['content-type'],
          rawBody: response.body,
          tag: resolvedTag,
        );
      }
      return response;
    }
  }

  bool _shouldRetry(int attempt, bool isRetriablePath, int? statusCode) {
    if (config.maxRetries == 0 || attempt >= config.maxRetries) return false;
    if (statusCode == null) return isRetriablePath;
    return isRetriablePath && _retriableStatusCodes.contains(statusCode);
  }

  String? _resolveTag(String? tag) {
    final prefix = config.requestTagPrefix;
    final combined =
        tag != null && prefix != null ? '$prefix.$tag' : tag ?? prefix;
    return combined == null ? null : validateRequestTag(combined);
  }

  Map<String, String> _buildHeaders({
    required String? token,
    required String? contentType,
    required Map<String, String> overrides,
  }) {
    final headers = <String, String>{
      ...config.headers,
      'Accept': 'application/json',
    };
    final effectiveToken = token ?? config.token;
    if (effectiveToken != null) {
      headers['Authorization'] = 'Bearer $effectiveToken';
    }
    if (!config.useProjectHostname && config.projectId.isNotEmpty) {
      headers['X-Sanity-Project-ID'] = config.projectId;
    }
    if (contentType != null) headers['Content-Type'] = contentType;
    headers.addAll(overrides);
    return headers;
  }

  String _buildUrl({
    required String path,
    required String? embeddedQueryString,
    required Map<String, String> query,
    required bool useCdn,
  }) {
    final base = useCdn && config.useCdn ? config.cdnUrl : config.url;
    final buffer =
        StringBuffer('$base/${path.replaceFirst(RegExp(r'^/'), '')}');
    if (embeddedQueryString != null && embeddedQueryString.isNotEmpty) {
      buffer.write(embeddedQueryString);
    }
    if (query.isNotEmpty) {
      final encoded = query.entries
          .map((entry) =>
              '${formUrlEncode(entry.key)}=${formUrlEncode(entry.value)}')
          .join('&');
      buffer.write(
        embeddedQueryString != null && embeddedQueryString.isNotEmpty
            ? '&'
            : '?',
      );
      buffer.write(encoded);
    }
    return buffer.toString();
  }

  void _printWarnings(http.Response response) {
    final warning = response.headers['x-sanity-warning'];
    if (warning == null || warning.isEmpty) return;
    if (_seenWarnings.contains(warning)) return;
    for (final pattern in config.ignoreWarnings) {
      if (pattern.allMatches(warning).isNotEmpty) return;
    }
    _seenWarnings.add(warning);
    sanityWarn(warning);
  }
}
