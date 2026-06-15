import 'package:agent_dance/agents/models/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChatState 枚举包含 reasoning 状态', () {
    expect(ChatState.values, contains(ChatState.reasoning));
  });
}
