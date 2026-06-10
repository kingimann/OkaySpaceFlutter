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

```bash
./scripts/build_web.sh                      # base-href "/"
./scripts/build_web.sh /OkaySpaceFlutter/   # subpath (GitHub project pages)
```

Deploy the current `main` build to GitHub Pages (`gh-pages` branch):

```bash
./scripts/deploy_gh_pages.sh
```

This builds with `--base-href "/OkaySpaceFlutter/"`, adds a `404.html` SPA
fallback, and force-pushes `build/web` to `gh-pages`. One-time setup: in the
repo on GitHub, **Settings > Pages > Source: Deploy from a branch >
`gh-pages` / root**. Served at `https://<user>.github.io/OkaySpaceFlutter/`.

**CORS:** the app calls the backend (`okayspace-v0vx.onrender.com`) from the
browser, so that backend must allow the deployed origin.

## Building for Android

Requires the Android SDK (with **platform 36** + **build-tools 36**) and a
JDK (17–21). The project uses **AGP 8.9.1 / Gradle 8.11.1 / Kotlin 2.1.0**.

```bash
# point Flutter at your SDK if needed:
flutter config --android-sdk /path/to/Android/sdk
# install the required packages:
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"

flutter build apk            # release APK -> build/app/outputs/flutter-apk/
flutter build apk --debug    # debug APK
flutter build appbundle      # Play Store bundle
```

If you see *"Dependency … requires Android Gradle plugin 8.9.1 or higher"*,
your local checkout is on the old AGP — pull latest (already fixed in
`android/settings.gradle.kts`).

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
