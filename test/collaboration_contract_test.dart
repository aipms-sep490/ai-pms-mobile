import 'package:ai_pms_mobile/core/api_client.dart';
import 'package:ai_pms_mobile/features/chat/chat_controller.dart';
import 'package:ai_pms_mobile/features/ai/ai_screen.dart';
import 'package:ai_pms_mobile/features/meetings/video_meeting_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'chat preserves 64-bit ids and replaces edited messages across pages',
    () {
      final rows = mergeChatMessages(
        [
          {
            'id': '9223372036854775806',
            'sequence': '9007199254740993',
            'body': 'old',
          },
        ],
        [
          {
            'id': '9223372036854775807',
            'sequence': '9007199254740994',
            'body': 'next',
          },
          {
            'id': '9223372036854775806',
            'sequence': '9007199254740993',
            'body': 'edited',
          },
        ],
      );
      expect(rows.map((m) => m['body']), ['edited', 'next']);
      expect(chatId(rows.last), '9223372036854775807');
      expect(() => chatId({'id': 9007199254740993}), throwsFormatException);
      expect(
        () => ChatPage({'items': [], 'hasMore': true}),
        throwsFormatException,
      );
      expect(
        aiEvidenceTarget({'sourceType': 'TASK', 'sourceId': 'TASK-42'})?.id,
        42,
      );
      expect(
        aiEvidenceTarget({'sourceType': 'MEETING', 'sourceId': 'MTG-7'})?.type,
        'MEETING',
      );
      expect(
        aiEvidenceTarget({'sourceType': 'TASK', 'sourceId': 'MTG-7'}),
        isNull,
      );
      expect(
        aiEvidenceTarget({'sourceType': 'TASK', 'sourceId': '../42'}),
        isNull,
      );
    },
  );
  test(
    'video rejects expired and unsafe credentials before starting media',
    () {
      final valid = <String, dynamic>{
        'provider': 'LIVEKIT',
        'serverUrl': 'wss://video.example.test',
        'accessToken': 'test-only',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'capabilities': {'publishAudio': true, 'publishVideo': false},
      };
      final credential = VideoCredential(valid);
      expect(credential.publishAudio, isTrue);
      expect(credential.publishVideo, isFalse);
      for (final change in [
        {'serverUrl': 'http://video.example.test'},
        {'serverUrl': 'wss://user:password@video.example.test'},
        {'expiresAt': '2020-01-01T00:00:00Z'},
        {'provider': 'UNKNOWN'},
      ]) {
        expect(
          () => VideoCredential({...valid, ...change}),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
}
