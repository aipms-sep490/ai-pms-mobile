import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import '../../ui/remote_page.dart';
import '../auth/auth_controller.dart';
import '../workspace/workspace_models.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.auth, this.showHeading = true});

  final AuthController auth;
  final bool showHeading;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  bool _avatarBusy = false;
  bool _googleBusy = false;
  String? _error;
  String? _notice;
  Uint8List? _avatarBytes;
  String? _avatarToken;
  bool _hasAvatar = false;
  List<Json>? _externalLogins;

  @override
  void initState() {
    super.initState();
    _loadAccountExtras();
  }

  Future<void> _loadAccountExtras() async {
    try {
      final results = await Future.wait<Object?>([
        widget.auth
            .request('/api/v1/users/me/avatar/metadata')
            .catchError((_) => null),
        widget.auth
            .request('/api/v1/auth/external-logins')
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      final meta = results[0] is Json ? results[0] as Json : null;
      final hasAvatar = meta?['hasAvatar'] == true;
      Uint8List? bytes;
      if (hasAvatar) {
        final raw = await widget.auth
            .request('/api/v1/users/me/avatar', binary: true)
            .catchError((_) => null);
        if (raw is Uint8List && raw.isNotEmpty) bytes = raw;
      }
      if (!mounted) return;
      setState(() {
        _hasAvatar = hasAvatar;
        _avatarToken = meta?['concurrencyToken'] as String?;
        _avatarBytes = bytes;
        _externalLogins = results[1] is List ? recordsOf(results[1]) : null;
      });
    } catch (_) {
      // Optional enhancements never block viewing account info or signing out.
    }
  }

  Future<void> _uploadAvatar() async {
    if (_avatarBusy || _busy) return;
    setState(() {
      _avatarBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      final file = await FilePicker.pickFile();
      if (file == null || !mounted) return;
      final ext = file.name.split('.').last.toLowerCase();
      const mime = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'webp': 'image/webp',
      };
      if (!mime.containsKey(ext)) {
        throw const ApiException('Chọn ảnh định dạng PNG, JPG hoặc WebP.');
      }
      final length = await file.length();
      if (length == null || length <= 0 || length > 3 * 1024 * 1024) {
        throw const ApiException('Ảnh đại diện tối đa 3 MB.');
      }
      final bytes = await file.readAsBytes();
      final updated = objectOf(
        await widget.auth.request(
          '/api/v1/users/me/avatar',
          method: 'POST',
          upload: ApiUpload(
            file.name,
            bytes,
            field: 'File',
            contentType: mime[ext]!,
          ),
          body: {'ConcurrencyToken': ?_avatarToken},
        ),
      );
      if (!mounted) return;
      setState(() {
        _hasAvatar = updated['hasAvatar'] == true || true;
        _avatarToken = updated['concurrencyToken'] as String?;
        _avatarBytes = bytes;
        _notice = 'Đã cập nhật ảnh đại diện.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarBusy || _busy || !_hasAvatar) return;
    setState(() {
      _avatarBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = objectOf(
        await widget.auth.request(
          '/api/v1/users/me/avatar/remove',
          method: 'POST',
          body: {'concurrencyToken': _avatarToken},
        ),
      );
      if (!mounted) return;
      setState(() {
        _hasAvatar = false;
        _avatarToken = updated['concurrencyToken'] as String?;
        _avatarBytes = null;
        _notice = 'Đã xóa ảnh đại diện.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _manageGoogleLink({required bool linked}) async {
    if (_googleBusy || _busy) return;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(linked ? 'Hủy liên kết Google?' : 'Liên kết Google'),
        content: SingleChildScrollView(
          child: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mật khẩu tài khoản hiện tại',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(linked ? 'Hủy liên kết' : 'Tiếp tục'),
          ),
        ],
      ),
    );
    final password = ctrl.text;
    ctrl.dispose();
    if (!mounted || confirmed != true || password.isEmpty) return;
    setState(() {
      _googleBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (linked) {
        await widget.auth.unlinkGoogleAccount(password);
      } else {
        await widget.auth.linkGoogleAccount(password);
      }
      await _loadAccountExtras();
      if (mounted) {
        setState(() {
          _notice = linked
              ? 'Đã hủy liên kết tài khoản Google.'
              : 'Đã liên kết tài khoản Google thành công.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signOut();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa thể đóng phiên. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.user;
    final textTheme = Theme.of(context).textTheme;
    const roleNames = {
      'STUDENT': 'Sinh viên',
      'LECTURER': 'Giảng viên',
      'SUPERVISOR': 'Giảng viên hướng dẫn',
      'DEPARTMENT_STAFF': 'Cán bộ bộ môn',
      'ADMIN': 'Quản trị viên',
    };
    final googleLogin = _externalLogins?.cast<Json?>().firstWhere(
      (row) =>
          textOf(row ?? const {}, 'provider', '').toUpperCase() == 'GOOGLE',
      orElse: () => null,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            if (widget.showHeading) ...[
              Semantics(
                header: true,
                child: Text('Tài khoản', style: textTheme.headlineMedium),
              ),
              const SizedBox(height: 14),
            ],
            NavyHeroCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.navyRaised,
                    backgroundImage: _avatarBytes != null
                        ? MemoryImage(_avatarBytes!)
                        : null,
                    child: _avatarBytes == null
                        ? const Icon(
                            Icons.person_outline,
                            size: 28,
                            color: AppColors.amber,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? '',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onNavy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.onNavyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _avatarBusy || _busy ? null : _uploadAvatar,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(_avatarBusy ? 'Đang xử lý…' : 'Đổi ảnh đại diện'),
                ),
                if (_hasAvatar)
                  TextButton.icon(
                    onPressed: _avatarBusy || _busy ? null : _removeAvatar,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Xóa ảnh'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vai trò', style: textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final role in user?.roles ?? const <String>[])
                        StatusBadge(
                          roleNames[role] ?? role,
                          tone: role == 'STUDENT'
                              ? StatusTone.primary
                              : role == 'LECTURER' || role == 'SUPERVISOR'
                              ? StatusTone.info
                              : StatusTone.neutral,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (_externalLogins != null) ...[
              const SizedBox(height: 14),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Đăng nhập bằng Google',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        StatusBadge(
                          googleLogin != null ? 'Đã liên kết' : 'Chưa liên kết',
                          tone: googleLogin != null
                              ? StatusTone.success
                              : StatusTone.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      googleLogin != null
                          ? textOf(
                              googleLogin,
                              'email',
                              'Tài khoản Google đã được liên kết.',
                            )
                          : 'Liên kết Google để đăng nhập nhanh hơn trên web và di động.',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _googleBusy || _busy
                          ? null
                          : () =>
                                _manageGoogleLink(linked: googleLogin != null),
                      child: Text(
                        _googleBusy
                            ? 'Đang xử lý…'
                            : googleLogin != null
                            ? 'Hủy liên kết Google'
                            : 'Liên kết Google',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _notice!,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              key: const Key('sign-out-button'),
              onPressed: _busy ? null : _signOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.dangerBorder),
              ),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI-PMS · Phiên bản 0.9.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
