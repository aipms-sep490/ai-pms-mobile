import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/realtime_hub_manager.dart';
import '../../ui/app_theme.dart';
import '../../ui/paged_records.dart';
import '../../ui/remote_page.dart';
import '../../ui/mobile_components.dart';
import '../auth/auth_controller.dart';
import 'activity_screen.dart';
import 'project_screen.dart';
import 'tasks_screen.dart';
import 'workspace_models.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.auth,
    required this.onChanged,
    this.realtime,
    this.revision = 0,
    this.initialInvites = false,
    this.showHeading = true,
  });
  final AuthController auth;
  final VoidCallback onChanged;
  final RealtimeHubManager? realtime;
  final int revision;
  final bool initialInvites;
  final bool showHeading;
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late bool _invites = widget.initialInvites;
  bool _unread = false;
  bool _saving = false;
  int _revision = 0;
  String? _message;
  bool _failed = false;
  StreamSubscription<LiveNotificationEvent>? _notifSub;

  @override
  void initState() {
    super.initState();
    widget.realtime?.clearUnreadBump();
    _notifSub = widget.realtime?.notificationEvents.listen((_) {
      if (!mounted) return;
      widget.realtime?.clearUnreadBump();
      setState(() => _revision++);
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  Future<void> _mutate(String path, {String? confirm}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    var sent = false;
    try {
      if (confirm != null) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(confirm),
            content: const Text(
              'Hệ thống sẽ kiểm tra lại điều kiện và trạng thái lời mời.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Xác nhận'),
              ),
            ],
          ),
        );
        if (!mounted || accepted != true) return;
      }
      sent = true;
      await widget.auth.request(path, method: 'POST');
      widget.onChanged();
      if (mounted) {
        setState(() {
          _failed = false;
          _message = 'Đã cập nhật hộp thư.';
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
          if (sent) _revision++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PagedRecords(
    auth: widget.auth,
    title: 'Hộp thư',
    showHeading: widget.showHeading,
    revision: widget.revision + _revision,
    path: _invites
        ? '/api/v1/teams/invitations'
        : '/api/v1/notifications${_unread ? '?isRead=false' : ''}',
    emptyText: _invites
        ? 'Chưa có lời mời nhóm.'
        : _unread
        ? 'Bạn đã đọc hết thông báo.'
        : 'Chưa có thông báo.',
    leading: [
      HorizontalChoices(
        children: [
          ChoiceChip(
            label: const Text('Thông báo'),
            selected: !_invites,
            onSelected: _saving
                ? null
                : (_) => setState(() {
                    _invites = false;
                    _message = null;
                  }),
          ),
          ChoiceChip(
            label: const Text('Lời mời nhóm'),
            selected: _invites,
            onSelected: _saving
                ? null
                : (_) => setState(() {
                    _invites = true;
                    _message = null;
                  }),
          ),
        ],
      ),
      if (!_invites)
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('Chưa đọc'),
              selected: _unread,
              onSelected: _saving
                  ? null
                  : (value) => setState(() => _unread = value),
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _mutate('/api/v1/notifications/read-all'),
              child: const Text('Đọc tất cả'),
            ),
          ],
        ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: TextStyle(
                color: _failed ? AppColors.danger : AppColors.success,
                height: 1.5,
              ),
            ),
          ),
        ),
      if (_saving)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Đang cập nhật hộp thư…'),
        ),
      const SizedBox(height: 16),
    ],
    item: (context, item, refresh) {
      if (!_invites) {
        return RecordTile(
          title: textOf(item, 'title'),
          subtitle:
              '${item['isRead'] == true ? 'Đã đọc' : 'Chưa đọc'} · ${displayDate(item['createdAt'])}',
          icon: item['isRead'] == true
              ? Icons.drafts_outlined
              : Icons.mark_email_unread_outlined,
          onTap: _saving
              ? null
              : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationScreen(
                        auth: widget.auth,
                        notification: item,
                        onChanged: widget.onChanged,
                      ),
                    ),
                  );
                  if (mounted) await refresh();
                },
        );
      }
      final canRespond =
          item['status'] == 'PENDING' &&
          item['invitedUserId'] == widget.auth.user?.id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                textOf(item, 'teamName', 'Nhóm #${item['teamId']}'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${statusText(item['status'])} · Người mời: ${textOf(item, 'invitedByName')}',
              ),
              if (textOf(item, 'message', '').isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableBody(item['message'] as String),
              ],
              const SizedBox(height: 8),
              Text('Hạn phản hồi: ${displayDate(item['expiresAt'])}'),
              if (canRespond) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _mutate(
                              '/api/v1/teams/invitations/${idOf(item)}/accept',
                              confirm:
                                  'Tham gia ${textOf(item, 'teamName', 'nhóm này')}?',
                            ),
                      child: const Text('Chấp nhận'),
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => _mutate(
                              '/api/v1/teams/invitations/${idOf(item)}/reject',
                              confirm: 'Từ chối lời mời nhóm?',
                            ),
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
  );
}

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    required this.auth,
    required this.notification,
    required this.onChanged,
  });
  final AuthController auth;
  final Json notification;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thông báo')),
    body: RemotePage<Json>(
      title: 'Thông báo',
      showHeading: false,
      load: () async {
        // Read status belongs to this recipient. The backend revalidates access.
        await auth.request(
          '/api/v1/notifications/${idOf(notification)}/read',
          method: 'PATCH',
        );
        onChanged();
        return notification;
      },
      content: (context, item, refresh) {
        final target = EntityTarget.fromNotification(item);
        return [
          ContentSection(textOf(item, 'title'), displayDate(item['createdAt'])),
          SelectableBody(textOf(item, 'content')),
          const SizedBox(height: 24),
          if (target != null)
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Xem nội dung liên quan'),
              onPressed: () => openEntity(context, auth, target, onChanged),
            )
          else
            const Text(
              'Bạn có thể xem thêm nội dung liên quan trên AI-PMS web.',
            ),
        ];
      },
    ),
  );
}

Future<void> openEntity(
  BuildContext context,
  AuthController auth,
  EntityTarget target,
  VoidCallback onChanged,
) async {
  final Widget screen;
  switch (target.type) {
    case 'TASK':
      screen = TaskDetailScreen(
        auth: auth,
        id: target.id,
        onChanged: onChanged,
      );
    case 'MEETING':
      screen = MeetingDetailScreen(
        auth: auth,
        id: target.id,
        onChanged: onChanged,
      );
    case 'PROGRESS_REPORT':
      screen = ReportDetailScreen(auth: auth, id: target.id);
    case 'MILESTONE':
      screen = MilestoneScreen(auth: auth, id: target.id, onChanged: onChanged);
    case 'PROJECT':
      screen = Scaffold(
        appBar: AppBar(title: const Text('Đồ án')),
        body: ProjectScreen(
          auth: auth,
          id: target.id,
          onChanged: onChanged,
          showHeading: false,
        ),
      );
    case 'TEAM':
      screen = TeamDetailScreen(auth: auth, id: target.id);
    case 'TEAM_INVITATION':
      screen = Scaffold(
        appBar: AppBar(title: const Text('Lời mời nhóm')),
        body: InboxScreen(
          auth: auth,
          initialInvites: true,
          showHeading: false,
          onChanged: onChanged,
        ),
      );
    default:
      return;
  }
  // Each destination loads its resource through the authorized API again.
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => screen),
  );
}
