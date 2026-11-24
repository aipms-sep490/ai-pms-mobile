import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/app_theme.dart';
import '../../ui/paged_records.dart';
import '../../ui/remote_page.dart';
import '../../ui/mobile_components.dart';
import '../auth/auth_controller.dart';
import '../ai/ai_screen.dart';
import '../meetings/video_meeting_screen.dart';
import 'project_quick_actions_screen.dart';
import 'report_editor_screen.dart';
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
  int _revision = 0;

  Future<void> _createReport() async {
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReportEditorScreen(auth: widget.auth, projectId: widget.projectId),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      widget.onChanged();
      setState(() => _revision++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreateReport =
        !widget.meetings && (widget.auth.user?.isStudent ?? false);
    return PagedRecords(
      auth: widget.auth,
      revision: _revision,
      path:
          '/api/v1/projects/${widget.projectId}/${widget.meetings ? 'meetings' : 'progress-reports'}${_status.isEmpty ? '' : '?status=$_status'}',
      title: widget.meetings ? 'Lịch họp' : 'Báo cáo & phản hồi',
      showHeading: false,
      emptyText: widget.meetings ? 'Không có lịch họp phù hợp.' : 'Chưa có báo cáo phù hợp. Bạn có thể tạo báo cáo tiến độ gọn ngay trên ứng dụng.',
      leading: [
        if (canCreateReport) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('create-progress-report-btn'),
              onPressed: _createReport,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Soạn báo cáo gọn'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        HorizontalChoices(
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
        badge: statusText(row['status']),
        badgeTone: StatusBadge.toneForStatus(row['status'] as String?),
        subtitle: widget.meetings
            ? '${displayDate(row['startAt'])}\n${statusText(row['status'])}'
            : '${statusText(row['status'])} · ${textOf(row, 'submittedByName')}\nĐến ${displayDate(row['periodEnd'])}',
        icon: widget.meetings
            ? Icons.event_outlined
            : Icons.fact_check_outlined,
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
                  : ReportDetailScreen(
                      auth: widget.auth,
                      id: idOf(row),
                      onChanged: widget.onChanged,
                    ),
            ),
          );
          if (mounted) await refresh();
        },
      ),
    );
  }
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
  final _feedbackCtrl = TextEditingController();
  int _revision = 0;
  bool _saving = false;
  String? _message;
  bool _failed = false;
  bool _choosingRsvp = false;

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _chooseRsvp(Json mine) async {
    if (_saving || _choosingRsvp) return;
    setState(() => _choosingRsvp = true);
    try {
      final selected = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        builder: (sheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Phản hồi tham gia',
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in const {
                    'ACCEPTED': 'Tham gia',
                    'TENTATIVE': 'Chưa chắc',
                    'DECLINED': 'Từ chối',
                  }.entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      trailing: mine['status'] == entry.key
                          ? const Icon(Icons.check_circle_outline)
                          : null,
                      onTap: mine['status'] == entry.key
                          ? null
                          : () => Navigator.pop(sheet, entry.key),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (mounted && selected != null) await _respond(mine, selected);
    } finally {
      if (mounted) setState(() => _choosingRsvp = false);
    }
  }

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

  Future<void> _submitMeetingFeedback() async {
    final text = _feedbackCtrl.text.trim();
    if (_saving || text.isEmpty) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/meetings/${widget.id}/feedback',
        method: 'POST',
        body: {'feedbackText': text},
      );
      _feedbackCtrl.clear();
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'Đã gửi nhận xét cuộc họp.';
          _revision++;
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
      if (mounted) setState(() => _saving = false);
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
        showHeading: false,
        revision: _revision,
        load: _load,
        content: (context, data, refresh) {
          final (meeting, collaboration, project) = data;
          final projectId = idOf(meeting, 'projectId');
          final mine = collaboration['myRsvp'] == null
              ? null
              : objectOf(collaboration['myRsvp']);
          final canRespond =
              mine != null &&
              mine['userId'] == widget.auth.user?.id &&
              textOf(mine, 'concurrencyToken', '').isNotEmpty &&
              project['status'] == 'ACTIVE' &&
              meeting['status'] == 'SCHEDULED';
          final isLecturer = widget.auth.user?.isLecturer ?? false;

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
            if (textOf(meeting, 'location', '').isNotEmpty)
              ContentSection('Địa điểm', textOf(meeting, 'location', '')),
            if (meeting['status'] == 'SCHEDULED' &&
                externalUri(meeting['onlineUrl']) != null) ...[
              ExternalLinkButton(uri: externalUri(meeting['onlineUrl'])!),
              const SizedBox(height: 20),
            ] else if (meeting['videoChannel'] == 'IN_APP_VIDEO')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  label: Text(
                    meeting['status'] == 'SCHEDULED'
                        ? 'Phòng họp video'
                        : 'Xem phòng họp',
                  ),
                  icon: const Icon(Icons.video_call_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => VideoMeetingScreen(
                        auth: widget.auth,
                        meetingId: widget.id,
                      ),
                    ),
                  ),
                ),
              ),
            HorizontalChoices(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Chuẩn bị họp với AI'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AiDocumentScreen(
                        auth: widget.auth,
                        title: 'Chuẩn bị họp',
                        load: () => widget.auth.request(
                          '/api/v1/projects/$projectId/ai/workflow-assistance?mode=MEETING_BRIEF&meetingId=${widget.id}',
                          requestTimeout: const Duration(seconds: 90),
                        ),
                      ),
                    ),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('Tóm tắt AI sau họp'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => _MeetingAiInsightsScreen(
                        auth: widget.auth,
                        meetingId: widget.id,
                      ),
                    ),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.checklist_outlined, size: 18),
                  label: const Text('Action Items'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ActionItemsScreen(
                        auth: widget.auth,
                        projectId: projectId,
                        meetingId: widget.id,
                        onChanged: widget.onChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (mine != null)
              ContentSection('Phản hồi của bạn', statusText(mine['status'])),
            if (canRespond) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _saving || _choosingRsvp
                      ? null
                      : () => _chooseRsvp(mine),
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Phản hồi tham gia'),
                ),
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
            if (isLecturer) ...[
              const SizedBox(height: 12),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Viết nhận xét giảng viên',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _feedbackCtrl,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        hintText: 'Nhập nhận xét ngắn cho buổi họp…',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _saving ? null : _submitMeetingFeedback,
                      child: Text(_saving ? 'Đang gửi…' : 'Gửi nhận xét'),
                    ),
                  ],
                ),
              ),
            ],
          ];
        },
      ),
    ),
  );
}

