import 'core/api_client.dart';
import 'core/api_config.dart';
import 'core/token_store.dart';
import 'services/auth_service.dart';
import 'services/communities_service.dart';
import 'services/feed_service.dart';
import 'services/groups_service.dart';
import 'services/marketplace_service.dart';
import 'services/messaging_service.dart';
import 'services/stories_service.dart';
import 'services/wallet_service.dart';

/// Entry point for the OkaySpace REST API.
///
/// Construct one instance for the lifetime of the app and reach the feature
/// services through it:
///
/// ```dart
/// final api = OkaySpaceApi();
///
/// // Sign in (token is stored automatically for later sessions).
/// await api.auth.login(identifier: 'me@example.com', password: 'secret');
///
/// // Read the home feed and post.
/// final feed = await api.feed.homeFeed();
/// await api.feed.post('Hello OkaySpace 👋');
/// ```
///
/// To authenticate with a Developer API key instead of logging in:
///
/// ```dart
/// final api = OkaySpaceApi();
/// await api.useApiKey('osk_live_...');
/// ```
class OkaySpaceApi {
  OkaySpaceApi({
    ApiConfig config = const ApiConfig(),
    TokenStore? tokenStore,
    ApiClient? client,
  }) : client = client ?? ApiClient(config: config, tokenStore: tokenStore) {
    auth = AuthService(this.client);
    feed = FeedService(this.client);
    stories = StoriesService(this.client);
    messaging = MessagingService(this.client);
    communities = CommunitiesService(this.client);
    groups = GroupsService(this.client);
    marketplace = MarketplaceService(this.client);
    wallet = WalletService(this.client);
  }

  /// Shared low-level client. Use it directly for endpoints not yet wrapped by
  /// a dedicated service.
  final ApiClient client;

  /// `/auth` — registration, login, current user, account & API keys.
  late final AuthService auth;

  /// `/feed`, `/posts`, `/hashtags` — the social feed.
  late final FeedService feed;

  /// `/stories` — the stories tray, viewing, posting and replies.
  late final StoriesService stories;

  /// `/conversations`, `/presence`, `/calls` — messaging.
  late final MessagingService messaging;

  /// `/communities` — topic hubs, membership and moderation.
  late final CommunitiesService communities;

  /// `/groups` — membership groups, posts, events and requests.
  late final GroupsService groups;

  /// `/listings`, `/marketplace` — buying and selling.
  late final MarketplaceService marketplace;

  /// `/wallet`, `/money` — balance, transfers and top-ups.
  late final WalletService wallet;

  /// Whether a credential (session token or API key) is currently stored.
  Future<bool> get isAuthenticated => client.isAuthenticated;

  /// Authenticate using a long-lived Developer API key.
  Future<void> useApiKey(String apiKey) => client.setToken(apiKey);

  /// Clears the stored credential locally (use [auth.logout] to also notify
  /// the server).
  Future<void> clearSession() => client.clearToken();

  /// Releases the underlying HTTP resources.
  void dispose() => client.close();
}
