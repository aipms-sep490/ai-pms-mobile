import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/app_theme.dart';
import '../../ui/paged_records.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../ai/ai_screen.dart';
import '../meetings/video_meeting_screen.dart';
import 'workspace_models.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({
    super.key,
    required this.auth,
    required this.projectId,
    required this.meetings,
    required this.onChanged,
  });
  final AuthController auth;
  final int projectId;
  final bool meetings;
  final VoidCallback onChanged;
  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _status = '';
  @override
  Widget build(BuildContext context) => PagedRecords(
    auth: widget.auth,
    path:
        '/api/v1/projects/${widget.projectId}/${widget.meetings ? 'meetings' : 'progress-reports'}${_status.isEmpty ? '' : '?status=$_status'}',
    title: widget.meetings ? 'Lịch họp' : 'Báo cáo & phản hồi',
    emptyText: widget.meetings ? 'Không có lịch họp phù hợp.' : 'Chưa có báo cáo phù hợp. Việc soạn và nộp báo cáo được thực hiện trên web.',
    leading: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry
              in (widget.meetings
                      ? const {
                          '': 'Tất cả',
                          'SCHEDULED': 'Đã lên lịch',
                          'COMPLETED': 'Đã kết thúc',
                          'CANCELLED': 'Đã hủy',
                        }
                      : const {
                          '': 'Tất cả',
                          'DRAFT': 'Bản nháp',
                          'SUBMITTED': 'Đã nộp',
                          'REVIEWED': 'Đã phản hồi',
                        })
                  .entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _status == entry.key,
              onSelected: (_) => setState(() => _status = entry.key),
            ),
        ],
      ),
      const SizedBox(height: 16),
    ],
    item: (context, row, refresh) => RecordTile(
      title: widget.meetings
          ? textOf(row, 'title')
          : '${statusText(row['reportType'])} · ${displayDate(row['periodStart'])}',
      subtitle: widget.meetings
          ? '${displayDate(row['startAt'])}\n${statusText(row['status'])}'
          : '${statusText(row['status'])} · ${textOf(row, 'submittedByName')}\nĐến ${displayDate(row['periodEnd'])}',
      icon: widget.meetings ? Icons.event_outlined : Icons.fact_check_outlined,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => widget.meetings
                ? MeetingDetailScreen(
                    auth: widget.auth,
                    id: idOf(row),
                    onChanged: widget.onChanged,
                  )
                : ReportDetailScreen(auth: widget.auth, id: idOf(row)),
          ),
        );
        if (mounted) await refresh();
      },
    ),
  );
}

