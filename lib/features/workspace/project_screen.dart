import 'package:material_ui/material_ui.dart';

import '../../ui/app_theme.dart';
import '../../ui/remote_page.dart';
import '../../ui/mobile_components.dart';
import '../auth/auth_controller.dart';
import '../ai/ai_screen.dart';
import '../dashboard/dashboard_model.dart';
import 'activity_screen.dart';
import 'project_quick_actions_screen.dart';
import 'tasks_screen.dart';
import 'workspace_models.dart';

typedef _ProjectData = ({
  StudentDashboard overview,
  Json? project,
  Json? team,
  List<Json> milestones,
  List<Json> progress,
});

class ProjectScreen extends StatelessWidget {
  const ProjectScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    this.revision = 0,
    this.id,
    this.showHeading = true,
  });
  final AuthController auth;
  final VoidCallback onChanged;
  final int revision;
  final int? id;
  final bool showHeading;

  Future<_ProjectData> _load() async {
    final overview = StudentDashboard.fromJson(
      await auth.getJson('/api/v1/dashboards/student'),
    );
    final projectId = id ?? overview.project?.id;
    final project = projectId == null
        ? null
        : await auth.getJson('/api/v1/projects/$projectId');
    if (project != null) idOf(project);
    final teamId = project == null ? overview.teamId : idOf(project, 'teamId');
    final data = await Future.wait([
      teamId == null
          ? Future<Object?>.value(null)
          : auth.request('/api/v1/teams/$teamId'),
      projectId == null
          ? Future<Object?>.value(<dynamic>[])
          : auth.request('/api/v1/milestones/project/$projectId'),
      projectId == null
          ? Future<Object?>.value(<dynamic>[])
          : auth.request('/api/v1/milestones/project/$projectId/progress'),
    ]);
    final milestones = recordsOf(data[1]);
    if (data[0] != null) {
      recordsOf(objectOf(data[0])['members']);
    }
    for (final milestone in milestones) {
      idOf(milestone);
    }
    milestones.sort(
      (a, b) => ((a['sortOrder'] as num?) ?? 0).compareTo(
        (b['sortOrder'] as num?) ?? 0,
      ),
    );
    return (
      overview: overview,
      project: project,
      team: data[0] == null ? null : objectOf(data[0]),
      milestones: milestones,
      progress: recordsOf(data[2]),
    );
  }

  @override
  Widget build(BuildContext context) => RemotePage<_ProjectData>(
    title: 'Đồ án',
    showHeading: showHeading,
    revision: revision,
    load: _load,
    content: (context, data, refresh) {
      final project = data.project;
      final team = data.team;
      final current =
          project != null && data.overview.project?.id == idOf(project)
          ? data.overview.project
          : null;
      void open(Widget screen, String title) async {
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
        if (project == null) ...[
          const Surface(
            child: Text(
              'Chưa có đồ án. Hoàn tất đăng ký trên web; dữ liệu sẽ được cập nhật tại đây.',
            ),
          ),
          const SizedBox(height: 20),
        ] else ...[
          NavyHeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      textOf(project, 'code'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amber,
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
                const SizedBox(height: 10),
                Text(
                  textOf(project, 'title'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onNavy,
                  ),
                ),
                if (current?.supervisorName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'GVHD: ${current!.supervisorName}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.onNavyMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (current?.progressPercentage != null) ...[
                  Text(
                    'Tiến độ công việc · ${current!.progressPercentage!.round()}%',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (current.progressPercentage! / 100).clamp(0.0, 1.0),
                    minHeight: 7,
                    color: AppColors.teal,
                    backgroundColor: AppColors.navyRaised,
                    borderRadius: BorderRadius.circular(4),
                    semanticsLabel: 'Tiến độ đồ án',
                    semanticsValue: '${current.progressPercentage!.round()}%',
                  ),
                ] else
                  const Text(
                    'Chưa đủ dữ liệu tiến độ.',
                    style: TextStyle(color: AppColors.onNavyMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          HorizontalChoices(
            children: [
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Trợ lý AI'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AiHomeScreen(auth: auth, projectId: idOf(project)),
                  ),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: const Text('Lịch họp'),
                onPressed: () => open(
                  ActivityScreen(
                    auth: auth,
                    projectId: idOf(project),
                    meetings: true,
                    onChanged: onChanged,
                  ),
                  'Lịch họp',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Báo cáo & phản hồi'),
                onPressed: () => open(
                  ActivityScreen(
                    auth: auth,
                    projectId: idOf(project),
                    meetings: false,
                    onChanged: onChanged,
                  ),
                  'Báo cáo & phản hồi',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.handshake_outlined, size: 18),
                label: const Text('Quy ước nhóm'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => WorkingAgreementScreen(
                        auth: auth,
                        projectId: idOf(project),
                        onChanged: onChanged,
                      ),
                    ),
                  );
                  await refresh();
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.groups_outlined, size: 18),
                label: const Text('Đánh giá chéo'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PeerEvaluationScreen(
                        auth: auth,
                        projectId: idOf(project),
                        onChanged: onChanged,
                      ),
                    ),
                  );
                  await refresh();
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.checklist_outlined, size: 18),
                label: const Text('Action Items'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ActionItemsScreen(
                        auth: auth,
                        projectId: idOf(project),
                        onChanged: onChanged,
                      ),
                    ),
                  );
                  await refresh();
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.monitor_heart_outlined, size: 18),
                label: const Text('Hồ sơ & sức khỏe'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProjectTrackingScreen(
                      auth: auth,
                      projectId: idOf(project),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Surface(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: const PageStorageKey('project-description'),
              title: const Text('Nội dung đồ án'),
              childrenPadding: const EdgeInsets.all(20),
              children: [
                ContentSection('Tên đồ án', textOf(project, 'title')),
                for (final entry in const {
                  'description': 'Mô tả',
                  'objectives': 'Mục tiêu',
                  'problemStatement': 'Vấn đề cần giải quyết',
                  'expectedOutput': 'Kết quả dự kiến',
                }.entries)
                  ContentSection(entry.value, textOf(project, entry.key, '')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionHeader(
            'Mốc tiến độ',
            trailing: StatusBadge('${data.milestones.length} mốc'),
          ),
          const SizedBox(height: 12),
          if (data.milestones.isEmpty)
            const Surface(child: Text('Đồ án chưa có mốc tiến độ.')),
          for (final milestone in data.milestones)
            RecordTile(
              title: textOf(milestone, 'title'),
              icon: Icons.flag_outlined,
              badge: statusText(milestone['status']),
              badgeTone: StatusBadge.toneForStatus(
                milestone['status'] as String?,
              ),
              subtitle:
                  '${statusText(milestone['status'])}\nHạn: ${displayDate(milestone['dueDate'])}${_progressText(data.progress, idOf(milestone))}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MilestoneScreen(
                    auth: auth,
                    id: idOf(milestone),
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        const SectionHeader('Nhóm thực hiện'),
        const SizedBox(height: 12),
        if (team == null)
          const Surface(
            child: Text(
              'Bạn chưa có nhóm trong học kỳ hiện tại. Xem lời mời trong Hộp thư.',
            ),
          )
        else ...[
          ContentSection(
            textOf(team, 'name'),
            '${textOf(team, 'code')} · ${statusText(team['status'])}',
          ),
          for (final member in recordsOf(team['members']))
            RecordTile(
              title: textOf(member, 'fullName'),
              badge: member['isLeader'] == true ? 'Trưởng nhóm' : 'Thành viên',
              badgeTone: member['isLeader'] == true
                  ? StatusTone.primary
                  : StatusTone.neutral,
              subtitle: member['isLeader'] == true
                  ? 'Trưởng nhóm'
                  : 'Thành viên',
              icon: Icons.person_outline,
            ),
        ],
      ];
    },
  );
}

String _progressText(List<Json> progress, int milestoneId) {
  for (final row in progress) {
    if (row['milestoneId'] == milestoneId && row['progressPercentage'] is num) {
      return '\nTiến độ ${(row['progressPercentage'] as num).round()}% · ${row['doneTasks']}/${row['totalTasks']} việc';
    }
  }
  return '';
}

class TeamDetailScreen extends StatelessWidget {
  const TeamDetailScreen({super.key, required this.auth, required this.id});
  final AuthController auth;
  final int id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi tiết nhóm')),
    body: RemotePage<Json>(
      title: 'Nhóm thực hiện',
      showHeading: false,
      load: () async {
        final team = await auth.getJson('/api/v1/teams/$id');
        recordsOf(team['members']);
        return team;
      },
      content: (context, team, refresh) => [
        ContentSection(
          textOf(team, 'name'),
          '${textOf(team, 'code')} · ${statusText(team['status'])}',
        ),
        ContentSection('Giới thiệu', textOf(team, 'description', '')),
        for (final member in recordsOf(team['members']))
          RecordTile(
            title: textOf(member, 'fullName'),
            subtitle: member['isLeader'] == true ? 'Trưởng nhóm' : 'Thành viên',
            icon: Icons.person_outline,
          ),
      ],
    ),
  );
}

class MilestoneScreen extends StatelessWidget {
  const MilestoneScreen({
    super.key,
    required this.auth,
    required this.id,
    required this.onChanged,
  });
  final AuthController auth;
  final int id;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mốc tiến độ')),
    body: RemotePage<Json>(
      title: 'Mốc tiến độ',
      showHeading: false,
      load: () => auth.getJson('/api/v1/milestones/$id'),
      content: (context, milestone, refresh) => [
        ContentSection(
          textOf(milestone, 'title'),
          statusText(milestone['status']),
        ),
        ContentSection('Mô tả', textOf(milestone, 'description', '')),
        ContentSection(
          'Thời gian',
          'Bắt đầu: ${displayDate(milestone['startDate'])}\nHạn: ${displayDate(milestone['dueDate'])}',
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_box_outlined),
          label: const Text('Xem công việc trong mốc'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Công việc trong mốc')),
                body: TasksScreen(
                  auth: auth,
                  showHeading: false,
                  milestoneId: id,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
