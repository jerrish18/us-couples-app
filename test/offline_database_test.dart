import 'package:drift/native.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/local_database.dart';

void main() {
  test('Queued messages and separate receipts survive closing and reopening SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('us-offline-test-');
    final file = File('${dir.path}/cache.sqlite');
    final first = LocalDatabase.forTest(NativeDatabase(file));
    await first.enqueue('messages', {
      'id': 'offline',
      'couple_id': 'couple',
      'body': 'Saved without a connection',
    });
    await first.replaceRows('message_states', [
      {'message_id': 'one', 'user_id': 'partner', 'read_at': 'today'},
      {'message_id': 'two', 'user_id': 'partner', 'read_at': 'today'},
    ]);
    await first.replaceRows('poll_votes', [
      {'poll_id': 'one', 'user_id': 'partner', 'choice': 0},
      {'poll_id': 'two', 'user_id': 'partner', 'choice': 1},
    ]);
    await first.close();
    final reopened = LocalDatabase.forTest(NativeDatabase(file));
    expect((await reopened.pending()).single.taskId, 'offline');
    expect((await reopened.readRows('message_states')).length, 2);
    expect((await reopened.readRows('poll_votes')).length, 2);
    await reopened.clear();
    await reopened.close();
    await dir.delete(recursive: true);
  });
  test(
    'Queue survives cache replacement and removes only acknowledged messages',
    () async {
      final db = LocalDatabase.forTest(NativeDatabase.memory());
      await db.enqueue('messages', {
        'id': 'one',
        'couple_id': 'couple',
        'body': 'waiting',
      });
      await db.enqueue('messages', {
        'id': 'two',
        'couple_id': 'couple',
        'body': 'also waiting',
      });
      await db.replaceRows('messages', [
        {'id': 'server-message', 'couple_id': 'couple', 'body': 'received'},
      ]);
      expect((await db.pending()).map((r) => r.taskId), ['one', 'two']);
      await db.complete('one');
      expect((await db.pending()).single.taskId, 'two');
      expect((await db.readRows('messages')).single['body'], 'received');
      await db.clear();
      expect(await db.pending(), isEmpty);
      expect(await db.readRows('messages'), isEmpty);
      await db.close();
    },
  );
}
