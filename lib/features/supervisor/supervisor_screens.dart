import 'package:material_ui/material_ui.dart';

import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/paged_records.dart';
import '../../ui/remote_page.dart';
import '../ai/ai_screen.dart';
import '../auth/auth_controller.dart';
import '../calendar/calendar_screen.dart';
import '../chat/chat_screen.dart';
import '../dashboard/dashboard_model.dart';
import '../workspace/activity_screen.dart';
import '../workspace/inbox_screen.dart';
import '../workspace/tasks_screen.dart';
import '../workspace/workspace_models.dart';

typedef _SupervisorHomeData = ({
  Json dashboard,
  List<Json> triageItems,
  int triageTotal,
});

/// Lecturer / Supervisor companion overview using `/dashboards/supervisor`
/// and `/supervisors/me/triage-queue`. Strictly avoids web-only grading/admin forms.
class SupervisorDashboardScreen extends StatelessWidget {
  const SupervisorDashboardScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    required this.onOpenProjects,
    this.revision = 0,
    this.showHeading = false,
  });

  final AuthController auth;
  final VoidCallback onChanged;
  final VoidCallback onOpenProjects;
  final int revision;
  final bool showHeading;

  Future<_SupervisorHomeData> _load() async {
    final results = await Future.wait<Object?>([
      auth.getJson('/api/v1/dashboards/supervisor?page=1&pageSize=10'),
      auth
          .request('/api/v1/supervisors/me/triage-queue')
          .catchError((_) => null),
    ]);
    final dashboard = objectOf(results[0]);
    final triage = results[1] is Json ? results[1] as Json : null;
    final items = triage != null && triage['items'] is List
        ? recordsOf(triage['items'])
        : <Json>[];
    final total = triage != null && triage['totalCount'] is int
        ? triage['totalCount'] as int
        : items.length;
    return (dashboard: dashboard, triageItems: items, triageTotal: total);
  }

  @override
  Widget build(BuildContext context) => RemotePage<_SupervisorHomeData>(
    title: 'Tổng quan giảng viên',
    showHeading: showHeading,
    revision: revision,
    load: _load,
    content: (context, data, refresh) {
      final dashboard = data.dashboard;
      final workload = dashboard['workload'] is Json
          ? dashboard['workload'] as Json
          : const <String, dynamic>{};
      final assigned = (workload['assignedProjects'] as num?)?.toInt() ?? 0;
      final maxProjects = (workload['profileMaxActiveProjects'] as num?)
          ?.toInt();
      final pendingReviews =
          (dashboard['pendingProgressReviews'] as num?)?.toInt() ?? 0;
      final overdueTasks = (dashboard['overdueTasks'] as num?)?.toInt() ?? 0;
      final projectsPage = dashboard['projects'] is Json
          ? PageData.fromJson(dashboard['projects'])
          : const PageData([], 1, 0, 0);
      final asOf = parseUtcTimestamp(textOf(dashboard, 'asOfUtc', ''));

      return [
        NavyHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'KHÔNG GIAN GIẢNG VIÊN',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.amber,
                    ),
                  ),
                  StatusBadge(
                    workload['isAvailable'] == true
                        ? 'Đang nhận nhóm'
                        : 'Đã đủ định mức',
                    tone: workload['isAvailable'] == true
                        ? StatusTone.success
                        : StatusTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Xin chào, ${auth.user?.fullName ?? ''}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onNavy,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  _HeroStat(
                    label: 'Đồ án hướng dẫn',
                    value: maxProjects == null
                        ? '$assigned'
                        : '$assigned/$maxProjects',
                  ),
                  _HeroStat(
                    label: 'Báo cáo chờ nhận xét',
                    value: '$pendingReviews',
                    highlight: pendingReviews > 0,
                  ),
                  _HeroStat(
                    label: 'Việc quá hạn',
                    value: '$overdueTasks',
                    highlight: overdueTasks > 0,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        HorizontalChoices(
          children: [
            ActionChip(
              avatar: const Icon(Icons.assignment_ind_outlined, size: 18),
              label: const Text('Yêu cầu hướng dẫn'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SupervisorRequestsScreen(
                      auth: auth,
                      onChanged: onChanged,
                    ),
                  ),
                );
                await refresh();
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 18),
              label: const Text('Lịch tổng hợp'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CalendarScreen(auth: auth, onChanged: onChanged),
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.folder_outlined, size: 18),
              label: const Text('Tất cả đồ án'),
              onPressed: onOpenProjects,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionHeader(
          'Hàng đợi cần xử lý',
          trailing: StatusBadge(
            '${data.triageTotal} mục',
            tone: data.triageTotal > 0
                ? StatusTone.warning
                : StatusTone.neutral,
          ),
        ),
        const SizedBox(height: 10),
        if (data.triageItems.isEmpty)
          const Surface(
            child: Text(
              'Hiện chưa có mục khẩn cấp cần giảng viên phản hồi ngay.',
            ),
          )
        else
          for (final item in data.triageItems.take(8))
            RecordTile(
              title: textOf(item, 'title'),
              icon: _triageIcon(textOf(item, 'kind', '')),
              urgent: const {
                'HIGH',
                'CRITICAL',
                'URGENT',
              }.contains(textOf(item, 'severity', '').toUpperCase()),
              badge: statusText(item['status']),
              badgeTone: StatusBadge.toneForStatus(item['status'] as String?),
              subtitle:
                  '${_triageKind(textOf(item, 'kind', ''))}${item['dueAt'] != null ? ' · Hạn ${displayDate(item['dueAt'])}' : ''}',
              onTap: () => _openTriageItem(context, item, refresh),
            ),
        const SizedBox(height: 20),
        SectionHeader(
          'Đồ án đang hướng dẫn',
          trailing: TextButton(
            onPressed: onOpenProjects,
            child: const Text('Xem tất cả'),
          ),
        ),
        const SizedBox(height: 8),
        if (projectsPage.items.isEmpty)
          const Surface(
            child: Text('Chưa có đồ án nào được phân công hướng dẫn.'),
          )
        else
          for (final project in projectsPage.items.take(5))
            _SupervisorProjectCard(
              project: project,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SupervisorProjectDetailScreen(
                      auth: auth,
                      projectId: idOf(project),
                      onChanged: onChanged,
                    ),
                  ),
                );
                await refresh();
              },
            ),
        if (asOf != null) ...[
          const SizedBox(height: 16),
          Text(
            'Cập nhật ${formatVietnamTime(asOf)} · Giờ Việt Nam',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ];
    },
  );

  Future<void> _openTriageItem(
    BuildContext context,
    Json item,
    Future<void> Function() refresh,
  ) async {
    final kind = textOf(item, 'kind', '').toUpperCase();
    final id = item['id'];
    final projectId = item['projectId'];
    if (kind.contains('REQUEST')) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              SupervisorRequestsScreen(auth: auth, onChanged: onChanged),
        ),
      );
      await refresh();
      return;
    }
    if (id is int && id > 0) {
      if (kind.contains('REPORT')) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                ReportDetailScreen(auth: auth, id: id, onChanged: onChanged),
          ),
        );
        await refresh();
        return;
      }
      if (kind.contains('MEETING')) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                MeetingDetailScreen(auth: auth, id: id, onChanged: onChanged),
          ),
        );
        await refresh();
        return;
      }
      if (kind.contains('TASK')) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                TaskDetailScreen(auth: auth, id: id, onChanged: onChanged),
          ),
        );
        await refresh();
        return;
      }
    }
    if (projectId is int && projectId > 0) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SupervisorProjectDetailScreen(
            auth: auth,
            projectId: projectId,
            onChanged: onChanged,
          ),
        ),
      );
      await refresh();
    }
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.navyRaised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: highlight
            ? AppColors.attentionBorder
            : Colors.white.withAlpha(24),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: highlight ? AppColors.amber : AppColors.onNavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.onNavyMuted),
        ),
      ],
    ),
  );
}

