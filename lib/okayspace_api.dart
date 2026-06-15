/// OkaySpace API client for Flutter.
///
/// A fully hand-written client for the OkaySpace REST API
/// (`https://okayspace-v0vx.onrender.com/api/v1`) — including its own HTTP
/// transport, with no third-party networking dependency. Import this single
/// file to access the client, services and models.
library;

// Core
export 'src/okayspace_api.dart';
export 'src/core/api_client.dart';
export 'src/core/api_config.dart';
export 'src/core/http_transport.dart';
export 'src/core/api_exception.dart';
export 'src/core/token_store.dart';

// Services
export 'src/services/admin_service.dart';
export 'src/services/ads_service.dart';
export 'src/services/auth_service.dart';
export 'src/services/circles_service.dart';
export 'src/services/communities_service.dart';
export 'src/services/feed_service.dart';
export 'src/services/forms_service.dart';
export 'src/services/friends_service.dart';
export 'src/services/games_service.dart';
export 'src/services/groups_service.dart';
export 'src/services/guides_service.dart';
export 'src/services/calendar_service.dart';
export 'src/services/marketplace_service.dart';
export 'src/services/messaging_service.dart';
export 'src/services/monetize_service.dart';
export 'src/services/notes_service.dart';
export 'src/services/reminders_service.dart';
export 'src/services/notifications_service.dart';
export 'src/services/oauth_service.dart';
export 'src/services/payments_service.dart';
export 'src/services/roadside_service.dart';
export 'src/services/hazards_service.dart';
export 'src/services/support_service.dart';
export 'src/services/users_service.dart';
export 'src/services/wallet_service.dart';

// Models
export 'src/models/auth_response.dart';
export 'src/models/badge.dart';
export 'src/models/calendar_event.dart';
export 'src/models/community.dart';
export 'src/models/game.dart';
export 'src/models/note.dart';
export 'src/models/reminder.dart';
export 'src/models/group.dart';
export 'src/models/listing.dart';
export 'src/models/message.dart';
export 'src/models/notification.dart';
export 'src/models/place.dart';
export 'src/models/post.dart';
export 'src/models/pub_site.dart';
export 'src/models/post_create.dart';
export 'src/models/public_user.dart';
export 'src/models/roadside_request.dart';
export 'src/models/hazard.dart';
export 'src/models/user.dart';
export 'src/models/wallet.dart';
