import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../dashboard/dashboard_model.dart';
import 'workspace_models.dart';

List<Json> taskCreationMajors(Json project, Json requirements) {
  final scope = project['academicScope'];
  if (project['academicScopeProvenance'] != 'FROZEN_REGISTRATION_SNAPSHOT' ||
      scope is! Json ||
      !['SINGLE_MAJOR', 'INTERDISCIPLINARY'].contains(scope['projectMode'])) {
    throw const ApiException(
      'Chưa có phạm vi học thuật đã xác minh để tạo công việc.',
    );
  }
  final frozen = recordsOf(scope['requirements']);
  final current = recordsOf(requirements['requirements']);
  final ids = (current.isEmpty ? frozen : current)
      .map((row) => idOf(row, 'majorId'))
      .toList();
  final frozenIds = frozen.map((row) => idOf(row, 'majorId')).toSet();
  if (ids.isEmpty ||
      frozenIds.length != frozen.length ||
      ids.toSet().length != ids.length ||
      !ids.every(frozenIds.contains)) {
    throw const ApiException(
      'Phạm vi ngành chưa khớp hồ sơ đăng ký. Hãy tải lại dữ liệu đồ án.',
    );
  }
  final names = {
    for (final row in recordsOf(project['majors']))
      idOf(row, 'majorId'): textOf(row, 'majorName'),
  };
  return [
    for (final id in ids) {'id': id, 'name': names[id] ?? 'Ngành #$id'},
  ];
}