class _SupervisorProjectCard extends StatelessWidget {
  const _SupervisorProjectCard({required this.project, required this.onTap});
  final Json project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final analysis = project['analysis'] is Json
        ? project['analysis'] as Json
        : const <String, dynamic>{};
    final progress = analysis['progressSummary'] is Json
        ? (analysis['progressSummary'] as Json)['progressPercentage'] as num?
        : null;
    final risk = analysis['riskLevel'] as String?;
    final pendingReviews =
        (project['pendingProgressReviews'] as num?)?.toInt() ?? 0;
    final majors = project['majors'] is List
        ? recordsOf(project['majors'])
        : const <Json>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        accentColor: risk == 'HIGH' || risk == 'CRITICAL'
            ? AppColors.danger
            : pendingReviews > 0
            ? AppColors.attentionBorder
            : AppColors.teal,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        textOf(project, 'code'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    StatusBadge(
                      statusText(project['status']),
                      tone: StatusBadge.toneForStatus(
                        project['status'] as String?,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  textOf(project, 'title'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (majors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final major in majors)
                        MajorTag(
                          textOf(major, 'code', textOf(major, 'name')),
                          code: textOf(major, 'code', ''),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: progress != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tiến độ ${progress.round()}%',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSoft,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                LinearProgressIndicator(
                                  value: (progress / 100).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  color: AppColors.primary,
                                  backgroundColor: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            )
                          : const Text(
                              'Chưa có số liệu tiến độ',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                    if (pendingReviews > 0) ...[
                      const SizedBox(width: 10),
                      StatusBadge(
                        '$pendingReviews báo cáo',
                        tone: StatusTone.warning,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paginated list of supervised projects for `LECTURER`.
class SupervisorProjectsScreen extends StatefulWidget {
  const SupervisorProjectsScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    this.revision = 0,
    this.showHeading = false,
  });

  final AuthController auth;
  final VoidCallback onChanged;
  final int revision;
  final bool showHeading;

  @override
  State<SupervisorProjectsScreen> createState() =>
      _SupervisorProjectsScreenState();
}

class _SupervisorProjectsScreenState extends State<SupervisorProjectsScreen> {
  String _status = '';
  String _search = '';
  int _page = 1;
  int _revision = 0;

  Future<PageData> _load() async {
    final query = Uri(
      queryParameters: {
        'page': '$_page',
        'pageSize': '15',
        if (_status.isNotEmpty) 'status': _status,
        if (_search.isNotEmpty) 'search': _search,
      },
    ).query;
    final data = await widget.auth.getJson(
      '/api/v1/dashboards/supervisor?$query',
    );
    return PageData.fromJson(data['projects']);
  }

  @override
  Widget build(BuildContext context) => RemotePage<PageData>(
    title: 'Đồ án hướng dẫn',
    showHeading: widget.showHeading,
    revision: widget.revision + _revision,
    load: _load,
    leading: [
      TextField(
        decoration: const InputDecoration(
          hintText: 'Tìm theo mã hoặc tên đồ án',
          prefixIcon: Icon(Icons.search),
        ),
        onSubmitted: (value) => setState(() {
          _search = value.trim();
          _page = 1;
          _revision++;
        }),
      ),
      const SizedBox(height: 10),
      HorizontalChoices(
        children: [
          for (final entry in const {
            '': 'Tất cả',
            'ACTIVE': 'Đang thực hiện',
            'APPROVED': 'Đã duyệt',
            'COMPLETED': 'Hoàn thành',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _status == entry.key,
              onSelected: (_) => setState(() {
                _status = entry.key;
                _page = 1;
                _revision++;
              }),
            ),
        ],
      ),
      const SizedBox(height: 16),
    ],
    content: (context, page, refresh) => [
      if (page.items.isEmpty)
        const Surface(child: Text('Không có đồ án phù hợp bộ lọc.')),
      for (final project in page.items)
        _SupervisorProjectCard(
          project: project,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SupervisorProjectDetailScreen(
                  auth: widget.auth,
                  projectId: idOf(project),
                  onChanged: widget.onChanged,
                ),
              ),
            );
            await refresh();
          },
        ),
      if (page.totalPages > 1)
        Pagination(
          data: page,
          change: (next) => setState(() {
            _page = next;
            _revision++;
          }),
        ),
    ],
  );
}

/// Supervisor view of a single project: overview, milestones, reports/meetings with quick feedback, chat & AI.
class SupervisorProjectDetailScreen extends StatelessWidget {
  const SupervisorProjectDetailScreen({
    super.key,
    required this.auth,
    required this.projectId,
    required this.onChanged,
  });

  final AuthController auth;
  final int projectId;
  final VoidCallback onChanged;

  Future<({Json project, List<Json> milestones, List<Json> progress})>
  _load() async {
    final results = await Future.wait<Object?>([
      auth.getJson('/api/v1/projects/$projectId'),
      auth.request('/api/v1/milestones/project/$projectId'),
      auth.request('/api/v1/milestones/project/$projectId/progress'),
    ]);
    return (
      project: objectOf(results[0]),
      milestones: recordsOf(results[1]),
      progress: recordsOf(results[2]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết đồ án')),
    body:
        RemotePage<
          ({Json project, List<Json> milestones, List<Json> progress})
        >(
          title: 'Chi tiết đồ án',
          showHeading: false,
          load: _load,
          content: (context, data, refresh) {
            final project = data.project;
            void openSub(Widget screen, String title) async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: screen,
                  ),
                ),
              );
              await refresh();
            }

            return [
              NavyHeroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            textOf(project, 'code'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.amber,
                            ),
                          ),
                        ),
                        StatusBadge(
                          statusText(project['status']),
                          tone: StatusBadge.toneForStatus(
                            project['status'] as String?,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      textOf(project, 'title'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onNavy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              HorizontalChoices(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Báo cáo & nhận xét'),
                    onPressed: () => openSub(
                      ActivityScreen(
                        auth: auth,
                        projectId: projectId,
                        meetings: false,
                        onChanged: onChanged,
                      ),
                      'Báo cáo & nhận xét',
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.event_outlined, size: 18),
                    label: const Text('Lịch họp'),
                    onPressed: () => openSub(
                      ActivityScreen(
                        auth: auth,
                        projectId: projectId,
                        meetings: true,
                        onChanged: onChanged,
                      ),
                      'Lịch họp',
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Chat nhóm'),
                    onPressed: () async {
                      try {
                        final conv = objectOf(
                          await auth.request(
                            '/api/v1/chat/projects/$projectId/conversation',
                            method: 'POST',
                          ),
                        );
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ChatThreadScreen(
                              auth: auth,
                              id: '${conv['id']}',
                            ),
                          ),
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(errorText(error))),
                          );
                        }
                      }
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Trợ lý AI'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            AiHomeScreen(auth: auth, projectId: projectId),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeader('Mốc tiến độ'),
              const SizedBox(height: 10),
              if (data.milestones.isEmpty)
                const Surface(child: Text('Đồ án chưa có mốc tiến độ.'))
              else
                for (final milestone in data.milestones)
                  RecordTile(
                    title: textOf(milestone, 'title'),
                    icon: Icons.flag_outlined,
                    badge: statusText(milestone['status']),
                    badgeTone: StatusBadge.toneForStatus(
                      milestone['status'] as String?,
                    ),
                    subtitle: 'Hạn: ${displayDate(milestone['dueDate'])}',
                    onTap: () => openEntity(
                      context,
                      auth,
                      EntityTarget('MILESTONE', idOf(milestone)),
                      onChanged,
                    ),
                  ),
            ];
          },
        ),
  );
}

/// Supervisor requests inbox: accept or reject student supervision requests.
class SupervisorRequestsScreen extends StatefulWidget {
  const SupervisorRequestsScreen({
    super.key,
    required this.auth,
    required this.onChanged,
  });

  final AuthController auth;
  final VoidCallback onChanged;

  @override
  State<SupervisorRequestsScreen> createState() =>
      _SupervisorRequestsScreenState();
}

class _SupervisorRequestsScreenState extends State<SupervisorRequestsScreen> {
  String _status = 'PENDING';
  int _revision = 0;
  bool _saving = false;
  String? _notice;
  bool _failed = false;

  Future<void> _respond(int requestId, {required bool accept}) async {
    if (_saving) return;
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          accept ? 'Chấp nhận hướng dẫn nhóm?' : 'Từ chối yêu cầu hướng dẫn?',
        ),
        content: SingleChildScrollView(
          child: TextField(
            controller: note,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: accept
                  ? 'Lời nhắn cho nhóm (không bắt buộc)'
                  : 'Lý do từ chối (khuyến nghị)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(accept ? 'Chấp nhận' : 'Từ chối'),
          ),
        ],
      ),
    );
    final message = note.text.trim();
    note.dispose();
    if (!mounted || confirmed != true) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/supervisor-requests/$requestId/${accept ? 'accept' : 'reject'}',
        method: 'POST',
        body: {'message': message.isEmpty ? null : message},
      );
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _notice = accept
              ? 'Đã chấp nhận yêu cầu hướng dẫn.'
              : 'Đã từ chối yêu cầu hướng dẫn.';
          _revision++;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _notice = errorText(error);
          _revision++;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yêu cầu hướng dẫn')),
    body: PagedRecords(
      auth: widget.auth,
      title: 'Yêu cầu hướng dẫn',
      showHeading: false,
      revision: _revision,
      path:
          '/api/v1/supervisors/requests${_status.isEmpty ? '' : '?status=$_status'}',
      emptyText: 'Không có yêu cầu hướng dẫn nào.',
      leading: [
        HorizontalChoices(
          children: [
            for (final entry in const {
              'PENDING': 'Đang chờ',
              'ACCEPTED': 'Đã nhận',
              'REJECTED': 'Đã từ chối',
              '': 'Tất cả',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _status == entry.key,
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                        _status = entry.key;
                        _notice = null;
                      }),
              ),
          ],
        ),
        if (_notice != null) ...[
          const SizedBox(height: 12),
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
        ],
        const SizedBox(height: 16),
      ],
      item: (context, row, refresh) {
        final pending = row['status'] == 'PENDING';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Surface(
            accentColor: pending ? AppColors.attentionBorder : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        textOf(
                          row,
                          'projectTitle',
                          'Đồ án #${row['projectId']}',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(
                      statusText(row['status']),
                      tone: StatusBadge.toneForStatus(row['status'] as String?),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Gửi lúc: ${displayDate(row['requestedAt'])}${row['expiresAt'] != null ? '\nHết hạn: ${displayDate(row['expiresAt'])}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                if (textOf(row, 'requestMessage', '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableBody(row['requestMessage'] as String),
                ],
                if (pending) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _respond(idOf(row), accept: true),
                        child: const Text('Chấp nhận'),
                      ),
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _respond(idOf(row), accept: false),
                        child: const Text('Từ chối'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

IconData _triageIcon(String kind) {
  final upper = kind.toUpperCase();
  if (upper.contains('REPORT')) return Icons.fact_check_outlined;
  if (upper.contains('MEETING')) return Icons.event_outlined;
  if (upper.contains('REQUEST')) return Icons.assignment_ind_outlined;
  if (upper.contains('TASK')) return Icons.check_box_outlined;
  return Icons.priority_high_outlined;
}

String _triageKind(String kind) {
  final upper = kind.toUpperCase();
  if (upper.contains('REPORT')) return 'Báo cáo chờ nhận xét';
  if (upper.contains('MEETING')) return 'Cuộc họp';
  if (upper.contains('REQUEST')) return 'Yêu cầu hướng dẫn';
  if (upper.contains('TASK')) return 'Công việc cần lưu ý';
  return 'Mục cần xử lý';
}
