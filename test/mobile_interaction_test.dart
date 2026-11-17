import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/features/workspace/inbox_screen.dart';
import 'package:ai_pms_mobile/ui/remote_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

void main() {
  testWidgets(
    'Inbox category controls survive a denied category at small width and large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      var notificationRequests = 0;
      var invitationRequests = 0;
      final api = ApiClient(
        origin: 'https://api.example.test',
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/v1/auth/login':
              return json(loginFixture());
            case '/api/v1/auth/me':
              return json(user);
            case '/api/v1/notifications':
              notificationRequests++;
              return json(pageFixture([]));
            case '/api/v1/teams/invitations':
              invitationRequests++;
              return json({'message': 'Forbidden'}, 403);
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
        MaterialApp(
          home: Scaffold(
            body: InboxScreen(auth: auth, onChanged: () {}, showHeading: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(notificationRequests, 1);

      final invites = find.text('Lời mời nhóm');
      await tester.ensureVisible(invites);
      await tester.tap(invites);
      await tester.pumpAndSettle();

      expect(invitationRequests, 1);
      expect(find.byType(Notice), findsOneWidget);
      // A denied response clears stale content, but the category rail remains
      // available so the student can leave the failed category.
      final notifications = find.text('Thông báo');
      expect(notifications, findsOneWidget);
      await tester.ensureVisible(notifications);
      await tester.tap(notifications);
      await tester.pumpAndSettle();

      expect(notificationRequests, 2);
      expect(find.byType(Notice), findsNothing);
      expect(find.text('Chưa có thông báo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
