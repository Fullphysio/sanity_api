import 'mutation.dart';
import 'selection.dart';
import 'validators.dart';

/// Where [SanityPatch.insert] places its items relative to the selector.
enum InsertLocation {
  /// Before the matched element.
  before,

  /// After the matched element.
  after,

  /// Replacing the matched range.
  replace,
}

/// A set of operations applied to one or more documents.
///
/// Operations accumulate; call [commit] to send them, or hand the patch to a
/// [SanityTransaction] to batch it with others.
class SanityPatch {
  /// Creates a patch against [selection].
  SanityPatch(this.selection, {Map<String, Object?>? operations, MutationExecutor? executor})
      : _operations = {...?operations},
        _executor = executor;

  /// The documents this patch applies to.
  final SanitySelection selection;

  final Map<String, Object?> _operations;
  final MutationExecutor? _executor;

  /// Overwrites [attrs]. Does not merge nested objects.
  ///
  /// Use JSONMatch paths for nested fields, e.g. `{'nested.prop': 'value'}`.
  SanityPatch set(Map<String, Object?> attrs) => _assign('set', attrs);

  /// Sets [attrs] only where no value is currently present.
  SanityPatch setIfMissing(Map<String, Object?> attrs) => _assign('setIfMissing', attrs);

  /// Applies diff-match-patch deltas to string fields.
  SanityPatch diffMatchPatch(Map<String, Object?> attrs) => _assign('diffMatchPatch', attrs);

  /// Removes the attribute paths in [attrs]. Replaces any previous `unset`.
  SanityPatch unset(List<String> attrs) {
    _operations['unset'] = attrs;
    return this;
  }

  /// Increments numeric fields by the given amounts.
  SanityPatch inc(Map<String, num> attrs) => _assign('inc', attrs);

  /// Decrements numeric fields by the given amounts.
  SanityPatch dec(Map<String, num> attrs) => _assign('dec', attrs);

  /// Inserts [items] at [at] relative to [selector].
  ///
  /// Note that repeated calls merge into a single `insert` operation rather than
  /// replacing it, matching the reference implementation; build a fresh patch if
  /// you need two independent inserts.
  SanityPatch insert(InsertLocation at, String selector, List<Object?> items) {
    validateInsert(at.name, selector, items);
    return _assign('insert', {at.name: selector, 'items': items});
  }

  /// Appends [items] to the array at [selector].
  SanityPatch append(String selector, List<Object?> items) => insert(InsertLocation.after, '$selector[-1]', items);

  /// Prepends [items] to the array at [selector].
  SanityPatch prepend(String selector, List<Object?> items) => insert(InsertLocation.before, '$selector[0]', items);

  /// Removes [deleteCount] elements at [start] and inserts [items] there.
  ///
  /// Indices follow JavaScript's `Array.prototype.splice`, not Sanity's native
  /// range semantics where `-1` means the end of the array. Omitting
  /// [deleteCount], or passing `-1`, removes everything from [start] onwards.
  /// For raw Sanity behaviour use [insert] with [InsertLocation.replace].
  SanityPatch splice(
    String selector,
    int start, {
    int? deleteCount,
    List<Object?>? items,
  }) {
    final deleteAll = deleteCount == null || deleteCount == -1;
    final startIndex = start < 0 ? start - 1 : start;
    final delCount = deleteAll ? -1 : (start + deleteCount).clamp(0, 1 << 31);
    final delRange = startIndex < 0 && delCount >= 0 ? '' : '$delCount';
    return insert(
      InsertLocation.replace,
      '$selector[$startIndex:$delRange]',
      items ?? const [],
    );
  }

  /// Refuses the patch unless the document is still at revision [rev].
  SanityPatch ifRevisionId(String rev) {
    _operations['ifRevisionID'] = rev;
    return this;
  }

  /// Drops every accumulated operation.
  SanityPatch reset() {
    _operations.clear();
    return this;
  }

  /// A copy of this patch, sharing the executor but not the operations.
  SanityPatch clone() => SanityPatch(selection, operations: _operations, executor: _executor);

  /// The wire representation of this patch.
  Map<String, Object?> serialize() => {...selection.toJson(), ..._operations};

  /// Alias of [serialize].
  Map<String, Object?> toJson() => serialize();

  /// Sends this patch.
  ///
  /// Defaults to returning the mutated documents. Throws [StateError] when the
  /// patch was built without a client.
  Future<SanityMutationResult> commit({
    MutationOptions options = const MutationOptions(),
  }) {
    final executor = _executor;
    if (executor == null) {
      throw StateError(
        'No client passed to patch, either provide one or pass the patch to a '
        "client's mutate() method",
      );
    }
    return executor.mutate(
      [
        {'patch': serialize()},
      ],
      options: options.withDefaults(
        returnDocuments: true,
        returnFirst: selection is DocumentIdSelection,
      ),
    );
  }

  SanityPatch _assign(String op, Map<String, Object?> props) {
    final existing = _operations[op];
    _operations[op] = {
      if (existing is Map<String, Object?>) ...existing,
      ...props,
    };
    return this;
  }
}
