import 'package:ai_pms_mobile/features/workspace/workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mobile_fixtures.dart';

void main() {
  test('task authority requires matching resource, state and version', () {
    expect(TaskAccess(taskFixture(), capabilityFixture()).canChange, isTrue);
    expect(
      TaskAccess(taskFixture(), capabilityFixture(allowed: false)).canChange,
      isFalse,
    );
    expect(
      TaskAccess(
        taskFixture(),
        capabilityFixture(token: 'new-version'),
      ).canChange,
      isFalse,
    );
    expect(
      TaskAccess(taskFixture(), capabilityFixture(status: 'DONE')).canChange,
      isFalse,
    );
    expect(
      TaskAccess(taskFixture(), capabilityFixture(token: '')).canChange,
      isFalse,
    );
    expect(
      () => TaskAccess(taskFixture(), {
        ...capabilityFixture(),
        'resourceId': 999,
      }),
      throwsFormatException,
    );
    expect(taskTransitions('NEW_UNKNOWN_STATE'), isEmpty);
    expect(taskTransitions('TODO'), isNot(contains('DONE')));
  });

  test('pagination rejects malformed collections and resource ids', () {
    expect(PageData.fromJson(pageFixture([])).items, isEmpty);
    expect(
      () => PageData.fromJson({'items': [], 'page': 1}),
      throwsFormatException,
    );
    expect(
      () => PageData.fromJson(
        pageFixture([
          {'id': -1},
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => PageData.fromJson(
        pageFixture([
          {'id': '12'},
        ]),
      ),
      throwsFormatException,
    );
  });

  test(
    'links only accept explicit HTTP destinations and supported entities',
    () {
      expect(
        externalUri('https://meet.example.test/room')?.host,
        'meet.example.test',
      );
      for (final uri in [
        'javascript:alert(1)',
        'file:///private',
        'https://secret@host.test',
        '//host.test',
        'https:',
      ]) {
        expect(externalUri(uri), isNull, reason: uri);
      }
      expect(
        EntityTarget.fromNotification({
          'relatedEntityType': 'TASK',
          'relatedEntityId': 12,
        })?.id,
        12,
      );
      expect(
        EntityTarget.fromNotification({
          'relatedEntityType': 'UNKNOWN',
          'relatedEntityId': 12,
        }),
        isNull,
      );
      expect(
        EntityTarget.fromNotification({
          'relatedEntityType': 'TASK',
          'relatedEntityId': 0,
        }),
        isNull,
      );
      expect(
        EntityTarget.fromNotification({
          'relatedEntityType': 'TASK',
          'relatedEntityId': '12',
        }),
        isNull,
      );
      expect(displayDate('2026-11-16'), '16/11/2026');
    },
  );
}
