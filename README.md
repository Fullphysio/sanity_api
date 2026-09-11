# sanity_api

A pure Dart client for the [Sanity.io](https://www.sanity.io) Content Lake. Query with GROQ, create and patch documents, commit transactions, and upload assets — from Dart servers, CLI tools, Cloud Functions and Flutter apps alike.

**No Flutter dependency.** Existing Dart Sanity packages either declare the Flutter SDK — which pub refuses to resolve inside a plain Dart project — or are read-only. This one is neither.

```dart
import 'package:sanity_api/sanity_api.dart';

final client = SanityClient(SanityConfig(
  projectId: 'abc123',
  dataset: 'production',
  apiVersion: '2024-05-03',
));

final exercises = await client.fetch<List<Object?>>(
  r'*[_type == "exercise" && $tag in tags]{_id, title}',
  params: {'tag': 'shoulder'},
);
```

## Writing

Writes need a token with Editor rights, and should use `useCdn: false` so a read
straight after a write isn't served a stale cached copy.

```dart
final writeClient = SanityClient(SanityConfig(
  projectId: 'abc123',
  dataset: 'production',
  apiVersion: '2024-05-03',
  token: Platform.environment['SANITY_TOKEN'],
  useCdn: false,
));

await writeClient.patchId('exercise-123')
    .set({'title': 'Shoulder press'})
    .inc({'revisions': 1})
    .commit();

await writeClient.transaction()
    .createIfNotExists({'_id': 'tag-a', '_type': 'tag', 'title': 'A'})
    .patchId('exercise-123', (p) => p.append('tags', [
          {'_type': 'reference', '_ref': 'tag-a'},
        ]))
    .commit();
```

## Assets

```dart
final asset = await writeClient.assets.upload(
  SanityAssetType.image,
  await File('slide.png').readAsBytes(),
  filename: 'slide.png',
  contentType: 'image/png',
  extract: ['blurhash', 'palette'],
);
```

## Image and file URLs

```dart
final url = client
    .image(SanityAssetRef(doc['image']['asset']['_ref'] as String))
    .width(800)
    .quality(90)
    .format(SanityImageFormat.auto)
    .build();
```

Transform parameters are skipped for GIFs, which the CDN cannot transcode without
losing animation.

## Perspectives

`SanityPerspective.drafts` and any `SanityPerspective.stack([...])` bypass the CDN
automatically, because the CDN cannot serve them.

```dart
await client.fetch<Object?>('*[_type == "exercise"]',
    perspective: SanityPerspective.drafts);
```

## Errors

Every failure throws. Nothing is swallowed, and an empty query result is a result,
not an error.

| Exception | When |
|---|---|
| `SanityClientException` | 4xx — bad query, missing permission, conflict |
| `SanityServerException` | 5xx |
| `SanityTransportException` | no response at all: DNS, connection reset, timeout |

`429`, `502` and `503` are retried automatically on queries (including the POST
fallback for long queries); mutations are not retried, since they are not
idempotent unless you supply a `transactionId`.

GROQ syntax errors arrive with a rendered code frame:

```
GROQ query parse error:
> 1 | *[_type == "exercise"
    |                     ^
> 2 |   && bad]
    | ^^ unexpected token
```

## On servers

`SanityClient` is cheap to construct and holds a connection pool. Create one per
process and reuse it, so warm Cloud Function invocations reuse connections:

```dart
SanityClient? _client;
SanityClient sanityClient() => _client ??= SanityClient(SanityConfig(...));
```

## Scope

Covered: queries, documents by id, mutations, patches, transactions, asset
uploads, image and file URLs, draft and version id helpers.

Not covered: live/listen (SSE), Content Releases, AI Agent Actions, the Media
Library, dataset/project/user administration, and the Studio visual-editing
machinery (Content Source Maps and stega encoding). Open an issue if you need one
of these.

## Relationship to @sanity/client

This is a Dart port of the official JavaScript client, `@sanity/client` 7.20.0
(MIT). Request construction, GROQ parameter encoding, mutation and patch
semantics, and error message formatting follow that implementation, and the test
suite compares this client's output against fixtures captured from it. See
`THIRD_PARTY_NOTICES`.

Two deliberate differences:

- **One result type for mutations.** The JavaScript client returns four different
  shapes depending on `returnDocuments` and `returnFirst`. `SanityMutationResult`
  always exposes `documentIds`, `documents`, `documentId` and `document`, so
  nothing is lost and nothing needs casting. The request sent is unchanged.
- **`Future`, not `Observable`.** There is no parallel observable API; `Stream`
  is reserved for genuinely multi-valued results.
