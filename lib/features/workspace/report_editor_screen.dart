import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import 'workspace_models.dart';

/// Quick progress report composer backed by `/progress-reports/prefill`,
/// create/update draft, and submit with concurrency & 409 lock handling.
class ReportEditorScreen extends StatefulWidget {
  const ReportEditorScreen({
    super.key,
    required this.auth,
    required this.projectId,
    this.existingReport,
  });

  final AuthController auth;
  final int projectId;
  final Json? existingReport;

  @override
  State<ReportEditorScreen> createState() => _ReportEditorScreenState();
}

class _ReportEditorScreenState extends State<ReportEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _summary = TextEditingController();
  final _completed = TextEditingController();
  final _inProgress = TextEditingController();
  final _planned = TextEditingController();
  final _blockers = TextEditingController();
  final _risks = TextEditingController();
  final _nextActions = TextEditingController();

  String _reportType = 'WEEKLY';
  String _periodStart = _isoDate(
    DateTime.now().subtract(const Duration(days: 6)),
  );
  String _periodEnd = _isoDate(DateTime.now());
  int? _periodId;
  String? _concurrencyToken;
  int? _reportId;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _insufficientData = false;
  List<Json> _evidence = [];
  String? _error;
  String? _notice;

  bool get _editing => _reportId != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _summary.dispose();
    _completed.dispose();
    _inProgress.dispose();
    _planned.dispose();
    _blockers.dispose();
    _risks.dispose();
    _nextActions.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final existing = widget.existingReport;
    if (existing != null) {
      _reportId = idOf(existing);
      _reportType = textOf(existing, 'reportType', 'WEEKLY');
      _periodStart = textOf(existing, 'periodStart', _periodStart);
      _periodEnd = textOf(existing, 'periodEnd', _periodEnd);
      _periodId = existing['progressReportPeriodId'] as int?;
      _concurrencyToken = existing['concurrencyToken'] as String?;
      _summary.text = textOf(existing, 'summary', '');
      _completed.text = textOf(existing, 'completedWork', '');
      _inProgress.text = textOf(existing, 'inProgressWork', '');
      _planned.text = textOf(existing, 'plannedWork', '');
      _blockers.text = textOf(existing, 'blockers', '');
      _risks.text = textOf(
        existing,
        'risks',
        textOf(existing, 'issuesAndRisks', ''),
      );
      _nextActions.text = textOf(existing, 'nextActions', '');
      setState(() => _loading = false);
      return;
    }
    await _loadPrefill();
  }

  Future<void> _loadPrefill() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.auth.getJson(
        '/api/v1/projects/${widget.projectId}/progress-reports/prefill',
      );
      if (!mounted) return;
      final suggested = data['suggested'] is Json
          ? data['suggested'] as Json
          : const <String, dynamic>{};
      setState(() {
        _reportType = textOf(data, 'reportType', 'WEEKLY');
        _periodStart = textOf(data, 'periodStart', _periodStart);
        _periodEnd = textOf(data, 'periodEnd', _periodEnd);
        _periodId = data['progressReportPeriodId'] as int?;
        _insufficientData = data['insufficientData'] == true;
        _evidence = data['evidence'] is List ? recordsOf(data['evidence']) : [];
        _summary.text = textOf(suggested, 'summary', '');
        _completed.text = textOf(suggested, 'completedWork', '');
        _inProgress.text = textOf(suggested, 'inProgressWork', '');
        _blockers.text = textOf(suggested, 'blockers', '');
        _risks.text = textOf(suggested, 'risks', '');
        _nextActions.text = textOf(suggested, 'nextActions', '');
        _notice = _insufficientData
            ? 'Dữ liệu kỳ này còn ít. Hãy bổ sung tóm tắt trước khi lưu hoặc nộp.'
            : 'Đã tự động điền gợi ý từ tiến độ công việc. Kiểm tra lại trước khi lưu.';
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _notice =
              'Không tải được dữ liệu tự điền; bạn vẫn có thể nhập thủ công.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save({required bool submit}) async {
    if (_saving || _loading) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (submit) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Nộp báo cáo tiến độ?'),
          content: const Text(
            'Sau khi nộp, báo cáo sẽ gửi cho giảng viên hướng dẫn và có thể bị khóa chỉnh sửa theo quy định kỳ báo cáo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Nộp báo cáo'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? trimOrNull(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      final Json saved;
      if (_editing) {
        saved = objectOf(
          await widget.auth.request(
            '/api/v1/progress-reports/$_reportId',
            method: 'PUT',
            body: {
              'summary': _summary.text.trim(),
              'completedWork': trimOrNull(_completed),
              'inProgressWork': trimOrNull(_inProgress),
              'plannedWork': trimOrNull(_planned),
              'issuesAndRisks': trimOrNull(_risks),
              'blockers': trimOrNull(_blockers),
              'risks': trimOrNull(_risks),
              'nextActions': trimOrNull(_nextActions),
              'progressReportPeriodId': _periodId,
              'concurrencyToken': _concurrencyToken,
            },
          ),
        );
      } else {
        saved = objectOf(
          await widget.auth.request(
            '/api/v1/projects/${widget.projectId}/progress-reports',
            method: 'POST',
            body: {
              'reportType': _reportType,
              'periodStart': _periodStart,
              'periodEnd': _periodEnd,
              'summary': _summary.text.trim(),
              'completedWork': trimOrNull(_completed),
              'inProgressWork': trimOrNull(_inProgress),
              'plannedWork': trimOrNull(_planned),
              'issuesAndRisks': trimOrNull(_risks),
              'blockers': trimOrNull(_blockers),
              'risks': trimOrNull(_risks),
              'nextActions': trimOrNull(_nextActions),
              'progressReportPeriodId': _periodId,
            },
          ),
        );
      }
      _reportId = idOf(saved);
      _concurrencyToken = saved['concurrencyToken'] as String?;

      Json finalResult = saved;
      if (submit) {
        final tokenQuery =
            _concurrencyToken == null || _concurrencyToken!.isEmpty
            ? ''
            : '?${Uri(queryParameters: {'concurrencyToken': _concurrencyToken!}).query}';
        finalResult = objectOf(
          await widget.auth.request(
            '/api/v1/progress-reports/$_reportId/submit$tokenQuery',
            method: 'POST',
          ),
        );
      }
      if (mounted) {
        _dirty = false;
        Navigator.pop(context, finalResult);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa thể lưu báo cáo tiến độ. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handlePop(bool didPop) async {
    if (didPop || _saving) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Hủy thay đổi báo cáo?'),
        content: const Text('Nội dung bạn vừa chỉnh sửa chưa được lưu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Bỏ thay đổi'),
          ),
        ],
      ),
    );
    if (mounted && discard == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_saving,
    onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
    child: Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Chỉnh sửa báo cáo' : 'Soạn báo cáo gọn'),
        actions: [
          if (!_editing)
            IconButton(
              tooltip: 'Tự điền lại từ tiến độ',
              onPressed: _saving || _loading ? null : _loadPrefill,
              icon: const Icon(Icons.auto_fix_high_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Form(
                    key: _form,
                    onChanged: () => _dirty = true,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                      children: [
                        if (_notice != null) ...[
                          AttentionBanner(
                            title:
                                '${statusText(_reportType)} · ${displayDate(_periodStart)} – ${displayDate(_periodEnd)}',
                            message: _notice!,
                            icon: Icons.auto_awesome_outlined,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_error != null) ...[
                          Notice(_error!),
                          const SizedBox(height: 16),
                        ],
                        if (!_editing) ...[
                          HorizontalChoices(
                            children: [
                              for (final entry in const {
                                'WEEKLY': 'Báo cáo tuần',
                                'MONTHLY': 'Báo cáo tháng',
                              }.entries)
                                ChoiceChip(
                                  label: Text(entry.value),
                                  selected: _reportType == entry.key,
                                  onSelected: _saving
                                      ? null
                                      : (_) => setState(() {
                                          _reportType = entry.key;
                                          _dirty = true;
                                        }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          key: const Key('report-summary-field'),
                          controller: _summary,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                            labelText: 'Tóm tắt kỳ báo cáo (bắt buộc)',
                            hintText: 'Tóm tắt ngắn tiến độ đạt được trong kỳ…',
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Nhập tóm tắt báo cáo tiến độ.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _completed,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Công việc đã hoàn thành',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _inProgress,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Đang thực hiện',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _blockers,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Vướng mắc hiện tại',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _nextActions,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Kế hoạch kỳ tiếp theo',
                          ),
                        ),
                        if (_evidence.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          SectionHeader(
                            'Dữ liệu tham chiếu (${_evidence.length})',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final item in _evidence.take(10))
                                StatusBadge(
                                  textOf(item, 'title'),
                                  tone: StatusBadge.toneForStatus(
                                    item['status'] as String?,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
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
                  key: const Key('report-save-draft-btn'),
                  onPressed: _saving || _loading
                      ? null
                      : () => _save(submit: false),
                  child: const Text('Lưu nháp'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('report-submit-btn'),
                  onPressed: _saving || _loading
                      ? null
                      : () => _save(submit: true),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onNavy,
                          ),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(_saving ? 'Đang gửi…' : 'Nộp báo cáo'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _isoDate(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
