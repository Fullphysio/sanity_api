import 'dart:convert';

import 'code_frame.dart';

const int _maxItemsInErrorMessage = 5;

/// Base class for every failure raised by this package.
sealed class SanityException implements Exception {
  /// Creates an exception carrying [message].
  const SanityException(this.message);

  /// Human-readable description of what went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The request never produced an HTTP response: DNS failure, connection reset,
/// TLS error or timeout.
class SanityTransportException extends SanityException {
  /// Creates a transport failure wrapping [cause].
  const SanityTransportException(super.message, {this.cause});

  /// The underlying error, when one is available.
  final Object? cause;
}

/// The API answered with a non-2xx status.
class SanityRequestException extends SanityException {
  /// Creates a request failure.
  const SanityRequestException(
    super.message, {
    required this.statusCode,
    required this.method,
    required this.url,
    this.responseBody,
    this.details,
  });

  /// HTTP status returned by the API.
  final int statusCode;

  /// HTTP method of the failed request.
  final String method;

  /// URL of the failed request.
  final String url;

  /// Raw response body, pretty-printed when it was JSON.
  final String? responseBody;

  /// Structured `error` object from the response, when the API sent one.
  final Object? details;
}

/// A 4xx response.
class SanityClientException extends SanityRequestException {
  /// Creates a client-side (4xx) failure.
  const SanityClientException(
    super.message, {
    required super.statusCode,
    required super.method,
    required super.url,
    super.responseBody,
    super.details,
  });
}

/// A 5xx response.
class SanityServerException extends SanityRequestException {
  /// Creates a server-side (5xx) failure.
  const SanityServerException(
    super.message, {
    required super.statusCode,
    required super.method,
    required super.url,
    super.responseBody,
    super.details,
  });
}

/// Builds the exception for a non-2xx response, reproducing the message ladder
/// of the reference implementation.
SanityRequestException buildRequestException({
  required int statusCode,
  required String method,
  required String url,
  required String? statusMessage,
  required String? contentType,
  required String rawBody,
  String? tag,
}) {
  Object? body;
  final isJson = (contentType ?? '').toLowerCase().contains('application/json');
  if (isJson) {
    try {
      body = jsonDecode(rawBody);
    } catch (_) {
      body = null;
    }
  }

  final responseBody = isJson && body != null
      ? const JsonEncoder.withIndent('  ').convert(body)
      : rawBody;

  String fallback() => _httpErrorMessage(
        method: method,
        url: url,
        statusCode: statusCode,
        statusMessage: statusMessage,
        body: isJson ? null : rawBody,
      );

  String message;
  Object? details;

  if (body is! Map<String, Object?>) {
    message = fallback();
  } else {
    final error = body['error'];
    final bodyMessage = body['message'];

    if (error is String && bodyMessage is String) {
      message = '$error - $bodyMessage';
    } else if (error is! Map<String, Object?>) {
      if (error is String) {
        message = error;
      } else if (bodyMessage is String) {
        message = bodyMessage;
      } else {
        message = fallback();
      }
    } else {
      final type = error['type'];
      final description = error['description'];

      if ((type == 'mutationError' || type == 'actionError') &&
          description is String) {
        final allItems = error['items'];
        final items = <String>[];
        if (allItems is List) {
          for (final item in allItems.take(_maxItemsInErrorMessage)) {
            if (item is Map<String, Object?>) {
              final itemError = item['error'];
              if (itemError is Map<String, Object?>) {
                final itemDescription = itemError['description'];
                if (itemDescription is String && itemDescription.isNotEmpty) {
                  items.add(itemDescription);
                }
              }
            }
          }
        }
        var itemsStr = items.isNotEmpty ? ':\n- ${items.join('\n- ')}' : '';
        final total = allItems is List ? allItems.length : 0;
        if (total > _maxItemsInErrorMessage) {
          itemsStr += '\n...and ${total - _maxItemsInErrorMessage} more';
        }
        message = '$description$itemsStr';
        details = error;
      } else if (type == 'queryParseError' &&
          error['query'] is String &&
          error['start'] is int) {
        message = _formatQueryParseError(error, tag);
        details = error;
      } else if (description is String) {
        message = description;
        details = error;
      } else {
        message = fallback();
      }
    }
  }

  if (statusCode >= 500) {
    return SanityServerException(
      message,
      statusCode: statusCode,
      method: method,
      url: url,
      responseBody: responseBody,
      details: details,
    );
  }
  return SanityClientException(
    message,
    statusCode: statusCode,
    method: method,
    url: url,
    responseBody: responseBody,
    details: details,
  );
}

String _formatQueryParseError(Map<String, Object?> error, String? tag) {
  final query = error['query'];
  final start = error['start'];
  final end = error['end'];
  final description = error['description'];

  if (query is! String || start is! int) {
    return 'GROQ query parse error: $description';
  }
  final withTag = tag != null && tag.isNotEmpty ? '\n\nTag: $tag' : '';
  final framed = codeFrame(
    query,
    start,
    end is int ? end : null,
    description is String ? description : null,
  );
  return 'GROQ query parse error:\n$framed$withTag';
}

String _httpErrorMessage({
  required String method,
  required String url,
  required int statusCode,
  required String? statusMessage,
  required String? body,
}) {
  final details = body != null && body.isNotEmpty
      ? ' (${_sliceWithEllipsis(body, 100)})'
      : '';
  final status = statusMessage != null && statusMessage.isNotEmpty
      ? ' $statusMessage'
      : '';
  return '$method-request to $url resulted in HTTP $statusCode$status$details';
}

String _sliceWithEllipsis(String value, int max) =>
    value.length > max ? '${value.substring(0, max)}…' : value;
