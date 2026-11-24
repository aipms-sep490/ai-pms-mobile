import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import 'workspace_models.dart';

/// Displays V4 task extras (criteria checklist, labels/taxonomy, comments) inside TaskDetailScreen.
class TaskExtrasSection extends StatefulWidget {
  const TaskExtrasSection({
    super.key,
    required this.auth,
    required this.task,
    required this.projectId,
    required this.canEdit,
    required this.onChanged,
  });

  final AuthController auth;
  final Json task;
  final int projectId;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  State<TaskExtrasSection> createState() => _TaskExtrasSectionState();
}

class _TaskExtrasSectionState extends State<TaskExtrasSection> {
  final _commentCtrl = TextEditingController();
  final _criterionCtrl = TextEditingController();

  Json? _criteria;
  List<Json> _comments = [];
  List<Json> _projectLabels = [];
  bool _loading = true;
  bool _postingComment = false;
  bool _togglingCriterion = false;
  bool _savingLabels = false;
  String? _notice;
  bool _failed = false;

  int get _taskId => idOf(widget.task);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TaskExtrasSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task['id'] != widget.task['id'] ||
        oldWidget.task['concurrencyToken'] != widget.task['concurrencyToken']) {
      _load();
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _criterionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<Object?>([
        widget.auth
            .request('/api/v1/tasks/$_taskId/criteria')
            .catchError((_) => null),
        widget.auth
            .request('/api/v1/tasks/$_taskId/comments?page=1&pageSize=30')
            .catchError((_) => null),
        widget.auth
            .request('/api/v1/projects/${widget.projectId}/labels')
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _criteria = results[0] is Json ? results[0] as Json : null;
        if (results[1] is Json && (results[1] as Json)['items'] is List) {
          _comments = recordsOf((results[1] as Json)['items']);
        }
        if (results[2] is List) {
          _projectLabels = recordsOf(results[2]);
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleCriterion(Json item) async {
    if (_togglingCriterion) return;
    final current = item['isCompleted'] == true;
    setState(() {
      _togglingCriterion = true;
      _notice = null;
    });
    try {
      final updated = objectOf(
        await widget.auth.request(
          '/api/v1/tasks/$_taskId/criteria/${idOf(item)}',
          method: 'PATCH',
          body: {'isCompleted': !current},
        ),
      );
      widget.onChanged();
      if (mounted) {
        setState(() {
          _criteria = updated;
          _failed = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _togglingCriterion = false);
    }
  }

  Future<void> _addCriterion() async {
    final title = _criterionCtrl.text.trim();
    if (_togglingCriterion || title.isEmpty || _criteria == null) return;
    final items = recordsOf(_criteria!['items'] ?? const <dynamic>[]);
    setState(() {
      _togglingCriterion = true;
      _notice = null;
    });
    try {
      final updated = objectOf(
        await widget.auth.request(
          '/api/v1/tasks/$_taskId/criteria',
          method: 'PUT',
          body: {
            'items': [
              for (final row in items)
                {
                  'title': textOf(row, 'title'),
                  'isCompleted': row['isCompleted'] == true,
                },
              {'title': title, 'isCompleted': false},
            ],
          },
        ),
      );
      _criterionCtrl.clear();
      widget.onChanged();
      if (mounted) {
        setState(() {
          _criteria = updated;
          _failed = false;
          _notice = 'Đã thêm tiêu chí hoàn thành.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _togglingCriterion = false);
    }
  }

  Future<void> _editLabels() async {
    if (_savingLabels || _projectLabels.isEmpty) return;
    final currentLabels = ((widget.task['labels'] as List?) ?? const [])
        .map((e) => '$e')
        .toSet();
    final selected = Set<String>.of(currentLabels);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gắn nhãn công việc',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final label in _projectLabels)
                      FilterChip(
                        label: Text(textOf(label, 'name')),
                        selected: selected.contains(textOf(label, 'slug')),
                        onSelected: (checked) => update(() {
                          final slug = textOf(label, 'slug');
                          if (checked) {
                            selected.add(slug);
                          } else {
                            selected.remove(slug);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, true),
                  child: const Text('Lưu nhãn'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || saved != true) return;
    setState(() {
      _savingLabels = true;
      _notice = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/tasks/$_taskId/taxonomy',
        method: 'PATCH',
        body: {
          'labels': selected.toList(),
          'concurrencyToken': widget.task['concurrencyToken'],
        },
      );
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _notice = 'Đã cập nhật nhãn công việc.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _savingLabels = false);
    }
  }

  Future<void> _sendComment() async {
    final content = _commentCtrl.text.trim();
    if (_postingComment || content.isEmpty) return;
    setState(() {
      _postingComment = true;
      _notice = null;
    });
    try {
      final created = objectOf(
        await widget.auth.request(
          '/api/v1/tasks/$_taskId/comments',
          method: 'POST',
          body: {'content': content},
        ),
      );
      _commentCtrl.clear();
      if (mounted) {
        setState(() {
          _comments = [..._comments, created];
          _failed = false;
          _notice = 'Đã gửi bình luận.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = ((widget.task['labels'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    final criteriaItems = _criteria != null && _criteria!['items'] is List
        ? recordsOf(_criteria!['items'])
        : const <Json>[];
    final canToggle = _criteria?['canToggle'] == true;
    final canManage = _criteria?['canManage'] == true;
    final completedCount = (_criteria?['completedCount'] as num?)?.toInt() ?? 0;
    final totalCount =
        (_criteria?['totalCount'] as num?)?.toInt() ?? criteriaItems.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _notice!,
              style: TextStyle(
                color: _failed ? AppColors.danger : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (labels.isNotEmpty ||
            (widget.canEdit && _projectLabels.isNotEmpty)) ...[
          SectionHeader(
            'Nhãn & phân loại',
            trailing: widget.canEdit && _projectLabels.isNotEmpty
                ? TextButton.icon(
                    onPressed: _savingLabels ? null : _editLabels,
                    icon: const Icon(Icons.label_outline, size: 18),
                    label: const Text('Gắn nhãn'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (labels.isEmpty)
            const Text(
              'Chưa gắn nhãn.',
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final slug in labels)
                  MajorTag(
                    _labelName(slug),
                    code: slug,
                    colorHex: _labelHex(slug),
                  ),
              ],
            ),
          const SizedBox(height: 20),
        ],
        SectionHeader(
          'Tiêu chí hoàn thành',
          trailing: totalCount > 0
              ? StatusBadge(
                  '$completedCount/$totalCount',
                  tone: completedCount == totalCount
                      ? StatusTone.success
                      : StatusTone.info,
                )
              : null,
        ),
        const SizedBox(height: 10),
        if (_loading && _criteria == null)
          const Text('Đang tải tiêu chí…')
        else if (criteriaItems.isEmpty)
          const Text(
            'Chưa có tiêu chí hoàn thành.',
            style: TextStyle(color: AppColors.textMuted),
          )
        else
          Surface(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < criteriaItems.length; i++) ...[
                  if (i > 0) const Divider(),
                  CheckboxListTile(
                    value: criteriaItems[i]['isCompleted'] == true,
                    onChanged: canToggle && !_togglingCriterion
                        ? (_) => _toggleCriterion(criteriaItems[i])
                        : null,
                    title: Text(
                      textOf(criteriaItems[i], 'title'),
                      style: TextStyle(
                        decoration: criteriaItems[i]['isCompleted'] == true
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ),
          ),
        if (canManage) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('task-criterion-input'),
                  controller: _criterionCtrl,
                  enabled: !_togglingCriterion,
                  decoration: const InputDecoration(
                    hintText: 'Thêm tiêu chí hoàn thành…',
                  ),
                  onSubmitted: (_) => _addCriterion(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _togglingCriterion ? null : _addCriterion,
                child: const Text('Thêm'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        SectionHeader(
          'Bình luận',
          trailing: StatusBadge('${_comments.length}'),
        ),
        const SizedBox(height: 10),
        if (_loading && _comments.isEmpty)
          const Text('Đang tải bình luận…')
        else if (_comments.isEmpty)
          const Text(
            'Chưa có bình luận nào cho công việc này.',
            style: TextStyle(color: AppColors.textMuted),
          )
        else
          for (final comment in _comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            textOf(comment, 'authorName', 'Thành viên'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        Text(
                          displayDate(comment['createdAt']),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableBody(textOf(comment, 'content')),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('task-comment-input'),
                controller: _commentCtrl,
                enabled: !_postingComment,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'Viết bình luận trao đổi…',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('task-comment-send'),
              onPressed: _postingComment ? null : _sendComment,
              child: _postingComment
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onNavy,
                      ),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  String _labelName(String slug) {
    for (final row in _projectLabels) {
      if (row['slug'] == slug) return textOf(row, 'name', slug);
    }
    return slug;
  }

  String? _labelHex(String slug) {
    for (final row in _projectLabels) {
      if (row['slug'] == slug) return row['colorHex'] as String?;
    }
    return null;
  }
}

/// Soft-deletes a task and displays a 5-second undo SnackBar calling `/tasks/{id}/restore`.
Future<bool> deleteTaskWithUndo(
  BuildContext context, {
  required AuthController auth,
  required int taskId,
  required String? concurrencyToken,
  required VoidCallback onChanged,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Xóa công việc?'),
      content: const Text(
        'Công việc sẽ được chuyển vào trạng thái đã xóa và có thể hoàn tác ngay trong 5 giây.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Xóa'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final query = concurrencyToken == null || concurrencyToken.isEmpty
      ? ''
      : '?${Uri(queryParameters: {'concurrencyToken': concurrencyToken}).query}';
  await auth.request('/api/v1/tasks/$taskId$query', method: 'DELETE');
  onChanged();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text('Đã xóa công việc.'),
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () async {
            try {
              await auth.request(
                '/api/v1/tasks/$taskId/restore',
                method: 'POST',
              );
              onChanged();
              messenger.showSnackBar(
                const SnackBar(content: Text('Đã khôi phục công việc.')),
              );
            } on ApiException catch (error) {
              messenger.showSnackBar(SnackBar(content: Text(error.message)));
            } catch (_) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Không thể hoàn tác lúc này.')),
              );
            }
          },
        ),
      ),
    );
  return true;
}
