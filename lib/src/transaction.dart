import 'mutation.dart';
import 'patch.dart';
import 'selection.dart';
import 'validators.dart';

/// A batch of mutations committed atomically.
///
/// Every operation returns the transaction, so calls chain. Commit once with
/// [commit]; the API applies all mutations or none.
class SanityTransaction {
  /// Creates a transaction, optionally seeded with [operations].
  SanityTransaction({
    List<Map<String, Object?>>? operations,
    MutationExecutor? executor,
    String? transactionId,
  })  : _operations = [...?operations],
        _executor = executor,
        _transactionId = transactionId;

  final List<Map<String, Object?>> _operations;
  final MutationExecutor? _executor;
  String? _transactionId;

  /// The client-supplied transaction id, when one was set.
  String? get transactionId => _transactionId;

  /// Sets the transaction id, used for idempotent retries.
  SanityTransaction setTransactionId(String id) {
    _transactionId = id;
    return this;
  }

  /// Creates [document], letting the API assign an id when `_id` is absent.
  SanityTransaction create(Map<String, Object?> document) =>
      _add({'create': document});

  /// Creates [document] unless a document with that id already exists.
  SanityTransaction createIfNotExists(Map<String, Object?> document) {
    requireDocumentId('createIfNotExists', document);
    return _add({'createIfNotExists': document});
  }

  /// Creates [document], replacing any existing document with that id.
  SanityTransaction createOrReplace(Map<String, Object?> document) {
    requireDocumentId('createOrReplace', document);
    return _add({'createOrReplace': document});
  }

  /// Deletes the document with [documentId].
  SanityTransaction delete(String documentId) {
    validateDocumentId('delete', documentId);
    return _add({
      'delete': {'id': documentId},
    });
  }

  /// Adds [patch] to the transaction.
  SanityTransaction patch(SanityPatch patch) =>
      _add({'patch': patch.serialize()});

  /// Builds a patch against [selection] via [build] and adds it.
  SanityTransaction patchSelection(
    SanitySelection selection,
    SanityPatch Function(SanityPatch patch) build,
  ) {
    final patch = build(SanityPatch(selection));
    return _add({'patch': patch.serialize()});
  }

  /// Builds a patch against the document [id] via [build] and adds it.
  SanityTransaction patchId(
    String id,
    SanityPatch Function(SanityPatch patch) build,
  ) =>
      patchSelection(SanitySelection.id(id), build);

  /// Drops every queued mutation.
  SanityTransaction reset() {
    _operations.clear();
    return this;
  }

  /// A copy of this transaction, sharing the executor but not the mutations.
  SanityTransaction clone() => SanityTransaction(
        operations: _operations,
        executor: _executor,
        transactionId: _transactionId,
      );

  /// The queued mutations, in order.
  List<Map<String, Object?>> serialize() =>
      List.unmodifiable(_operations.map(Map<String, Object?>.from));

  /// Alias of [serialize].
  List<Map<String, Object?>> toJson() => serialize();

  /// Commits every queued mutation atomically.
  ///
  /// Defaults to returning ids rather than documents, since transactions are
  /// typically large. Throws [StateError] when built without a client.
  Future<SanityMutationResult> commit({
    MutationOptions options = const MutationOptions(),
  }) {
    final executor = _executor;
    if (executor == null) {
      throw StateError(
        'No client passed to transaction, either provide one or pass the '
        "transaction to a client's mutate() method",
      );
    }
    final effective = options.transactionId == null && _transactionId != null
        ? MutationOptions(
            visibility: options.visibility,
            returnDocuments: options.returnDocuments,
            returnFirst: options.returnFirst,
            dryRun: options.dryRun,
            autoGenerateArrayKeys: options.autoGenerateArrayKeys,
            skipCrossDatasetReferenceValidation:
                options.skipCrossDatasetReferenceValidation,
            transactionId: _transactionId,
            tag: options.tag,
            token: options.token,
            timeout: options.timeout,
          )
        : options;
    return executor.mutate(
      serialize(),
      options: effective.withDefaults(returnDocuments: false),
    );
  }

  SanityTransaction _add(Map<String, Object?> mutation) {
    _operations.add(mutation);
    return this;
  }
}
