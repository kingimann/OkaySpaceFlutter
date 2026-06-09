/// OkaySpace API client for Flutter.
///
/// A hand-written, Dio-based client for the OkaySpace REST API
/// (`https://okayspace-api.onrender.com/api/v1`). Import this single file to
/// access the client, services and models.
library;

// Core
export 'src/okayspace_api.dart';
export 'src/core/api_client.dart';
export 'src/core/api_config.dart';
export 'src/core/api_exception.dart';
export 'src/core/token_store.dart';

// Services
export 'src/services/ads_service.dart';
export 'src/services/auth_service.dart';
export 'src/services/communities_service.dart';
export 'src/services/feed_service.dart';
export 'src/services/friends_service.dart';
export 'src/services/groups_service.dart';
export 'src/services/marketplace_service.dart';
export 'src/services/messaging_service.dart';
export 'src/services/notifications_service.dart';
export 'src/services/payments_service.dart';
export 'src/services/roadside_service.dart';
export 'src/services/stories_service.dart';
export 'src/services/support_service.dart';
export 'src/services/users_service.dart';
export 'src/services/wallet_service.dart';

// Models
export 'src/models/auth_response.dart';
export 'src/models/badge.dart';
export 'src/models/community.dart';
export 'src/models/group.dart';
export 'src/models/listing.dart';
export 'src/models/message.dart';
export 'src/models/notification.dart';
export 'src/models/post.dart';
export 'src/models/post_create.dart';
export 'src/models/public_user.dart';
export 'src/models/roadside_request.dart';
export 'src/models/story.dart';
export 'src/models/user.dart';
export 'src/models/wallet.dart';
