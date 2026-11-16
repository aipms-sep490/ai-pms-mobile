import 'package:ai_pms_mobile/app.dart';
import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/ai/ai_screen.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/ui/mobile_components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

Finder _appBarTitle(String value) =>
    find.descendant(of: find.byType(AppBar).first, matching: find.text(value));

void main() {
  testWidgets('AI composer and options fit landscape with keyboard open', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(812, 375));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Widget test view uses DPR 3; 732 physical px equals a 244dp keyboard.
    tester.view.viewInsets = const FakeViewPadding(bottom: 732);
    addTearDown(() => tester.view.viewInsets = const FakeViewPadding());

    final api = ApiClient(
      origin: 'https://api.example.test',
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/v1/auth/login':
            return json(loginFixture());
          case '/api/v1/auth/me':
            return json(user);
          default:
            return json({}, 404);
        }
      }),
    );
    final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
    addTearDown(auth.dispose);
    addTearDown(api.close);
    await auth.signIn('student@example.test', 'fixture');

    await tester.pumpWidget(
      MaterialApp(home: AssistantChatScreen(auth: auth, projectId: 1)),
    );
    await tester.pumpAndSettle();

    final options = find.byTooltip('Tùy chọn');
    final send = find.byTooltip('Gửi câu hỏi');
    final attach = find.byTooltip('Đính kèm tài liệu cho AI');
    expect(options, findsOneWidget);
    expect(send, findsOneWidget);
    expect(attach, findsOneWidget);
    expect(tester.getRect(options).bottom, lessThanOrEqualTo(375 - 244));
    expect(tester.getRect(send).bottom, lessThanOrEqualTo(375 - 244));
    expect(tester.getRect(attach).bottom, lessThanOrEqualTo(375 - 244));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-text category rails scroll and preserve tap selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final selected = ValueNotifier('Tất cả');
    addTearDown(selected.dispose);
    const labels = ['Tất cả', 'Đang làm', 'Quá hạn', 'Bị chặn', 'Hoàn tất'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<String>(
                valueListenable: selected,
                builder: (context, value, _) => HorizontalChoices(
                  children: [
                    for (final label in labels)
                      ChoiceChip(
                        label: Text(label),
                        selected: value == label,
                        onSelected: (_) => selected.value = label,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final rail = find.byType(HorizontalChoices);
    final lastChip = find.ancestor(
      of: find.text('Hoàn tất'),
      matching: find.byType(ChoiceChip),
    );
    expect(
      tester.getSize(find.byType(ChoiceChip).first).height,
      greaterThanOrEqualTo(48),
    );
    await tester.drag(
      find.descendant(of: rail, matching: find.byType(SingleChildScrollView)),
      const Offset(-1000, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Hoàn tất')).overlaps(tester.getRect(rail)),
      isTrue,
    );
    await tester.tap(find.text('Hoàn tất'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(lastChip).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small phone keyboard and large text keep sign-in and tab navigation usable with reduced motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final api = ApiClient(
        origin: 'https://api.example.test',
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/v1/auth/login':
              return json(loginFixture());
            case '/api/v1/auth/me':
              return json(user);
            case '/api/v1/dashboards/student':
              return json(dashboard());
            default:
              if (request.url.path == '/api/v1/tasks/project/1') {
                return json(pageFixture([]));
              }
              if (request.url.path == '/api/v1/projects/1/execution-actions') {
                return json({
                  'resourceType': 'PROJECT',
                  'resourceId': 1,
                  'projectId': 1,
                  'actions': [],
                });
              }
              return json({}, 404);
          }
        }),
      );
      final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
      addTearDown(auth.dispose);
      addTearDown(api.close);

      await auth.restore();
      expect(auth.status, SessionStatus.anonymous);
      await tester.pumpWidget(AiPmsApp(auth: auth));
      await tester.pumpAndSettle();

      final email = find.byKey(const Key('email-field'));
      final password = find.byKey(const Key('password-field'));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        email,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(email, 'mobile-smoke@example.test');
      await tester.scrollUntilVisible(
        password,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(password, 'fixture-password');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();

      final signIn = find.byKey(const Key('sign-in-button'));
      await tester.scrollUntilVisible(
        signIn,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(signIn).bottom, lessThanOrEqualTo(640 - 260));
      await tester.tap(signIn);
      await tester.pumpAndSettle();
      expect(auth.status, SessionStatus.authenticated);
      expect(_appBarTitle('Tổng quan'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Hệ thống quản lý tiến trình đồ án'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Hệ thống quản lý tiến trình đồ án'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Simulate closing the keyboard before using the primary navigation.
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đồ án').last);
      await tester.pumpAndSettle();
      expect(_appBarTitle('Đồ án'), findsOneWidget);

      // Main-page swipe remains an optional shortcut; taps stay available.
      await tester.binding.setSurfaceSize(const Size(375, 812));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scaffold).first, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(_appBarTitle('Công việc'), findsOneWidget);
      final search = find.widgetWithText(TextField, 'Tìm công việc');
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.enterText(search, 'retained search');
      final searchController = tester.widget<TextField>(search).controller!;
      final editable = find.descendant(
        of: search,
        matching: find.byType(EditableText),
      );
      final searchFocus = tester.widget<EditableText>(editable).focusNode;
      expect(searchFocus.hasFocus, isTrue);
      await tester.tap(find.text('Đồ án').last);
      await tester.pumpAndSettle();
      expect(_appBarTitle('Đồ án'), findsOneWidget);
      expect(searchFocus.hasFocus, isFalse);
      expect(searchController.text, 'retained search');
      await tester.tap(find.text('Tài khoản').last);
      await tester.pumpAndSettle();
      expect(find.text('mobile-smoke@example.test'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