class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({
    super.key,
    required this.auth,
    required this.id,
    required this.onChanged,
  });
  final AuthController auth;
  final int id;
  final VoidCallback onChanged;
  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  int _revision = 0;
  bool _saving = false;
  String? _message;
  bool _failed = false;

  Future<(Json, Json, Json)> _load() async {
    final meeting = await widget.auth.getJson('/api/v1/meetings/${widget.id}');
    final data = await Future.wait([
      widget.auth.getJson('/api/v1/meetings/${widget.id}/collaboration'),
      widget.auth.getJson('/api/v1/projects/${idOf(meeting, 'projectId')}'),
    ]);
    recordsOf(meeting['participants']);
    recordsOf(meeting['feedbacks']);
    if (data[0]['myRsvp'] != null) {
      objectOf(data[0]['myRsvp']);
    }
    return (meeting, data[0], data[1]);
  }

  Future<void> _respond(Json mine, String status) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/meetings/${widget.id}/rsvp',
        method: 'PUT',
        body: {
          'status': status,
          'concurrencyToken': textOf(mine, 'concurrencyToken', ''),
        },
      );
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'Đã cập nhật phản hồi tham gia.';
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
        title: const Text('Chi tiết lịch họp'),
        automaticallyImplyLeading: !_saving,
      ),
      body: RemotePage<(Json, Json, Json)>(
        title: 'Lịch họp',
        revision: _revision,
        load: _load,
        content: (context, data, refresh) {
          final (meeting, collaboration, project) = data;
          final mine = collaboration['myRsvp'] == null
              ? null
              : objectOf(collaboration['myRsvp']);
          final canRespond =
              mine != null &&
              mine['userId'] == widget.auth.user?.id &&
              textOf(mine, 'concurrencyToken', '').isNotEmpty &&
              project['status'] == 'ACTIVE' &&
              meeting['status'] == 'SCHEDULED';
          return [
            if (_message != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _failed ? AppColors.danger : AppColors.success,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            ContentSection(
              textOf(meeting, 'title'),
              statusText(meeting['status']),
            ),
            ContentSection(
              'Thời gian',
              '${displayDate(meeting['startAt'])}\nĐến ${displayDate(meeting['endAt'])}\nGiờ theo thiết bị.',
            ),
            ContentSection('Địa điểm', textOf(meeting, 'location', '')),
            if (meeting['status'] == 'SCHEDULED' &&
                externalUri(meeting['onlineUrl']) != null) ...[
              ExternalLinkButton(uri: externalUri(meeting['onlineUrl'])!),
              const SizedBox(height: 20),
            ] else if (meeting['videoChannel'] == 'IN_APP_VIDEO')
              RecordTile(
                title: 'Phòng họp video',
                subtitle: 'Tham gia bằng mic và camera trong app',
                icon: Icons.video_call_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VideoMeetingScreen(
                      auth: widget.auth,
                      meetingId: widget.id,
                    ),
                  ),
                ),
              ),
            RecordTile(
              title: 'Chuẩn bị họp với AI',
              subtitle: 'Nội dung cần trao đổi theo dữ liệu đồ án',
              icon: Icons.auto_awesome_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AiDocumentScreen(
                    auth: widget.auth,
                    title: 'Chuẩn bị họp',
                    load: () => widget.auth.request(
                      '/api/v1/projects/${idOf(meeting, 'projectId')}/ai/workflow-assistance?mode=MEETING_BRIEF&meetingId=${widget.id}',
                      requestTimeout: const Duration(seconds: 90),
                    ),
                  ),
                ),
              ),
            ),
            if (mine != null)
              ContentSection('Phản hồi của bạn', statusText(mine['status'])),
            if (canRespond) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in const {
                    'ACCEPTED': 'Tham gia',
                    'TENTATIVE': 'Chưa chắc',
                    'DECLINED': 'Từ chối',
                  }.entries)
                    OutlinedButton(
                      onPressed: _saving || mine['status'] == entry.key
                          ? null
                          : () => _respond(mine, entry.key),
                      child: Text(entry.value),
                    ),
                ],
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Đang cập nhật phản hồi…'),
                ),
              const SizedBox(height: 20),
            ],
            for (final entry in const {
              'agenda': 'Nội dung họp',
              'meetingNotes': 'Ghi chú',
              'minutes': 'Biên bản',
              'decisions': 'Quyết định',
              'blockers': 'Vướng mắc',
            }.entries)
              if (textOf(meeting, entry.key, '').isNotEmpty)
                ContentSection(entry.value, meeting[entry.key] as String),
            const ContentSection('Người tham gia', null),
            for (final person in recordsOf(meeting['participants']))
              RecordTile(
                title: textOf(person, 'fullName'),
                subtitle: statusText(person['rsvpStatus']),
                icon: Icons.person_outline,
              ),
            ...feedbackSections(recordsOf(meeting['feedbacks'])),
          ];
        },
      ),
    ),
  );
}

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.auth, required this.id});
  final AuthController auth;
  final int id;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Báo cáo tiến độ')),
    body: RemotePage<Json>(
      title: 'Báo cáo & phản hồi',
      load: () async {
        final report = await auth.getJson('/api/v1/progress-reports/$id');
        recordsOf(report['feedbacks']);
        return report;
      },
      content: (context, report, refresh) => [
        RecordTile(
          title: 'Tóm tắt báo cáo bằng AI',
          subtitle: 'Điểm chính, rủi ro và việc tiếp theo',
          icon: Icons.auto_awesome_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AiDocumentScreen(
                auth: auth,
                title: 'Tóm tắt báo cáo',
                load: () => auth.request(
                  '/api/v1/projects/${idOf(report, 'projectId')}/reports/$id/summary',
                  requestTimeout: const Duration(seconds: 90),
                ),
              ),
            ),
          ),
        ),
        ContentSection(
          '${statusText(report['reportType'])} · ${statusText(report['status'])}',
          '${displayDate(report['periodStart'])} – ${displayDate(report['periodEnd'])}\nNgười báo cáo: ${textOf(report, 'submittedByName')}',
        ),
        for (final entry in const {
          'summary': 'Tóm tắt',
          'completedWork': 'Đã hoàn thành',
          'inProgressWork': 'Đang thực hiện',
          'plannedWork': 'Kế hoạch',
          'issuesAndRisks': 'Vấn đề và rủi ro',
          'blockers': 'Vướng mắc',
          'risks': 'Rủi ro',
          'nextActions': 'Bước tiếp theo',
        }.entries)
          if (textOf(report, entry.key, '').isNotEmpty)
            ContentSection(entry.value, report[entry.key] as String),
        ...feedbackSections(recordsOf(report['feedbacks'])),
      ],
    ),
  );
}

List<Widget> feedbackSections(List<Json> feedbacks) => [
  const ContentSection('Phản hồi giảng viên', null),
  if (feedbacks.isEmpty) const Text('Chưa có phản hồi.'),
  for (final feedback in feedbacks)
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              textOf(feedback, 'supervisorName'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(displayDate(feedback['createdAt'])),
            const SizedBox(height: 12),
            SelectableBody(textOf(feedback, 'feedbackText')),
          ],
        ),
      ),
    ),
];

class ExternalLinkButton extends StatelessWidget {
  const ExternalLinkButton({super.key, required this.uri});
  final Uri uri;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SelectableBody(uri.toString()),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: Text('Mở liên kết · ${uri.host}'),
        onPressed: () async {
          try {
            if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              return;
            }
          } catch (_) {
            /* The selectable URL remains available as a fallback. */
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Chưa thể mở liên kết. Bạn có thể sao chép địa chỉ ở trên.',
                ),
              ),
            );
          }
        },
      ),
    ],
  );
}
