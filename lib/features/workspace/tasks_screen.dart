import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_model.dart';
import 'workspace_models.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    this.revision = 0,
    this.milestoneId,
  });
  final AuthController auth;
  final VoidCallback onChanged;
  final int revision;
  final int? milestoneId;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  int _page = 1;
  String _filter = 'all';
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<(StudentDashboard, PageData?)> _load() async {
    final dashboard = StudentDashboard.fromJson(
      await widget.auth.getJson('/api/v1/dashboards/student'),
    );
    final project = dashboard.project;
    if (project == null) return (dashboard, null);
    if (widget.milestoneId != null) {
      final milestone = await widget.auth.getJson(
        '/api/v1/milestones/${widget.milestoneId}',
      );
      if (milestone['projectId'] != project.id) {
        throw const ApiException(
          'Mốc tiến độ không thuộc đồ án hiện tại.',
          statusCode: 403,
        );
      }
    }
    final query = Uri(
      queryParameters: {
        'page': '$_page',
        'pageSize': '20',
        if (widget.milestoneId == null)
          'assigneeUserId': '${widget.auth.user!.id}',
        if (widget.milestoneId != null) 'milestoneId': '${widget.milestoneId}',
        if (_filter == 'progress') 'status': 'IN_PROGRESS',
        if (_filter == 'done') 'status': 'DONE',
        if (_filter == 'overdue') 'isOverdue': 'true',
        if (_filter == 'blocked') 'isBlocked': 'true',
        if (_search.isNotEmpty) 'search': _search,
      },
    ).query;
    final result = PageData.fromJson(
      await widget.auth.request('/api/v1/tasks/project/${project.id}?$query'),
    );
    return (dashboard, result);
  }

  @override
  Widget build(
    BuildContext context,
  ) => RemotePage<(StudentDashboard, PageData?)>(
    key: ValueKey('$_page/$_filter/$_search'),
    revision: widget.revision,
    title: widget.milestoneId == null ? 'Việc của tôi' : 'Việc trong mốc',
    load: _load,
    content: (context, data, refresh) {
      final (dashboard, page) = data;
      if (page == null) {
        return const [
          Surface(
            child: Text(
              'Bạn chưa có đồ án. Tham gia nhóm và đăng ký đồ án trên web để bắt đầu.',
            ),
          ),
        ];
      }
      return [
        Text(dashboard.project!.title),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'Tìm công việc',
            hintText: 'Nhập tên rồi nhấn tìm',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (value) => setState(() {
            _search = value.trim();
            _page = 1;
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in const {
              'all': 'Tất cả',
              'progress': 'Đang làm',
              'overdue': 'Quá hạn',
              'blocked': 'Bị chặn',
              'done': 'Hoàn tất',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) => setState(() {
                  _filter = entry.key;
                  _page = 1;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (page.items.isEmpty)
          const Surface(child: Text('Không có công việc phù hợp bộ lọc.')),
        for (final task in page.items)
          Builder(
            builder: (context) {
              final due = parseUtcTimestamp(textOf(task, 'dueAt', ''));
              final overdue =
                  due != null &&
                  due.isBefore(dashboard.asOfUtc) &&
                  !['DONE', 'CANCELLED'].contains(task['status']);
              return RecordTile(
                title: textOf(task, 'title'),
                icon: Icons.check_box_outlined,
                urgent: overdue,
                subtitle:
                    '${statusText(task['status'])} · Ưu tiên ${statusText(task['priority'])}\n${overdue ? 'Quá hạn' : 'Hạn'}: ${displayDate(task['dueAt'])}',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TaskDetailScreen(
                        auth: widget.auth,
                        id: idOf(task),
                        onChanged: widget.onChanged,
                      ),
                    ),
                  );
                  if (mounted) await refresh();
                },
              );
            },
          ),
        const SizedBox(height: 8),
        Pagination(
          data: page,
          change: (value) => setState(() => _page = value),
        ),
        const SizedBox(height: 12),
        const Text(
          'Thời gian theo múi giờ thiết bị.',
          textAlign: TextAlign.center,
        ),
      ];
    },
  );
}

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.auth,
    required this.id,
    required this.onChanged,
  });
  final AuthController auth;
  final int id;
  final VoidCallback onChanged;
  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  int _revision = 0;
  bool _saving = false;
  bool _editing = false;
  String? _message;
  bool _failed = false;

  Future<(TaskAccess, List<Json>)> _load() async {
    final data = await Future.wait([
      widget.auth.request('/api/v1/tasks/${widget.id}'),
      widget.auth.request('/api/v1/tasks/${widget.id}/execution-actions'),
      widget.auth.request('/api/v1/tasks/${widget.id}/history'),
    ]);
    return (
      TaskAccess(objectOf(data[0]), objectOf(data[1])),
      recordsOf(data[2]),
    );
  }

  Future<(String, String)?> _chooseChange(TaskAccess access) async {
    if (_editing) return null;
    setState(() => _editing = true);
    try {
      final target = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheet) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Chuyển trạng thái',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final status in taskTransitions(
                  textOf(access.task, 'status'),
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(statusText(status)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(sheet, status),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || target == null) return null;
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => _ChangeReasonDialog(target: target),
      );
      return reason == null ? null : (target, reason);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _change(TaskAccess access) async {
    if (_saving || _editing || !access.canChange) return;
    final change = await _chooseChange(access);
    if (!mounted || change == null) return;
    final (target, note) = change;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/tasks/${widget.id}/status',
        method: 'PUT',
        body: {
          'newStatus': target,
          'reason': note.isEmpty ? null : note,
          'concurrencyToken': access.token,
        },
      );
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'Đã cập nhật công việc.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = errorText(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _revision++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết công việc'),
        automaticallyImplyLeading: !_saving,
      ),
      body: RemotePage<(TaskAccess, List<Json>)>(
        title: 'Công việc',
        revision: _revision,
        load: _load,
        content: (context, data, refresh) {
          final (access, history) = data;
          final task = access.task;
          return [
            if (_message != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _failed ? AppColors.danger : AppColors.success,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            ContentSection(
              textOf(task, 'title'),
              '${statusText(task['status'])} · Ưu tiên ${statusText(task['priority'])}',
            ),
            if (access.canChange &&
                taskTransitions(textOf(task, 'status')).isNotEmpty)
              FilledButton.icon(
                onPressed: _saving || _editing ? null : () => _change(access),
                icon: const Icon(Icons.sync),
                label: Text(_saving ? 'Đang cập nhật…' : 'Đổi trạng thái'),
              )
            else
              const Surface(
                child: Text(
                  'Hiện bạn có thể xem công việc. Quyền cập nhật do hệ thống quyết định.',
                ),
              ),
            const SizedBox(height: 20),
            ContentSection('Mô tả', textOf(task, 'description', '')),
            ContentSection(
              'Thời gian',
              'Bắt đầu: ${displayDate(task['startAt'])}\nHạn: ${displayDate(task['dueAt'])}\nGiờ theo thiết bị.',
            ),
            ContentSection(
              'Người thực hiện',
              recordsOf(task['assignees'])
                  .map((person) => textOf(person, 'userFullName'))
                  .join('\n'),
            ),
            if (recordsOf(task['dependencies']).isNotEmpty) ...[
              const ContentSection(
                'Công việc phụ thuộc',
                'Kiểm tra tiến độ các việc cần hoàn tất trước.',
              ),
              for (final dependency in recordsOf(task['dependencies']))
                RecordTile(
                  title: 'Công việc #${dependency['dependsOnTaskId']}',
                  subtitle: textOf(dependency, 'dependencyType'),
                  onTap:
                      dependency['dependsOnTaskId'] is int &&
                          dependency['dependsOnTaskId'] > 0 &&
                          !_saving
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => TaskDetailScreen(
                              auth: widget.auth,
                              id: dependency['dependsOnTaskId'] as int,
                              onChanged: widget.onChanged,
                            ),
                          ),
                        )
                      : null,
                ),
            ],
            const ContentSection(
              'Lịch sử trạng thái',
              'Các cập nhật gần đây của công việc.',
            ),
            if (history.isEmpty) const Text('Chưa có thay đổi trạng thái.'),
            for (final item in history.reversed)
              RecordTile(
                title:
                    '${statusText(item['oldStatus'])} → ${statusText(item['newStatus'])}',
                subtitle:
                    '${textOf(item, 'changedByFullName')} · ${displayDate(item['changedAt'])}\n${textOf(item, 'reason', '')}',
                icon: Icons.history,
              ),
          ];
        },
      ),
    ),
  );
}

class _ChangeReasonDialog extends StatefulWidget {
  const _ChangeReasonDialog({required this.target});
  final String target;
  @override
  State<_ChangeReasonDialog> createState() => _ChangeReasonDialogState();
}

class _ChangeReasonDialogState extends State<_ChangeReasonDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Chuyển sang ${statusText(widget.target).toLowerCase()}?'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: TextFormField(
          controller: _reason,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: widget.target == 'BLOCKED'
                ? 'Lý do bị chặn (bắt buộc)'
                : 'Ghi chú (không bắt buộc)',
          ),
          validator: (value) =>
              widget.target == 'BLOCKED' && (value?.trim().isEmpty ?? true)
              ? 'Nhập lý do công việc bị chặn.'
              : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('Cập nhật'),
      ),
    ],
  );
}
