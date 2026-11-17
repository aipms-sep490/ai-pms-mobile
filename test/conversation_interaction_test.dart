import 'dart:async';

import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/ai/ai_screen.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/chat/chat_screen.dart';
import 'package:ai_pms_mobile/features/chat/composer_exit_guard.dart';
import 'package:ai_pms_mobile/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

Future<AuthController> _auth(
  Future<http.Response> Function(http.Request)? handler,
) async {
  final api = ApiClient(
    origin: 'https://api.example.test',
    client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) return json(loginFixture());
      if (request.url.path.endsWith('/me')) return json(user);
      if (handler != null) return handler(request);
      if (request.url.path.endsWith('/messages')) {
        return json({'items': [], 'hasMore': false, 'nextCursor': null});
      }
      return json({
        'id': '31',
        'title': 'Hội thoại kiểm thử',
        'canSend': true,
        'version': 1,
      });
    }),
  );
  final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
  addTearDown(auth.dispose);
  addTearDown(api.close);
  await auth.signIn('student@example.test', 'fixture');
  return auth;
}

Future<void> _open(WidgetTester tester, Widget screen) async {
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => screen),
            ),
            child: const Text('Mở hội thoại'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở hội thoại'));
  await tester.pumpAndSettle();
}

void main() {
  for (final ai in [true, false]) {
    testWidgets(
      '${ai ? 'AI' : 'chat'} back protects unsent draft and allows explicit discard',
      (tester) async {
        final auth = await _auth(null);
        await _open(
          tester,
          ai
              ? AssistantChatScreen(auth: auth)
              : ChatThreadScreen(auth: auth, id: '31'),
        );
        await tester.enterText(
          find.byType(TextField),
          'Bản đang soạn chưa gửi',
        );
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Bỏ tin đang soạn?'), findsOneWidget);
        await tester.tap(find.text('Tiếp tục soạn'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextField, 'Bản đang soạn chưa gửi'),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bỏ bản soạn'));
        await tester.pumpAndSettle();
        expect(find.text('Mở hội thoại'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('context-only composer requires explicit discard', (
    tester,
  ) async {
    final text = TextEditingController();
    addTearDown(text.dispose);
    await _open(
      tester,
      ComposerExitGuard(
        controller: text,
        sending: false,
        hasContext: true,
        child: Scaffold(appBar: AppBar(title: const Text('Tệp đang soạn'))),
      ),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Bỏ tin đang soạn?'), findsOneWidget);
  });

  testWidgets(
    'pending chat send blocks Back then allows leaving after success',
    (tester) async {
      final response = Completer<http.Response>();
      var writes = 0;
      final auth = await _auth((request) async {
        if (request.url.path.endsWith('/messages')) {
          if (request.method == 'POST') {
            writes++;
            return response.future;
          }
          return json({'items': [], 'hasMore': false, 'nextCursor': null});
        }
        return json({
          'id': '31',
          'title': 'Hội thoại kiểm thử',
          'canSend': true,
          'version': 1,
        });
      });
      await _open(tester, ChatThreadScreen(auth: auth, id: '31'));
      await tester.enterText(find.byType(TextField), 'Tin đang gửi');
      await tester.tap(find.byTooltip('Gửi tin nhắn'));
      await tester.pump();
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatThreadScreen), findsOneWidget);
      expect(
        find.text('Đang gửi. Vui lòng chờ kết quả trước khi rời hội thoại.'),
        findsOneWidget,
      );
      expect(writes, 1);
      response.complete(json({}));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Mở hội thoại'), findsOneWidget);
      expect(find.text('Bỏ tin đang soạn?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new conversation sheet scrolls in short landscape with large type',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(812, 375));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final auth = await _auth(null);
      await _open(tester, ChatInboxScreen(auth: auth));
      await tester.tap(find.byTooltip('Cuộc trò chuyện mới'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Chat nhóm / đồ án'));
      expect(find.text('Chat nhóm / đồ án').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('chat edit fits long text above a landscape keyboard', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(812, 375));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(() => tester.view.viewInsets = const FakeViewPadding());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => ChatEditDialog(
                  initial: List.filled(30, 'Nội dung kiểm thử dài.').join('\n'),
                ),
              ),
              child: const Text('Sửa'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Lưu').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
