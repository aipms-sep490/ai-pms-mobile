import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/auth/auth_controller.dart';
import 'signalr_client.dart';
import 'ws_connector.dart';

class ChatHubEvent {
  const ChatHubEvent({
    required this.type,
    this.conversationId,
    this.userId,
    this.isTyping,
    this.onlineUserIds = const [],
  });

  final String type;
  final String? conversationId;
  final String? userId;
  final bool? isTyping;
  final List<String> onlineUserIds;
}

class LiveNotificationEvent {
  const LiveNotificationEvent({
    required this.notificationId,
    required this.title,
    required this.content,
    this.notificationType,
    this.relatedEntityType,
    this.relatedEntityId,
  });

  final int notificationId;
  final String title;
  final String content;
  final String? notificationType;
  final String? relatedEntityType;
  final int? relatedEntityId;
}

/// Coordinates foreground SignalR connections for `/hubs/chat` and `/hubs/notifications`.
/// Automatically starts/stops with auth session and app lifecycle.
class RealtimeHubManager extends ChangeNotifier {
  RealtimeHubManager({
    required this.auth,
    this.socketFactory,
    this.enabled = true,
  }) {
    auth.addListener(_onAuthChanged);
    _syncSession();
  }

  final AuthController auth;
  final WebSocketFactory? socketFactory;
  final bool enabled;

  SignalRHubClient? _chatHub;
  SignalRHubClient? _notificationHub;
  int? _connectedUserId;
  bool _paused = false;
  HubConnectionStatus _chatStatus = HubConnectionStatus.disconnected;
  HubConnectionStatus _notificationStatus = HubConnectionStatus.disconnected;
  int _unreadNotificationBump = 0;
  LiveNotificationEvent? _latestNotification;
  String? _watchedConversationId;

  final _chatEvents = StreamController<ChatHubEvent>.broadcast();
  final _notificationEvents =
      StreamController<LiveNotificationEvent>.broadcast();

  HubConnectionStatus get chatStatus => _chatStatus;
  HubConnectionStatus get notificationStatus => _notificationStatus;
  bool get chatConnected => _chatStatus == HubConnectionStatus.connected;
  bool get notificationConnected =>
      _notificationStatus == HubConnectionStatus.connected;
  int get unreadNotificationBump => _unreadNotificationBump;
  LiveNotificationEvent? get latestNotification => _latestNotification;

  Stream<ChatHubEvent> get chatEvents => _chatEvents.stream;
  Stream<LiveNotificationEvent> get notificationEvents =>
      _notificationEvents.stream;

  void clearUnreadBump() {
    if (_unreadNotificationBump == 0 && _latestNotification == null) return;
    _unreadNotificationBump = 0;
    _latestNotification = null;
    notifyListeners();
  }

