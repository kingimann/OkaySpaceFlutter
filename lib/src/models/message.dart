import 'json.dart';
import 'post.dart';
import 'public_user.dart';

/// A message within a conversation. Messages are polymorphic (text, media,
/// voice, place, post, gif, file, contact, form, money, poll); the [type]
/// field selects which payload is populated, and [raw] always holds the rest.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.type = 'text',
    this.text,
    this.media = const [],
    this.audioBase64,
    this.audioDurationMs,
    this.transcript,
    this.postId,
    this.gifUrl,
    this.amount,
    this.pollQuestion,
    this.pollOptions = const [],
    this.replyToId,
    this.deleted = false,
    this.pinned = false,
    this.readBy = const [],
    this.deliveredBy = const [],
    this.editedAt,
    this.expiresAt,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String? text;
  final List<PostMedia> media;
  final String? audioBase64;
  final int? audioDurationMs;
  final String? transcript;
  final String? postId;
  final String? gifUrl;
  final num? amount;
  final String? pollQuestion;
  final List<String> pollOptions;
  final String? replyToId;
  final bool deleted;
  final bool pinned;
  final List<String> readBy;
  final List<String> deliveredBy;
  final DateTime? editedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: asString(json['id']),
        conversationId: asString(json['conversation_id']),
        senderId: asString(json['sender_id']),
        type: asString(json['type'], 'text'),
        text: asStringOrNull(json['text']),
        media: asModelList(json['media'], PostMedia.fromJson),
        audioBase64: asStringOrNull(json['audio_base64']),
        audioDurationMs: asIntOrNull(json['audio_duration_ms']),
        transcript: asStringOrNull(json['transcript']),
        postId: asStringOrNull(json['post_id']),
        gifUrl: asStringOrNull(json['gif_url']),
        amount: asDoubleOrNull(json['amount']),
        pollQuestion: asStringOrNull(json['poll_question']),
        pollOptions: asStringList(json['poll_options']),
        replyToId: asStringOrNull(json['reply_to_id']),
        deleted: asBool(json['deleted']),
        pinned: asBool(json['pinned']),
        readBy: asStringList(json['read_by']),
        deliveredBy: asStringList(json['delivered_by']),
        editedAt: asDateOrNull(json['edited_at']),
        expiresAt: asDateOrNull(json['expires_at']),
        createdAt: asDate(json['created_at']),
        raw: json,
      );
}

/// A conversation (one-to-one or group) as returned by the messaging API.
class ConversationView {
  const ConversationView({
    required this.id,
    this.kind = 'direct',
    this.name,
    this.avatar,
    this.theme,
    this.disappearingSeconds = 0,
    this.receiptsEnabled = true,
    this.otherUser,
    this.members = const [],
    this.ownerId,
    this.adminIds = const [],
    this.listingId,
    this.listingTitle,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
    this.raw = const {},
  });

  final String id;
  final String kind; // 'direct' | 'group'
  final String? name;
  final String? avatar;
  final String? theme;
  final int disappearingSeconds;
  final bool receiptsEnabled;
  final PublicUser? otherUser;
  final List<PublicUser> members;
  final String? ownerId;
  final List<String> adminIds;
  final String? listingId;
  final String? listingTitle;
  final Message? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  bool get isGroup => kind == 'group';

  factory ConversationView.fromJson(Map<String, dynamic> json) {
    final other = asMapOrNull(json['other_user']);
    final last = asMapOrNull(json['last_message']);
    return ConversationView(
      id: asString(json['id']),
      kind: asString(json['kind'], 'direct'),
      name: asStringOrNull(json['name']),
      avatar: asStringOrNull(json['avatar']),
      theme: asStringOrNull(json['theme']),
      disappearingSeconds: asInt(json['disappearing_seconds']),
      receiptsEnabled: asBool(json['receipts_enabled'], true),
      otherUser: other != null ? PublicUser.fromJson(other) : null,
      members: asModelList(json['members'], PublicUser.fromJson),
      ownerId: asStringOrNull(json['owner_id']),
      adminIds: asStringList(json['admin_ids']),
      listingId: asStringOrNull(json['listing_id']),
      listingTitle: asStringOrNull(json['listing_title']),
      lastMessage: last != null ? Message.fromJson(last) : null,
      lastMessageAt: asDateOrNull(json['last_message_at']),
      unreadCount: asInt(json['unread_count']),
      createdAt: asDate(json['created_at']),
      raw: json,
    );
  }
}

