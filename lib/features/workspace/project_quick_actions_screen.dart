import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/paged_records.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import 'workspace_models.dart';

/// 1-tap team Working Agreement view and member consent screen.
class WorkingAgreementScreen extends StatefulWidget {
  const WorkingAgreementScreen({
    super.key,
    required this.auth,
    required this.projectId,
    required this.onChanged,
  });

  final AuthController auth;
  final int projectId;
  final VoidCallback onChanged;

  @override
  State<WorkingAgreementScreen> createState() => _WorkingAgreementScreenState();
}

class _WorkingAgreementScreenState extends State<WorkingAgreementScreen> {
  int _revision = 0;
  bool _saving = false;
  String? _message;
  bool _failed = false;

  Future<void> _accept(Json agreement) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.auth.request(
        '/api/v1/projects/${widget.projectId}/working-agreement/acceptances',
        method: 'POST',
        body: {
          'agreementId': idOf(agreement),
          'concurrencyToken': textOf(agreement, 'concurrencyToken', ''),
        },
      );
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'Bạn đã xác nhận đồng thuận quy ước làm việc.';
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

  List<Json> _parseSections(Json agreement) {
    final raw = agreement['contentJson'];
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return recordsOf(decoded);
      if (decoded is Json && decoded['sections'] is List) {
        return recordsOf(decoded['sections']);
      }
    } catch (_) {}
    return [
      {'title': 'Nội dung quy ước', 'body': raw},
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quy ước làm việc')),
    body: RemotePage<Json?>(
      title: 'Quy ước làm việc',
      showHeading: false,
      revision: _revision,
      load: () async {
        final result = await widget.auth.request(
          '/api/v1/projects/${widget.projectId}/working-agreement',
        );
        return result == null ? null : objectOf(result);
      },
      content: (context, agreement, refresh) {
        if (agreement == null) {
          return const [
            Surface(
              child: Text(
                'Nhóm chưa phát hành quy ước làm việc. Trưởng nhóm có thể tạo trên web.',
              ),
            ),
          ];
        }
        final acceptedByMe = agreement['acceptedByMe'] == true;
        final acceptances = agreement['acceptances'] is List
            ? recordsOf(agreement['acceptances'])
            : const <Json>[];
        final memberCount = (agreement['memberCount'] as num?)?.toInt() ?? 0;
        final sections = _parseSections(agreement);
        final status = textOf(agreement, 'status');

        return [
          if (_message != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(
                  color: _failed ? AppColors.danger : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          NavyHeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Phiên bản v${agreement['version'] ?? 1}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onNavy,
                        ),
                      ),
                    ),
                    StatusBadge(
                      statusText(status),
                      tone: StatusBadge.toneForStatus(status),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Đã đồng thuận: ${acceptances.length}/$memberCount thành viên',
                  style: const TextStyle(color: AppColors.onNavyMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!acceptedByMe && status == 'PUBLISHED') ...[
            FilledButton.icon(
              key: const Key('accept-agreement-button'),
              onPressed: _saving ? null : () => _accept(agreement),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onNavy,
                      ),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(
                _saving ? 'Đang xác nhận…' : 'Đồng ý quy ước làm việc',
              ),
            ),
            const SizedBox(height: 18),
          ] else if (acceptedByMe) ...[
            const AttentionBanner(
              title: 'Bạn đã xác nhận đồng thuận',
              message: 'Phiên bản hiện hành đã ghi nhận sự đồng ý của bạn.',
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 18),
          ],
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                child: ContentSection(
                  textOf(section, 'title', 'Điều khoản'),
                  textOf(section, 'body', ''),
                ),
              ),
            ),
        ];
      },
    ),
  );
}

/// Private versioned peer evaluation screen enforcing >= 30 chars reason when rating < 50%.
class PeerEvaluationScreen extends StatefulWidget {
  const PeerEvaluationScreen({
    super.key,
    required this.auth,
    required this.projectId,
    required this.onChanged,
  });

  final AuthController auth;
  final int projectId;
  final VoidCallback onChanged;

