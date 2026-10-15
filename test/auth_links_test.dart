import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/auth_links.dart';
import 'package:us/core/space.dart';

void main() {
  test('Only the registered app callback can establish a session', () {
    expect(
      AuthLinks.accepts(
        Uri.parse('com.jerrish18.us://login-callback?code=one'),
      ),
      isTrue,
    );
    expect(
      AuthLinks.accepts(
        Uri.parse('https://example.com/login-callback?code=one'),
      ),
      isFalse,
    );
    expect(
      AuthLinks.accepts(Uri.parse('com.jerrish18.us://other?code=one')),
      isFalse,
    );
  });
  test('Realtime keys keep both people’s receipts and poll votes distinct', () {
    expect(
      UsSpace.rowKey('message_states', {'message_id': 'one', 'user_id': 'a'}),
      isNot(
        UsSpace.rowKey('message_states', {'message_id': 'one', 'user_id': 'b'}),
      ),
    );
    expect(
      UsSpace.rowKey('poll_votes', {'poll_id': 'one', 'user_id': 'a'}),
      'one:a',
    );
    expect(UsSpace.rowKey('profiles', {'user_id': 'a'}), 'a');
  });
}
