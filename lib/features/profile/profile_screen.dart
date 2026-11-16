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
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Semantics(
              header: true,
              child: Text('Tài khoản', style: textTheme.headlineMedium),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primarySoft,
                  child: Icon(
                    Icons.person_outline,
                    size: 26,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.fullName ?? '', style: textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(user?.email ?? '', style: textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vai trò', style: textTheme.bodyMedium),
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
              'AI-PMS · Phiên bản 0.3.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