  @override
  State<PeerEvaluationScreen> createState() => _PeerEvaluationScreenState();
}

class _PeerEvaluationScreenState extends State<PeerEvaluationScreen> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Đánh giá chéo nhóm')),
    body: PagedRecords(
      auth: widget.auth,
      title: 'Vòng đánh giá chéo',
      showHeading: false,
      revision: _revision,
      path: '/api/v1/projects/${widget.projectId}/peer-evaluations/rounds',
      emptyText: 'Chưa có vòng đánh giá chéo nào trong đồ án này.',
      item: (context, round, refresh) {
        final canSubmit = round['canSubmit'] == true;
        return RecordTile(
          title: textOf(round, 'title'),
          icon: Icons.groups_outlined,
          badge: statusText(round['status']),
          badgeTone: StatusBadge.toneForStatus(round['status'] as String?),
          subtitle:
              'Mở: ${displayDate(round['opensAt'])}\nĐóng: ${displayDate(round['closesAt'])}${canSubmit ? '\nCó thể chấm điểm' : ''}',
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => _PeerRoundFormScreen(
                  auth: widget.auth,
                  projectId: widget.projectId,
                  round: round,
                  onChanged: widget.onChanged,
                ),
              ),
            );
            if (mounted) setState(() => _revision++);
          },
        );
      },
    ),
  );
}

class _PeerRoundFormScreen extends StatefulWidget {
  const _PeerRoundFormScreen({
    required this.auth,
    required this.projectId,
    required this.round,
    required this.onChanged,
  });

  final AuthController auth;
  final int projectId;
  final Json round;
  final VoidCallback onChanged;

  @override
  State<_PeerRoundFormScreen> createState() => _PeerRoundFormScreenState();
}

class _PeerRoundFormScreenState extends State<_PeerRoundFormScreen> {
  final _ratings = <int, int>{};
  final _comments = <int, TextEditingController>{};
  String? _concurrencyToken;
  String _submissionStatus = 'DRAFT';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _notice;

  int get _roundId => idOf(widget.round);
  bool get _readOnly =>
      widget.round['canSubmit'] != true || _submissionStatus == 'SUBMITTED';

  List<Json> get _roster => widget.round['roster'] is List
      ? recordsOf(widget.round['roster'])
      : const [];

  @override
  void initState() {
    super.initState();
    for (final member in _roster) {
      final uid = idOf(member, 'userId');
      _ratings[uid] = 80;
      _comments[uid] = TextEditingController();
    }
    _loadMine();
  }

