import 'package:material_ui/material_ui.dart';

import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../workspace/workspace_models.dart';
import 'chat_controller.dart';

class ChatMembersScreen extends StatefulWidget {
  const ChatMembersScreen({super.key, required this.auth, required this.id});
  final AuthController auth;
  final String id;
  @override
  State<ChatMembersScreen> createState() => _ChatMembersScreenState();
}

class _ChatMembersScreenState extends State<ChatMembersScreen> {
  final _rows = <Json>[];
  String? _before;
  String? _next;
  int _revision = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thành viên')),
    body: RemotePage<List<Json>>(
      title: 'Người tham gia',
      revision: _revision,
      load: () async {
        final query = Uri(
          queryParameters: {'pageSize': '50', 'cursor': ?_before},
        ).query;
        final page = ChatPage(
          await widget.auth.request(
            '/api/v1/chat/conversations/${widget.id}/members?$query',
          ),
        );
        if (_before == null) _rows.clear();
        final merged = {
          for (final row in _rows) chatId(row, 'userId'): row,
          for (final row in page.items) chatId(row, 'userId'): row,
        };
        _rows
          ..clear()
          ..addAll(merged.values);
        _next = page.hasMore ? page.cursor : null;
        _before = null;
        return List.of(_rows);
      },
      content: (context, rows, refresh) => [
        if (rows.isEmpty) const Text('Chưa có thành viên để hiển thị.'),
        for (final row in rows)
          RecordTile(
            title: textOf(row, 'fullName'),
            subtitle: row['lastReadSequence'] == null
                ? 'Chưa có trạng thái đọc'
                : 'Đã đọc đến tin số ${row['lastReadSequence']}',
            icon: Icons.person_outline,
          ),
        if (_next != null)
          OutlinedButton(
            onPressed: () => setState(() {
              _before = _next;
              _revision++;
            }),
            child: const Text('Tải thêm'),
          ),
      ],
    ),
  );
}
