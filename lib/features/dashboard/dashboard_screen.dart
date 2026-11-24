import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../calendar/calendar_screen.dart';
import '../workspace/inbox_screen.dart';
import '../workspace/workspace_models.dart';
import 'dashboard_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.auth,
    this.onOpenProject,
    this.onOpenDeadline,
    this.onChanged,
    this.showHeading = true,
  });

  final AuthController auth;
  final VoidCallback? onOpenProject;
  final ValueChanged<DashboardDeadline>? onOpenDeadline;
  final VoidCallback? onChanged;
  final bool showHeading;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StudentDashboard? _data;
  List<Json> _nextActions = const [];
  String? _error;
  bool _loading = true;
  int _loadVersion = 0;

  bool get _isStudent => widget.auth.user?.roles.contains('STUDENT') ?? false;

  @override
  void initState() {
    super.initState();
    if (_isStudent) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _loadVersion++;
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!_isStudent) return;
    final version = ++_loadVersion;
    final accountId = widget.auth.user?.id;
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object?>([
        widget.auth.getJson('/api/v1/dashboards/student'),
        widget.auth
            .request('/api/v1/students/me/next-actions')
            .catchError((_) => null),
      ]);
      final dashboard = StudentDashboard.fromJson(results[0] as Json);
      final actionsJson = results[1] is Json ? results[1] as Json : null;
      final actions = actionsJson != null && actionsJson['items'] is List
          ? recordsOf(actionsJson['items'])
          : const <Json>[];
      if (!mounted ||
          version != _loadVersion ||
          accountId != widget.auth.user?.id) {
        return;
      }
      setState(() {
        _data = dashboard;
        _nextActions = actions;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          version != _loadVersion ||
          accountId != widget.auth.user?.id) {
        return;
      }
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Không thể tải tổng quan. Vui lòng thử lại.';
        _loading = false;
        if (error is ApiException &&
            [401, 403, 404].contains(error.statusCode)) {
          _data = null;
          _nextActions = const [];
        }
      });
    }
  }

  Future<void> _openNextAction(Json item) async {
    final kind = textOf(item, 'kind', '').toUpperCase();
    final id = item['id'];
    final targetType = kind.contains('TASK')
        ? 'TASK'
        : kind.contains('MEETING')
        ? 'MEETING'
        : kind.contains('REPORT')
        ? 'PROGRESS_REPORT'
        : kind.contains('MILESTONE')
        ? 'MILESTONE'
        : kind.contains('INVIT')
        ? 'TEAM_INVITATION'
        : null;
    if (targetType != null && id is int && id > 0) {
      await openEntity(
        context,
        widget.auth,
        EntityTarget(targetType, id),
        widget.onChanged ?? () {},
      );
      if (mounted) await _load(refresh: true);
    } else if (widget.onOpenProject != null) {
      widget.onOpenProject!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _isStudent ? _overview() : _unsupportedRole(),
      ),
    );
  }

  Widget _overview() {
    final dashboard = _data;
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.showHeading)
                      Semantics(
                        header: true,
                        child: Text(
                          'Tổng quan',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      'Xin chào, ${widget.auth.user?.fullName ?? ''}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    if (dashboard?.semesterName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Học kỳ · ${dashboard!.semesterName!}',
                        style: _caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Lịch tổng hợp',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CalendarScreen(
                      auth: widget.auth,
                      onChanged: widget.onChanged ?? () {},
                    ),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_outlined),
              ),
              IconButton(
                key: const Key('refresh-dashboard-button'),
                tooltip: 'Làm mới tổng quan',
                onPressed: _loading ? null : () => _load(refresh: true),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Đang cập nhật tổng quan',
                        ),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading && dashboard == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text('Đang tải tổng quan…', style: _body),
            ),
          if (_error != null) ...[_errorNotice(), const SizedBox(height: 18)],
          if (dashboard != null) ...[
            _project(dashboard),
            const SizedBox(height: 16),
            _metrics(dashboard),
            if (_nextActions.isNotEmpty) ...[
              const SizedBox(height: 22),
              SectionHeader(
                'Việc cần xử lý ngay',
                trailing: StatusBadge(
                  '${_nextActions.length} mục',
                  tone: StatusTone.primary,
                ),
              ),
              const SizedBox(height: 10),
              for (final item in _nextActions.take(5))
                RecordTile(
                  title: textOf(item, 'title'),
                  icon: Icons.bolt_outlined,
                  urgent: const {
                    'HIGH',
                    'CRITICAL',
                    'URGENT',
                  }.contains(textOf(item, 'severity', '').toUpperCase()),
                  badge: statusText(item['status']),
                  badgeTone: StatusBadge.toneForStatus(
                    item['status'] as String?,
                  ),
                  subtitle: item['dueAt'] != null
                      ? 'Hạn · ${displayDate(item['dueAt'])}'
                      : textOf(item, 'kind', 'Hành động tiếp theo'),
                  onTap: () => _openNextAction(item),
                ),
            ],
            const SizedBox(height: 22),
            SectionHeader(
              'Hạn cần theo dõi',
              trailing: StatusBadge('${dashboard.deadlines.length} mục'),
            ),
            const SizedBox(height: 10),
            _deadlines(dashboard),
            const SizedBox(height: 24),
            Text(
              'Cập nhật ${formatVietnamTime(dashboard.asOfUtc)} · Giờ Việt Nam',
              style: _caption,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _unsupportedRole() => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      NavyHeroCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI-PMS MOBILE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.amber,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Tài khoản đã được kết nối',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.onNavy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Các nghiệp vụ quản trị học vụ chuyên sâu được tối ưu trên AI-PMS web. '
              'Bạn có thể xem thông tin tài khoản tại ứng dụng này.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.onNavyMuted,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _errorNotice() => Semantics(
    liveRegion: true,
    child: Surface(
      borderColor: AppColors.dangerBorder,
      color: AppColors.dangerSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _data == null
                ? 'Chưa tải được tổng quan'
                : 'Chưa cập nhật được dữ liệu',
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: _body),
          if (_data != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Bạn đang xem dữ liệu từ lần tải thành công gần nhất.',
              style: _caption,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        ],
      ),
    ),
  );

  Widget _metrics(StudentDashboard dashboard) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 21;
      final stacked = largeText || constraints.maxWidth < 300;
      final metrics = [
        _Metric(
          value: dashboard.assignedOpenTasks,
          label: 'Việc đang mở',
          icon: Icons.check_box_outlined,
          accent: AppColors.info,
          horizontal: stacked,
        ),
        _Metric(
          value: dashboard.assignedOverdueTasks,
          label: 'Việc quá hạn',
          icon: Icons.schedule_outlined,
          accent: dashboard.assignedOverdueTasks > 0
              ? AppColors.danger
              : AppColors.success,
          danger: dashboard.assignedOverdueTasks > 0,
          horizontal: stacked,
        ),
        _Metric(
          value: dashboard.unreadNotifications,
          label: 'Thông báo chưa đọc',
          icon: Icons.notifications_outlined,
          accent: AppColors.primary,
          horizontal: stacked,
        ),
      ];
      return Surface(
        padding: EdgeInsets.zero,
        child: stacked
            ? Column(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: AppColors.border),
                    metrics[i],
                  ],
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0)
                        const VerticalDivider(
                          width: 1,
                          color: AppColors.border,
                        ),
                      Expanded(child: metrics[i]),
                    ],
                  ],
                ),
              ),
      );
    },
  );

  Widget _project(StudentDashboard dashboard) {
    final project = dashboard.project;
    if (project == null) {
      return Surface(
        accentColor: AppColors.attentionBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.folder_open_outlined,
              size: 30,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              dashboard.teamName == null
                  ? 'Chưa có đồ án để theo dõi'
                  : 'Nhóm chưa có đồ án',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              dashboard.teamName == null
                  ? 'Hoàn tất tham gia nhóm và đăng ký đồ án trên web AI-PMS. Thông tin sẽ xuất hiện tại đây sau khi được cập nhật.'
                  : 'Bạn đang tham gia ${dashboard.teamName}. Hoàn tất đăng ký đồ án trên web để theo dõi tiến độ tại đây.',
              style: _body,
            ),
          ],
        ),
      );
    }
    return NavyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'ĐỒ ÁN CỦA BẠN · ${project.code}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.amber,
                ),
              ),
              StatusBadge(
                dashboardStatusLabel(project.status),
                tone: StatusBadge.toneForStatus(project.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              project.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: AppColors.onNavy,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Tiến độ công việc',
                  style: TextStyle(fontSize: 13, color: AppColors.onNavyMuted),
                ),
              ),
              Text(
                project.progressPercentage == null
                    ? '—'
                    : '${project.progressPercentage!.round()}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (project.progressPercentage != null)
            LinearProgressIndicator(
              value: (project.progressPercentage! / 100).clamp(0.0, 1.0),
              minHeight: 7,
              color: AppColors.teal,
              backgroundColor: AppColors.navyRaised,
              borderRadius: BorderRadius.circular(4),
              semanticsLabel: 'Tiến độ công việc của đồ án',
              semanticsValue: '${project.progressPercentage!.round()}%',
            )
          else
            const Text(
              'Chưa đủ dữ liệu để hiển thị tiến độ.',
              style: TextStyle(fontSize: 13, color: AppColors.onNavyMuted),
            ),
          if (widget.onOpenProject != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.onNavy,
                  backgroundColor: AppColors.navyRaised,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: widget.onOpenProject,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Xem chi tiết đồ án'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deadlines(StudentDashboard dashboard) {
    if (dashboard.deadlines.isEmpty) {
      return const Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              color: AppColors.textMuted,
              size: 28,
            ),
            SizedBox(height: 12),
            Text(
              'Chưa có hạn công việc hoặc mốc tiến độ cần theo dõi.',
              style: _body,
            ),
          ],
        ),
      );
    }
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < dashboard.deadlines.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: AppColors.border),
            InkWell(
              onTap: widget.onOpenDeadline == null
                  ? null
                  : () => widget.onOpenDeadline!(dashboard.deadlines[index]),
              child: _DeadlineRow(deadline: dashboard.deadlines[index]),
            ),
          ],
        ],
      ),
    );
  }
}

