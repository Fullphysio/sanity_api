import 'package:http/http.dart' as http;

import 'assets.dart';
import 'config.dart';
import 'mutation.dart';
import 'patch.dart';
import 'perspective.dart';
import 'query_string.dart';
import 'selection.dart';
import 'transaction.dart';
import 'transport.dart';
import 'url_builder.dart';

/// Queries longer than this are sent as POST rather than GET.
const int getQuerySizeLimit = 11264;

/// The envelope returned by a query when the full response is requested.
class SanityQueryResponse<T> {
  /// Creates a query response.
  const SanityQueryResponse({
    required this.result,
    required this.query,
    this.ms,
    this.syncTags,
  });

  /// The query result.
  final T result;

  /// The GROQ that produced it, when the API echoed it back.
  final String? query;

  /// Server-side execution time in milliseconds.
  final int? ms;

  /// Cache-invalidation tags, when the API version supports them.
  final List<String>? syncTags;
}

/// A client for the Sanity Content Lake.
///
/// Instances are cheap to construct and safe to keep for the life of a process;
/// reuse one so the underlying HTTP connection pool is shared.
///
/// ```dart
/// final client = SanityClient(SanityConfig(
///   projectId: 'abc123',
///   dataset: 'production',
///   apiVersion: '2024-05-03',
/// ));
/// final exercises = await client.fetch<List<Object?>>('*[_type == "exercise"]');
/// ```
class SanityClient implements MutationExecutor {
  /// Creates a client for [config], optionally reusing [httpClient].
  SanityClient(this.config, {http.Client? httpClient}) : _transport = SanityTransport(config, httpClient: httpClient);

  /// The configuration in force.
  final SanityConfig config;

  final SanityTransport _transport;

  /// Asset uploads for the configured dataset.
  SanityAssets get assets => SanityAssets(_transport, config);

  /// A client with [config] replaced, sharing nothing with this one.
  SanityClient withConfig(SanityConfig config) => SanityClient(config);

  /// Releases the underlying HTTP client when this client created it.
  void close() => _transport.close();

  /// Runs [query], returning just its result.
  ///
  /// Uses GET when the encoded query fits within [getQuerySizeLimit] and POST
  /// otherwise. A [perspective] of `drafts`, or any stack, bypasses the CDN
  /// because the CDN cannot serve them.
  Future<T> fetch<T>(
    String query, {
    Map<String, Object?> params = const {},
    SanityPerspective? perspective,
    String? tag,
    String? token,
    Duration? timeout,
    bool? useCdn,
  }) async {
    final response = await _fetch<T>(
      query,
      params: params,
      perspective: perspective,
      tag: tag,
      token: token,
      timeout: timeout,
      useCdn: useCdn,
      returnQuery: false,
    );
    return response.result;
  }

  /// Runs [query], returning the full response envelope including timing.
  ///
  /// Unlike [fetch], this asks the API to echo the query back, so
  /// [SanityQueryResponse.query] is populated.
  Future<SanityQueryResponse<T>> fetchFull<T>(
    String query, {
    Map<String, Object?> params = const {},
    SanityPerspective? perspective,
    String? tag,
    String? token,
    Duration? timeout,
    bool? useCdn,
  }) =>
      _fetch<T>(
        query,
        params: params,
        perspective: perspective,
        tag: tag,
        token: token,
        timeout: timeout,
        useCdn: useCdn,
        returnQuery: true,
      );

  Future<SanityQueryResponse<T>> _fetch<T>(
    String query, {
    required Map<String, Object?> params,
    required SanityPerspective? perspective,
    required String? tag,
    required String? token,
    required Duration? timeout,
    required bool? useCdn,
    required bool returnQuery,
  }) async {
    final dataset = config.requireDataset();
    final encoded = encodeQueryString(query, params);
    final useGet = encoded.length < getQuerySizeLimit;

    final effectivePerspective = perspective ?? config.perspective;
    var canUseCdn = useCdn ?? config.useCdn;
    if (effectivePerspective != null && effectivePerspective.forcesCdnOff) {
      canUseCdn = false;
    }

    final queryParams = <String, String>{
      if (!returnQuery) 'returnQuery': 'false',
      if (effectivePerspective != null) 'perspective': effectivePerspective.value,
    };

    final decoded = await _transport.requestJson(
      method: useGet ? 'GET' : 'POST',
      path: 'data/query/$dataset',
      embeddedQueryString: useGet ? encoded : null,
      query: queryParams,
      body: useGet ? null : {'query': query, 'params': params},
      tag: tag,
      token: token,
      timeout: timeout,
      useCdn: canUseCdn,
    );

    if (decoded is! Map<String, Object?>) {
      throw StateError('Unexpected query response: $decoded');
    }
    final syncTags = decoded['syncTags'];
    return SanityQueryResponse<T>(
      result: decoded['result'] as T,
      query: decoded['query'] as String?,
      ms: decoded['ms'] as int?,
      syncTags: syncTags is List ? syncTags.cast<String>() : null,
    );
  }

