/// Identifies the documents a patch or delete applies to.
sealed class SanitySelection {
  const SanitySelection();

  /// Selects the single document with [id].
  const factory SanitySelection.id(String id) = DocumentIdSelection;

  /// Selects every document whose `_id` appears in [ids].
  const factory SanitySelection.ids(List<String> ids) = DocumentIdsSelection;

  /// Selects every document matching the GROQ filter [query].
  const factory SanitySelection.query(String query, {Map<String, Object?>? params}) = QuerySelection;

  /// The wire representation merged into the mutation.
  Map<String, Object?> toJson();
}

/// A selection of exactly one document, by id.
class DocumentIdSelection extends SanitySelection {
  /// Selects the document with [id].
  const DocumentIdSelection(this.id);

  /// The document id.
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// A selection of several documents, by id.
class DocumentIdsSelection extends SanitySelection {
  /// Selects the documents with [ids].
  const DocumentIdsSelection(this.ids);

  /// The document ids.
  final List<String> ids;

  @override
  Map<String, Object?> toJson() => {
        'query': r'*[_id in $ids]',
        'params': {'ids': ids},
      };
}

/// A selection expressed as a GROQ filter.
class QuerySelection extends SanitySelection {
  /// Selects documents matching [query], bound with [params].
  const QuerySelection(this.query, {this.params});

  /// The GROQ filter.
  final String query;

  /// Parameters bound into [query].
  final Map<String, Object?>? params;

  @override
  Map<String, Object?> toJson() => {
        'query': query,
        if (params != null) 'params': params,
      };
}
