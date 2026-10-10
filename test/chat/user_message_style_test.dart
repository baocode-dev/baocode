import 'package:baocode/chat/user_message_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => UserMessageStyle.current.value = UserMessageStyle.sticky);

  test('settings.json\'s values: sticky; unset or else is bubble, which is '
      'not written', () {
    expect(UserMessageStyle.parse(null), UserMessageStyle.bubble);
    expect(UserMessageStyle.parse('round'), UserMessageStyle.bubble);
    expect(UserMessageStyle.parse('sticky'), UserMessageStyle.sticky);
    expect(UserMessageStyle.bubble.setting, isNull);
    expect(UserMessageStyle.sticky.setting, 'sticky');
  });

  test('follows the settings as they change', () {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    Object? value = 'sticky';
    UserMessageStyle.follow(changes, () => value);
    expect(UserMessageStyle.current.value, UserMessageStyle.sticky);
    value = null;
    changes.value++;
    expect(UserMessageStyle.current.value, UserMessageStyle.bubble);
  });
}
