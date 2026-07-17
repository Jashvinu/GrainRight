import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/satellite/farm_chat_message_model.dart';

void main() {
  group('FarmChatMessageDraft', () {
    test('serializes optional farm memory context', () {
      final createdAt = DateTime.utc(2026, 7, 3, 12, 30);
      final draft = FarmChatMessageDraft(
        role: 'farmer',
        source: 'status_chat',
        message: 'Leaves are yellow near the lower side.',
        language: 'en',
        growthStage: 'Vegetative',
        daysAfterSowing: 28,
        weatherSnapshot: const {'rain_24h_mm': 12.5},
        farmContext: const {
          'farm': {'name': 'Plot A'},
        },
        createdAt: createdAt,
      );

      expect(draft.toJson(), {
        'role': 'farmer',
        'source': 'status_chat',
        'message': 'Leaves are yellow near the lower side.',
        'language': 'en',
        'growthStage': 'Vegetative',
        'daysAfterSowing': 28,
        'weatherSnapshot': {'rain_24h_mm': 12.5},
        'farmContext': {
          'farm': {'name': 'Plot A'},
        },
        'createdAt': createdAt.toIso8601String(),
      });
    });
  });

  group('FarmChatMemoryEntry', () {
    test('parses backend snake case rows', () {
      final entry = FarmChatMemoryEntry.fromJson(const {
        'id': 'msg-1',
        'farm_id': 'farm-1',
        'farmer_phone': '9876543210',
        'farmer_id': 'FMR-1',
        'role': 'assistant',
        'source': 'ai_chat',
        'message': 'Check moisture before irrigation.',
        'language': 'en',
        'growth_stage': 'Flowering',
        'days_after_sowing': 48,
        'weather_snapshot': {'rain_7d_mm': 31},
        'farm_context': {'crop': 'ragi'},
        'created_at': '2026-07-03T12:30:00.000Z',
      });

      expect(entry.id, 'msg-1');
      expect(entry.farmId, 'farm-1');
      expect(entry.role, 'assistant');
      expect(entry.daysAfterSowing, 48);
      expect(entry.weatherSnapshot['rain_7d_mm'], 31);
      expect(entry.farmContext['crop'], 'ragi');
      expect(entry.createdAt, DateTime.parse('2026-07-03T12:30:00.000Z'));
    });
  });
}
