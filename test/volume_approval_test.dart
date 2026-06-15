import 'package:agent_dance/utils/volume_approval_listener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('音量+ 按一次批准', () {
    expect(resolveVolumePressCount(1), ApprovalVolumeResult.approve);
  });

  test('音量+ 连按两次拒绝', () {
    expect(resolveVolumePressCount(2), ApprovalVolumeResult.deny);
    expect(resolveVolumePressCount(3), ApprovalVolumeResult.deny);
  });
}
