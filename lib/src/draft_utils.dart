/// Folder prefix marking a draft document id.
const String draftsFolder = 'drafts';

/// Folder prefix marking a version (release) document id.
const String versionFolder = 'versions';

const String _pathSeparator = '.';
const String _draftsPrefix = '$draftsFolder$_pathSeparator';
const String _versionPrefix = '$versionFolder$_pathSeparator';

/// Whether [id] refers to a draft document, i.e. `drafts.<publishedId>`.
bool isDraftId(String id) => id.startsWith(_draftsPrefix);

/// Whether [id] refers to a release version, i.e. `versions.<release>.<publishedId>`.
bool isVersionId(String id) => id.startsWith(_versionPrefix);

/// Whether [id] is neither a draft nor a version id.
bool isPublishedId(String id) => !isDraftId(id) && !isVersionId(id);

/// The draft id for [id], regardless of whether it is published, draft or version.
String getDraftId(String id) {
  if (isVersionId(id)) return '$_draftsPrefix${getPublishedId(id)}';
  return isDraftId(id) ? id : '$_draftsPrefix$id';
}

/// The version id for [id] within the release named [version].
///
/// Throws [ArgumentError] when [version] is `drafts` or `published`, which are
/// reserved and cannot name a release.
String getVersionId(String id, String version) {
  if (version == 'drafts' || version == 'published') {
    throw ArgumentError('Version can not be "published" or "drafts"');
  }
  return '$_versionPrefix$version$_pathSeparator${getPublishedId(id)}';
}

/// The release name encoded in [id], or `null` when [id] is not a version id.
///
/// `versions.summer-drop.foo` yields `summer-drop`; `drafts.foo` and `foo`
/// yield `null`.
String? getVersionFromId(String id) {
  if (!isVersionId(id)) return null;
  final parts = id.split(_pathSeparator);
  return parts.length > 1 ? parts[1] : null;
}

/// The published id underlying [id], stripping any draft or version prefix.
String getPublishedId(String id) {
  if (isVersionId(id)) {
    return id.split(_pathSeparator).skip(2).join(_pathSeparator);
  }
  if (isDraftId(id)) return id.substring(_draftsPrefix.length);
  return id;
}
