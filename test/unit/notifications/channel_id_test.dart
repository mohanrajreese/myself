import 'package:fitbuddy/core/notifications/local_notification_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each chosen sound has its own stable channel; the default keeps the versioned id', () {
    expect(channelIdFor('hydration'), 'hydration_v1');
    final a = channelIdFor('hydration', soundUri: 'content://a');
    expect(a, startsWith('hydration_s'));
    expect(channelIdFor('hydration', soundUri: 'content://a'), a);
    expect(channelIdFor('hydration', soundUri: 'content://b'), isNot(a));
    expect(channelKeyOf(a), 'hydration');
  });
}
