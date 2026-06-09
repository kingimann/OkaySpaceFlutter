# OkaySPace

A new Flutter project created with FlutLab - https://flutlab.io

## OkaySpace API client

This app talks to the OkaySpace REST API
(`https://nampo-backend.onrender.com/api/v1`) through a hand-written,
Dio-based client under `lib/src/`. Import it via the barrel file:

```dart
import 'package:okayspace/okayspace_api.dart';

final api = OkaySpaceApi();

// Auth + profile
await api.auth.register(
  email: 'me@example.com', password: 'secret', name: 'Me', username: 'me',
);
await api.auth.login(identifier: 'me@example.com', password: 'secret');
final me = await api.auth.me();                 // current user
await api.auth.updateProfile({'bio': 'hello'});

// Social feed
final home = await api.feed.homeFeed();         // List<Post>
final post = await api.feed.post('Hello OkaySpace 👋');
await api.feed.toggleLike(post.id);
await api.feed.reply(post.id, 'nice');
```

The session token is stored automatically (secure storage) and attached as
`Authorization: Bearer <token>` to every request. To use a Developer API key
instead: `await api.useApiKey('osk_...')`. Failed requests throw a normalized
`ApiException` (`statusCode`, `code`, `message`, `details`).

**Structure:** `core/` (client, config, errors, token store) ·
`models/` (typed, null-tolerant data models) · `services/` (`auth`, `feed`).
The API is large (~386 endpoints); auth + the social feed are implemented so
far, and new feature areas are added as services following the same pattern.

## Getting Started

A few resources to get you started if this is your first Flutter project:

- https://flutter.dev/docs/get-started/codelab
- https://flutter.dev/docs/cookbook

For help getting started with Flutter, view our
https://flutter.dev/docs, which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Getting Started: FlutLab - Flutter Online IDE

- How to use FlutLab? Please, view our https://flutlab.io/docs
- Join the discussion and conversation on https://flutlab.io/residents
