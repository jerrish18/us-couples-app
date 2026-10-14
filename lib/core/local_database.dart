import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

class CachedRows extends Table {
  TextColumn get tableNameKey => text()();
  TextColumn get rowId => text()();
  TextColumn get payload => text()();
  @override
  Set<Column> get primaryKey => {tableNameKey, rowId};
}
class SyncTasks extends Table {
  TextColumn get taskId => text()();
  TextColumn get tableNameKey => text()();
  TextColumn get payload => text()();
  TextColumn get localFile => text().nullable()();
  TextColumn get failure => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {taskId};
}

@DriftDatabase(tables: [CachedRows, SyncTasks])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(String userId) : super(LazyDatabase(() async {
    final root = await getApplicationSupportDirectory();
    return NativeDatabase.createInBackground(File('${root.path}/us-$userId.sqlite'));
  }));
  LocalDatabase.forTest(QueryExecutor executor) : super(executor);
  @override
  int get schemaVersion => 1;
  Future<List<Map<String, dynamic>>> readRows(String table) async {
    final rows = await (select(cachedRows)..where((r) => r.tableNameKey.equals(table))).get();
    return rows.map((r) => Map<String, dynamic>.from(jsonDecode(r.payload) as Map)).toList();
  }
  Future<void> replaceRows(String table, List<Map<String, dynamic>> rows) => transaction(() async {
    await (delete(cachedRows)..where((r) => r.tableNameKey.equals(table))).go();
    for (final row in rows) {
      final id = (row['id'] ?? row['user_id'] ?? '${row['message_id']}:${row['user_id']}').toString();
      await into(cachedRows).insertOnConflictUpdate(CachedRowsCompanion.insert(tableNameKey: table, rowId: id, payload: jsonEncode(row)));
    }
  });
  Future<void> enqueue(String table, Map<String,dynamic> row, {String? file}) async {
    await into(syncTasks).insert(SyncTasksCompanion.insert(taskId: row['id'] as String,
      tableNameKey: table, payload: jsonEncode(row), localFile: Value(file)));
  }
  Future<List<SyncTask>> pending() => select(syncTasks).get();
  Future<void> complete(String id) => (delete(syncTasks)..where((t) => t.taskId.equals(id))).go();
  Future<void> fail(String id, String error, int attempts) => (update(syncTasks)..where((t) => t.taskId.equals(id)))
      .write(SyncTasksCompanion(failure: Value(error), attempts: Value(attempts)));
  Future<void> clear() => transaction(() async { await delete(cachedRows).go(); await delete(syncTasks).go(); });
}
