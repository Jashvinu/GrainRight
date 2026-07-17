import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/satellite/farm_chat_message_model.dart';
import 'package:kalsubai_farms/screens/farmer_ai_chat_screen.dart';

void main() {
  test('AI chat visible memory excludes farm status updates', () {
    const aiQuestion = FarmChatMemoryEntry(
      id: 'ai-1',
      farmId: 'farm-1',
      role: 'farmer',
      source: 'ai_chat',
      message: 'Should I irrigate today?',
    );
    const aiAnswer = FarmChatMemoryEntry(
      id: 'ai-2',
      farmId: 'farm-1',
      role: 'assistant',
      source: 'ai_chat',
      message: 'Check soil moisture first.',
    );
    const statusUpdate = FarmChatMemoryEntry(
      id: 'status-1',
      farmId: 'farm-1',
      role: 'farmer',
      source: 'status_chat',
      message: 'Leaves are yellow near the lower patch.',
    );
    const emptyAiMessage = FarmChatMemoryEntry(
      id: 'ai-empty',
      farmId: 'farm-1',
      role: 'assistant',
      source: 'ai_chat',
      message: '   ',
    );

    expect(isVisibleAiAssistantMemory(aiQuestion), isTrue);
    expect(isVisibleAiAssistantMemory(aiAnswer), isTrue);
    expect(isVisibleAiAssistantMemory(statusUpdate), isFalse);
    expect(isVisibleAiAssistantMemory(emptyAiMessage), isFalse);
  });
}
