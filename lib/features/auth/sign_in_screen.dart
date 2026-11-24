import 'package:material_ui/material_ui.dart';

import '../../core/api_client.dart';
import '../../ui/app_theme.dart';
import '../../ui/mobile_components.dart';
import 'auth_controller.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _showPassword = false;
  bool _busy = false;
  bool _googleBusy = false;
  String? _error;

  bool get _anyBusy => _busy || _googleBusy;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_anyBusy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn(_email.text, _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa thể đăng nhập. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGoogle() async {
    if (_anyBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithGoogle();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa thể đăng nhập bằng Google. Bạn có thể đăng nhập bằng mật khẩu.',
        );
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  NavyHeroCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.layers_outlined,
                                color: AppColors.onNavy,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI-PMS',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                      color: AppColors.onNavy,
                                    ),
                                  ),
                                  Text(
                                    'Quản lý tiến độ đồ án học phần',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.onNavyMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Semantics(
                          header: true,
                          child: const Text(
                            'Chào mừng trở lại',
                            style: TextStyle(
                              fontSize: 24,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: AppColors.onNavy,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Theo dõi tiến độ, báo cáo, trao đổi và hỗ trợ AI đồng bộ cùng bản web.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.onNavyMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.cardShadow,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Sử dụng tài khoản được trường cấp.',
                            style: textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const Key('email-field'),
                            controller: _email,
                            enabled: !_anyBusy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'ban@truong.edu.vn',
                              labelText: 'Email',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                            onFieldSubmitted: (_) =>
                                _passwordFocus.requestFocus(),
                            validator: (value) =>
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Nhập địa chỉ email hợp lệ.',
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const Key('password-field'),
                            controller: _password,
                            focusNode: _passwordFocus,
                            enabled: !_anyBusy,
                            obscureText: !_showPassword,
                            autofillHints: const [AutofillHints.password],
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: 'Nhập mật khẩu',
                              labelText: 'Mật khẩu',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'Ẩn mật khẩu'
                                    : 'Hiện mật khẩu',
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: _anyBusy
                                    ? null
                                    : () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (value) => value == null || value.isEmpty
                                ? 'Nhập mật khẩu tài khoản của bạn.'
                                : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.dangerSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.dangerBorder,
                                ),
                              ),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w500,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            key: const Key('sign-in-button'),
                            onPressed: _anyBusy ? null : _submit,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_busy) ...[
                                  const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onNavy,
                                      semanticsLabel: 'Đang đăng nhập',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Flexible(
                                  child: Text(
                                    _busy ? 'Đang đăng nhập…' : 'Đăng nhập',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (!_busy) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.arrow_forward, size: 18),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'hoặc',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            key: const Key('google-sign-in-button'),
                            onPressed: _anyBusy ? null : _submitGoogle,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_googleBusy) ...[
                                  const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      semanticsLabel: 'Đang đăng nhập Google',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ] else ...[
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.infoBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppColors.infoBorder,
                                      ),
                                    ),
                                    child: const Text(
                                      'G',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: AppColors.info,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Flexible(
                                  child: Text(
                                    _googleBusy
                                        ? 'Đang xác thực Google…'
                                        : 'Tiếp tục với Google',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 18,
                        color: AppColors.success,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dùng cùng tài khoản sinh viên hoặc giảng viên với AI-PMS trên web.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
