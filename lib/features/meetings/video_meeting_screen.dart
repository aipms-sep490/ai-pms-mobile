import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
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
    if (!quiet) setState(() => _busy = true);
    try {
      final session = await widget.auth.getJson('$_path/session');
      if (mounted) {
        setState(() {
          _session = session;
          if (!quiet) _error = null;
        });
      }
      if (session['session'] is Json &&
          (session['session'] as Json)['status'] == 'ENDED' &&
          _room != null) {
        await _leave();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorText(error);
          // Never keep actionable capabilities after access has been revoked.
          _session = null;
        });
      }
      if (error is ApiException && [401, 403, 404].contains(error.statusCode)) {
        await _leave();
      }
    } finally {
      if (mounted && !quiet) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _capabilities['canStart'] != true) return;
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
    _timer?.cancel();
    unawaited(_leave());
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phòng họp'),
        actions: [
          IconButton(
            tooltip: 'Cập nhật quyền tham gia',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Đang xử lý phòng họp',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Notice(_error!, retry: _busy ? null : _refresh),
              ),
            if (room == null) ...[
              const ContentSection(
                'Trước khi tham gia',
                'Mic và camera mặc định tắt. Bạn có thể bật sau khi vào phòng.',
              ),
              if (_session != null) ...[
                ContentSection(
                  'Trạng thái',
                  _session!['session'] is Json
                      ? statusText((_session!['session'] as Json)['status'])
                      : 'Chưa mở phòng',
                ),
                if (_session!['joinWindow'] is Json)
                  ContentSection(
                    'Khoảng thời gian tham gia',
                    '${displayDate((_session!['joinWindow'] as Json)['availableFrom'])} – ${displayDate((_session!['joinWindow'] as Json)['availableUntil'])}',
                  ),
                for (final reason
                    in (_session!['denialReasons'] as List? ?? [])
                        .whereType<String>())
                  ContentSection('Điều kiện tham gia', videoDenial(reason)),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_capabilities['canStart'] == true)
                    FilledButton.icon(
                      onPressed: _busy ? null : _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Mở phòng họp'),
                    ),
                  FilledButton.icon(
                    onPressed: _busy || _capabilities['canJoin'] != true
                        ? null
                        : _join,
                    icon: const Icon(Icons.video_call_outlined),
                    label: const Text('Tham gia phòng'),
                  ),
                ],
              ),
            ] else ...[
              ContentSection('Kết nối', switch (room.connectionState) {
                lk.ConnectionState.connected => 'Đã kết nối',
                lk.ConnectionState.reconnecting => 'Đang kết nối lại…',
                lk.ConnectionState.connecting => 'Đang kết nối…',
                _ => 'Đã ngắt kết nối. Rời phòng để tham gia lại.',
              }),
              for (final participant in participants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ParticipantView(participant: participant),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy || !connected || !_publishAudio
                        ? null
                        : () => _toggleMedia(video: false),
                    icon: Icon(
                      local?.isMicrophoneEnabled() == true
                          ? Icons.mic
                          : Icons.mic_off,
                    ),
                    label: Text(
                      local?.isMicrophoneEnabled() == true
                          ? 'Tắt mic'
                          : 'Bật mic',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || !connected || !_publishVideo
                        ? null
                        : () => _toggleMedia(video: true),
                    icon: Icon(
                      local?.isCameraEnabled() == true
                          ? Icons.videocam
                          : Icons.videocam_off,
                    ),
                    label: Text(
                      local?.isCameraEnabled() == true
                          ? 'Tắt camera'
                          : 'Bật camera',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            try {
                              await room.startAudio();
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error = 'Chưa phát được âm thanh. Kiểm tra thiết bị đầu ra.',
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Bật âm thanh'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _leave();
                            await _refresh();
                          },
                    icon: const Icon(Icons.call_end),
                    label: const Text('Rời phòng'),
                  ),
                ],
              ),
            ],
            if (_capabilities['canEnd'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: OutlinedButton(
                  onPressed: _busy ? null : _end,
                  child: const Text('Kết thúc phòng cho mọi người'),
                ),
              ),
          ],
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
  'VIDEO_START_FORBIDDEN' => 'Chỉ người có quyền chủ trì được mở phòng.',
  'VIDEO_END_FORBIDDEN' => 'Chỉ người có quyền chủ trì được kết thúc phòng.',
  'NOT_IN_APP_VIDEO' => 'Lịch này không dùng phòng video tích hợp.',
  _ => 'Phòng chưa khả dụng theo quyền và lịch họp hiện tại ($reason).',
};