/// A snapshot of a live-location share: where the sharer is now, and whether
/// the share is still running.
class LiveLocationView {
  const LiveLocationView({
    required this.shareId,
    required this.userId,
    this.name,
    required this.latitude,
    required this.longitude,
    this.active = true,
    this.expiresAt,
    this.updatedAt,
  });

  final String shareId;
  final String userId;
  final String? name;
  final double latitude;
  final double longitude;
  final bool active;
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  factory LiveLocationView.fromJson(Map<String, dynamic> json) =>
      LiveLocationView(
        shareId: asString(json['share_id']),
        userId: asString(json['user_id']),
        name: asStringOrNull(json['name']),
        latitude: asDoubleOrNull(json['latitude']) ?? 0,
        longitude: asDoubleOrNull(json['longitude']) ?? 0,
        active: asBool(json['active'], true),
        expiresAt: asDateOrNull(json['expires_at']),
        updatedAt: asDateOrNull(json['updated_at']),
      );
}

/// A snapshot of an in-chat game (e.g. tic-tac-toe).
class GameView {
  const GameView({
    required this.gameId,
    required this.conversationId,
    required this.gameType,
    required this.board,
    required this.xPlayer,
    required this.oPlayer,
    required this.turn,
    this.status = 'active',
    this.winner,
  });

  final String gameId;
  final String conversationId;
  final String gameType;
  final List<String> board; // 9 cells: '', 'X' or 'O'
  final String xPlayer;
  final String oPlayer;
  final String turn; // user id whose move it is
  final String status; // active | won | draw
  final String? winner; // user id of the winner

  bool get isOver => status != 'active';

  factory GameView.fromJson(Map<String, dynamic> json) => GameView(
        gameId: asString(json['game_id']),
        conversationId: asString(json['conversation_id']),
        gameType: asString(json['game_type'], 'tictactoe'),
        board: asStringList(json['board']),
        xPlayer: asString(json['x_player']),
        oPlayer: asString(json['o_player']),
        turn: asString(json['turn']),
        status: asString(json['status'], 'active'),
        winner: asStringOrNull(json['winner']),
      );
}

/// A snapshot of a blackjack hand (player vs dealer).
class BlackjackView {
  const BlackjackView({
    required this.gameId,
    required this.player,
    required this.dealer,
    required this.playerTotal,
    required this.dealerTotal,
    this.status = 'active',
  });

  final String gameId;
  final List<Map<String, dynamic>> player; // [{'r':'A','s':'♠'}, ...]
  final List<Map<String, dynamic>> dealer;
  final int playerTotal;
  final int dealerTotal;
  final String status; // active | blackjack | win | lose | push

  bool get isOver => status != 'active';

  static List<Map<String, dynamic>> _cards(Object? v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  factory BlackjackView.fromJson(Map<String, dynamic> json) => BlackjackView(
        gameId: asString(json['game_id']),
        player: _cards(json['player']),
        dealer: _cards(json['dealer']),
        playerTotal: asInt(json['player_total']),
        dealerTotal: asInt(json['dealer_total']),
        status: asString(json['status'], 'active'),
      );
}

/// A snapshot of a chess game.
class ChessView {
  const ChessView({
    required this.gameId,
    required this.board,
    required this.whitePlayer,
    required this.blackPlayer,
    required this.turn,
    this.inCheck = false,
    this.status = 'active',
    this.winner,
  });

  final String gameId;
  final String board; // 64 chars, a8..h1; uppercase white, lowercase black, '.' empty
  final String whitePlayer;
  final String blackPlayer;
  final String turn; // user id whose move it is
  final bool inCheck;
  final String status; // active | checkmate | stalemate | draw
  final String? winner;