  /// Fetches the document with [id], or null when it does not exist.
  Future<Map<String, Object?>?> getDocument(
    String id, {
    String? tag,
    String? token,
    Duration? timeout,
  }) async {
    final documents = await getDocuments([id], tag: tag, token: token, timeout: timeout);
    return documents.first;
  }

  /// Fetches the documents with [ids], preserving order and returning null for
  /// each id that does not exist.
  Future<List<Map<String, Object?>?>> getDocuments(
    List<String> ids, {
    String? tag,
    String? token,
    Duration? timeout,
  }) async {
    final dataset = config.requireDataset();
    final decoded = await _transport.requestJson(
      method: 'GET',
      path: 'data/doc/$dataset/${ids.join(',')}',
      tag: tag,
      token: token,
      timeout: timeout,
      useCdn: true,
    );
    if (decoded is! Map<String, Object?>) {
      throw StateError('Unexpected document response: $decoded');
    }
    final documents = decoded['documents'];
    final indexed = <String, Map<String, Object?>>{};
    if (documents is List) {
      for (final document in documents) {
        if (document is Map<String, Object?>) {
          final id = document['_id'];
          if (id is String) indexed[id] = document;
        }
      }
    }
    return ids.map((id) => indexed[id]).toList(growable: false);
  }

  /// Submits [mutations] to the mutate endpoint.
  ///
  /// Mutations are always POSTed to the origin API; they never use the CDN.
  @override
  Future<SanityMutationResult> mutate(
    List<Map<String, Object?>> mutations, {
    MutationOptions options = const MutationOptions(),
  }) async {
    final dataset = config.requireDataset();
    final decoded = await _transport.requestJson(
      method: 'POST',
      path: 'data/mutate/$dataset',
      query: options.toQueryParameters(),
      body: {
        'mutations': mutations,
        if (options.transactionId != null) 'transactionId': options.transactionId,
      },
      tag: options.tag,
      token: options.token,
      timeout: options.timeout,
    );
    if (decoded is! Map<String, Object?>) {
      throw StateError('Unexpected mutation response: $decoded');
    }
    return SanityMutationResult.fromJson(decoded);
  }

  /// Creates [document], letting the API assign an id when `_id` is absent.
  Future<SanityMutationResult> create(
    Map<String, Object?> document, {
    MutationOptions options = const MutationOptions(),
  }) =>
      mutate(
        [
          {'create': document},
        ],
        options: options.withDefaults(returnDocuments: true, returnFirst: true),
      );

  /// Creates [document] unless a document with that id already exists.
  Future<SanityMutationResult> createIfNotExists(
    Map<String, Object?> document, {
    MutationOptions options = const MutationOptions(),
  }) =>
      SanityTransaction(executor: this).createIfNotExists(document).commit(
            options: options.withDefaults(returnDocuments: true, returnFirst: true),
          );

  /// Creates [document], replacing any existing document with that id.
  Future<SanityMutationResult> createOrReplace(
    Map<String, Object?> document, {
    MutationOptions options = const MutationOptions(),
  }) =>
      SanityTransaction(executor: this).createOrReplace(document).commit(
            options: options.withDefaults(returnDocuments: true, returnFirst: true),
          );

  /// Deletes everything matched by [selection].
  Future<SanityMutationResult> delete(
    SanitySelection selection, {
    MutationOptions options = const MutationOptions(),
  }) =>
      mutate(
        [
          {'delete': selection.toJson()},
        ],
        options: options,
      );

  /// Deletes the document with [id].
  Future<SanityMutationResult> deleteById(
    String id, {
    MutationOptions options = const MutationOptions(),
  }) =>
      delete(SanitySelection.id(id), options: options);

  /// Deletes every document matching the GROQ filter [query].
  Future<SanityMutationResult> deleteByQuery(
    String query, {
    Map<String, Object?>? params,
    MutationOptions options = const MutationOptions(),
  }) =>
      delete(SanitySelection.query(query, params: params), options: options);

  /// Starts a patch against [selection], bound to this client.
  SanityPatch patch(SanitySelection selection) => SanityPatch(selection, executor: this);

  /// Starts a patch against the document [id], bound to this client.
  SanityPatch patchId(String id) => patch(SanitySelection.id(id));

  /// Starts a transaction bound to this client.
  SanityTransaction transaction() => SanityTransaction(executor: this);

  /// Builds a CDN image URL for [ref].
  SanityImageUrlBuilder image(SanityAssetRef ref) => SanityImageUrlBuilder(
        projectId: config.projectId,
        dataset: config.requireDataset(),
        ref: ref,
      );

  /// Builds a CDN file URL for [ref].
  SanityFileUrlBuilder file(SanityAssetRef ref) => SanityFileUrlBuilder(
        projectId: config.projectId,
        dataset: config.requireDataset(),
        ref: ref,
      );
}