const _body = TextStyle(fontSize: 15, height: 1.5, color: AppColors.textMuted);
const _caption = TextStyle(
  fontSize: 13,
  height: 1.45,
  color: AppColors.textMuted,
);

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.icon,
    required this.accent,
    this.danger = false,
    this.horizontal = false,
  });
  final int value;
  final String label;
  final IconData icon;
  final Color accent;
  final bool danger;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    final valueText = Text(
      '$value',
      style: TextStyle(
        fontSize: 23,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(13),
      child: horizontal
          ? Row(
              children: [
                Icon(icon, size: 20, color: accent),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: _caption)),
                const SizedBox(width: 12),
                valueText,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: valueText),
                    const SizedBox(width: 4),
                    Icon(icon, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(label, style: _caption),
              ],
            ),
    );
  }
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.deadline});
  final DashboardDeadline deadline;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: deadline.isOverdue
                  ? AppColors.dangerSoft
                  : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              deadline.isMilestone
                  ? Icons.flag_outlined
                  : Icons.check_box_outlined,
              size: 20,
              color: deadline.isOverdue ? AppColors.danger : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    deadline.isMilestone ? 'Mốc tiến độ' : 'Công việc',
                    style: _caption,
                  ),
                  StatusBadge(
                    dashboardStatusLabel(deadline.status),
                    tone: StatusBadge.toneForStatus(deadline.status),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                deadline.title,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${deadline.isOverdue ? 'Quá hạn' : 'Hạn'} · ${deadline.formattedDue}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: deadline.isOverdue
                      ? AppColors.danger
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
