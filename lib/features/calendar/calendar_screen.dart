import 'package:material_ui/material_ui.dart';

import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../workspace/inbox_screen.dart';
import '../workspace/workspace_models.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    this.showHeading = false,
  });

  final AuthController auth;
  final VoidCallback onChanged;
  final bool showHeading;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  String _sourceType = '';
  int _windowDays = 14;
  int _revision = 0;
  String? _cursor;
  String? _nextCursor;
  final _items = <Json>[];

  Future<List<Json>> _load() async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(const Duration(days: 1)).toIso8601String();
    final to = now.add(Duration(days: _windowDays)).toIso8601String();
    final query = Uri(
      queryParameters: {
        'from': from,
        'to': to,
        'pageSize': '50',
        if (_sourceType.isNotEmpty) 'sourceType': _sourceType,
        'cursor': ?_cursor,
      },
    ).query;
    final data = await widget.auth.getJson('/api/v1/calendar?$query');
    final incoming = recordsOf(data['items']);
    if (_cursor == null) _items.clear();
    _items.addAll(incoming);
    _nextCursor = data['hasMore'] == true
        ? data['nextCursor'] as String?
        : null;
    _cursor = null;
    return List<Json>.of(_items);
  }

  void _reload() => setState(() {
    _cursor = null;
    _revision++;
  });

  IconData _iconFor(String type) => switch (type.toUpperCase()) {
    'MEETING' => Icons.videocam_outlined,
    'MILESTONE' => Icons.flag_outlined,
    'TASK' => Icons.check_box_outlined,
    'PROGRESS_REPORT' => Icons.fact_check_outlined,
    _ => Icons.event_outlined,
  };

  String _labelFor(String type) => switch (type.toUpperCase()) {
    'MEETING' => 'Cuộc họp',
    'MILESTONE' => 'Mốc tiến độ',
    'TASK' => 'Công việc',
    'PROGRESS_REPORT' => 'Báo cáo',
    _ => type,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch tổng hợp')),
    body: RemotePage<List<Json>>(
      title: 'Lịch tổng hợp',
      showHeading: widget.showHeading,
      revision: _revision,
      load: _load,
      leading: [
        HorizontalChoices(
          children: [
            for (final entry in const {
              7: '7 ngày tới',
              14: '14 ngày tới',
              30: '30 ngày tới',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _windowDays == entry.key,
                onSelected: (_) {
                  _windowDays = entry.key;
                  _reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        HorizontalChoices(
          children: [
            for (final entry in const {
              '': 'Tất cả',
              'MEETING': 'Cuộc họp',
              'TASK': 'Công việc',
              'MILESTONE': 'Mốc tiến độ',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _sourceType == entry.key,
                onSelected: (_) {
                  _sourceType = entry.key;
                  _reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      content: (context, items, refresh) => [
        if (items.isEmpty)
          const Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  color: AppColors.primary,
                  size: 28,
                ),
                SizedBox(height: 12),
                Text(
                  'Không có lịch họp hoặc hạn công việc trong khoảng thời gian đã chọn.',
                ),
              ],
            ),
          ),
        for (final item in items)
          RecordTile(
            title: textOf(item, 'title'),
            icon: _iconFor(textOf(item, 'sourceType', '')),
            badge:
                '${_labelFor(textOf(item, 'sourceType', ''))} · ${statusText(item['status'])}',
            badgeTone: StatusBadge.toneForStatus(item['status'] as String?),
            subtitle:
                '${textOf(item, 'projectCode')} · ${displayDate(item['startAt'] ?? item['dueAt'])}',
            onTap: () {
              final type = textOf(item, 'sourceType', '').toUpperCase();
              final id = item['sourceId'];
              if (id is int &&
                  id > 0 &&
                  const {
                    'TASK',
                    'MEETING',
                    'MILESTONE',
                    'PROGRESS_REPORT',
                    'PROJECT',
                  }.contains(type)) {
                openEntity(
                  context,
                  widget.auth,
                  EntityTarget(type, id),
                  widget.onChanged,
                );
              }
            },
          ),
        if (_nextCursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: () => setState(() {
                _cursor = _nextCursor;
                _revision++;
              }),
              child: const Text('Tải thêm lịch'),
            ),
          ),
      ],
    ),
  );
}
