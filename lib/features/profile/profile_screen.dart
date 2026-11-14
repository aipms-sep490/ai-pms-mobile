import 'package:material_ui/material_ui.dart';

import '../../ui/app_theme.dart';
import '../auth/auth_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  String? _error;

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
      'DEPARTMENT_STAFF': 'Cán bộ bộ môn',
      'ADMIN': 'Quản trị viên',
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'KHÔNG GIAN CÁ NHÂN',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text('Tài khoản', style: textTheme.headlineLarge),
            ),
            const SizedBox(height: 36),
            const Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.primarySoft,
                child: Icon(
                  Icons.person_outline,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user?.fullName ?? '',
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              user?.email ?? '',
              style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vai trò'),
                  const SizedBox(height: 8),
                  Text(
                    user?.roles
                            .map((role) => roleNames[role] ?? role)
                            .join(' · ') ??
                        '',
                    style: textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const Key('sign-out-button'),
              onPressed: _busy ? null : _signOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
            const SizedBox(height: 24),
            const Text(
              'AI-PMS · Phiên bản 0.1.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
