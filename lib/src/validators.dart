const List<String> _validAssetTypes = ['image', 'file'];
const List<String> _validInsertLocations = ['before', 'after', 'replace'];

final RegExp _datasetPattern =
    RegExp(r'^(~[a-z0-9]{1}[-\w]{0,63}|[a-z0-9]{1}[-\w]{0,63})$');
final RegExp _projectIdPattern = RegExp(r'^[-a-z0-9]+$', caseSensitive: false);
final RegExp _documentIdPattern =
    RegExp(r'^[a-z0-9_][a-z0-9_.-]{0,127}$', caseSensitive: false);
final RegExp _requestTagPattern =
    RegExp(r'^[a-z0-9._-]{1,75}$', caseSensitive: false);

/// Validates a dataset name, throwing [ArgumentError] when malformed.
void validateDataset(String name) {
  if (!_datasetPattern.hasMatch(name)) {
    throw ArgumentError(
      'Datasets can only contain lowercase characters, numbers, underscores and '
      'dashes, and start with tilde, and be maximum 64 characters',
    );
  }
}

/// Validates a project id, throwing [ArgumentError] when malformed.
void validateProjectId(String id) {
  if (!_projectIdPattern.hasMatch(id)) {
    throw ArgumentError(
        '`projectId` can only contain only a-z, 0-9 and dashes');
  }
}

/// Validates an asset type, which must be `image` or `file`.
void validateAssetType(String type) {
  if (!_validAssetTypes.contains(type)) {
    throw ArgumentError(
      'Invalid asset type: $type. Must be one of ${_validAssetTypes.join(', ')}',
    );
  }
}

/// Validates a document id, throwing [ArgumentError] when malformed.
///
/// [op] names the calling operation and appears in the error message.
void validateDocumentId(String op, String id) {
  if (!_documentIdPattern.hasMatch(id) || id.contains('..')) {
    throw ArgumentError('$op(): "$id" is not a valid document ID');
  }
}

/// Asserts that [document] carries a valid `_id`, for operation [op].
void requireDocumentId(String op, Map<String, Object?> document) {
  final id = document['_id'];
  if (id == null || id == '') {
    throw ArgumentError(
      '$op() requires that the document contains an ID ("_id" property)',
    );
  }
  if (id is! String) {
    throw ArgumentError('$op(): "$id" is not a valid document ID');
  }
  validateDocumentId(op, id);
}

/// Asserts that [document] carries a `_type`, for operation [op].
void requireDocumentType(String op, Map<String, Object?> document) {
  final type = document['_type'];
  if (type == null || type == '') {
    throw ArgumentError(
      '`$op()` requires that the document contains a type (`_type` property)',
    );
  }
  if (type is! String) {
    throw ArgumentError('`$op()`: `$type` is not a valid document type');
  }
}

/// Asserts that [documentId], when present, matches [builtVersionId].
void validateVersionIdMatch(
    String builtVersionId, Map<String, Object?> document) {
  final id = document['_id'];
  if (id != null && id != builtVersionId) {
    throw ArgumentError(
      'The provided document ID (`$id`) does not match the generated version ID '
      '(`$builtVersionId`)',
    );
  }
}

/// Validates the arguments of a patch `insert` operation.
void validateInsert(String at, String selector, List<Object?> items) {
  const signature = 'insert(at, selector, items)';
  if (!_validInsertLocations.contains(at)) {
    final valid = _validInsertLocations.map((loc) => '"$loc"').join(', ');
    throw ArgumentError(
        '$signature takes an "at"-argument which is one of: $valid');
  }
}

/// Validates a request tag and returns it unchanged.
String validateRequestTag(String tag) {
  if (!_requestTagPattern.hasMatch(tag)) {
    throw ArgumentError(
      'Tag can only contain alphanumeric characters, underscores, dashes and '
      'dots, and be between one and 75 characters long.',
    );
  }
  return tag;
}
