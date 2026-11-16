import 'package:material_ui/material_ui.dart';

import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../ai/ai_screen.dart';
import '../dashboard/dashboard_model.dart';
import 'activity_screen.dart';
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
  });
  final AuthController auth;
  final VoidCallback onChanged;
  final int revision;
  final int? id;

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
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textOf(project, 'code')),
                const SizedBox(height: 8),
                Text(
                  textOf(project, 'title'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(statusText(project['status'])),
                if (current?.supervisorName != null) ...[
                  const SizedBox(height: 12),
                  Text('GVHD: ${current!.supervisorName}'),
                ],
                const SizedBox(height: 16),
                if (current?.progressPercentage != null) ...[
                  Text(
                    'Tiến độ công việc · ${current!.progressPercentage!.round()}%',
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: current.progressPercentage! / 100,
                    semanticsLabel: 'Tiến độ đồ án',
                    semanticsValue: '${current.progressPercentage!.round()}%',
                  ),
                ] else
                  const Text('Chưa đủ dữ liệu tiến độ.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          RecordTile(
            title: 'Trợ lý AI & kết quả',
            subtitle: 'Tiến độ, gợi ý, lịch sử và kết quả công bố',
            icon: Icons.auto_awesome_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    AiHomeScreen(auth: auth, projectId: idOf(project)),
              ),
            ),
          ),
          RecordTile(
            title: 'Lịch họp',
            subtitle: 'Lịch, liên kết tham gia và phản hồi',
            icon: Icons.event_outlined,
            onTap: () => open(
              ActivityScreen(
                auth: auth,
                projectId: idOf(project),
                meetings: true,
                onChanged: onChanged,
              ),
              'Lịch họp',
            ),
          ),
          RecordTile(
            title: 'Báo cáo & phản hồi',
            subtitle: 'Đọc báo cáo tiến độ và góp ý từ giảng viên',
            icon: Icons.fact_check_outlined,
            onTap: () => open(
              ActivityScreen(
                auth: auth,
                projectId: idOf(project),
                meetings: false,
                onChanged: onChanged,
              ),
              'Báo cáo & phản hồi',
            ),
          ),
          Surface(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: const PageStorageKey('project-description'),
              title: const Text('Nội dung đồ án'),
              childrenPadding: const EdgeInsets.all(20),
              children: [
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
          Text('Mốc tiến độ', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (data.milestones.isEmpty)
            const Surface(child: Text('Đồ án chưa có mốc tiến độ.')),
          for (final milestone in data.milestones)
            RecordTile(
              title: textOf(milestone, 'title'),
              icon: Icons.flag_outlined,
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
        Text('Nhóm thực hiện', style: Theme.of(context).textTheme.titleLarge),
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
