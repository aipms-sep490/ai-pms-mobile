import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_model.dart';
import 'workspace_models.dart';
import 'task_editor_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    this.revision = 0,
    this.milestoneId,
    this.showHeading = true,
  });
  final AuthController auth;
  final VoidCallback onChanged;
  final int revision;
  final int? milestoneId;
  final bool showHeading;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  int _page = 1;
  String _filter = 'all';
  String _search = '';
  bool _mine = true;
  int _revision = 0;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<(StudentDashboard, PageData?, Json?)> _load() async {
    final dashboard = StudentDashboard.fromJson(
      await widget.auth.getJson('/api/v1/dashboards/student'),
    );
    final project = dashboard.project;
    if (project == null) return (dashboard, null, null);
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
        if (widget.milestoneId == null && _mine)
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
    final capability = await widget.auth.getJson(
      '/api/v1/projects/${project.id}/execution-actions',
    );
    recordsOf(capability['actions']);
    if (capability['resourceType'] != 'PROJECT' ||
        capability['resourceId'] != project.id ||
        capability['projectId'] != project.id) {
      throw const FormatException('Invalid project capability');
    }
    return (dashboard, result, capability);
  }

  Future<void> _create(int projectId, Future<void> Function() refresh) async {
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          auth: widget.auth,
          projectId: projectId,
          milestoneId: widget.milestoneId,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      widget.onChanged();
      setState(() {
        _mine = false;
        _filter = 'all';
        _search = '';
        _page = 1;
        _searchController.clear();
        _revision++;
      });
    } else {
      await refresh();
    }
  }

  void _resetFilters({bool restoreScope = false}) => setState(() {
    _filter = 'all';
    _search = '';
    _page = 1;
    if (restoreScope) _mine = true;
    _searchController.clear();
  });

  @override
  Widget build(
    BuildContext context,
  ) => RemotePage<(StudentDashboard, PageData?, Json?)>(
    key: ValueKey('$_page/$_filter/$_search/$_mine'),
    revision: widget.revision + _revision,
    showHeading: widget.showHeading,
    errorActions: [
      if (_filter != 'all' || _search.isNotEmpty || !_mine)
        TextButton.icon(
          key: const Key('task-error-clear'),
          icon: const Icon(Icons.filter_alt_off_outlined),
          label: const Text('Xóa bộ lọc'),
          onPressed: () => _resetFilters(restoreScope: true),
        ),
    ],
    title: widget.milestoneId == null
        ? (_mine ? 'Việc của tôi' : 'Việc của đồ án')
        : 'Việc trong mốc',
    load: _load,
    content: (context, data, refresh) {
      final (dashboard, page, capability) = data;
      if (page == null) {
        return const [
          Surface(
            child: Text(
              'Bạn chưa có đồ án. Tham gia nhóm và đăng ký đồ án trên web để bắt đầu.',
            ),
          ),
        ];
      }
      final canCreate =
          capability != null &&
          executionAllowed(
            capability,
            type: 'PROJECT',
            id: dashboard.project!.id,
            projectId: dashboard.project!.id,
            action: 'create_task',
          );
      return [
        Row(
          children: [
            Expanded(
              child: Text(
                dashboard.project!.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (canCreate) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: 'Tạo công việc',
                excludeFromSemantics: true,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo', semanticsLabel: 'Tạo công việc'),
                  onPressed: () => _create(dashboard.project!.id, refresh),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (widget.milestoneId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HorizontalChoices(
              children: [
                for (final mine in [true, false])
                  ChoiceChip(
                    label: Text(mine ? 'Việc của tôi' : 'Việc của đồ án'),
                    selected: _mine == mine,
                    onSelected: (_) => setState(() {
                      _mine = mine;
                      _page = 1;
                    }),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Tìm công việc',
            hintText: 'Nhập tên rồi nhấn tìm',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Xóa tìm kiếm',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _search = '';
                      _page = 1;
                    }),
                  ),
          ),
          onSubmitted: (value) => setState(() {
            _search = value.trim();
            _page = 1;
          }),
        ),
        const SizedBox(height: 8),
        HorizontalChoices(
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
        const SizedBox(height: 12),
        if (page.items.isEmpty)
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Không có công việc phù hợp bộ lọc.'),
                if (_filter != 'all' || _search.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Xóa bộ lọc'),
                    onPressed: _resetFilters,
                  ),
                ],
              ],
            ),
          ),
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
                icon: switch (task['status']) {
                  'DONE' => Icons.task_alt,
                  'BLOCKED' => Icons.block_outlined,
                  'IN_PROGRESS' => Icons.timelapse,
                  _ => Icons.assignment_outlined,
                },
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
  final _pageKey = GlobalKey<RemotePageState<(TaskAccess, List<Json>)>>();
  int _revision = 0;
  bool _saving = false;
  bool _editing = false;
  String? _message;
  bool _failed = false;

  Future<void> _showActions(TaskAccess access) async {
    if (_saving || _editing) return;
    setState(() => _editing = true);
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tùy chọn công việc',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (access.allows('update_task'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Sửa nội dung'),
                  subtitle: const Text('Tên, mô tả và thời gian'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheet, 'content'),
                ),
              if (access.allows('assign_task'))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Phân công'),
                  subtitle: const Text('Chọn người phụ trách công việc'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(sheet, 'assignment'),
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
    if (!mounted) return;
    setState(() => _editing = false);
    if (action != null) await _edit(access, assignment: action == 'assignment');
  }

  Future<void> _edit(TaskAccess access, {bool assignment = false}) async {
    if (_saving || _editing) return;
    setState(() => _editing = true);
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorScreen(
          auth: widget.auth,
          projectId: idOf(access.capability, 'projectId'),
          taskId: widget.id,
          assignmentOnly: assignment,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (result != null) widget.onChanged();
    setState(() => _revision++);
  }

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
        builder: (sheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
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
      final latest = await widget.auth.getJson(
        '/api/v1/tasks/${widget.id}/execution-actions',
      );
      if (latest['projectId'] != access.capability['projectId'] ||
          !recordsOf(latest['actions']).any(
            (action) =>
                action['code'] == 'change_task_status' &&
                action['allowed'] == true,
          )) {
        throw const ApiException(
          'Quyền cập nhật đã thay đổi. Hãy tải lại công việc.',
          statusCode: 403,
        );
      }
      final freshAccess = TaskAccess(access.task, latest);
      if (!freshAccess.canChange) {
        throw const ApiException(
          'Công việc vừa thay đổi. Hãy kiểm tra trạng thái mới trước khi cập nhật.',
          statusCode: 409,
        );
      }
      await widget.auth.request(
        '/api/v1/tasks/${widget.id}/status',
        method: 'PUT',
        body: {
          'newStatus': target,
          'reason': note.isEmpty ? null : note,
          'concurrencyToken': freshAccess.token,
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
        actions: [
          IconButton(
            tooltip: 'Làm mới công việc',
            onPressed: _saving || _editing
                ? null
                : () => _pageKey.currentState?.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RemotePage<(TaskAccess, List<Json>)>(
        key: _pageKey,
        title: 'Công việc',
        showHeading: false,
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
            Text(
              textOf(task, 'title'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${statusText(task['status'])} · Ưu tiên ${statusText(task['priority'])}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (access.allows('update_task') ||
                access.allows('assign_task')) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _saving || _editing
                      ? null
                      : () => _showActions(access),
                  icon: const Icon(Icons.more_horiz),
                  label: const Text('Tùy chọn công việc'),
                ),
              ),
              const SizedBox(height: 8),
            ],
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
