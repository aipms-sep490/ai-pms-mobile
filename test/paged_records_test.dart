import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/core/refresh_token_store.dart';
import 'package:ai_pms_mobile/features/auth/auth_controller.dart';
import 'package:ai_pms_mobile/ui/paged_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mobile_fixtures.dart';

void main() {
  testWidgets(
    'refresh stays on the surviving page after its last row disappears',
    (tester) async {
      var removed = false;
      final requestedPages = <int>[];
      final api = ApiClient(
        origin: 'https://api.example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return json(loginFixture());
          }
          if (request.url.path == '/api/v1/auth/me') return json(user);
          final page = int.parse(request.url.queryParameters['page']!);
          requestedPages.add(page);
          return json(
            pageFixture(
              removed && page == 2
                  ? []
                  : [
                      {'id': page, 'title': 'Record $page'},
                    ],
              page: page,
              pages: removed ? 1 : 2,
              total: removed ? 1 : 21,
            ),
          );
        }),
      );
      final auth = AuthController(api: api, storage: MemoryRefreshTokenStore());
      addTearDown(auth.dispose);
      addTearDown(api.close);
      await auth.signIn('student@example.test', 'fixture');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedRecords(
              auth: auth,
              path: '/api/v1/records',
              title: 'Danh sách',
              emptyText: 'Trống',
              item: (_, row, refresh) => TextButton(
                onPressed: () async {
                  removed = true;
                  await refresh();
                },
                child: Text(row['title'] as String),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Trang sau'));
      await tester.pumpAndSettle();
      expect(find.text('Record 2'), findsOneWidget);

      await tester.tap(find.text('Record 2'));
      await tester.pumpAndSettle();
      expect(find.text('Record 1'), findsOneWidget);
      expect(requestedPages, [1, 2, 2, 1]);

      requestedPages.clear();
      await tester.tap(find.byTooltip('Làm mới danh sách'));
      await tester.pumpAndSettle();
      expect(requestedPages, [1]);
      expect(find.text('Trang 1/1 · 1 mục'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
