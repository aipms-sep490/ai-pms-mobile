import 'package:material_ui/material_ui.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/ai/ai_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/workspace/inbox_screen.dart';
import 'features/workspace/project_screen.dart';
import 'features/workspace/tasks_screen.dart';
import 'features/workspace/workspace_models.dart';
import 'ui/app_theme.dart';

class AiPmsApp extends StatelessWidget {
  const AiPmsApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => MaterialApp(
        // Reset every pushed detail route when identity/role changes, including logout.
        key: ValueKey('${auth.user?.id}/${auth.user?.roles.join(',')}'),
        title: 'AI-PMS',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: switch (auth.status) {
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
  int _revision = 0;
  final _visited = <int>{0};
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _revision++);
  }

  void _select(int index) {
    FocusScope.of(context).unfocus();
    final animate =
        (_selected - index).abs() == 1 &&
        !MediaQuery.disableAnimationsOf(context);
    setState(() {
      _visited.add(index);
      _selected = index;
    });
    if (!_pages.hasClients) return;
    if (animate) {
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.auth.user?.roles.contains('STUDENT') ?? false;
    final titles = student
        ? const ['Tổng quan', 'Đồ án', 'Công việc', 'Hộp thư', 'Tài khoản']
        : const ['Tổng quan', 'Tài khoản'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_selected],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (student) ...[
            IconButton(
              tooltip: 'Trò chuyện',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChatInboxScreen(auth: widget.auth),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Trợ lý AI',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AiHomeScreen(auth: widget.auth),
                ),
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: PageView(
          key: const Key('workspace-pages'),
          controller: _pages,
          physics: MediaQuery.viewInsetsOf(context).bottom > 0
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          onPageChanged: (index) => setState(() {
            _selected = index;
            _visited.add(index);
          }),
          children: [
            _RetainedPage(
              child: DashboardScreen(
                key: ValueKey('dashboard/$_revision'),
                auth: widget.auth,
                showHeading: false,
                onOpenProject: student ? () => _select(1) : null,
                onOpenDeadline: student
                    ? (deadline) => openEntity(
                        context,
                        widget.auth,
                        EntityTarget(
                          deadline.isMilestone ? 'MILESTONE' : 'TASK',
                          deadline.id,
                        ),
                        _changed,
                      )
                    : null,
              ),
            ),
            if (student) ...[
              _RetainedPage(
                child: _visited.contains(1)
                    ? ProjectScreen(
                        auth: widget.auth,
                        onChanged: _changed,
                        revision: _revision,
                        showHeading: false,
                      )
                    : const SizedBox.shrink(),
              ),
              _RetainedPage(
                child: _visited.contains(2)
                    ? TasksScreen(
                        auth: widget.auth,
                        onChanged: _changed,
                        revision: _revision,
                        showHeading: false,
                      )
                    : const SizedBox.shrink(),
              ),
              _RetainedPage(
                child: _visited.contains(3)
                    ? InboxScreen(
                        auth: widget.auth,
                        onChanged: _changed,
                        revision: _revision,
                        showHeading: false,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
            _RetainedPage(
              child: ProfileScreen(auth: widget.auth, showHeading: false),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selected,
          onDestinationSelected: _select,
          height: 76,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              label: 'Tổng quan',
            ),
            if (student) ...[
              const NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                label: 'Đồ án',
              ),
              const NavigationDestination(
                icon: Icon(Icons.check_box_outlined),
                label: 'Công việc',
              ),
              const NavigationDestination(
                icon: Icon(Icons.inbox_outlined),
                label: 'Hộp thư',
              ),
            ],
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Tài khoản',
            ),
          ],
        ),
      ),
    );
  }
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({required this.child});
  final Widget child;
  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
