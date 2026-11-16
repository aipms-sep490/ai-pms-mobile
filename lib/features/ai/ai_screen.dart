import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../../ui/paged_records.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_model.dart';
import '../workspace/inbox_screen.dart';
import '../workspace/workspace_models.dart';
import '../workspace/task_editor_screen.dart';

const _aiTimeout = Duration(seconds: 90);

String _scopeLabel(String scope) => switch (scope) {
  'PROJECT' => 'Đồ án',
  'COMBINED' => 'Đồ án & học vụ',
  _ => 'Học vụ',
};
String _modeLabel(String mode) => switch (mode) {
  'PROGRESS' => 'Tiến độ',
  'TASK' => 'Nháp công việc',
  _ => 'Hỏi tự do',
};

class _AiQuestion extends StatelessWidget {
  const _AiQuestion(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 720) * .85,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableBody(text),
        ),
      ),
    ),
  );
}

/// A small, inert reader: headings, lists and bold text; no HTML or URL actions.
class _AiReadingSection extends StatelessWidget {
  const _AiReadingSection(this.title, this.content);
  final String title;
  final String? content;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (content != null) ...[
          const SizedBox(height: 8),
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final raw
                    in (content!.trim().isEmpty
                            ? 'Chưa có thông tin.'
                            : content!)
                        .split('\n'))
                  if (raw.trim().isEmpty)
                    const SizedBox(height: 8)
                  else
                    Builder(
                      builder: (context) {
                        final heading = RegExp(r'^#{1,6}\s+').hasMatch(raw);
                        final line = raw
                            .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
                            .replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ');
                        final spans = <TextSpan>[];
                        var end = 0;
                        for (final match in RegExp(
                          r'\*\*([^*]+)\*\*',
                        ).allMatches(line)) {
                          spans.add(
                            TextSpan(text: line.substring(end, match.start)),
                          );
                          spans.add(
                            TextSpan(
                              text: match.group(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                          end = match.end;
                        }
                        spans.add(TextSpan(text: line.substring(end)));
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Semantics(
                            header: heading,
                            child: Text.rich(
                              TextSpan(children: spans),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: heading
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

EntityTarget? aiEvidenceTarget(Json source) {
  final type = textOf(source, 'sourceType', '').toUpperCase();
  final prefix = switch (type) {
    'TASK' => 'TASK-',
    'MILESTONE' => 'MS-',
    'MEETING' => 'MTG-',
    'PROGRESS_REPORT' => 'PR-',
    _ => null,
  };
  if (prefix == null) return null;
  var raw = textOf(source, 'sourceId', '');
  if (raw.startsWith(prefix)) raw = raw.substring(prefix.length);
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(raw)) return null;
  final id = int.tryParse(raw);
  if (id == null || '$id' != raw) return null;
  return EntityTarget(type, id);
}

class AiHomeScreen extends StatelessWidget {
  const AiHomeScreen({super.key, required this.auth, this.projectId});
  final AuthController auth;
  final int? projectId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trợ lý AI')),
    body: RemotePage<Json>(
      title: 'AI đồng hành',
      showHeading: false,
      load: () async {
        final dashboard = StudentDashboard.fromJson(
          await auth.getJson('/api/v1/dashboards/student'),
        );
        return {'projectId': projectId ?? dashboard.project?.id};
      },
      content: (context, data, refresh) {
        final id = data['projectId'] as int?;
        void open(Widget screen) => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => screen),
        );
        return [
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Cùng tìm bước tiếp theo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hỏi về đồ án hoặc học vụ. Xem nguồn tham chiếu trước khi áp dụng gợi ý.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Hỏi trợ lý AI'),
                  onPressed: () =>
                      open(AssistantChatScreen(auth: auth, projectId: id)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _AiShortcut(
            title: 'Lịch sử hội thoại',
            subtitle: 'Mở lại trao đổi trước đây',
            icon: Icons.history,
            onTap: () =>
                open(AssistantHistoryScreen(auth: auth, projectId: id)),
          ),
          if (id != null) ...[
            _AiShortcut(
              title: 'Lịch sử học vụ chung',
              subtitle: 'Các hội thoại không gắn với đồ án',
              icon: Icons.menu_book_outlined,
              onTap: () => open(AssistantHistoryScreen(auth: auth)),
            ),
            const SizedBox(height: 20),
            const ContentSection('Theo dõi đồ án', null),
            _AiShortcut(
              title: 'Cảnh báo & tiến độ AI',
              subtitle: 'Rủi ro, dấu hiệu và việc nên ưu tiên',
              icon: Icons.insights_outlined,
              onTap: () => open(
                AiDocumentScreen(
                  auth: auth,
                  title: 'Tiến độ & rủi ro',
                  load: () => auth.request('/api/v1/projects/$id/ai/digest'),
                ),
              ),
            ),
            for (final entry in const {
              'NEXT_STEPS': 'Bây giờ cần làm gì?',
              'BLOCKERS': 'Vì sao bị chặn?',
              'SUBMISSION_CHECK': 'Kiểm tra trước khi nộp',
            }.entries)
              _AiShortcut(
                title: entry.value,
                subtitle: 'Gợi ý theo trạng thái hiện tại',
                icon: Icons.assistant_outlined,
                onTap: () => open(
                  AiDocumentScreen(
                    auth: auth,
                    title: entry.value,
                    load: () => auth.request(
                      '/api/v1/projects/$id/ai/workflow-assistance?mode=${entry.key}',
                      requestTimeout: _aiTimeout,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            const ContentSection('Phân tích & kết quả', null),
            _AiShortcut(
              title: 'Lịch sử phân tích AI',
              subtitle: 'Các kết quả đã được lưu trên hệ thống',
              icon: Icons.manage_search,
              onTap: () => open(AiRunsScreen(auth: auth, projectId: id)),
            ),
            _AiShortcut(
              title: 'Phân tích tiến độ mới',
              subtitle: 'Tạo và lưu một lần phân tích theo dữ liệu hiện tại',
              icon: Icons.analytics_outlined,
              onTap: () => open(
                AiDocumentScreen(
                  auth: auth,
                  title: 'Phân tích tiến độ',
                  load: () => auth.request(
                    '/api/v1/projects/$id/ai/progress-analysis',
                    method: 'POST',
                    requestTimeout: _aiTimeout,
                  ),
                ),
              ),
            ),
            _AiShortcut(
              title: 'Kết quả đã công bố',
              subtitle: 'Điểm và kết quả do hệ thống công bố',
              icon: Icons.school_outlined,
              onTap: () =>
                  open(PublishedResultScreen(auth: auth, projectId: id)),
            ),
          ],
        ];
      },
    ),
  );
}

class _AiShortcut extends StatelessWidget {
  const _AiShortcut({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    leading: Icon(icon, color: AppColors.primary),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class AiDocumentScreen extends StatelessWidget {
  const AiDocumentScreen({
    super.key,
    required this.auth,
    required this.title,
    required this.load,
  });
  final AuthController auth;
  final String title;
  final Future<Object?> Function() load;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: RemotePage<Json>(
      title: title,
      showHeading: false,
      load: () async => objectOf(await load()),
      content: (context, data, refresh) => aiContent(context, auth, data),
    ),
  );
}

List<Widget> aiContent(
  BuildContext context,
  AuthController auth,
  Json data, {
  int? projectId,
  bool includeFooter = true,
}) {
  final draftProjectId =
      projectId ?? (data['projectId'] is int ? data['projectId'] as int : null);
  if (data['errorCode'] == 'AI_HISTORY_SCOPE_CHANGED') {
    return const [
      Notice(
        'Phạm vi dữ liệu đã thay đổi. Kết quả cũ hiện không thể hiển thị.',
      ),
    ];
  }
  if (data['answer'] is Json) {
    return aiContent(
      context,
      auth,
      data['answer'] as Json,
      projectId: draftProjectId,
      includeFooter: includeFooter,
    );
  }
  if (data['reportSummary'] is Json) {
    return aiContent(
      context,
      auth,
      data['reportSummary'] as Json,
      projectId: draftProjectId,
      includeFooter: includeFooter,
    );
  }
  if (data['progressAnalysis'] is Json) {
    return aiContent(
      context,
      auth,
      data['progressAnalysis'] as Json,
      projectId: draftProjectId,
      includeFooter: includeFooter,
    );
  }
  final widgets = <Widget>[];
  if (data['generationStatus'] == 'FAILED') {
    widgets.add(
      const Notice('AI chưa thể tạo kết quả. Bạn có thể thử lại sau.'),
    );
  }
  if (data['insufficientEvidence'] == true ||
      data['dataStatus'] == 'INSUFFICIENT_DATA') {
    widgets.add(
      const _AiReadingSection(
        'Chưa đủ dữ liệu',
        'Một số kết luận chưa thể xác định từ dữ liệu trong phạm vi của bạn.',
      ),
    );
  }
  if (data['riskLevel'] is String) {
    widgets.add(
      _AiReadingSection('Mức rủi ro', switch (data['riskLevel']) {
        'LOW' => 'Thấp',
        'MEDIUM' => 'Trung bình',
        'HIGH' => 'Cao',
        'CRITICAL' => 'Rất cao',
        _ => 'Chưa xác định',
      }),
    );
  }
  if (data['answer'] is String) {
    widgets.add(_AiReadingSection('Trả lời', data['answer'] as String));
  }
  if (data['summary'] is String) {
    widgets.add(_AiReadingSection('Tóm tắt', data['summary'] as String));
  }
  if (data['summary'] is Json) {
    final summary = data['summary'] as Json;
    for (final entry in const {
      'completed': 'Đã hoàn thành',
      'inProgress': 'Đang thực hiện',
      'blockers': 'Vướng mắc',
      'risks': 'Rủi ro',
      'nextActions': 'Bước tiếp theo',
    }.entries) {
      widgets.add(
        _AiReadingSection(entry.value, textOf(summary, entry.key, '')),
      );
    }
  }
  if (data['progressSummary'] is Json && data['dataStatus'] == 'SUFFICIENT') {
    final progress = data['progressSummary'] as Json;
    widgets.add(
      _AiReadingSection(
        'Tiến độ công việc',
        '${progress['progressPercentage']}% · ${progress['doneTasks']}/${progress['totalTasks']} việc hoàn tất\n${progress['overdueTasks']} quá hạn · ${progress['blockedTasks']} bị chặn',
      ),
    );
  }
  for (final key in ['signals', 'factors', 'items']) {
    for (final item in recordsOf(data[key] ?? [])) {
      widgets.add(
        _AiReadingSection(
          textOf(
            item,
            'title',
            textOf(item, 'description', textOf(item, 'code', 'Dấu hiệu')),
          ),
          item['detail'] is String
              ? item['detail'] as String
              : item['explanation'] as String?,
        ),
      );
    }
  }
  for (final entry in const {
    'nextActions': 'Việc nên ưu tiên',
    'recommendations': 'Khuyến nghị',
    'decisions': 'Quyết định',
    'openQuestions': 'Câu hỏi còn mở',
    'limitations': 'Giới hạn dữ liệu',
  }.entries) {
    final value = data[entry.key];
    if (value is List && value.isNotEmpty) {
      widgets.add(
        _AiReadingSection(
          entry.value,
          value.whereType<String>().map((s) => '• $s').join('\n'),
        ),
      );
    }
    if (value is String && value.isNotEmpty) {
      widgets.add(_AiReadingSection(entry.value, value));
    }
  }
  for (final item in recordsOf(data['actionItems'] ?? [])) {
    widgets.add(
      _AiReadingSection(
        textOf(item, 'title'),
        '${textOf(item, 'ownerName', 'Chưa xác định người phụ trách')}\n${item['dueAt'] == null ? 'Chưa có hạn' : displayDate(item['dueAt'])}',
      ),
    );
  }
  if (data['limitationNote'] is String) {
    widgets.add(
      _AiReadingSection('Lưu ý về kết quả', data['limitationNote'] as String),
    );
  }
  if (data['draft'] is Json) {
    final draft = data['draft'] as Json;
    final text =
        '${textOf(draft, 'title', '')}\n${textOf(draft, 'description', '')}';
    widgets.add(_AiReadingSection('Bản gợi ý', text));
    widgets.add(
      const Text('Gợi ý chưa được lưu thành công việc, lịch hoặc báo cáo.'),
    );
    widgets.add(
      TextButton.icon(
        icon: const Icon(Icons.copy),
        label: const Text('Sao chép gợi ý'),
        onPressed: () => Clipboard.setData(ClipboardData(text: text)),
      ),
    );
    if (draft['kind'] == 'TASK' &&
        draftProjectId != null &&
        draftProjectId > 0) {
      widgets.add(
        OutlinedButton.icon(
          icon: const Icon(Icons.add_task),
          label: const Text('Kiểm tra & tạo công việc'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<Json>(
              builder: (_) => TaskEditorScreen(
                auth: auth,
                projectId: draftProjectId,
                initialDraft: draft,
              ),
            ),
          ),
        ),
      );
    }
  }
  final evidence = recordsOf(data['evidence'] ?? data['projectEvidence'] ?? []);
  if (evidence.isNotEmpty) {
    widgets.add(const _AiReadingSection('Nguồn tham chiếu', null));
  }
  for (final source in evidence) {
    final target = aiEvidenceTarget(source);
    widgets.add(
      RecordTile(
        title: textOf(source, 'title'),
        subtitle: textOf(source, 'excerpt', textOf(source, 'periodOrDate', '')),
        icon: Icons.source_outlined,
        onTap: target == null
            ? null
            : () => openEntity(context, auth, target, () {}),
      ),
    );
  }
  final citations = recordsOf(data['citations'] ?? []);
  for (var index = 0; index < citations.length; index++) {
    final citation = citations[index];
    final runId = data['runId'];
    final citationIndex = index;
    widgets.add(
      RecordTile(
        title: textOf(citation, 'title'),
        subtitle:
            '${textOf(citation, 'version', '')} · ${textOf(citation, 'section', '')}\n${textOf(citation, 'excerpt', '')}',
        icon: Icons.menu_book_outlined,
        onTap: runId is int && runId > 0
            ? () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AiDocumentScreen(
                    auth: auth,
                    title: 'Nguồn học vụ',
                    load: () => auth.request(
                      '/api/v1/academic/assistant/runs/$runId/citations/$citationIndex',
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
  if (data['excerpt'] is String) {
    widgets.add(
      _AiReadingSection(
        textOf(data, 'title', 'Nguồn học vụ'),
        data['excerpt'] as String,
      ),
    );
  }
  if (widgets.isEmpty) widgets.add(const Text('Chưa có nội dung để hiển thị.'));
  if (includeFooter) {
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: const Text(
          'AI hỗ trợ tham khảo; quyền thao tác và kết quả chính thức do hệ thống quyết định.',
        ),
      ),
    );
  }
  return widgets;
}

class AssistantHistoryScreen extends StatefulWidget {
  const AssistantHistoryScreen({super.key, required this.auth, this.projectId});
  final AuthController auth;
  final int? projectId;
  @override
  State<AssistantHistoryScreen> createState() => _AssistantHistoryScreenState();
}

class _AssistantHistoryScreenState extends State<AssistantHistoryScreen> {
  int? _before;
  int? _nextBefore;
  bool _hasMore = false;
  int _revision = 0;
  final _rows = <Json>[];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hội thoại AI')),
    body: RemotePage<List<Json>>(
      title: 'Lịch sử trợ lý',
      showHeading: false,
      revision: _revision,
      load: () async {
        final query = Uri(
          queryParameters: {
            if (widget.projectId != null) 'projectId': '${widget.projectId}',
            if (_before != null) 'beforeId': '$_before',
          },
        ).query;
        final rows = recordsOf(
          await widget.auth.request(
            '/api/v1/academic/assistant/conversations?$query',
          ),
        );
        if (_before == null) _rows.clear();
        final merged = {
          for (final row in _rows) idOf(row): row,
          for (final row in rows) idOf(row): row,
        };
        _rows
          ..clear()
          ..addAll(merged.values);
        _hasMore = rows.length == 20;
        _nextBefore = rows.isEmpty ? null : idOf(rows.last);
        _before = null;
        return List.of(_rows);
      },
      content: (context, rows, refresh) => [
        if (rows.isEmpty) const Text('Bạn chưa có hội thoại AI được lưu.'),
        for (final row in rows)
          RecordTile(
            title: textOf(row, 'title'),
            subtitle: displayDate(row['updatedAt']),
            icon: Icons.chat_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AssistantChatScreen(
                  auth: widget.auth,
                  projectId: row['projectId'] as int?,
                  conversationId: idOf(row),
                  scope: textOf(row, 'scope', 'ACADEMIC'),
                ),
              ),
            ),
          ),
        if (_hasMore)
          OutlinedButton(
            onPressed: () => setState(() {
              _before = _nextBefore;
              _revision++;
            }),
            child: const Text('Tải hội thoại cũ hơn'),
          ),
      ],
    ),
  );
}

class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({
    super.key,
    required this.auth,
    this.projectId,
    this.conversationId,
    this.scope,
  });
  final AuthController auth;
  final int? projectId;
  final int? conversationId;
  final String? scope;
  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <Json>[];
  late int? _id = widget.conversationId;
  late String _scope =
      widget.scope ?? (widget.projectId == null ? 'ACADEMIC' : 'COMBINED');
  int? _revision;
  bool _loading = false;
  bool _busy = false;
  bool _more = false;
  String? _error;
  ApiUpload? _file;
  Json? _unsyncedResponse;
  String? _unsyncedQuery;
  String _mode = 'CHAT';
  @override
  void initState() {
    super.initState();
    if (_id != null) _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _revealLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _load({bool older = false}) async {
    if (_id == null || _loading) return;
    setState(() => _loading = true);
    try {
      final before = older && _turns.isNotEmpty
          ? '?beforeTurnId=${idOf(_turns.first)}'
          : '';
      final data = await widget.auth.getJson(
        '/api/v1/academic/assistant/conversations/$_id$before',
      );
      if (!mounted) return;
      final conversation = objectOf(data['conversation']);
      final rows = recordsOf(data['turns']);
      setState(() {
        _revision = conversation['revision'] as int;
        _scope = textOf(conversation, 'scope', 'ACADEMIC');
        _more = data['hasMore'] == true;
        if (!older) _turns.clear();
        _turns.insertAll(0, rows);
        _error = null;
        _unsyncedResponse = null;
        _unsyncedQuery = null;
      });
      if (!older) _revealLatest();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorText(error);
          if (error is ApiException &&
              [401, 403, 404].contains(error.statusCode)) {
            _turns.clear();
            _unsyncedResponse = null;
            _unsyncedQuery = null;
          }
        });
        _revealLatest();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ask() async {
    final query = _query.text.trim().isEmpty && _mode == 'PROGRESS'
        ? 'Tóm tắt tiến độ, công việc quá hạn và các mốc cần theo dõi.'
        : _query.text.trim();
    if (_busy || _loading || query.isEmpty) return;
    if (query.length < 2 || query.length > 2000) {
      setState(() => _error = 'Câu hỏi cần từ 2 đến 2000 ký tự.');
      _revealLatest();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_id == null) {
        final c = objectOf(
          await widget.auth.request(
            '/api/v1/academic/assistant/conversations',
            method: 'POST',
            body: {'projectId': widget.projectId, 'scope': _scope},
          ),
        );
        _id = idOf(c);
        _revision = c['revision'] as int;
        if (!mounted) return;
      }
      final body = <String, dynamic>{
        'query': query,
        'scope': _scope,
        'projectId': widget.projectId,
        'conversationId': _id,
        'expectedRevision': _revision,
        'pageContext': 'Mobile',
        if (_mode == 'PROGRESS') 'toolMode': 'PROGRESS',
        if (_mode == 'TASK') 'draftKind': 'TASK',
      };
      final response = objectOf(
        await widget.auth.request(
          _file == null
              ? '/api/v1/academic/assistant/ask'
              : '/api/v1/academic/assistant/ask-with-files',
          method: 'POST',
          body: _file == null
              ? body
              : {
                  for (final e in body.entries)
                    if (e.value != null) e.key: '${e.value}',
                },
          upload: _file,
          requestTimeout: _aiTimeout,
        ),
      );
      if (!mounted) return;
      _query.clear();
      setState(() {
        _file = null;
        _unsyncedResponse = response;
        _unsyncedQuery = query;
      });
      await _load();
    } catch (error) {
      if (error is ApiException && error.statusCode == 409) await _load();
      if (mounted) {
        setState(() => _error = errorText(error));
        _revealLatest();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attach() async {
    if (_busy) return;
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final extension = file.name.split('.').last.toLowerCase();
      const mime = {
        'pdf': 'application/pdf',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'txt': 'text/plain',
        'md': 'text/markdown',
      };
      if (!mime.containsKey(extension)) {
        throw const ApiException('Chọn tài liệu PDF, DOCX, TXT hoặc Markdown.');
      }
      final size = await file.length();
      if (size == null || size <= 0 || size > 10 * 1024 * 1024) {
        throw const ApiException('Tệp cho trợ lý tối đa 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(
        () => _file = ApiUpload(
          file.name,
          bytes,
          field: 'Files',
          contentType: mime[extension]!,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = errorText(error));
        _revealLatest();
      }
    }
  }

  Future<void> _options() async {
    FocusManager.instance.primaryFocus?.unfocus();
    var scope = _scope;
    var mode = _mode;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Tùy chọn trợ lý',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  _id == null
                      ? 'Phạm vi dữ liệu'
                      : 'Phạm vi của hội thoại: ${_scopeLabel(scope)}',
                ),
                if (_id == null)
                  HorizontalChoices(
                    children: [
                      for (final value in [
                        'ACADEMIC',
                        if (widget.projectId != null) ...[
                          'PROJECT',
                          'COMBINED',
                        ],
                      ])
                        ChoiceChip(
                          label: Text(_scopeLabel(value)),
                          selected: scope == value,
                          onSelected: (_) => update(() {
                            scope = value;
                            if (scope == 'ACADEMIC') mode = 'CHAT';
                          }),
                        ),
                    ],
                  ),
                if (widget.projectId != null &&
                    (scope != 'ACADEMIC' || _id == null)) ...[
                  const SizedBox(height: 16),
                  const Text('Cách trợ lý hỗ trợ'),
                  for (final value in ['CHAT', 'PROGRESS', 'TASK'])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_modeLabel(value)),
                      subtitle: value == 'PROGRESS'
                          ? const Text('Dùng dữ liệu hệ thống, không cần tệp.')
                          : null,
                      trailing: mode == value
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () => update(() {
                        mode = value;
                        if (mode != 'CHAT' && scope == 'ACADEMIC') {
                          scope = 'COMBINED';
                        }
                      }),
                    ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _scope = scope;
                      _mode = mode;
                      if (mode == 'PROGRESS') _file = null;
                    });
                    Navigator.pop(sheet);
                  },
                  child: const Text('Áp dụng'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Hỏi trợ lý AI',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'Tùy chọn',
          onPressed: _busy || _loading ? null : _options,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, viewport) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '${_scopeLabel(_scope)} · ${_modeLabel(_mode)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_loading || _busy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Trợ lý đang xử lý',
                    ),

                  if (_more)
                    OutlinedButton(
                      onPressed: _loading ? null : () => _load(older: true),
                      child: const Text('Tin cũ hơn'),
                    ),
                  if (_turns.isEmpty && !_loading && _unsyncedResponse == null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ContentSection(
                          'Bạn muốn hỏi gì?',
                          'Chọn một gợi ý hoặc viết câu hỏi bên dưới. AI chỉ dùng dữ liệu trong phạm vi bạn được phép xem.',
                        ),
                        for (final prompt in [
                          if (widget.projectId != null)
                            'Việc nào đang chặn tiến độ?',
                          'Cần chuẩn bị gì trước buổi họp?',
                          'Quy định nộp báo cáo là gì?',
                        ])
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(prompt),
                            trailing: const Icon(Icons.north_west, size: 18),
                            onTap: _busy ? null : () => _query.text = prompt,
                          ),
                      ],
                    ),
                  for (final turn in _turns) ...[
                    _AiQuestion(textOf(turn, 'query')),
                    const SizedBox(height: 16),
                    ...aiContent(
                      context,
                      widget.auth,
                      objectOf(turn['response']),
                      projectId: widget.projectId,
                      includeFooter: false,
                    ),
                    const Divider(height: 32),
                  ],
                  if (_unsyncedResponse != null) ...[
                    _AiQuestion(_unsyncedQuery!),
                    const SizedBox(height: 16),
                    ...aiContent(
                      context,
                      widget.auth,
                      _unsyncedResponse!,
                      projectId: widget.projectId,
                      includeFooter: false,
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Notice(
                        _error!,
                        retry: _busy || _id == null ? null : _load,
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: viewport.maxHeight * .5),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_file != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: InputChip(
                            label: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width - 120,
                              ),
                              child: Text(
                                _file!.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: _busy
                                ? null
                                : () => setState(() => _file = null),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Đính kèm tài liệu cho AI',
                            onPressed: _busy || _mode == 'PROGRESS'
                                ? null
                                : _attach,
                            icon: const Icon(Icons.attach_file),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _query,
                              enabled: !_busy,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 2000,
                              decoration: const InputDecoration(
                                hintText: 'Câu hỏi của bạn…',
                                counterText: '',
                              ),
                            ),
                          ),
                          IconButton.filled(
                            tooltip: _mode == 'PROGRESS'
                                ? 'Xem tiến độ'
                                : 'Gửi câu hỏi',
                            onPressed: _busy || _loading ? null : _ask,
                            icon: _busy
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
  );
}

class AiRunsScreen extends StatelessWidget {
  const AiRunsScreen({super.key, required this.auth, required this.projectId});
  final AuthController auth;
  final int projectId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch sử AI')),
    body: PagedRecords(
      auth: auth,
      showHeading: false,
      path: '/api/v1/projects/$projectId/ai/runs',
      title: 'Phân tích đã lưu',
      emptyText: 'Chưa có phân tích AI được lưu.',
      item: (context, row, refresh) => RecordTile(
        title: switch (row['kind']) {
          'PROJECT_ASK' => 'Hỏi đáp đồ án',
          'REPORT_SUMMARY' => 'Tóm tắt báo cáo',
          'PROGRESS_ANALYSIS' => 'Phân tích tiến độ',
          _ => 'Kết quả AI',
        },
        subtitle: displayDate(row['startedAt']),
        icon: Icons.auto_awesome_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AiDocumentScreen(
              auth: auth,
              title: 'Kết quả AI',
              load: () => auth.request(
                '/api/v1/projects/$projectId/ai/runs/${idOf(row)}',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PublishedResultScreen extends StatelessWidget {
  const PublishedResultScreen({
    super.key,
    required this.auth,
    required this.projectId,
  });
  final AuthController auth;
  final int projectId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kết quả đồ án')),
    body: RemotePage<Json>(
      title: 'Kết quả đã công bố',
      showHeading: false,
      load: () async {
        await auth.getJson('/api/v1/projects/$projectId');
        try {
          return await auth.getJson('/api/v1/projects/$projectId/result');
        } on ApiException catch (e) {
          if (e.statusCode == 404) return {'published': false};
          rethrow;
        }
      },
      content: (context, data, refresh) => data['published'] == false
          ? const [Surface(child: Text('Đồ án chưa có kết quả được công bố.'))]
          : [
              ContentSection(
                'Kết quả',
                data['outcome'] == 'PASS'
                    ? 'Đạt'
                    : data['outcome'] == 'FAIL'
                    ? 'Chưa đạt'
                    : textOf(data, 'outcome'),
              ),
              ContentSection('Điểm tổng kết', '${data['totalScore']}'),
              ContentSection('Ngưỡng đạt', '${data['passThreshold']}'),
              ContentSection('Công bố', displayDate(data['publishedAt'])),
              ContentSection('Phiên bản', '${data['version'] ?? 1}'),
            ],
    ),
  );
}