  void setAppPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (paused) {
      unawaited(_stopHubs());
    } else {
      _syncSession(forceRestart: true);
    }
  }

  Future<void> watchConversation(String conversationId) async {
    _watchedConversationId = conversationId;
    await _chatHub?.invoke('WatchConversation', [conversationId]);
  }

  Future<void> unwatchConversation(String conversationId) async {
    if (_watchedConversationId == conversationId) {
      _watchedConversationId = null;
    }
    await _chatHub?.invoke('UnwatchConversation', [conversationId]);
  }

  Future<void> setTyping(String conversationId, bool isTyping) async {
    await _chatHub?.invoke('SetTyping', [conversationId, isTyping]);
  }

  void _onAuthChanged() => _syncSession();

  void _syncSession({bool forceRestart = false}) {
    if (!enabled) return;
    final user = auth.user;
    final isAuthed = auth.status == SessionStatus.authenticated && user != null;
    if (!isAuthed || _paused) {
      _connectedUserId = null;
      _watchedConversationId = null;
      _unreadNotificationBump = 0;
      _latestNotification = null;
      unawaited(_stopHubs());
      return;
    }
    if (!forceRestart && _connectedUserId == user.id && _chatHub != null) {
      return;
    }
    _connectedUserId = user.id;
    unawaited(_startHubs());
  }

  Future<void> _startHubs() async {
    await _stopHubs();
    if (!enabled || _paused || auth.status != SessionStatus.authenticated) {
      return;
    }

    final roles = auth.user?.roles ?? const <String>[];
    final isPureAdmin =
        roles.isNotEmpty && roles.every((r) => r.toUpperCase() == 'ADMIN');

    if (!isPureAdmin) {
      final chat = SignalRHubClient(
        api: auth.api,
        hubPath: '/hubs/chat',
        tokenProvider: auth.validAccessToken,
        socketFactory: socketFactory,
      );
      chat.addStatusListener((next) {
        _chatStatus = next;
        if (next == HubConnectionStatus.connected &&
            _watchedConversationId != null) {
          unawaited(chat.invoke('WatchConversation', [_watchedConversationId]));
        }
        notifyListeners();
      });
      for (final name in const [
        'MessagesChanged',
        'ConversationChanged',
        'ReadStateChanged',
        'AccessRevoked',
      ]) {
        chat.on(name, (args) {
          final map = args.isNotEmpty && args.first is Map<String, dynamic>
              ? args.first as Map<String, dynamic>
              : const <String, dynamic>{};
          final id = map['conversationId']?.toString();
          _chatEvents.add(ChatHubEvent(type: name, conversationId: id));
        });
      }
      chat.on('TypingChanged', (args) {
        final map = args.isNotEmpty && args.first is Map<String, dynamic>
            ? args.first as Map<String, dynamic>
            : const <String, dynamic>{};
        _chatEvents.add(
          ChatHubEvent(
            type: 'TypingChanged',
            conversationId: map['conversationId']?.toString(),
            userId: map['userId']?.toString(),
            isTyping: map['isTyping'] == true,
          ),
        );
      });
      chat.on('PresenceChanged', (args) {
        final map = args.isNotEmpty && args.first is Map<String, dynamic>
            ? args.first as Map<String, dynamic>
            : const <String, dynamic>{};
        final ids = map['onlineUserIds'] is List
            ? (map['onlineUserIds'] as List).map((e) => '$e').toList()
            : const <String>[];
        _chatEvents.add(
          ChatHubEvent(
            type: 'PresenceChanged',
            conversationId: map['conversationId']?.toString(),
            onlineUserIds: ids,
          ),
        );
      });
      _chatHub = chat;
      unawaited(chat.start());
    }

    // Native clients can send Bearer header to /hubs/notifications; web also tries cleanly.
    final notifications = SignalRHubClient(
      api: auth.api,
      hubPath: '/hubs/notifications',
      tokenProvider: auth.validAccessToken,
      socketFactory: socketFactory,
    );
    notifications.addStatusListener((next) {
      _notificationStatus = next;
      notifyListeners();
    });
    notifications.on('NotificationReceived', (args) {
      final map = args.isNotEmpty && args.first is Map<String, dynamic>
          ? args.first as Map<String, dynamic>
          : const <String, dynamic>{};
      final id = map['notificationId'] is int
          ? map['notificationId'] as int
          : int.tryParse('${map['notificationId']}') ?? 0;
      final event = LiveNotificationEvent(
        notificationId: id,
        title: map['title'] is String
            ? map['title'] as String
            : 'Thông báo mới',
        content: map['content'] is String ? map['content'] as String : '',
        notificationType: map['notificationType'] as String?,
        relatedEntityType: map['relatedEntityType'] as String?,
        relatedEntityId: map['relatedEntityId'] is int
            ? map['relatedEntityId'] as int
            : null,
      );
      _unreadNotificationBump++;
      _latestNotification = event;
      _notificationEvents.add(event);
      notifyListeners();
    });
    _notificationHub = notifications;
    unawaited(notifications.start());
  }

  Future<void> _stopHubs() async {
    final chat = _chatHub;
    final notifications = _notificationHub;
    _chatHub = null;
    _notificationHub = null;
    _chatStatus = HubConnectionStatus.disconnected;
    _notificationStatus = HubConnectionStatus.disconnected;
    await chat?.stop();
    await notifications?.stop();
  }

  @override
  void dispose() {
    auth.removeListener(_onAuthChanged);
    unawaited(_stopHubs());
    unawaited(_chatEvents.close());
    unawaited(_notificationEvents.close());
    super.dispose();
  }
}
