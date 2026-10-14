import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/local_database.dart';

void main(){
 test('Queue survives cache replacement and removes only acknowledged messages',() async {
  final db=LocalDatabase.forTest(NativeDatabase.memory());
  await db.enqueue('messages',{'id':'one','couple_id':'couple','body':'waiting'});
  await db.enqueue('messages',{'id':'two','couple_id':'couple','body':'also waiting'});
  await db.replaceRows('messages',[{'id':'server-message','couple_id':'couple','body':'received'}]);
  expect((await db.pending()).map((r)=>r.taskId),['one','two']);
  await db.complete('one');
  expect((await db.pending()).single.taskId,'two');
  expect((await db.readRows('messages')).single['body'],'received');
  await db.clear();expect(await db.pending(),isEmpty);expect(await db.readRows('messages'),isEmpty);await db.close();
 });
}
