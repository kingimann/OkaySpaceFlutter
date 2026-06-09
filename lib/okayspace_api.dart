/// OkaySpace API client for Flutter.
///
/// A hand-written, Dio-based client for the OkaySpace REST API
/// (`https://nampo-backend.onrender.com/api/v1`). Import this single file to
/// access the client, services and models.
library;

// Core
export 'src/okayspace_api.dart';
export 'src/core/api_client.dart';
export 'src/core/api_config.dart';
export 'src/core/api_exception.dart';
export 'src/core/token_store.dart';

// Services
export 'src/services/auth_service.dart';
export 'src/services/feed_service.dart';

// Models
export 'src/models/auth_response.dart';
export 'src/models/badge.dart';
export 'src/models/post.dart';
export 'src/models/post_create.dart';
export 'src/models/user.dart';
