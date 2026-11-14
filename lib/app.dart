import 'package:material_ui/material_ui.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/profile/profile_screen.dart';
import 'ui/app_theme.dart';

class AiPmsApp extends StatelessWidget {
  const AiPmsApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI-PMS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => switch (auth.status) {
          SessionStatus.loading => const Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Đang mở không gian của bạn…'),
                  ],
                ),
              ),
            ),
          ),
          SessionStatus.anonymous => SignInScreen(auth: auth),
          SessionStatus.authenticated => _Workspace(
            key: ValueKey(auth.user!.id),
            auth: auth,
          ),
        },
      ),
    );
  }
}

class _Workspace extends StatefulWidget {
  const _Workspace({super.key, required this.auth});

  final AuthController auth;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selected,
          children: [
            DashboardScreen(auth: widget.auth),
            ProfileScreen(auth: widget.auth),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selected,
          onDestinationSelected: (index) => setState(() => _selected = index),
          height: 76,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              label: 'Tổng quan',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Tài khoản',
            ),
          ],
        ),
      ),
    );
  }
}
