import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../auth/auth_controller.dart';
import '../workspace/workspace_models.dart';

String chatId(Json value, [String key = 'id']) {
  final id = value[key];
  if (id is! String || !RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
    throw const FormatException('Invalid chat id');
  }
  return id;
}

class ChatPage {
  ChatPage(Object? value) {
    final json = objectOf(value);
    items = recordsOf(json['items']);
    cursor = json['nextCursor'] as String?;
    hasMore = json['hasMore'] == true;
    if (hasMore && (cursor == null || cursor!.isEmpty)) {
      throw const FormatException('Invalid cursor');
    }
  }
  late final List<Json> items;
  late final String? cursor;
  late final bool hasMore;
}

List<Json> mergeChatMessages(List<Json> current, List<Json> incoming) {
  final rows = {for (final message in current) chatId(message): message};
  for (final message in incoming) {
    rows[chatId(message)] = message;
  }
  return rows.values.toList()..sort(
    (a, b) =>
        BigInt.parse(a['sequence'] as String)
            .compareTo(BigInt.parse(b['sequence'] as String)),
  );
}

class ChatController extends ChangeNotifier {
  ChatController(this.auth, this.id);
  final AuthController auth;
  final String id;
  Json? conversation;
  List<Json> messages = [];
  bool loading = false;
  bool hasMore = false;
  String? error;
  String? _cursor;
  String? _lastRead;
  bool _disposed = false;
  DateTime? _backoff;

  Future<void> refresh({
    bool older = false,
    bool quiet = false,
    bool markRead = true,
  }) async {
    if (_disposed ||
        loading ||
        (quiet && _backoff != null && DateTime.now().isBefore(_backoff!))) {
      return;
    }
    loading = true;
    if (!quiet) {
      error = null;
      notifyListeners();
    }
    try {
      final detail = await auth.getJson('/api/v1/chat/conversations/$id');
      if (_disposed) return;
      if (quiet && detail['version'] == conversation?['version']) {
        if (markRead) await _readLatest();
        return;
      }
      final oldest = messages.isEmpty
          ? null
          : BigInt.parse(messages.first['sequence'] as String);
      final fetched = <Json>[];
      String? before = older ? _cursor : null;
      ChatPage page;
      do {
        final query = Uri(
          queryParameters: {'pageSize': '50', 'before': ?before},
        ).query;
        page = ChatPage(
          await auth.request('/api/v1/chat/conversations/$id/messages?$query'),
        );
        if (_disposed) return;
        fetched.addAll(page.items);
        before = page.cursor;
        if (older || oldest == null || !page.hasMore || page.items.isEmpty) {
          break;
        }
        final earliest = page.items
            .map((m) => BigInt.parse(m['sequence'] as String))
            .reduce((a, b) => a < b ? a : b);
        if (earliest <= oldest) break;
      } while (true);
      conversation = detail;
      messages = mergeChatMessages(older ? messages : [], fetched);
      _cursor = page.cursor;
      hasMore = page.hasMore;
      error = null;
      if (markRead && !older) await _readLatest();
    } catch (failure) {
      if (_disposed) return;
      error = errorText(failure);
      if (failure is ApiException) {
        if ([401, 403, 404].contains(failure.statusCode)) {
          conversation = null;
          messages = [];
        }
        if (failure.statusCode == 429) {
          _backoff = DateTime.now().add(const Duration(seconds: 30));
        }
      }
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _readLatest() async {
    if (messages.isNotEmpty && _lastRead != chatId(messages.last)) {
      final latest = chatId(messages.last);
      await auth.request(
        '/api/v1/chat/conversations/$id/read',
        method: 'PUT',
        body: {'messageId': latest},
      );
      if (!_disposed) _lastRead = latest;
    }
  }
}