  bool get isOver => status != 'active';

  factory ChessView.fromJson(Map<String, dynamic> json) => ChessView(
        gameId: asString(json['game_id']),
        board: asString(json['board']),
        whitePlayer: asString(json['white_player']),
        blackPlayer: asString(json['black_player']),
        turn: asString(json['turn']),
        inCheck: asBool(json['in_check']),
        status: asString(json['status'], 'active'),
        winner: asStringOrNull(json['winner']),
      );
}

/// A snapshot of a checkers game.
class CheckersView {
  const CheckersView({
    required this.gameId,
    required this.board,
    required this.whitePlayer,
    required this.blackPlayer,
    required this.turn,
    this.chain,
    this.status = 'active',
    this.winner,
  });

  final String gameId;
  final String board; // 64 chars; w/W white, b/B black, '.' empty
  final String whitePlayer;
  final String blackPlayer;
  final String turn;
  final int? chain; // square mid multi-jump that must continue
  final String status; // active | white_won | black_won
  final String? winner;

  bool get isOver => status != 'active';

  factory CheckersView.fromJson(Map<String, dynamic> json) => CheckersView(
        gameId: asString(json['game_id']),
        board: asString(json['board']),
        whitePlayer: asString(json['white_player']),
        blackPlayer: asString(json['black_player']),
        turn: asString(json['turn']),
        chain: asIntOrNull(json['chain']),
        status: asString(json['status'], 'active'),
        winner: asStringOrNull(json['winner']),
      );
}

/// A snapshot of a Connect Four game.
class ConnectFourView {
  const ConnectFourView({
    required this.gameId,
    required this.board,
    required this.redPlayer,
    required this.yellowPlayer,
    required this.turn,
    this.status = 'active',
    this.winner,
  });

  final String gameId;
  final String board; // 42 chars, row0=top, '.'/'R'/'Y'
  final String redPlayer;
  final String yellowPlayer;
  final String turn;
  final String status; // active | won | draw
  final String? winner;

  bool get isOver => status != 'active';

  factory ConnectFourView.fromJson(Map<String, dynamic> json) =>
      ConnectFourView(
        gameId: asString(json['game_id']),
        board: asString(json['board']),
        redPlayer: asString(json['red_player']),
        yellowPlayer: asString(json['yellow_player']),
        turn: asString(json['turn']),
        status: asString(json['status'], 'active'),
        winner: asStringOrNull(json['winner']),
      );
}

/// A snapshot of a Dots and Boxes game on a [dots]×[dots] grid.
class DotsBoxesView {
  const DotsBoxesView({
    required this.gameId,
    required this.h,
    required this.v,
    required this.owner,
    required this.dots,
    required this.redPlayer,
    required this.yellowPlayer,
    required this.turn,
    this.redScore = 0,
    this.yellowScore = 0,
    this.status = 'active',
    this.winner,
  });

  final String gameId;
  final String h; // horizontal edges, '0'/'1'
  final String v; // vertical edges, '0'/'1'
  final String owner; // box owners, '.'/'R'/'Y'
  final int dots;
  final String redPlayer;
  final String yellowPlayer;
  final String turn;
  final int redScore;
  final int yellowScore;
  final String status; // active | won | draw
  final String? winner;

  bool get isOver => status != 'active';

  factory DotsBoxesView.fromJson(Map<String, dynamic> json) => DotsBoxesView(
        gameId: asString(json['game_id']),
        h: asString(json['h']),
        v: asString(json['v']),
        owner: asString(json['owner']),
        dots: asInt(json['dots'], 4),
        redPlayer: asString(json['red_player']),
        yellowPlayer: asString(json['yellow_player']),
        turn: asString(json['turn']),
        redScore: asInt(json['red_score']),
        yellowScore: asInt(json['yellow_score']),
        status: asString(json['status'], 'active'),
        winner: asStringOrNull(json['winner']),
      );
}

/// A snapshot of a five-card draw poker hand (player vs dealer).
class PokerView {
  const PokerView({
    required this.gameId,
    required this.you,
    required this.opponent,
    required this.yourHand,
    this.opponentHand,
    this.status = 'active',
  });

