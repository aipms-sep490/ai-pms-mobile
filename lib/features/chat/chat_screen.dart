import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_model.dart';
import '../workspace/workspace_models.dart';
import '../ai/ai_screen.dart';
import 'chat_controller.dart';
import 'composer_exit_guard.dart';
import 'chat_members_screen.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  int _revision = 0;
  bool _busy = false;
  final _rows = <Json>[];
  String? _cursor;
  String? _nextCursor;
  String _search = '';
  bool _unreadOnly = false;

  Future<List<Json>> _load() async {
    final query = Uri(queryParameters: {'pageSize': '30', 'cursor': ?_cursor})
        .query;
    final page = ChatPage(
      await widget.auth.request('/api/v1/chat/conversations?$query'),
    );
    final rows = {
      for (final row in _cursor == null ? <Json>[] : _rows) chatId(row): row,
    };
    for (final row in page.items) {
      rows[chatId(row)] = row;
    }
    _rows
      ..clear()
      ..addAll(rows.values);
    _nextCursor = page.hasMore ? page.cursor : null;
    _cursor = null;
    return List.of(_rows);
  }

  Future<void> _open(String path, {Object? body}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final conversation = objectOf(
        await widget.auth.request(path, method: 'POST', body: body),
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatThreadScreen(auth: widget.auth, id: chatId(conversation)),
        ),
      );
      if (mounted) {
        setState(() {
          _cursor = null;
          _revision++;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newConversation() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Nhắn trực tiếp'),
                subtitle: const Text('Chọn người nhận trong phạm vi của bạn'),
                onTap: () => Navigator.pop(sheet, 'direct'),
              ),
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Chat nhóm / đồ án'),
                subtitle: const Text('Mở không gian trao đổi của nhóm'),
                onTap: () => Navigator.pop(sheet, 'group'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || kind == null) return;
    if (kind == 'direct') {
      final person = await Navigator.push<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatContactsScreen(auth: widget.auth),
        ),
      );
      if (mounted && person != null) {
        await _open(
          '/api/v1/chat/conversations/direct',
          body: {'recipientUserId': chatId(person, 'userId')},
        );
      }
      return;
    }
    try {
      final dashboard = StudentDashboard.fromJson(
        await widget.auth.getJson('/api/v1/dashboards/student'),
      );
      if (!mounted) return;
      if (dashboard.project != null) {
        await _open(
          '/api/v1/chat/projects/${dashboard.project!.id}/conversation',
        );
      } else if (dashboard.teamId != null) {
        await _open('/api/v1/chat/teams/${dashboard.teamId}/conversation');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn chưa có nhóm để trò chuyện.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(error))));
      }
    }
  }

  bool _matches(Json row) =>
      (!_unreadOnly ||
          (row['unreadCount'] is num && (row['unreadCount'] as num) > 0)) &&
      textOf(row, 'title').toLowerCase().contains(_search);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Trò chuyện'),
      actions: [
        IconButton(
          tooltip: 'Cuộc trò chuyện mới',
          onPressed: _busy ? null : _newConversation,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.edit_square),
        ),
      ],
    ),
    body: RemotePage<List<Json>>(
      title: 'Tin nhắn',
      showHeading: false,
      revision: _revision,
      load: _load,
      content: (context, rows, refresh) => [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Tìm cuộc trò chuyện đã tải',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => _search = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 8),
        HorizontalChoices(
          children: [
            ChoiceChip(
              label: const Text('Tất cả'),
              selected: !_unreadOnly,
              onSelected: (_) => setState(() => _unreadOnly = false),
            ),
            ChoiceChip(
              label: const Text('Chưa đọc'),
              selected: _unreadOnly,
              onSelected: (_) => setState(() => _unreadOnly = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty) ...[
          const ContentSection(
            'Bắt đầu trao đổi',
            'Nhắn với thành viên hoặc mở cuộc trò chuyện nhóm để theo dõi đồ án cùng nhau.',
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Cuộc trò chuyện mới'),
          ),
        ],
        if (rows.isNotEmpty && !rows.any(_matches))
          const ContentSection(
            'Không có cuộc trò chuyện phù hợp',
            'Thử tên khác, đổi bộ lọc hoặc tải thêm cuộc trò chuyện.',
          ),
        for (final row in rows.where(_matches))
          _ConversationRow(
            conversation: row,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ChatThreadScreen(auth: widget.auth, id: chatId(row)),
                ),
              );
              if (context.mounted) {
                _cursor = null;
                await refresh();
              }
            },
          ),
        if (_nextCursor != null)
          OutlinedButton(
            onPressed: () => setState(() {
              _cursor = _nextCursor;
              _revision++;
            }),
            child: const Text('Tải thêm cuộc trò chuyện'),
          ),
      ],
    ),
  );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.onTap});
  final Json conversation;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final unread = conversation['unreadCount'] is num
        ? conversation['unreadCount'] as num
        : 0;
    final last = conversation['lastMessage'];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 21,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textOf(conversation, 'title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: unread > 0
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      last is Json
                          ? textOf(last, 'body', 'Tệp đính kèm')
                          : 'Chưa có tin nhắn',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayDate(conversation['updatedAt']),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Semantics(
                    label: '$unread tin chưa đọc',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$unread',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatContactsScreen extends StatefulWidget {
  const ChatContactsScreen({super.key, required this.auth});
  final AuthController auth;
  @override
  State<ChatContactsScreen> createState() => _ChatContactsScreenState();
}

class _ChatContactsScreenState extends State<ChatContactsScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _cursor;
  String? _nextCursor;
  int _revision = 0;
  final _rows = <Json>[];
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Người nhận')),
    body: RemotePage<List<Json>>(
      title: 'Chọn người nhận',
      showHeading: false,
      revision: _revision,
      load: () async {
        final query = Uri(
          queryParameters: {
            'search': _query,
            'pageSize': '30',
            'cursor': ?_cursor,
          },
        ).query;
        final page = ChatPage(
          await widget.auth.request('/api/v1/chat/recipients?$query'),
        );
        if (_cursor == null) _rows.clear();
        final merged = {
          for (final row in _rows) chatId(row, 'userId'): row,
          for (final row in page.items) chatId(row, 'userId'): row,
        };
        _rows
          ..clear()
          ..addAll(merged.values);
        _nextCursor = page.hasMore ? page.cursor : null;
        _cursor = null;
        return List.of(_rows);
      },
      content: (context, rows, refresh) => [
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Tìm tên người nhận',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Tìm người nhận',
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => setState(() {
                _query = _search.text.trim();
                _cursor = null;
                _revision++;
              }),
            ),
          ),
          onSubmitted: (value) => setState(() {
            _query = value.trim();
            _cursor = null;
            _revision++;
          }),
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const Text('Không tìm thấy người nhận trong phạm vi của bạn.'),
        for (final person in rows)
          RecordTile(
            title: textOf(person, 'fullName'),
            subtitle: 'Nhắn tin trực tiếp',
            icon: Icons.person_outline,
            onTap: () => Navigator.pop(context, person),
          ),
        if (_nextCursor != null)
          OutlinedButton(
            onPressed: () => setState(() {
              _cursor = _nextCursor;
              _revision++;
            }),
            child: const Text('Tải thêm'),
          ),
      ],
    ),
  );
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({super.key, required this.auth, required this.id});
  final AuthController auth;
  final String id;
  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen>
    with WidgetsBindingObserver {
  late final ChatController _chat = ChatController(widget.auth, widget.id);
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _busy = false;
  bool _sending = false;
  String? _error;
  Json? _reply;
  final _attachments = <Json>[];
  String? _pendingId;
  String? _pendingSignature;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chat.addListener(_syncReply);
    _chat.refresh();
    _startPolling();
  }

  void _syncReply() {
    if (_reply == null || !mounted) return;
    Json? current;
    if (_chat.conversation != null) {
      for (final message in _chat.messages) {
        if (message['id'] == _reply!['id'] && message['recalledAt'] == null) {
          current = message;
          break;
        }
      }
    }
    setState(() => _reply = current);
  }

  void _startPolling() {
    _timer?.cancel();
    // ponytail: foreground REST invalidation every four seconds; switch to the
    // existing SignalR hub when concurrent mobile traffic warrants it.
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        _chat.refresh(
          quiet: true,
          markRead: !_scroll.hasClients || _scroll.position.pixels < 80,
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _chat.refresh(quiet: true);
      _startPolling();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _chat.removeListener(_syncReply);
    _chat.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _busy || _chat.conversation?['canSend'] != true) return;
    final text = _text.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (text.length > 4000) {
      setState(() => _error = 'Tin nhắn tối đa 4000 ký tự.');
      return;
    }
    final ids = _attachments.map((f) => chatId(f)).toList();
    final signature = '$text/${_reply?['id']}/${ids.join(',')}';
    if (_pendingSignature != signature) {
      _pendingSignature = signature;
      _pendingId = const Uuid().v4();
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/chat/conversations/${widget.id}/messages',
        method: 'POST',
        body: {
          'clientMessageId': _pendingId,
          'body': text.isEmpty ? null : text,
          'replyToMessageId': _reply?['id'],
          'attachmentIds': ids,
        },
      );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _reply = null;
        _attachments.clear();
        _pendingId = null;
        _pendingSignature = null;
      });
      await _chat.refresh();
      if (mounted && _scroll.hasClients) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(0);
        } else {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy || _sending) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _chat.refresh();
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async => _action(() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) return;
    final policy = await widget.auth.getJson(
      '/api/v1/upload-policies/CHAT_ATTACHMENT',
    );
    final maxBytes = policy['maxBytes'] as int;
    final size = await file.length();
    if (size == null || size <= 0 || size > maxBytes) {
      throw ApiException(
        'Chọn tệp không vượt quá ${textOf(policy, 'maxBytesLabel')}.',
      );
    }
    final extension = file.name.split('.').last.toLowerCase();
    final allowed = (policy['allowedExtensions'] as List).whereType<String>();
    if (!allowed.contains('.$extension')) {
      throw const ApiException(
        'Định dạng tệp chưa được hỗ trợ cho trò chuyện.',
      );
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    const mime = {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'txt': 'text/plain',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'zip': 'application/zip',
    };
    final attachment = objectOf(
      await widget.auth.request(
        '/api/v1/chat/conversations/${widget.id}/uploads',
        method: 'POST',
        upload: ApiUpload(
          file.name,
          bytes,
          contentType: mime[extension] ?? 'application/octet-stream',
        ),
        requestTimeout: const Duration(seconds: 60),
      ),
    );
    if (mounted) setState(() => _attachments.add(attachment));
  });

  Future<void> _download(
    Json message,
    Json attachment,
  ) async => _action(() async {
    final bytes = await widget.auth.request(
      '/api/v1/chat/conversations/${widget.id}/messages/${chatId(message)}/attachments/${chatId(attachment)}/download',
      binary: true,
    ) as Uint8List;
    if (!mounted) return;
    await FilePicker.saveFile(
      fileName: textOf(attachment, 'fileName', 'attachment'),
      bytes: bytes,
      mimeType: textOf(attachment, 'contentType', 'application/octet-stream'),
    );
  });

  Future<void> _messageMenu(Json message) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Trả lời'),
                onTap: () => Navigator.pop(sheet, 'reply'),
              ),
              if (message['canEdit'] == true)
                ListTile(
                  title: const Text('Sửa tin nhắn'),
                  onTap: () => Navigator.pop(sheet, 'edit'),
                ),
              if (message['canRecall'] == true)
                ListTile(
                  title: const Text('Thu hồi'),
                  onTap: () => Navigator.pop(sheet, 'recall'),
                ),
              ListTile(
                title: const Text('Thích 👍'),
                onTap: () => Navigator.pop(sheet, 'react'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'reply') {
      setState(() => _reply = message);
      return;
    }
    if (choice == 'edit') {
      final body = await showDialog<String>(
        context: context,
        builder: (_) => ChatEditDialog(initial: textOf(message, 'body', '')),
      );
      if (!mounted || body == null) return;
      await _action(() async {
        await widget.auth.request(
          '/api/v1/chat/conversations/${widget.id}/messages/${chatId(message)}',
          method: 'PATCH',
          body: {'body': body, 'concurrencyToken': message['concurrencyToken']},
        );
      });
    } else if (choice == 'recall') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Thu hồi tin nhắn?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Thu hồi'),
            ),
          ],
        ),
      );
      if (confirm == true && mounted) {
        await _action(() async {
          await widget.auth.request(
            '/api/v1/chat/conversations/${widget.id}/messages/${chatId(message)}/recall',
            method: 'POST',
            body: {'concurrencyToken': message['concurrencyToken']},
          );
        });
      }
    } else {
      final reacted = recordsOf(message['reactions'] ?? [])
          .any((r) => r['emoji'] == '👍' && r['reactedByMe'] == true);
      await _action(() async {
        await widget.auth.request(
          '/api/v1/chat/conversations/${widget.id}/messages/${chatId(message)}/reactions${reacted ? '?emoji=${Uri.encodeComponent('👍')}' : ''}',
          method: reacted ? 'DELETE' : 'PUT',
          body: reacted ? null : {'emoji': '👍'},
        );
      });
    }
  }

  Widget _messageBubble(Json message) {
    final own = message['senderId'] == '${widget.auth.user?.id}';
    final recalled = message['recalledAt'] != null;
    final reactions = recordsOf(message['reactions'] ?? []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 680) - 32,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: own
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!own)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 4),
                        child: Text(
                          textOf(message, 'senderName'),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    Material(
                      color: own ? AppColors.primarySoft : AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onLongPress: recalled || _busy || _sending
                            ? null
                            : () => _messageMenu(message),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message['reply'] is Json) ...[
                                Text(
                                  '↳ ${textOf(message['reply'] as Json, 'body', 'Tin nhắn không còn khả dụng')}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                              ],
                              if (recalled ||
                                  textOf(message, 'body', '').isNotEmpty)
                                SelectableBody(
                                  recalled
                                      ? 'Tin nhắn đã được thu hồi.'
                                      : textOf(message, 'body', ''),
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        fontStyle: recalled
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                ),
                              if (!recalled)
                                for (final attachment in recordsOf(
                                  message['attachments'] ?? [],
                                ))
                                  TextButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _download(message, attachment),
                                    icon: const Icon(
                                      Icons.attach_file,
                                      size: 18,
                                    ),
                                    label: Text(
                                      textOf(attachment, 'fileName'),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              if (!recalled && reactions.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  reactions
                                      .map((r) => '${r['emoji']} ${r['count']}')
                                      .join('  '),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Text(
                        '${displayDate(message['createdAt'])}${message['editedAt'] != null ? ' · Đã sửa' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              if (!recalled)
                IconButton(
                  tooltip: 'Thao tác tin nhắn',
                  onPressed: _busy || _sending
                      ? null
                      : () => _messageMenu(message),
                  icon: const Icon(Icons.more_horiz, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ComposerExitGuard(
    controller: _text,
    sending: _sending,
    hasContext: _reply != null || _attachments.isNotEmpty,
    child: Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _chat,
          builder: (context, _) => Text(
            textOf(_chat.conversation ?? {}, 'title', 'Trò chuyện'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn cuộc trò chuyện',
            onSelected: (value) async {
              if (value == 'members') {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChatMembersScreen(auth: widget.auth, id: widget.id),
                  ),
                );
              } else {
                final until = DateTime.tryParse(
                  textOf(_chat.conversation ?? {}, 'mutedUntil', ''),
                );
                final muted = until != null && until.isAfter(DateTime.now());
                await _action(() async {
                  await widget.auth.request(
                    '/api/v1/chat/conversations/${widget.id}/mute',
                    method: 'PUT',
                    body: {
                      'mutedUntil': muted
                          ? null
                          : DateTime.now()
                                .toUtc()
                                .add(const Duration(hours: 8))
                                .toIso8601String(),
                    },
                  );
                });
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'members',
                child: Text('Thành viên & trạng thái đọc'),
              ),
              PopupMenuItem(
                value: 'mute',
                child: Text('Tắt 8 giờ / bật lại thông báo'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Tóm tắt bằng AI',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AiDocumentScreen(
                  auth: widget.auth,
                  title: 'Tóm tắt trò chuyện',
                  load: () => widget.auth.request(
                    '/api/v1/chat/conversations/${widget.id}/ai/summary',
                    method: 'POST',
                    body: {},
                    requestTimeout: const Duration(seconds: 90),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _chat,
          builder: (context, _) => LayoutBuilder(
            builder: (context, viewport) => Column(
              children: [
                if ((_chat.loading && _chat.messages.isEmpty) || _busy)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Đang xử lý cuộc trò chuyện',
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _chat.refresh(),
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _chat.messages.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _error != null || _chat.error != null
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Notice(
                                    _error ?? _chat.error!,
                                    retry: () => _chat.refresh(),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }
                        final messageIndex = index - 1;
                        if (messageIndex == _chat.messages.length) {
                          return Center(
                            child: _chat.hasMore
                                ? TextButton(
                                    onPressed: _chat.loading
                                        ? null
                                        : () => _chat.refresh(older: true),
                                    child: const Text('Tin nhắn cũ hơn'),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    child: Text(
                                      _chat.loading && _chat.messages.isEmpty
                                          ? 'Đang tải cuộc trò chuyện…'
                                          : _chat.messages.isEmpty
                                          ? 'Chưa có tin nhắn trong cuộc trò chuyện.'
                                          : 'Bắt đầu cuộc trò chuyện',
                                    ),
                                  ),
                          );
                        }
                        final message = _chat
                            .messages[_chat.messages.length - 1 - messageIndex];
                        return _messageBubble(message);
                      },
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: viewport.maxHeight * .55,
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_reply != null)
                          ListTile(
                            title: Text(
                              'Trả lời ${textOf(_reply!, 'senderName')}',
                            ),
                            subtitle: Text(
                              textOf(_reply!, 'body', 'Tệp đính kèm'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Bỏ trả lời',
                              onPressed: _sending
                                  ? null
                                  : () => setState(() => _reply = null),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                        if (_attachments.isNotEmpty)
                          HorizontalChoices(
                            children: [
                              for (final attachment in _attachments)
                                InputChip(
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 220,
                                    ),
                                    child: Text(
                                      textOf(attachment, 'fileName'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onDeleted: _sending
                                      ? null
                                      : () => setState(
                                          () => _attachments.remove(attachment),
                                        ),
                                ),
                            ],
                          ),
                        if (_chat.conversation != null &&
                            _chat.conversation?['canSend'] != true)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Bạn chỉ có thể đọc trong cuộc trò chuyện này.',
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Đính kèm tệp',
                                onPressed:
                                    _busy ||
                                        _sending ||
                                        _chat.conversation?['canSend'] != true
                                    ? null
                                    : _upload,
                                icon: const Icon(Icons.attach_file),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _text,
                                  enabled:
                                      !_sending &&
                                      _chat.conversation?['canSend'] == true,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 4000,
                                  decoration: InputDecoration(
                                    hintText:
                                        _chat.conversation?['canSend'] == true
                                        ? 'Tin nhắn'
                                        : 'Cuộc trò chuyện chỉ đọc',
                                    counterText: '',
                                  ),
                                ),
                              ),
                              IconButton.filled(
                                tooltip: 'Gửi tin nhắn',
                                onPressed:
                                    _sending ||
                                        _busy ||
                                        _chat.conversation?['canSend'] != true
                                    ? null
                                    : _send,
                                icon: _sending
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_upward),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ChatEditDialog extends StatefulWidget {
  const ChatEditDialog({super.key, required this.initial});
  final String initial;
  @override
  State<ChatEditDialog> createState() => _ChatEditDialogState();
}

class _ChatEditDialogState extends State<ChatEditDialog> {
  late final _text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Sửa tin nhắn'),
    content: TextField(
      controller: _text,
      maxLength: 4000,
      minLines: 2,
      maxLines: 6,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () {
          if (_text.text.trim().isNotEmpty) {
            Navigator.pop(context, _text.text.trim());
          }
        },
        child: const Text('Lưu'),
      ),
    ],
  );
}