  @override
  void dispose() {
    for (final ctrl in _comments.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.auth.getJson(
        '/api/v1/projects/${widget.projectId}/peer-evaluations/mine?roundId=$_roundId',
      );
      if (!mounted) return;
      final submission = data['submission'] is Json
          ? data['submission'] as Json
          : null;
      setState(() {
        _submissionStatus = textOf(data, 'status', 'DRAFT');
        _concurrencyToken = submission?['concurrencyToken'] as String?;
        if (submission != null && submission['items'] is List) {
          for (final row in recordsOf(submission['items'])) {
            final uid = idOf(row, 'targetUserId');
            _ratings[uid] = (row['rating'] as num?)?.round() ?? 80;
            _comments.putIfAbsent(uid, TextEditingController.new).text = textOf(
              row,
              'comment',
              '',
            );
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorText(error);
          _loading = false;
        });
      }
    }
  }

  String? _validateUnder50() {
    for (final member in _roster) {
      final uid = idOf(member, 'userId');
      final score = _ratings[uid] ?? 80;
      final note = _comments[uid]?.text.trim() ?? '';
      if (score < 50 && note.length < 30) {
        return 'Đánh giá dưới 50% cho ${textOf(member, 'fullName')} cần giải trình tối thiểu 30 ký tự (hiện có ${note.length}/30).';
      }
    }
    return null;
  }

  Future<void> _save({required bool submit}) async {
    if (_saving || _readOnly) return;
    final validation = _validateUnder50();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final saved = objectOf(
        await widget.auth.request(
          '/api/v1/projects/${widget.projectId}/peer-evaluations/rounds/$_roundId/mine',
          method: 'PUT',
          body: {
            'concurrencyToken': _concurrencyToken,
            'items': [
              for (final member in _roster)
                {
                  'targetUserId': idOf(member, 'userId'),
                  'rating': _ratings[idOf(member, 'userId')] ?? 80,
                  'comment':
                      (_comments[idOf(member, 'userId')]?.text.trim().isEmpty ??
                          true)
                      ? null
                      : _comments[idOf(member, 'userId')]!.text.trim(),
                },
            ],
          },
        ),
      );
      _concurrencyToken = saved['concurrencyToken'] as String?;
      if (submit) {
        final submitted = objectOf(
          await widget.auth.request(
            '/api/v1/projects/${widget.projectId}/peer-evaluations/rounds/$_roundId/mine/submit',
            method: 'POST',
            body: {'concurrencyToken': _concurrencyToken ?? ''},
          ),
        );
        _submissionStatus = textOf(submitted, 'status', 'SUBMITTED');
      }
      widget.onChanged();
      if (mounted) {
        setState(() {
          _notice = submit
              ? 'Đã nộp đánh giá chéo thành công.'
              : 'Đã lưu bản nháp đánh giá chéo.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(textOf(widget.round, 'title'))),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                  children: [
                    AttentionBanner(
                      title: 'Quy tắc đánh giá chéo',
                      message: 'Mức đóng góp từ 0% đến 100%. Nếu đánh giá dưới 50%, bắt buộc nhập giải trình rõ ràng tối thiểu 30 ký tự.',
                      icon: Icons.rule_outlined,
                    ),
                    const SizedBox(height: 14),
                    if (_error != null) ...[
                      Notice(_error!),
                      const SizedBox(height: 14),
                    ],
                    if (_notice != null) ...[
                      Text(
                        _notice!,
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    for (final member in _roster) ...[
                      Builder(
                        builder: (context) {
                          final uid = idOf(member, 'userId');
                          final score = _ratings[uid] ?? 80;
                          final lowScore = score < 50;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Surface(
                              accentColor: lowScore
                                  ? AppColors.danger
                                  : AppColors.teal,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          textOf(member, 'fullName'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                      StatusBadge(
                                        '$score%',
                                        tone: lowScore
                                            ? StatusTone.danger
                                            : StatusTone.success,
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: score.toDouble(),
                                    min: 0,
                                    max: 100,
                                    divisions: 20,
                                    label: '$score%',
                                    activeColor: lowScore
                                        ? AppColors.danger
                                        : AppColors.primary,
                                    onChanged: _readOnly || _saving
                                        ? null
                                        : (v) => setState(
                                            () => _ratings[uid] = v.round(),
                                          ),
                                  ),
                                  TextField(
                                    controller: _comments[uid],
                                    enabled: !_readOnly && !_saving,
                                    minLines: 2,
                                    maxLines: 4,
                                    maxLength: 500,
                                    decoration: InputDecoration(
                                      labelText: lowScore
                                          ? 'Giải trình bắt buộc (≥ 30 ký tự)'
                                          : 'Nhận xét (không bắt buộc)',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
    bottomNavigationBar: _readOnly
        ? null
        : SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _save(submit: false),
                      child: const Text('Lưu nháp'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('peer-eval-submit-btn'),
                      onPressed: _saving ? null : () => _save(submit: true),
                      child: Text(_saving ? 'Đang gửi…' : 'Nộp đánh giá'),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

/// Project Action Items list with quick create and status toggle.
class ActionItemsScreen extends StatefulWidget {
  const ActionItemsScreen({
    super.key,
    required this.auth,
    required this.projectId,
    required this.onChanged,
    this.meetingId,
  });

  final AuthController auth;
  final int projectId;
  final VoidCallback onChanged;
  final int? meetingId;

  @override
  State<ActionItemsScreen> createState() => _ActionItemsScreenState();
}

class _ActionItemsScreenState extends State<ActionItemsScreen> {
  int _revision = 0;
  bool _saving = false;

  Future<void> _toggle(Json item) async {
    if (_saving) return;
    final current = textOf(item, 'status', 'OPEN');
    final next = current == 'DONE' ? 'OPEN' : 'DONE';
    setState(() => _saving = true);
    try {
      await widget.auth.request(
        '/api/v1/projects/${widget.projectId}/action-items/${idOf(item)}/status',
        method: 'POST',
        body: {'status': next, 'concurrencyToken': item['concurrencyToken']},
      );
      widget.onChanged();
      if (mounted) setState(() => _revision++);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _create() async {
    final titleCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Thêm việc cần làm sau họp'),
        content: TextField(
          controller: titleCtrl,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Nội dung việc cần làm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    titleCtrl.dispose();
    if (!mounted || ok != true || title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.auth.request(
        '/api/v1/projects/${widget.projectId}/action-items',
        method: 'POST',
        body: {
          'sourceType': widget.meetingId != null ? 'MEETING' : 'PROJECT',
          'meetingId': widget.meetingId,
          'title': title,
        },
      );
      widget.onChanged();
      if (mounted) setState(() => _revision++);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorText(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.meetingId == null
        ? ''
        : '?meetingId=${widget.meetingId}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Việc cần làm (Action Items)'),
        actions: [
          IconButton(
            tooltip: 'Thêm việc cần làm',
            onPressed: _saving ? null : _create,
            icon: const Icon(Icons.add_task_outlined),
          ),
        ],
      ),
      body: PagedRecords(
        auth: widget.auth,
        title: 'Action Items',
        showHeading: false,
        revision: _revision,
        path: '/api/v1/projects/${widget.projectId}/action-items$query',
        emptyText: 'Chưa có action item nào.',
        item: (context, item, refresh) {
          final done = item['status'] == 'DONE';
          return RecordTile(
            title: textOf(item, 'title'),
            icon: done
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            badge: statusText(item['status']),
            badgeTone: StatusBadge.toneForStatus(item['status'] as String?),
            subtitle:
                '${textOf(item, 'ownerName', 'Chưa phân công')}${item['dueAt'] != null ? ' · Hạn ${displayDate(item['dueAt'])}' : ''}',
            onTap: _saving ? null : () => _toggle(item),
          );
        },
      ),
    );
  }
}

/// Read-only hub tracking: Health Pulse, Pinned Resources, Deliverables/Submissions, Result History.
class ProjectTrackingScreen extends StatefulWidget {
  const ProjectTrackingScreen({
    super.key,
    required this.auth,
    required this.projectId,
  });

  final AuthController auth;
  final int projectId;

  @override
  State<ProjectTrackingScreen> createState() => _ProjectTrackingScreenState();
}

class _ProjectTrackingScreenState extends State<ProjectTrackingScreen> {
  String _tab = 'hub';

  Future<Json> _load() async {
    final results = await Future.wait<Object?>([
      widget.auth
          .request('/api/v1/projects/${widget.projectId}/hub/health-pulse')
          .catchError((_) => null),
      widget.auth
          .request('/api/v1/projects/${widget.projectId}/hub/pinned-resources')
          .catchError((_) => null),
      widget.auth
          .request('/api/v1/projects/${widget.projectId}/deliverables')
          .catchError((_) => null),
      widget.auth
          .request('/api/v1/projects/${widget.projectId}/cold/progress')
          .catchError((_) => null),
      widget.auth
          .request('/api/v1/projects/${widget.projectId}/result/history')
          .catchError((_) => null),
    ]);
    return {
      'pulse': results[0],
      'pins': results[1],
      'deliverables': results[2],
      'cold': results[3],
      'resultHistory': results[4],
    };
  }

  Future<void> _openUrl(String raw) async {
    final uri = externalUri(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Theo dõi hồ sơ & sức khỏe')),
    body: RemotePage<Json>(
      title: 'Theo dõi đồ án',
      showHeading: false,
      load: _load,
      leading: [
        HorizontalChoices(
          children: [
            for (final entry in const {
              'hub': 'Sức khỏe & ghim',
              'deliverables': 'Sản phẩm & hồ sơ',
              'results': 'Lịch sử kết quả',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _tab == entry.key,
                onSelected: (_) => setState(() => _tab = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      content: (context, data, refresh) {
        if (_tab == 'hub') {
          final pulse = data['pulse'] is Json ? data['pulse'] as Json : null;
          final pins = data['pins'] is List
              ? recordsOf(data['pins'])
              : const <Json>[];
          return [
            if (pulse != null) ...[
              NavyHeroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Sức khỏe đồ án',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onNavy,
                            ),
                          ),
                        ),
                        StatusBadge(
                          statusText(pulse['status']),
                          tone: StatusBadge.toneForStatus(
                            pulse['status'] as String?,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      textOf(pulse, 'summary', 'Chưa có tóm tắt sức khỏe.'),
                      style: const TextStyle(
                        color: AppColors.onNavyMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            const SectionHeader('Tài nguyên đã ghim'),
            const SizedBox(height: 10),
            if (pins.isEmpty)
              const Surface(child: Text('Nhóm chưa ghim tài nguyên nào.'))
            else
              for (final pin in pins)
                RecordTile(
                  title: textOf(pin, 'title'),
                  icon: Icons.push_pin_outlined,
                  badge: textOf(pin, 'resourceType', 'LINK'),
                  subtitle: textOf(pin, 'url'),
                  onTap: () => _openUrl(textOf(pin, 'url', '')),
                ),
          ];
        }
        if (_tab == 'deliverables') {
          final rawDeliverables = data['deliverables'];
          final deliverables = rawDeliverables is List
              ? recordsOf(rawDeliverables)
              : rawDeliverables is Json && rawDeliverables['items'] is List
              ? recordsOf(rawDeliverables['items'])
              : const <Json>[];
          final cold = data['cold'] is Json ? data['cold'] as Json : null;
          return [
            if (cold != null) ...[
              Surface(
                accentColor: AppColors.info,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tiến độ hồ sơ kiểm tra (Cold)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hoàn tất: ${cold['submittedRequiredCount'] ?? cold['completedCount'] ?? 0}/${cold['totalRequiredCount'] ?? cold['totalCount'] ?? 0}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            const SectionHeader('Danh mục sản phẩm (chế độ đọc)'),
            const SizedBox(height: 10),
            if (deliverables.isEmpty)
              const Surface(
                child: Text(
                  'Chưa có sản phẩm nào. Tải lên gói hồ sơ dung lượng lớn được thực hiện trên web.',
                ),
              )
            else
              for (final item in deliverables)
                RecordTile(
                  title: textOf(item, 'title', textOf(item, 'name')),
                  icon: Icons.inventory_2_outlined,
                  badge: statusText(item['status']),
                  badgeTone: StatusBadge.toneForStatus(
                    item['status'] as String?,
                  ),
                  subtitle:
                      'Hạn: ${displayDate(item['dueAt'] ?? item['dueDate'])}',
                ),
          ];
        }
        final rawHistory = data['resultHistory'];
        final versions = rawHistory is List
            ? recordsOf(rawHistory)
            : rawHistory is Json && rawHistory['items'] is List
            ? recordsOf(rawHistory['items'])
            : const <Json>[];
        return [
          const SectionHeader('Lịch sử phiên bản kết quả'),
          const SizedBox(height: 10),
          if (versions.isEmpty)
            const Surface(
              child: Text('Chưa có lịch sử phiên bản kết quả công bố.'),
            )
          else
            for (final v in versions)
              RecordTile(
                title: 'Phiên bản v${v['version'] ?? v['versionNumber'] ?? 1}',
                icon: Icons.history_edu_outlined,
                badge: statusText(v['status']),
                badgeTone: StatusBadge.toneForStatus(v['status'] as String?),
                subtitle:
                    'Cập nhật: ${displayDate(v['publishedAt'] ?? v['createdAt'])}',
              ),
        ];
      },
    ),
  );
}
