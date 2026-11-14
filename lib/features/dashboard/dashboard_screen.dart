import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../auth/auth_controller.dart';
import 'dashboard_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StudentDashboard? _data;
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
      final json = await widget.auth.getJson('/api/v1/dashboards/student');
      final dashboard = StudentDashboard.fromJson(json);
      if (!mounted ||
          version != _loadVersion ||
          accountId != widget.auth.user?.id) {
        return;
      }
      setState(() {
        _data = dashboard;
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
      });
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Tổng quan',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Xin chào, ${widget.auth.user?.fullName ?? ''}',
                      style: _body,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
          const SizedBox(height: 20),
          if (_loading && dashboard == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text('Đang tải tổng quan…', style: _body),
            ),
          if (_error != null) ...[_errorNotice(), const SizedBox(height: 20)],
          if (dashboard != null) ...[
            if (dashboard.semesterName != null) ...[
              Text('Học kỳ · ${dashboard.semesterName!}', style: _caption),
              const SizedBox(height: 12),
            ],
            _metrics(dashboard),
            const SizedBox(height: 16),
            _project(dashboard),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: _SectionTitle('Hạn cần theo dõi')),
                const SizedBox(width: 8),
                Text('${dashboard.deadlines.length} mục', style: _caption),
              ],
            ),
            const SizedBox(height: 12),
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
    padding: const EdgeInsets.all(24),
    children: const [
      _Eyebrow('AI-PMS MOBILE'),
      SizedBox(height: 16),
      _SectionTitle('Không gian sinh viên'),
      SizedBox(height: 24),
      _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.school_outlined, color: AppColors.primary, size: 32),
            SizedBox(height: 16),
            _SectionTitle('Tài khoản đã được kết nối'),
            SizedBox(height: 8),
            Text(
              'Tổng quan trên ứng dụng hiện dành cho sinh viên. Với vai trò hiện tại, '
              'bạn có thể xem tài khoản tại đây và sử dụng các nghiệp vụ của mình trên web AI-PMS.',
              style: _body,
            ),
          ],
        ),
      ),
    ],
  );

  Widget _errorNotice() => Semantics(
    liveRegion: true,
    child: _Surface(
      borderColor: AppColors.danger,
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
          horizontal: stacked,
        ),
        _Metric(
          value: dashboard.assignedOverdueTasks,
          label: 'Việc quá hạn',
          icon: Icons.schedule_outlined,
          danger: dashboard.assignedOverdueTasks > 0,
          horizontal: stacked,
        ),
        _Metric(
          value: dashboard.unreadNotifications,
          label: 'Thông báo chưa đọc',
          icon: Icons.notifications_outlined,
          horizontal: stacked,
        ),
      ];
      return _Surface(
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
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('Đồ án của bạn'),
          const SizedBox(height: 12),
          if (project != null) ...[
            Semantics(
              header: true,
              child: Text(
                project.title,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(project.code, style: _caption),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dashboardStatusLabel(project.status),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
            if (dashboard.teamName != null) ...[
              const SizedBox(height: 16),
              _InfoLine(icon: Icons.people_outline, text: dashboard.teamName!),
            ],
            if (project.supervisorName != null) ...[
              const SizedBox(height: 8),
              _InfoLine(
                icon: Icons.person_outline,
                text: 'GVHD: ${project.supervisorName}',
              ),
            ],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text('Tiến độ công việc', style: _caption),
                ),
                const SizedBox(width: 12),
                Text(
                  project.progressPercentage == null
                      ? '—'
                      : '${project.progressPercentage!.round()}%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (project.progressPercentage != null)
              LinearProgressIndicator(
                value: project.progressPercentage! / 100,
                minHeight: 7,
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(4),
                semanticsLabel: 'Tiến độ công việc của đồ án',
                semanticsValue: '${project.progressPercentage!.round()}%',
              )
            else
              const Text(
                'Chưa đủ dữ liệu để hiển thị tiến độ.',
                style: _caption,
              ),
          ] else ...[
            const Icon(
              Icons.folder_open_outlined,
              size: 32,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              dashboard.teamName == null
                  ? 'Chưa có đồ án để theo dõi'
                  : 'Nhóm chưa có đồ án',
            ),
            const SizedBox(height: 8),
            Text(
              dashboard.teamName == null
                  ? 'Hoàn tất tham gia nhóm và đăng ký đồ án trên web AI-PMS. Thông tin sẽ xuất hiện tại đây sau khi được cập nhật.'
                  : 'Bạn đang tham gia ${dashboard.teamName}. Hoàn tất đăng ký đồ án trên web để theo dõi tiến độ tại đây.',
              style: _body,
            ),
          ],
        ],
      ),
    );
  }

  Widget _deadlines(StudentDashboard dashboard) {
    if (dashboard.deadlines.isEmpty) {
      return const _Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              color: AppColors.textMuted,
              size: 28,
            ),
            SizedBox(height: 16),
            Text(
              'Chưa có hạn công việc hoặc mốc tiến độ cần theo dõi.',
              style: _body,
            ),
          ],
        ),
      );
    }
    return _Surface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < dashboard.deadlines.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: AppColors.border),
            _DeadlineRow(deadline: dashboard.deadlines[index]),
          ],
        ],
      ),
    );
  }
}

const _body = TextStyle(fontSize: 16, height: 1.55, color: AppColors.textMuted);
const _caption = TextStyle(
  fontSize: 13,
  height: 1.5,
  color: AppColors.textMuted,
);

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      height: 1.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 19,
        height: 1.45,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.borderColor = AppColors.border,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: borderColor),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.icon,
    this.danger = false,
    this.horizontal = false,
  });
  final int value;
  final String label;
  final IconData icon;
  final bool danger;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.text;
    final valueText = Text(
      '$value',
      style: TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: horizontal
          ? Row(
              children: [
                Icon(icon, size: 20, color: color),
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
                    Icon(icon, size: 18, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                Text(label, style: _caption),
              ],
            ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.textMuted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: _caption)),
    ],
  );
}

class _DeadlineRow extends StatelessWidget {
  const _DeadlineRow({required this.deadline});
  final DashboardDeadline deadline;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: deadline.isOverdue
                  ? AppColors.dangerSoft
                  : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              deadline.isMilestone
                  ? Icons.flag_outlined
                  : Icons.check_box_outlined,
              size: 21,
              color: deadline.isOverdue ? AppColors.danger : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deadline.isMilestone ? 'Mốc tiến độ' : 'Công việc',
                style: _caption,
              ),
              const SizedBox(height: 4),
              Text(
                deadline.title,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(dashboardStatusLabel(deadline.status), style: _caption),
              const SizedBox(height: 4),
              Text(
                '${deadline.isOverdue ? 'Quá hạn' : 'Hạn'} · ${deadline.formattedDue}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
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
