import 'package:material_ui/material_ui.dart';

import 'core/realtime_hub_manager.dart';
import 'features/ai/ai_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/supervisor/supervisor_screens.dart';
import 'features/workspace/inbox_screen.dart';
import 'features/workspace/project_screen.dart';
import 'features/workspace/tasks_screen.dart';
import 'features/workspace/workspace_models.dart';
import 'ui/app_theme.dart';

class AiPmsApp extends StatefulWidget {
  const AiPmsApp({
    super.key,
    required this.auth,
    this.realtime,
    this.enableRealtime = false,
  });

  final AuthController auth;
  final RealtimeHubManager? realtime;
  final bool enableRealtime;

  @override
  State<AiPmsApp> createState() => _AiPmsAppState();
}

class _AiPmsAppState extends State<AiPmsApp> with WidgetsBindingObserver {
  RealtimeHubManager? _ownedRealtime;

  RealtimeHubManager? get _realtime => widget.realtime ?? _ownedRealtime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.realtime == null && widget.enableRealtime) {
      _ownedRealtime = RealtimeHubManager(auth: widget.auth);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hub = _realtime;
    if (hub == null) return;
    if (state == AppLifecycleState.resumed) {
      hub.setAppPaused(false);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      hub.setAppPaused(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ownedRealtime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) => MaterialApp(
        // Reset every pushed detail route when identity/role changes, including logout.
        key: ValueKey(
          '${widget.auth.user?.id}/${widget.auth.user?.roles.join(',')}',
        ),
        title: 'AI-PMS',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: switch (widget.auth.status) {
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
          SessionStatus.anonymous => SignInScreen(auth: widget.auth),
          SessionStatus.authenticated => _Workspace(
            key: ValueKey(widget.auth.user!.id),
            auth: widget.auth,
            realtime: _realtime,
          ),
        },
      ),
    );
  }
}

enum _ShellMode { student, lecturer, basic }

class _Workspace extends StatefulWidget {
  const _Workspace({super.key, required this.auth, this.realtime});

  final AuthController auth;
  final RealtimeHubManager? realtime;

  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  int _selected = 0;
  int _revision = 0;
  final _visited = <int>{0};
  final _pages = PageController();

  _ShellMode get _mode {
    final user = widget.auth.user;
    if (user == null) return _ShellMode.basic;
    if (user.isStudent) return _ShellMode.student;
    if (user.isLecturer) return _ShellMode.lecturer;
    return _ShellMode.basic;
  }

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

  Widget _inboxIcon() {
    final hub = widget.realtime;
    if (hub == null) return const Icon(Icons.inbox_outlined);
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final count = hub.unreadNotificationBump;
        return Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.inbox_outlined),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final hasCollab = mode == _ShellMode.student || mode == _ShellMode.lecturer;
    final titles = switch (mode) {
      _ShellMode.student => const [
        'Tổng quan',
        'Đồ án',
        'Công việc',
        'Hộp thư',
        'Tài khoản',
      ],
      _ShellMode.lecturer => const [
        'Tổng quan',
        'Đồ án',
        'Hộp thư',
        'Tài khoản',
      ],
      _ShellMode.basic => const ['Tổng quan', 'Tài khoản'],
    };

    final pages = switch (mode) {
      _ShellMode.student => [
        _RetainedPage(
          child: DashboardScreen(
            key: ValueKey('dashboard/$_revision'),
            auth: widget.auth,
            showHeading: false,
            onChanged: _changed,
            onOpenProject: () => _select(1),
            onOpenDeadline: (deadline) => openEntity(
              context,
              widget.auth,
              EntityTarget(
                deadline.isMilestone ? 'MILESTONE' : 'TASK',
                deadline.id,
              ),
              _changed,
            ),
          ),
        ),
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
                  realtime: widget.realtime,
                  onChanged: _changed,
                  revision: _revision,
                  showHeading: false,
                )
              : const SizedBox.shrink(),
        ),
        _RetainedPage(
          child: ProfileScreen(auth: widget.auth, showHeading: false),
        ),
      ],
      _ShellMode.lecturer => [
        _RetainedPage(
          child: SupervisorDashboardScreen(
            key: ValueKey('sup-dashboard/$_revision'),
            auth: widget.auth,
            onChanged: _changed,
            onOpenProjects: () => _select(1),
            revision: _revision,
            showHeading: false,
          ),
        ),
        _RetainedPage(
          child: _visited.contains(1)
              ? SupervisorProjectsScreen(
                  auth: widget.auth,
                  onChanged: _changed,
                  revision: _revision,
                  showHeading: false,
                )
              : const SizedBox.shrink(),
        ),
        _RetainedPage(
          child: _visited.contains(2)
              ? InboxScreen(
                  auth: widget.auth,
                  realtime: widget.realtime,
                  onChanged: _changed,
                  revision: _revision,
                  showHeading: false,
                )
              : const SizedBox.shrink(),
        ),
        _RetainedPage(
          child: ProfileScreen(auth: widget.auth, showHeading: false),
        ),
      ],
      _ShellMode.basic => [
        _RetainedPage(
          child: DashboardScreen(
            key: ValueKey('dashboard/$_revision'),
            auth: widget.auth,
            showHeading: false,
          ),
        ),
        _RetainedPage(
          child: ProfileScreen(auth: widget.auth, showHeading: false),
        ),
      ],
    };

    final destinations = switch (mode) {
      _ShellMode.student => [
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          label: 'Tổng quan',
        ),
        const NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          label: 'Đồ án',
        ),
        const NavigationDestination(
          icon: Icon(Icons.check_box_outlined),
          label: 'Công việc',
        ),
        NavigationDestination(icon: _inboxIcon(), label: 'Hộp thư'),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Tài khoản',
        ),
      ],
      _ShellMode.lecturer => [
        const NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          label: 'Tổng quan',
        ),
        const NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          label: 'Đồ án',
        ),
        NavigationDestination(icon: _inboxIcon(), label: 'Hộp thư'),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Tài khoản',
        ),
      ],
      _ShellMode.basic => const [
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          label: 'Tổng quan',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Tài khoản',
        ),
      ],
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_selected.clamp(0, titles.length - 1)],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (hasCollab) ...[
            IconButton(
              tooltip: 'Trò chuyện',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChatInboxScreen(
                    auth: widget.auth,
                    realtime: widget.realtime,
                  ),
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
          children: pages,
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _selected.clamp(0, destinations.length - 1),
          onDestinationSelected: _select,
          height: 76,
          destinations: destinations,
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