class _MeetingAiInsightsScreen extends StatelessWidget {
  const _MeetingAiInsightsScreen({required this.auth, required this.meetingId});
  final AuthController auth;
  final int meetingId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tóm tắt AI sau họp')),
    body: RemotePage<List<Json>>(
      title: 'Tóm tắt AI sau họp',
      showHeading: false,
      load: () async {
        final raw = await auth.request(
          '/api/v1/meetings/$meetingId/video/ai/insights?limit=5',
        );
        return recordsOf(raw);
      },
      content: (context, insights, refresh) {
        if (insights.isEmpty) {
          return const [
            Surface(
              child: Text(
                'Chưa có bản tóm tắt AI nào được tạo cho cuộc họp này.',
              ),
            ),
          ];
        }
        return [
          for (final item in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Surface(
                accentColor: AppColors.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        StatusBadge(
                          textOf(item, 'insightType', 'SUMMARY'),
                          tone: StatusTone.primary,
                        ),
                        Text(
                          displayDate(item['createdAt']),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (textOf(item, 'executiveSummary', '').isNotEmpty)
                      ContentSection(
                        'Tóm tắt điều hành',
                        item['executiveSummary'] as String,
                      ),
                    if (item['decisions'] is List &&
                        (item['decisions'] as List).isNotEmpty)
                      ContentSection(
                        'Quyết định chính',
                        (item['decisions'] as List)
                            .map((e) => '• $e')
                            .join('\n'),
                      ),
                    if (item['blockersAndRisks'] is List &&
                        (item['blockersAndRisks'] as List).isNotEmpty)
                      ContentSection(
                        'Rủi ro & vướng mắc',
                        (item['blockersAndRisks'] as List)
                            .map((e) => '• $e')
                            .join('\n'),
                      ),
                  ],
                ),
              ),
            ),
        ];
      },
    ),
  );
}

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.auth,
    required this.id,
    this.onChanged,
  });
  final AuthController auth;
  final int id;
  final VoidCallback? onChanged;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final _feedbackCtrl = TextEditingController();
  int _revision = 0;
  bool _saving = false;
  String? _notice;
  bool _failed = false;

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback(Json report) async {
    final text = _feedbackCtrl.text.trim();
    if (_saving || text.isEmpty) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final token = report['concurrencyToken'] as String?;
      final query = token == null || token.isEmpty
          ? ''
          : '?${Uri(queryParameters: {'concurrencyToken': token}).query}';
      await widget.auth.request(
        '/api/v1/progress-reports/${widget.id}/feedback$query',
        method: 'POST',
        body: {'feedbackText': text},
      );
      _feedbackCtrl.clear();
      widget.onChanged?.call();
      if (mounted) {
        setState(() {
          _failed = false;
          _notice = 'Đã gửi nhận xét cho báo cáo tiến độ.';
          _revision++;
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Báo cáo tiến độ')),
    body: RemotePage<Json>(
      title: 'Báo cáo & phản hồi',
      showHeading: false,
      revision: _revision,
      load: () async {
        final report = await widget.auth.getJson(
          '/api/v1/progress-reports/${widget.id}',
        );
        recordsOf(report['feedbacks']);
        return report;
      },
      content: (context, report, refresh) {
        final isDraft = report['status'] == 'DRAFT';
        final isStudent = widget.auth.user?.isStudent ?? false;
        final isLecturer = widget.auth.user?.isLecturer ?? false;
        return [
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
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isDraft && isStudent)
                FilledButton.icon(
                  onPressed: () async {
                    final saved = await Navigator.push<Json>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportEditorScreen(
                          auth: widget.auth,
                          projectId: idOf(report, 'projectId'),
                          existingReport: report,
                        ),
                      ),
                    );
                    if (saved != null && mounted) {
                      widget.onChanged?.call();
                      setState(() => _revision++);
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Sửa & nộp báo cáo'),
                ),
              TextButton.icon(
                label: const Text('Tóm tắt báo cáo bằng AI'),
                icon: const Icon(Icons.auto_awesome_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AiDocumentScreen(
                      auth: widget.auth,
                      title: 'Tóm tắt báo cáo',
                      load: () => widget.auth.request(
                        '/api/v1/projects/${idOf(report, 'projectId')}/reports/${widget.id}/summary',
                        requestTimeout: const Duration(seconds: 90),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          if (isLecturer) ...[
            const SizedBox(height: 12),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Viết nhận xét giảng viên',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('report-feedback-input'),
                    controller: _feedbackCtrl,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: 'Nhập nhận xét ngắn cho báo cáo tiến độ…',
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const Key('report-feedback-submit'),
                    onPressed: _saving ? null : () => _submitFeedback(report),
                    child: Text(_saving ? 'Đang gửi…' : 'Gửi nhận xét'),
                  ),
                ],
              ),
            ),
          ],
        ];
      },
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
        accentColor: AppColors.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              textOf(feedback, 'supervisorName'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              displayDate(feedback['createdAt']),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            SelectableBody(textOf(feedback, 'feedbackText')),
          ],
        ),
      ),
    ),
];

class ExternalLinkButton extends StatefulWidget {
  const ExternalLinkButton({super.key, required this.uri});
  final Uri uri;
  @override
  State<ExternalLinkButton> createState() => _ExternalLinkButtonState();
}

class _ExternalLinkButtonState extends State<ExternalLinkButton> {
  String? _error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        icon: const Icon(Icons.open_in_new),
        label: const Text('Mở liên kết họp'),
        onPressed: () async {
          setState(() => _error = null);
          try {
            final opened = await launchUrl(
              widget.uri,
              mode: LaunchMode.externalApplication,
            );
            if (!opened && mounted) {
              setState(
                () => _error = 'Không mở được liên kết ngoài. Bạn có thể sao chép địa chỉ bên dưới.',
              );
            }
          } catch (_) {
            if (mounted) {
              setState(
                () => _error = 'Không mở được liên kết ngoài. Bạn có thể sao chép địa chỉ bên dưới.',
              );
            }
          }
        },
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppColors.danger)),
        const SizedBox(height: 4),
        SelectableText(widget.uri.toString()),
      ],
    ],
  );
}