  final String gameId;
  final List<Map<String, dynamic>> you;
  final List<Map<String, dynamic>> opponent; // hidden until showdown
  final String yourHand;
  final String? opponentHand;
  final String status; // active | revealing | win | lose | push

  bool get isOver => status == 'win' || status == 'lose' || status == 'push';

  static List<Map<String, dynamic>> _cards(Object? v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  factory PokerView.fromJson(Map<String, dynamic> json) => PokerView(
        gameId: asString(json['game_id']),
        you: _cards(json['you']),
        opponent: _cards(json['opponent']),
        yourHand: asString(json['your_hand']),
        opponentHand: asStringOrNull(json['opponent_hand']),
        status: asString(json['status'], 'active'),
      );
}

/// A player's all-games win/loss/tie record.
class GameStats {
  const GameStats(
      {this.wins = 0, this.losses = 0, this.ties = 0, this.games = 0});

  final int wins;
  final int losses;
  final int ties;
  final int games;

  factory GameStats.fromJson(Map<String, dynamic> json) => GameStats(
        wins: asInt(json['wins']),
        losses: asInt(json['losses']),
        ties: asInt(json['ties']),
        games: asInt(json['games']),
      );
}

/// A player's best score per arcade game type (Pong/Snake).
class GameScores {
  const GameScores({this.scores = const {}});

  final Map<String, int> scores; // game_type -> best score

  int best(String gameType) => scores[gameType] ?? 0;

  factory GameScores.fromJson(Map<String, dynamic> json) {
    final out = <String, int>{};
    final s = json['scores'];
    if (s is Map) {
      s.forEach((k, v) => out['$k'] = v is num ? v.toInt() : 0);
    }
    return GameScores(scores: out);
  }
}

/// Request body for sending a message. Defaults to a plain text message.
class MessageCreate {
  const MessageCreate({
    this.type = 'text',
    this.text,
    this.media = const [],
    this.audioBase64,
    this.audioDurationMs,
    this.postId,
    this.gifUrl,
    this.amount,
    this.pollQuestion,
    this.pollOptions,
    this.placeName,
    this.placeAddress,
    this.placeLongitude,
    this.placeLatitude,
    this.fileBase64,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.contactUserId,
    this.formId,
    this.replyTo,
  });

  final String type;
  final String? text;
  final List<PostMedia> media;
  final String? audioBase64;
  final int? audioDurationMs;
  final String? postId;
  final String? gifUrl;
  final num? amount;
  final String? pollQuestion;
  final List<String>? pollOptions;
  final String? placeName;
  final String? placeAddress;
  final double? placeLongitude;
  final double? placeLatitude;
  final String? fileBase64;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;
  final String? contactUserId;
  final String? formId;
  final String? replyTo;

  /// A plain text message.
  factory MessageCreate.text(String text, {String? replyTo}) =>
      MessageCreate(type: 'text', text: text, replyTo: replyTo);

  Map<String, dynamic> toJson() => {
        'type': type,
        if (text != null) 'text': text,
        if (media.isNotEmpty) 'media': media.map((m) => m.toJson()).toList(),
        if (audioBase64 != null) 'audio_base64': audioBase64,
        if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
        if (postId != null) 'post_id': postId,
        if (gifUrl != null) 'gif_url': gifUrl,
        if (amount != null) 'amount': amount,
        if (pollQuestion != null) 'poll_question': pollQuestion,
        if (pollOptions != null) 'poll_options': pollOptions,
        if (placeName != null) 'place_name': placeName,
        if (placeAddress != null) 'place_address': placeAddress,
        if (placeLongitude != null) 'place_longitude': placeLongitude,
        if (placeLatitude != null) 'place_latitude': placeLatitude,
        if (fileBase64 != null) 'file_base64': fileBase64,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (fileMime != null) 'file_mime': fileMime,
        if (contactUserId != null) 'contact_user_id': contactUserId,
        if (formId != null) 'form_id': formId,
        if (replyTo != null) 'reply_to': replyTo,
      };
}
