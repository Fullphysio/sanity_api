/// When a mutation's effects become visible to subsequent queries.
enum SanityVisibility {
  /// Block until the change is queryable.
  sync,

  /// Return as soon as the change is committed.
  async,

  /// Return immediately, applying the change in the background.
  deferred,
}

/// Per-request options for a mutation, patch, transaction or action.
class MutationOptions {
  /// Creates mutation options.
  ///
  /// [returnDocuments] and [returnFirst] shape the request; the result always
  /// exposes both documents and ids, so leaving them unset is usually right.
  const MutationOptions({
    this.visibility = SanityVisibility.sync,
    this.returnDocuments,
    this.returnFirst,
    this.dryRun,
    this.autoGenerateArrayKeys,
    this.skipCrossDatasetReferenceValidation,
    this.transactionId,
    this.tag,
    this.token,
    this.timeout,
  });

  /// When the change becomes queryable.
  final SanityVisibility visibility;

  /// Whether the API should echo the mutated documents back.
  final bool? returnDocuments;

  /// Whether only the first result is of interest.
  final bool? returnFirst;

  /// Validate without persisting anything.
  final bool? dryRun;

  /// Let the API mint `_key` values for array items that lack them.
  final bool? autoGenerateArrayKeys;

  /// Skip validation of references pointing into other datasets.
  final bool? skipCrossDatasetReferenceValidation;

  /// Client-supplied transaction id, for idempotent retries.
  final String? transactionId;

  /// Request tag, joined to the client's `requestTagPrefix`.
  final String? tag;

  /// Overrides the client token for this request.
  final String? token;

  /// Overrides the client timeout for this request.
  final Duration? timeout;

  /// Returns a copy with [returnDocuments] and [returnFirst] defaulted when the
  /// caller left them unset.
  MutationOptions withDefaults({bool? returnDocuments, bool? returnFirst}) =>
      MutationOptions(
        visibility: visibility,
        returnDocuments: this.returnDocuments ?? returnDocuments,
        returnFirst: this.returnFirst ?? returnFirst,
        dryRun: dryRun,
        autoGenerateArrayKeys: autoGenerateArrayKeys,
        skipCrossDatasetReferenceValidation:
            skipCrossDatasetReferenceValidation,
        transactionId: transactionId,
        tag: tag,
        token: token,
        timeout: timeout,
      );

  /// The query parameters this option set contributes to a mutate request.
  Map<String, String> toQueryParameters() => {
        if (dryRun != null) 'dryRun': '$dryRun',
        'returnIds': 'true',
        if (returnDocuments != false) 'returnDocuments': 'true',
        'visibility': visibility.name,
        if (autoGenerateArrayKeys != null)
          'autoGenerateArrayKeys': '$autoGenerateArrayKeys',
        if (skipCrossDatasetReferenceValidation != null)
          'skipCrossDatasetReferenceValidation':
              '$skipCrossDatasetReferenceValidation',
      };
}

/// What the API did to one document in a mutation.
enum MutationOperation {
  /// A new document was created.
  create,

  /// An existing document was updated.
  update,

  /// A document was deleted.
  delete,

  /// Nothing changed.
  none,
}

/// The outcome for a single document within a mutation.
class MutationResultItem {
  /// Creates a result item.
  const MutationResultItem({required this.id, required this.operation});

  /// Parses a result item from its wire form.
  factory MutationResultItem.fromJson(Map<String, Object?> json) {
    final operation = json['operation'];
    return MutationResultItem(
      id: json['id']! as String,
      operation: MutationOperation.values.firstWhere(
        (value) => value.name == operation,
        orElse: () => MutationOperation.none,
      ),
    );
  }

  /// The affected document id.
  final String id;

  /// What happened to it.
  final MutationOperation operation;
}

/// The outcome of a mutation, patch, transaction or delete.
///
/// Both [documentIds] and [documents] are exposed; [documents] is empty unless
/// the request asked the API to echo them back.
class SanityMutationResult {
  /// Creates a mutation result.
  const SanityMutationResult({
    required this.transactionId,
    required this.results,
    required this.documents,
  });

  /// Parses a mutation result from the response body.
  factory SanityMutationResult.fromJson(Map<String, Object?> json) {
    final rawResults = json['results'];
    final results = <MutationResultItem>[];
    final documents = <Map<String, Object?>>[];
    if (rawResults is List) {
      for (final entry in rawResults) {
        if (entry is! Map<String, Object?>) continue;
        results.add(MutationResultItem.fromJson(entry));
        final document = entry['document'];
        if (document is Map<String, Object?>) documents.add(document);
      }
    }
    return SanityMutationResult(
      transactionId: json['transactionId'] as String?,
      results: List.unmodifiable(results),
      documents: List.unmodifiable(documents),
    );
  }

  /// The transaction the mutations were committed in.
  final String? transactionId;

  /// Per-document outcomes, in mutation order.
  final List<MutationResultItem> results;

  /// The mutated documents, when the API was asked to return them.
  final List<Map<String, Object?>> documents;

  /// Ids of every affected document, in mutation order.
  List<String> get documentIds =>
      results.map((result) => result.id).toList(growable: false);

  /// The first affected document id, or null when nothing matched.
  String? get documentId => results.isEmpty ? null : results.first.id;

  /// The first returned document, or null when none was returned.
  Map<String, Object?>? get document =>
      documents.isEmpty ? null : documents.first;
}

/// Implemented by the client so patches and transactions can commit themselves.
abstract interface class MutationExecutor {
  /// Submits [mutations] to the mutate endpoint.
  Future<SanityMutationResult> mutate(
    List<Map<String, Object?>> mutations, {
    MutationOptions options,
  });
}
