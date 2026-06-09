# OkaySPace

A new Flutter project created with FlutLab - https://flutlab.io

## OkaySpace API client

This app talks to the OkaySpace REST API
(`https://okayspace-v0vx.onrender.com/api/v1`) through a hand-written,
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

## Building & deploying the web app

Build the static web bundle with the helper script:

```bash
./scripts/build_web.sh            # base-href "/" (root-domain hosting)
./scripts/build_web.sh /OkaySpaceFlutter/   # subpath hosting (e.g. GitHub project pages)
```

This runs `flutter build web --release` and writes static files to
**`build/web/`**. Deploy that folder to any static host — GitHub Pages,
Render static site, Netlify, Vercel, S3/CloudFront, Nginx, etc. The build
command per provider is:

```
Build command:     flutter build web --release
Publish directory: build/web
```

Preview locally (Flutter web must be served over HTTP — opening `index.html`
directly via `file://` shows a blank page):

```bash
cd build/web && python3 -m http.server 8000   # http://localhost:8000
```

**Two deployment notes:**
- **`--base-href`** must match the path you serve from. Use `/` for a root
  domain; use `/<repo>/` (with leading and trailing slashes) for subpath
  hosting like GitHub project pages.
- **CORS:** the app calls the backend (`okayspace-v0vx.onrender.com`) from the
  browser, so that backend must allow your deployed origin. If requests fail
  only in the deployed build, check the backend's CORS allow-list.

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