/// Content and assignment are separate saves because the backend gives each its
/// own capability and concurrency token. No multi-request partial save.
class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    super.key,
    required this.auth,
    required this.projectId,
    this.taskId,
    this.milestoneId,
    this.assignmentOnly = false,
    this.initialDraft,
  });
  final AuthController auth;
  final int projectId;
  final int? taskId;
  final int? milestoneId;
  final bool assignmentOnly;
  final Json? initialDraft;
  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  Json? _project;
  Json? _capability;
  Json? _task;
  List<Json> _milestones = [];
  List<Json> _members = [];
  List<Json> _majors = [];
  final _assignees = <int>{};
  final _supporting = <int>{};
  int? _milestone;
  int? _primary;
  String? _priority = 'MEDIUM';
  DateTime? _start;
  DateTime? _due;
  bool _loading = true;
  bool _saving = false;
  bool _initialized = false;
  bool _dirty = false;
  bool _needsReload = false;
  bool _uncertainCreate = false;
  String? _error;
  String? _notice;
  bool get _creating => widget.taskId == null;
  String get _action => widget.assignmentOnly
      ? 'assign_task'
      : _creating
      ? 'create_task'
      : 'update_task';
  String get _capPath => _creating
      ? '/api/v1/projects/${widget.projectId}/execution-actions'
      : '/api/v1/tasks/${widget.taskId}/execution-actions';
  bool get _allowed =>
      _project?['status'] == 'ACTIVE' &&
      _capability != null &&
      executionAllowed(
        _capability!,
        type: _creating ? 'PROJECT' : 'TASK',
        id: widget.taskId ?? widget.projectId,
        projectId: widget.projectId,
        action: _action,
      ) &&
      (_creating || TaskAccess(_task!, _capability!).allows(_action));
  bool get _interdisciplinary =>
      _project?['academicScope'] is Json &&
      (_project!['academicScope'] as Json)['projectMode'] ==
          'INTERDISCIPLINARY';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_saving) return;
    setState(() => _loading = true);
    try {
      final first = await Future.wait([
        widget.auth.getJson('/api/v1/projects/${widget.projectId}'),
        widget.auth.getJson(_capPath),
        _creating
            ? Future.value(<String, dynamic>{})
            : widget.auth.getJson('/api/v1/tasks/${widget.taskId}'),
      ]);
      final project = first[0];
      final capability = first[1];
      final task = first[2];
      if (idOf(project) != widget.projectId ||
          !executionAllowed(
            capability,
            type: _creating ? 'PROJECT' : 'TASK',
            id: widget.taskId ?? widget.projectId,
            projectId: widget.projectId,
            action: _action,
          ) ||
          project['status'] != 'ACTIVE') {
        throw const ApiException(
          'Bạn hiện không có quyền thực hiện thao tác công việc này.',
          statusCode: 403,
        );
      }
      if (!_creating && !TaskAccess(task, capability).allows(_action)) {
        throw const ApiException(
          'Công việc vừa thay đổi. Hãy tải lại trước khi chỉnh sửa.',
          statusCode: 409,
        );
      }
      final rest = await Future.wait([
        widget.assignmentOnly
            ? Future<Object?>.value([])
            : widget.auth.request(
                '/api/v1/milestones/project/${widget.projectId}',
              ),
        (_creating || widget.assignmentOnly)
            ? widget.auth.request('/api/v1/teams/${idOf(project, 'teamId')}')
            : Future<Object?>.value({'members': []}),
        _creating
            ? widget.auth.request(
                '/api/v1/projects/${widget.projectId}/major-requirements',
              )
            : Future<Object?>.value({}),
      ]);
      final milestones = recordsOf(rest[0]);
      for (final row in milestones) {
        if (row['projectId'] != widget.projectId) {
          throw const FormatException('Milestone project mismatch');
        }
      }
      final members = recordsOf(objectOf(rest[1])['members']);
      final majors = _creating
          ? taskCreationMajors(project, objectOf(rest[2]))
          : <Json>[];
      if (!mounted) return;
      setState(() {
        _project = project;
        _capability = capability;
        _task = _creating ? null : task;
        _milestones = milestones;
        _members = members;
        _majors = majors;
        _needsReload = false;
        _error = null;
        if (!_initialized) {
          _hydrate();
          _initialized = true;
        } else {
          _notice = 'Đã tải dữ liệu mới. Bản đang soạn được giữ lại; kiểm tra thông tin trước khi lưu.';
        }
        if (_creating || widget.assignmentOnly) {
          final memberIds = _members.map((row) => idOf(row, 'userId')).toSet();
          if (!_assignees.every(memberIds.contains)) _notice = 'Một số người không còn trong nhóm và đã được bỏ khỏi lựa chọn. Kiểm tra phân công trước khi lưu.';
          _assignees.retainWhere(memberIds.contains);
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorText(error);
          _needsReload = true;
          if (error is ApiException &&
              [401, 403, 404].contains(error.statusCode)) {
            _capability = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Json? _unique(List<Json> rows, String key, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final matches = rows
        .where(
          (row) =>
              textOf(row, key, '').trim().toLowerCase() ==
              value.trim().toLowerCase(),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  void _hydrate() {
    if (!_creating) {
      final task = _task!;
      _title.text = textOf(task, 'title', '');
      _description.text = textOf(task, 'description', '');
      _priority = task['priority'] as String?;
      _milestone = idOf(task, 'milestoneId');
      _start = parseUtcTimestamp(textOf(task, 'startAt', ''));
      _due = parseUtcTimestamp(textOf(task, 'dueAt', ''));
      _assignees.addAll(
        recordsOf(task['assignees']).map((row) => idOf(row, 'userId')),
      );
      return;
    }
    _milestone = _milestones.any((row) => row['id'] == widget.milestoneId)
        ? widget.milestoneId
        : (_milestones.length == 1 ? idOf(_milestones.single) : null);
    final draft = widget.initialDraft;
    if (draft == null) return;
    _title.text = textOf(draft, 'title', '');
    _description.text = textOf(draft, 'description', '');
    final input = draft['task'] is Json
        ? draft['task'] as Json
        : <String, dynamic>{};
    final milestone = _unique(
      _milestones,
      'title',
      input['milestoneTitle'] as String?,
    );
    if (milestone != null) _milestone = idOf(milestone);
    final primary = _unique(
      _majors,
      'name',
      input['primaryMajorName'] as String?,
    );
    if (primary != null) _primary = idOf(primary);
    for (final name
        in (input['assigneeNames'] as List? ?? []).whereType<String>()) {
      final person = _unique(_members, 'fullName', name);
      if (person != null) _assignees.add(idOf(person, 'userId'));
    }
    if (['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'].contains(input['priority'])) {
      _priority = input['priority'] as String;
    }
    _due = parseUtcTimestamp(textOf(input, 'dueAt', ''));
    _notice = 'Đã điền gợi ý AI. Kiểm tra tên, mốc, ngành và người phụ trách; các tên không khớp duy nhất cần chọn lại.';
    _dirty = true;
  }

  Future<void> _pickDate(bool start) async {
    final existing = (start ? _start : _due)?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: existing,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(existing),
    );
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (start) {
        _start = value;
      } else {
        _due = value;
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    if (_loading ||
        _saving ||
        _needsReload ||
        _uncertainCreate ||
        !_allowed ||
        !_form.currentState!.validate()) {
      return;
    }
    if (!widget.assignmentOnly &&
        _start != null &&
        _due != null &&
        _due!.isBefore(_start!)) {
      setState(
        () => _error = 'Hạn hoàn thành phải từ thời gian bắt đầu trở đi.',
      );
      return;
    }
    if (_creating &&
        (_interdisciplinary || _supporting.isNotEmpty) &&
        _primary == null) {
      setState(() => _error = 'Chọn ngành chính cho công việc liên ngành.');
      return;
    }
    if (!widget.assignmentOnly &&
        !_milestones.any((m) => m['id'] == _milestone)) {
      setState(() => _error = 'Chọn mốc thuộc đồ án hiện tại.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var posted = false;
    try {
      final latest = await widget.auth.getJson(_capPath);
      if (!executionAllowed(
        latest,
        type: _creating ? 'PROJECT' : 'TASK',
        id: widget.taskId ?? widget.projectId,
        projectId: widget.projectId,
        action: _action,
      )) {
        throw const ApiException(
          'Quyền thao tác đã thay đổi. Hãy tải lại dữ liệu.',
          statusCode: 403,
        );
      }
      if (!_creating && !TaskAccess(_task!, latest).allows(_action)) {
        throw const ApiException(
          'Công việc vừa được cập nhật ở nơi khác. Tải dữ liệu mới để đối chiếu.',
          statusCode: 409,
        );
      }
      if (!mounted) return;
      final Object body = widget.assignmentOnly
          ? _assignees.toList()
          : {
              'milestoneId': _milestone,
              'parentTaskId': _task?['parentTaskId'],
              'title': _title.text.trim(),
              'description': _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              'priority': _priority,
              'startAt': _start?.toUtc().toIso8601String(),
              'dueAt': _due?.toUtc().toIso8601String(),
              if (_creating) 'assigneeUserIds': _assignees.toList(),
              if (_creating)
                'disciplines': [
                  if (_primary != null)
                    {'majorId': _primary, 'role': 'PRIMARY'},
                  for (final id in _supporting)
                    if (id != _primary) {'majorId': id, 'role': 'SUPPORTING'},
                ],
              if (!_creating)
                'concurrencyToken': TaskAccess(_task!, latest).token,
            };
      final path = _creating
          ? '/api/v1/tasks'
          : widget.assignmentOnly
          ? '/api/v1/tasks/${widget.taskId}/assignees?${Uri(queryParameters: {'concurrencyToken': TaskAccess(_task!, latest).token}).query}'
          : '/api/v1/tasks/${widget.taskId}';
      posted = true;
      final result = objectOf(
        await widget.auth.request(
          path,
          method: _creating || widget.assignmentOnly ? 'POST' : 'PUT',
          body: body,
        ),
      );
      if (idOf(result) <= 0 || (!_creating && idOf(result) != widget.taskId)) {
        throw const ApiException(
          'Chưa xác nhận được kết quả lưu. Quay lại danh sách để kiểm tra.',
        );
      }
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        Navigator.pop(context, result);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorText(error);
          if (error is ApiException &&
              [401, 403, 404, 409].contains(error.statusCode)) {
            _needsReload = true;
          }
          if (error is ApiException &&
              [401, 403, 404].contains(error.statusCode)) {
            _capability = null;
          }
          if (_creating &&
              posted &&
              (error is! ApiException ||
                  error.statusCode == 0 ||
                  error.statusCode >= 500)) {
            _uncertainCreate = true;
            _error = 'Chưa xác nhận được kết quả tạo. Quay lại danh sách và kiểm tra trước khi tạo lại để tránh trùng công việc.';
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard(bool didPop) async {
    if (didPop || _saving) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Bỏ bản đang soạn?'),
        content: const Text('Nội dung chưa lưu sẽ bị bỏ.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Tiếp tục soạn'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Bỏ bản soạn'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _dirty = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && !_dirty,
    onPopInvokedWithResult: (didPop, _) => _discard(didPop),
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.assignmentOnly
              ? 'Phân công'
              : _creating
              ? 'Tạo công việc'
              : 'Sửa công việc',
        ),
        automaticallyImplyLeading: !_saving,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading || _saving)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Đang xử lý công việc',
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Notice(
                          _error!,
                          retry: _saving || _loading || _uncertainCreate
                              ? null
                              : _load,
                        ),
                      ),
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_notice!),
                      ),
                    if (_initialized) ...[
                      Text(
                        textOf(_project!, 'title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 20),
                      if (!_creating && _needsReload)
                        const Text(
                          'Tải dữ liệu mới trước khi lưu tiếp. Bản đang soạn được giữ lại.',
                        ),
                      if (!_creating && _notice != null)
                        ContentSection(
                          'Bản hiện có trên hệ thống',
                          '${textOf(_task!, 'title')}\nCập nhật: ${displayDate(_task!['updatedAt'])}',
                        ),
                      AbsorbPointer(
                        absorbing: _saving || _loading || !_allowed,
                        child: ExcludeFocus(
                          excluding: _saving || _loading || !_allowed,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!widget.assignmentOnly) ...[
                                TextFormField(
                                  controller: _title,
                                  maxLength: 255,
                                  onChanged: (_) =>
                                      setState(() => _dirty = true),
                                  decoration: const InputDecoration(
                                    labelText: 'Tên công việc',
                                  ),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'Nhập tên công việc.'
                                      : v.trim().length > 255
                                      ? 'Tên tối đa 255 ký tự.'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<int>(
                                  key: ValueKey('milestone/$_milestone'),
                                  initialValue:
                                      _milestones.any(
                                        (m) => m['id'] == _milestone,
                                      )
                                      ? _milestone
                                      : null,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Mốc đồ án',
                                  ),
                                  items: [
                                    for (final row in _milestones)
                                      DropdownMenuItem(
                                        value: idOf(row),
                                        child: Text(
                                          textOf(row, 'title'),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _milestone = v;
                                    _dirty = true;
                                  }),
                                  validator: (v) =>
                                      v == null ? 'Chọn mốc đồ án.' : null,
                                ),
                                const SizedBox(height: 16),
                                DropdownButtonFormField<String>(
                                  initialValue: _priority,
                                  decoration: const InputDecoration(
                                    labelText: 'Ưu tiên',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: null,
                                      child: Text('Chưa chọn'),
                                    ),
                                    for (final v in [
                                      'LOW',
                                      'MEDIUM',
                                      'HIGH',
                                      'CRITICAL',
                                    ])
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text(statusText(v)),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _priority = v;
                                    _dirty = true;
                                  }),
                                ),
                                const SizedBox(height: 16),
                                for (final start in [true, false])
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      start
                                          ? 'Bắt đầu dự kiến'
                                          : 'Hạn hoàn thành',
                                    ),
                                    subtitle: Text(
                                      displayDate(
                                        (start ? _start : _due)
                                            ?.toUtc()
                                            .toIso8601String(),
                                      ),
                                    ),
                                    onTap: () => _pickDate(start),
                                    trailing: IconButton(
                                      tooltip: start
                                          ? 'Bỏ thời gian bắt đầu'
                                          : 'Bỏ hạn hoàn thành',
                                      onPressed: () => setState(() {
                                        if (start) {
                                          _start = null;
                                        } else {
                                          _due = null;
                                        }
                                        _dirty = true;
                                      }),
                                      icon: const Icon(Icons.clear),
                                    ),
                                  ),
                                const Text('Ngày giờ theo múi giờ thiết bị.'),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _description,
                                  minLines: 3,
                                  maxLines: 8,
                                  maxLength: 10000,
                                  onChanged: (_) =>
                                      setState(() => _dirty = true),
                                  decoration: const InputDecoration(
                                    labelText: 'Mô tả (không bắt buộc)',
                                  ),
                                  validator: (v) => (v?.length ?? 0) > 10000
                                      ? 'Mô tả tối đa 10000 ký tự.'
                                      : null,
                                ),
                              ],
                              if (_creating) ...[
                                const SizedBox(height: 16),
                                DropdownButtonFormField<int>(
                                  key: ValueKey('major/$_primary'),
                                  initialValue: _primary,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: _interdisciplinary
                                        ? 'Ngành chính (bắt buộc)'
                                        : 'Ngành chính',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: null,
                                      child: Text('Chưa phân loại'),
                                    ),
                                    for (final row in _majors)
                                      DropdownMenuItem(
                                        value: idOf(row),
                                        child: Text(textOf(row, 'name')),
                                      ),
                                  ],
                                  onChanged: (v) => setState(() {
                                    _primary = v;
                                    _supporting.remove(v);
                                    _dirty = true;
                                  }),
                                  validator: (v) =>
                                      (_interdisciplinary ||
                                              _supporting.isNotEmpty) &&
                                          v == null
                                      ? 'Chọn một ngành chính.'
                                      : null,
                                ),
                                const SizedBox(height: 16),
                                const ContentSection('Ngành hỗ trợ', null),
                                for (final row in _majors)
                                  if (idOf(row) != _primary)
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(textOf(row, 'name')),
                                      value: _supporting.contains(idOf(row)),
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          _supporting.add(idOf(row));
                                        } else {
                                          _supporting.remove(idOf(row));
                                        }
                                        _dirty = true;
                                      }),
                                    ),
                              ],
                              if (_creating || widget.assignmentOnly) ...[
                                const SizedBox(height: 16),
                                const ContentSection(
                                  'Người phụ trách',
                                  'Có thể chọn nhiều người hoặc để trống.',
                                ),
                                for (final row in _members)
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(textOf(row, 'fullName')),
                                    value: _assignees.contains(
                                      idOf(row, 'userId'),
                                    ),
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _assignees.add(idOf(row, 'userId'));
                                      } else {
                                        _assignees.remove(idOf(row, 'userId'));
                                      }
                                      _dirty = true;
                                    }),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_uncertainCreate)
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() => _dirty = false);
                                  Navigator.pop(context);
                                },
                          child: const Text('Quay về danh sách để kiểm tra'),
                        )
                      else if (_needsReload)
                        FilledButton(
                          onPressed: _loading || _saving ? null : _load,
                          child: const Text('Tải dữ liệu mới'),
                        )
                      else
                        FilledButton(
                          onPressed: _loading || _saving || !_allowed
                              ? null
                              : _save,
                          child: Text(
                            _saving
                                ? 'Đang lưu…'
                                : widget.assignmentOnly
                                ? 'Lưu phân công'
                                : _creating
                                ? 'Tạo công việc'
                                : 'Lưu nội dung',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
