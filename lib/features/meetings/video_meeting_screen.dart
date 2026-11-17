import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../workspace/workspace_models.dart';

class VideoCredential {
  VideoCredential(Json data) {
    final uri = Uri.tryParse(textOf(data, 'serverUrl', ''));
    final expiry = DateTime.tryParse(textOf(data, 'expiresAt', ''));
    if (data['provider'] != 'LIVEKIT' ||
        uri == null ||
        !['https', 'wss'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        textOf(data, 'accessToken', '').isEmpty ||
        expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const ApiException(
        'Thông tin phòng họp không hợp lệ hoặc đã hết hạn.',
      );
    }
    serverUrl = uri.toString();
    token = data['accessToken'] as String;
    final capabilities = objectOf(data['capabilities']);
    publishAudio = capabilities['publishAudio'] == true;
    publishVideo = capabilities['publishVideo'] == true;
  }
  late final String serverUrl;
  late final String token;
  late final bool publishAudio;
  late final bool publishVideo;
}

class VideoMeetingScreen extends StatefulWidget {
  const VideoMeetingScreen({
    super.key,
    required this.auth,
    required this.meetingId,
  });
  final AuthController auth;
  final int meetingId;
  @override
  State<VideoMeetingScreen> createState() => _VideoMeetingScreenState();
}

class _VideoMeetingScreenState extends State<VideoMeetingScreen> {
  Json? _session;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _events;
  bool _busy = false;
  bool _publishAudio = false;
  bool _publishVideo = false;
  String? _error;
  Timer? _timer;
  int _sessionVersion = 0;
  String get _path => '/api/v1/meetings/${widget.meetingId}/video';
  Json get _capabilities => _session?['capabilities'] is Json
      ? _session!['capabilities'] as Json
      : {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_busy && (ModalRoute.of(context)?.isCurrent ?? false)) {
        _refresh(quiet: true);
      }
    });
  }

  Future<void> _refresh({bool quiet = false}) async {
    final version = ++_sessionVersion;
    if (!quiet) setState(() => _busy = true);
    try {
      final session = await widget.auth.getJson('$_path/session');
      if (!mounted || version != _sessionVersion) return;
      setState(() {
        _session = session;
        if (!quiet) _error = null;
      });
      if (session['session'] is Json &&
          (session['session'] as Json)['status'] == 'ENDED' &&
          _room != null) {
        await _leave();
      }
    } catch (error) {
      if (!mounted || version != _sessionVersion) return;
      setState(() {
        _error = errorText(error);
        // Never keep actionable capabilities after access has been revoked.
        _session = null;
      });
      if (error is ApiException && [401, 403, 404].contains(error.statusCode)) {
        await _leave();
      }
    } finally {
      if (mounted && !quiet && version == _sessionVersion) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _start() async {
    if (_busy || _capabilities['canStart'] != true) return;
    _sessionVersion++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = objectOf(
        await widget.auth.request('$_path/start', method: 'POST'),
      );
      if (mounted) setState(() => _session = session);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    if (_busy || _room != null || _capabilities['canJoin'] != true) return;
    _sessionVersion++;
    setState(() {
      _busy = true;
      _error = null;
    });
    lk.Room? connecting;
    try {
      final credential = VideoCredential(
        objectOf(await widget.auth.request('$_path/join', method: 'POST')),
      );
      if (!mounted) return;
      final room = lk.Room(
        roomOptions: const lk.RoomOptions(adaptiveStream: true, dynacast: true),
      );
      connecting = room;
      _room = room;
      _publishAudio = credential.publishAudio;
      _publishVideo = credential.publishVideo;
      _events = room.createListener()
        ..on<lk.RoomEvent>((event) {
          if (mounted) setState(() {});
        });
      room.addListener(_roomChanged);
      // Credentials stay in this request/SDK session; devices start muted.
      await room.connect(credential.serverUrl, credential.token);
      if (!mounted || _room != room) {
        await room.disconnect();
        await room.dispose();
        return;
      }
      setState(() {});
    } catch (_) {
      // SDK exceptions may include connection credentials; never display/log them.
      if (_room == connecting) await _leave();
      if (mounted) {
        setState(
          () => _error =
              'Chưa thể kết nối phòng họp. Kiểm tra mạng rồi thử tham gia lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _roomChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _leave() async {
    final room = _room;
    _room = null;
    final events = _events;
    _events = null;
    room?.removeListener(_roomChanged);
    await events?.dispose();
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {
        /* Dispose still releases local media. */
      }
      await room.dispose();
    }
    if (mounted) setState(() {});
  }

  Future<void> _end() async {
    if (_busy || _capabilities['canEnd'] != true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Kết thúc phòng cho mọi người?'),
        content: const Text('Chọn Rời phòng nếu bạn chỉ muốn tự thoát.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Kết thúc phòng'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _sessionVersion++;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = objectOf(
        await widget.auth.request('$_path/end', method: 'POST'),
      );
      await _leave();
      if (mounted) setState(() => _session = session);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMedia({required bool video}) async {
    final local = _room?.localParticipant;
    if (_busy || local == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (video) {
        await local.setCameraEnabled(!local.isCameraEnabled());
      } else {
        await local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa thể bật thiết bị. Kiểm tra quyền camera/micro trong cài đặt của thiết bị hoặc trình duyệt.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _sessionVersion++;
    _timer?.cancel();
    unawaited(_leave());
    super.dispose();
  }

  String get _sessionLabel {
    if (_session == null) {
      return _busy
          ? 'Đang kiểm tra phòng họp…'
          : 'Chưa tải được thông tin phòng';
    }
    final session = _session?['session'];
    if (session is! Json) return 'Phòng chưa mở';
    return switch (session['status']) {
      'CREATED' =>
        session['startedAt'] == null ? 'Phòng đang chuẩn bị' : 'Phòng đang mở',
      'LIVE' || 'ACTIVE' => 'Phòng đang mở',
      'ENDED' => 'Phòng đã kết thúc',
      'FAILED' => 'Phòng gặp sự cố',
      _ => 'Đang kiểm tra trạng thái phòng',
    };
  }

  String? get _joinWindow {
    final window = _session?['joinWindow'];
    if (window is! Json) return null;
    final lines = [
      if (textOf(window, 'availableFrom', '').isNotEmpty)
        'Từ ${displayDate(window['availableFrom'])}',
      if (textOf(window, 'availableUntil', '').isNotEmpty)
        'Đến ${displayDate(window['availableUntil'])}',
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }

  Widget _dockControl({
    required String label,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool leave = false,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center),
      ],
    );
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(48, 76)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: leave
            ? FilledButton(
                style: style.copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? null
                        : AppColors.danger,
                  ),
                ),
                onPressed: onPressed,
                child: content,
              )
            : OutlinedButton(
                style: style,
                onPressed: onPressed,
                child: content,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final local = room?.localParticipant;
    final connected = room?.connectionState == lk.ConnectionState.connected;
    final participants = <lk.Participant>[
      ?local,
      ...?room?.remoteParticipants.values,
    ];
    final canJoin = _capabilities['canJoin'] == true;
    final canStart = _capabilities['canStart'] == true;
    final reasons = (_session?['denialReasons'] as List? ?? [])
        .whereType<String>()
        .where(
          (reason) => ![
            'VIDEO_START_FORBIDDEN',
            'VIDEO_END_FORBIDDEN',
          ].contains(reason),
        )
        .toList();
    final microphoneOn = local?.isMicrophoneEnabled() == true;
    final cameraOn = local?.isCameraEnabled() == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phòng họp'),
        actions: [
          IconButton(
            tooltip: 'Cập nhật quyền tham gia',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (room != null || _capabilities['canEnd'] == true)
            PopupMenuButton<String>(
              tooltip: 'Tùy chọn phòng họp',
              enabled: !_busy,
              onSelected: (value) async {
                if (value == 'end') {
                  await _end();
                } else if (room != null) {
                  try {
                    await room.startAudio();
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _error = 'Chưa phát được âm thanh. Kiểm tra thiết bị đầu ra.',
                      );
                    }
                  }
                }
              },
              itemBuilder: (_) => [
                if (room != null)
                  PopupMenuItem(
                    value: 'audio',
                    enabled: connected,
                    child: const Text('Bật âm thanh'),
                  ),
                if (_capabilities['canEnd'] == true)
                  const PopupMenuItem(
                    value: 'end',
                    child: Text('Kết thúc phòng cho mọi người'),
                  ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Đang xử lý phòng họp',
                  ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Notice(
                            _error!,
                            retry: _busy ? null : _refresh,
                          ),
                        ),
                      if (room == null)
                        Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.video_call_outlined,
                                color: AppColors.primary,
                                size: 28,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _sessionLabel,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Mic và camera mặc định tắt. Bạn có thể bật sau khi vào phòng.',
                              ),
                              if (_joinWindow != null) ...[
                                const SizedBox(height: 20),
                                const ContentSection(
                                  'Thời gian tham gia',
                                  null,
                                ),
                                Text(_joinWindow!),
                                const SizedBox(height: 8),
                                Text(
                                  'Giờ theo múi giờ thiết bị.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (reasons.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                for (final reason in reasons)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(videoDenial(reason)),
                                  ),
                              ] else if (_session != null &&
                                  !canJoin &&
                                  !canStart) ...[
                                const SizedBox(height: 20),
                                const Text(
                                  'Hiện bạn chưa thể tham gia. Cập nhật quyền hoặc đợi người chủ trì mở phòng.',
                                ),
                              ],
                            ],
                          ),
                        )
                      else ...[
                        Surface(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                switch (room.connectionState) {
                                  lk.ConnectionState.connected => 'Đã kết nối',
                                  lk.ConnectionState.reconnecting =>
                                    'Đang kết nối lại…',
                                  lk.ConnectionState.connecting =>
                                    'Đang kết nối…',
                                  _ => 'Kết nối đã đóng',
                                },
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (room.connectionState ==
                                  lk.ConnectionState.reconnecting) ...[
                                const SizedBox(height: 12),
                                const LinearProgressIndicator(
                                  semanticsLabel: 'Đang kết nối lại phòng họp',
                                ),
                              ],
                              if (!connected &&
                                  room.connectionState !=
                                      lk.ConnectionState.connecting) ...[
                                const SizedBox(height: 8),
                                Text(
                                  room.connectionState ==
                                          lk.ConnectionState.reconnecting
                                      ? 'Đang khôi phục kết nối. Chờ một chút để dùng mic và camera.'
                                      : 'Rời phòng rồi tham gia lại để kết nối.',
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ContentSection(
                          'Người trong phòng (${participants.length})',
                          null,
                        ),
                        if (participants.isEmpty)
                          const Text('Đang tải người tham gia…'),
                        for (final participant in participants)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _ParticipantView(participant: participant),
                          ),
                      ],
                    ],
                  ),
                ),
                if (room == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : canJoin
                          ? _join
                          : canStart
                          ? _start
                          : null,
                      icon: Icon(
                        canJoin ? Icons.video_call_outlined : Icons.play_arrow,
                      ),
                      label: Text(
                        _busy
                            ? 'Đang xử lý…'
                            : canJoin
                            ? 'Tham gia phòng'
                            : canStart
                            ? 'Mở phòng họp'
                            : 'Chưa thể tham gia',
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _dockControl(
                            label: microphoneOn ? 'Mic bật' : 'Mic tắt',
                            tooltip: microphoneOn ? 'Tắt mic' : 'Bật mic',
                            icon: microphoneOn ? Icons.mic : Icons.mic_off,
                            onPressed: _busy || !connected || !_publishAudio
                                ? null
                                : () => _toggleMedia(video: false),
                          ),
                          const SizedBox(width: 8),
                          _dockControl(
                            label: cameraOn ? 'Camera bật' : 'Camera tắt',
                            tooltip: cameraOn ? 'Tắt camera' : 'Bật camera',
                            icon: cameraOn
                                ? Icons.videocam
                                : Icons.videocam_off,
                            onPressed: _busy || !connected || !_publishVideo
                                ? null
                                : () => _toggleMedia(video: true),
                          ),
                          const SizedBox(width: 8),
                          _dockControl(
                            label: 'Rời phòng',
                            tooltip: 'Rời phòng họp',
                            icon: Icons.call_end,
                            leave: true,
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _leave();
                                    await _refresh();
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantView extends StatelessWidget {
  const _ParticipantView({required this.participant});
  final lk.Participant participant;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: participant,
    builder: (context, _) {
      final tracks = participant.videoTrackPublications
          .where((p) => p.track is lk.VideoTrack && !p.muted)
          .map((p) => p.track as lk.VideoTrack)
          .toList();
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${participant.name.isEmpty ? 'Người tham gia' : participant.name}${participant is lk.LocalParticipant ? ' · Bạn' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (tracks.isEmpty)
              const SizedBox(
                height: 100,
                child: Center(child: Icon(Icons.person_outline, size: 48)),
              ),
            for (final track in tracks)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: lk.VideoTrackRenderer(track),
              ),
            Text(
              participant.isMicrophoneEnabled()
                  ? 'Mic đang bật'
                  : 'Mic đang tắt',
            ),
          ],
        ),
      );
    },
  );
}

String videoDenial(String reason) => switch (reason) {
  'VIDEO_NOT_ENABLED' => 'Dịch vụ họp video hiện chưa được bật.',
  'PROJECT_NOT_ACTIVE' => 'Đồ án hiện không ở trạng thái đang thực hiện.',
  'MEETING_NOT_SCHEDULED' => 'Lịch họp đã kết thúc hoặc đã hủy.',
  'VIDEO_JOIN_TOO_EARLY' => 'Chưa đến thời gian được tham gia.',
  'VIDEO_JOIN_WINDOW_CLOSED' => 'Đã qua thời gian được tham gia.',
  'VIDEO_SESSION_NOT_STARTED' => 'Người chủ trì chưa mở phòng họp.',
  'VIDEO_SESSION_ENDED' => 'Phòng họp đã kết thúc.',
  'VIDEO_SESSION_FAILED' => 'Phòng gặp lỗi. Người chủ trì cần mở lại phòng.',
  'MEETING_PARTICIPANT_REQUIRED' =>
    'Bạn chưa thuộc danh sách người tham gia lịch họp.',
  'VIDEO_JOIN_FORBIDDEN' => 'Bạn hiện không có quyền tham gia phòng họp này.',
  'VIDEO_START_FORBIDDEN' => 'Chỉ người có quyền chủ trì được mở phòng.',
  'VIDEO_END_FORBIDDEN' => 'Chỉ người có quyền chủ trì được kết thúc phòng.',
  'NOT_IN_APP_VIDEO' => 'Lịch này không dùng phòng video tích hợp.',
  _ => 'Phòng chưa khả dụng theo quyền và lịch họp hiện tại.',
};
