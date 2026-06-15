import 'core/api_client.dart';
import 'core/api_config.dart';
import 'core/token_store.dart';
import 'services/admin_service.dart';
import 'services/ads_service.dart';
import 'services/auth_service.dart';
import 'services/circles_service.dart';
import 'services/communities_service.dart';
import 'services/feed_service.dart';
import 'services/forms_service.dart';
import 'services/friends_service.dart';
import 'services/games_service.dart';
import 'services/groups_service.dart';
import 'services/guides_service.dart';
import 'services/calendar_service.dart';
import 'services/maps_service.dart';
import 'services/marketplace_service.dart';
import 'services/messaging_service.dart';
import 'services/monetize_service.dart';
import 'services/notes_service.dart';
import 'services/reminders_service.dart';
import 'services/notifications_service.dart';
import 'services/oauth_service.dart';
import 'services/payments_service.dart';
import 'services/roadside_service.dart';
import 'services/hazards_service.dart';
import 'services/support_service.dart';
import 'services/users_service.dart';
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
    forms = FormsService(this.client);
    maps = MapsService(this.client);
    messaging = MessagingService(this.client);
    circles = CirclesService(this.client);
    communities = CommunitiesService(this.client);
    groups = GroupsService(this.client);
    guides = GuidesService(this.client);
    marketplace = MarketplaceService(this.client);
    wallet = WalletService(this.client);
    users = UsersService(this.client);
    friends = FriendsService(this.client);
    notifications = NotificationsService(this.client);
    roadside = RoadsideService(this.client);
    hazards = HazardsService(this.client);
    payments = PaymentsService(this.client);
    ads = AdsService(this.client);
    support = SupportService(this.client);
    admin = AdminService(this.client);
    oauth = OAuthService(this.client);
    games = GamesService(this.client);
    monetize = MonetizeService(this.client);
    notes = NotesService(this.client);
    calendar = CalendarService(this.client);
    reminders = RemindersService(this.client);
  }

  /// Shared low-level client. Use it directly for endpoints not yet wrapped by
  /// a dedicated service.
  final ApiClient client;

  /// `/auth` — registration, login, current user, account & API keys.
  late final AuthService auth;

  /// `/feed`, `/posts`, `/hashtags` — the social feed.
  late final FeedService feed;

  /// `/forms` — custom form builder and submissions.
  late final FormsService forms;

  /// `/maps/*` — AI-assisted place search via the local model.
  late final MapsService maps;

  /// `/conversations`, `/presence`, `/calls` — messaging.
  late final MessagingService messaging;

  /// `/circles` — private audience circles for post targeting.
  late final CirclesService circles;

  /// `/communities` — topic hubs, membership and moderation.
  late final CommunitiesService communities;

  /// `/groups` — membership groups, posts, events and requests.
  late final GroupsService groups;

  /// `/places`, `/guides` — saved places and curated guide collections.
  late final GuidesService guides;

  /// `/listings`, `/marketplace` — buying and selling.
  late final MarketplaceService marketplace;

  /// `/wallet`, `/money` — balance, transfers and top-ups.
  late final WalletService wallet;

  /// `/users` — public profiles, search, following, subscribe/tip/poke.
  late final UsersService users;

  /// `/friends` — friend list, requests and the request lifecycle.
  late final FriendsService friends;

  /// `/notifications` — list, unread count and read/dismiss actions.
  late final NotificationsService notifications;

  /// `/roadside` — roadside assistance requests and lifecycle.
  late final RoadsideService roadside;

  /// `/hazards` — crowd-reported road incidents.
  late final HazardsService hazards;

  /// `/payments` — checkout, payment intents, identity and payout setup.
  late final PaymentsService payments;

  /// `/ads` — advertiser account, campaigns and ad serving.
  late final AdsService ads;

  /// `/support` — help-desk tickets.
  late final SupportService support;

  /// `/admin` — moderation, finance and platform ops (admin accounts only).
  late final AdminService admin;

  /// `/oauth` — OAuth apps, authorization flow and connections.
  late final OAuthService oauth;

  /// `/games` — browse/create games and SDK leaderboards.
  late final GamesService games;

  /// `/pub` — publisher ad network (monetize): sites, earnings, embed.
  late final MonetizeService monetize;

  /// `/notes` — personal private notes.
  late final NotesService notes;

  /// `/calendar` — personal calendar events.
  late final CalendarService calendar;

  /// `/reminders` — personal to-do checklist.
  late final RemindersService reminders;

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
