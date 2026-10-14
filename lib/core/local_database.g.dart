// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $CachedRowsTable extends CachedRows
    with TableInfo<$CachedRowsTable, CachedRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tableNameKeyMeta = const VerificationMeta(
    'tableNameKey',
  );
  @override
  late final GeneratedColumn<String> tableNameKey = GeneratedColumn<String>(
    'table_name_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tableNameKey, rowId, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('table_name_key')) {
      context.handle(
        _tableNameKeyMeta,
        tableNameKey.isAcceptableOrUnknown(
          data['table_name_key']!,
          _tableNameKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tableNameKeyMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tableNameKey, rowId};
  @override
  CachedRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedRow(
      tableNameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name_key'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $CachedRowsTable createAlias(String alias) {
    return $CachedRowsTable(attachedDatabase, alias);
  }
}

class CachedRow extends DataClass implements Insertable<CachedRow> {
  final String tableNameKey;
  final String rowId;
  final String payload;
  const CachedRow({
    required this.tableNameKey,
    required this.rowId,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['table_name_key'] = Variable<String>(tableNameKey);
    map['row_id'] = Variable<String>(rowId);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  CachedRowsCompanion toCompanion(bool nullToAbsent) {
    return CachedRowsCompanion(
      tableNameKey: Value(tableNameKey),
      rowId: Value(rowId),
      payload: Value(payload),
    );
  }

  factory CachedRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedRow(
      tableNameKey: serializer.fromJson<String>(json['tableNameKey']),
      rowId: serializer.fromJson<String>(json['rowId']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tableNameKey': serializer.toJson<String>(tableNameKey),
      'rowId': serializer.toJson<String>(rowId),
      'payload': serializer.toJson<String>(payload),
    };
  }

  CachedRow copyWith({String? tableNameKey, String? rowId, String? payload}) =>
      CachedRow(
        tableNameKey: tableNameKey ?? this.tableNameKey,
        rowId: rowId ?? this.rowId,
        payload: payload ?? this.payload,
      );
  CachedRow copyWithCompanion(CachedRowsCompanion data) {
    return CachedRow(
      tableNameKey: data.tableNameKey.present
          ? data.tableNameKey.value
          : this.tableNameKey,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedRow(')
          ..write('tableNameKey: $tableNameKey, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tableNameKey, rowId, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedRow &&
          other.tableNameKey == this.tableNameKey &&
          other.rowId == this.rowId &&
          other.payload == this.payload);
}

class CachedRowsCompanion extends UpdateCompanion<CachedRow> {
  final Value<String> tableNameKey;
  final Value<String> rowId;
  final Value<String> payload;
  final Value<int> rowid;
  const CachedRowsCompanion({
    this.tableNameKey = const Value.absent(),
    this.rowId = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedRowsCompanion.insert({
    required String tableNameKey,
    required String rowId,
    required String payload,
    this.rowid = const Value.absent(),
  }) : tableNameKey = Value(tableNameKey),
       rowId = Value(rowId),
       payload = Value(payload);
  static Insertable<CachedRow> custom({
    Expression<String>? tableNameKey,
    Expression<String>? rowId,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tableNameKey != null) 'table_name_key': tableNameKey,
      if (rowId != null) 'row_id': rowId,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedRowsCompanion copyWith({
    Value<String>? tableNameKey,
    Value<String>? rowId,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return CachedRowsCompanion(
      tableNameKey: tableNameKey ?? this.tableNameKey,
      rowId: rowId ?? this.rowId,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tableNameKey.present) {
      map['table_name_key'] = Variable<String>(tableNameKey.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedRowsCompanion(')
          ..write('tableNameKey: $tableNameKey, ')
          ..write('rowId: $rowId, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncTasksTable extends SyncTasks
    with TableInfo<$SyncTasksTable, SyncTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tableNameKeyMeta = const VerificationMeta(
    'tableNameKey',
  );
  @override
  late final GeneratedColumn<String> tableNameKey = GeneratedColumn<String>(
    'table_name_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFileMeta = const VerificationMeta(
    'localFile',
  );
  @override
  late final GeneratedColumn<String> localFile = GeneratedColumn<String>(
    'local_file',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureMeta = const VerificationMeta(
    'failure',
  );
  @override
  late final GeneratedColumn<String> failure = GeneratedColumn<String>(
    'failure',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    tableNameKey,
    payload,
    localFile,
    failure,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('table_name_key')) {
      context.handle(
        _tableNameKeyMeta,
        tableNameKey.isAcceptableOrUnknown(
          data['table_name_key']!,
          _tableNameKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tableNameKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('local_file')) {
      context.handle(
        _localFileMeta,
        localFile.isAcceptableOrUnknown(data['local_file']!, _localFileMeta),
      );
    }
    if (data.containsKey('failure')) {
      context.handle(
        _failureMeta,
        failure.isAcceptableOrUnknown(data['failure']!, _failureMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  SyncTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTask(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      tableNameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name_key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      localFile: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file'],
      ),
      failure: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $SyncTasksTable createAlias(String alias) {
    return $SyncTasksTable(attachedDatabase, alias);
  }
}

class SyncTask extends DataClass implements Insertable<SyncTask> {
  final String taskId;
  final String tableNameKey;
  final String payload;
  final String? localFile;
  final String? failure;
  final int attempts;
  const SyncTask({
    required this.taskId,
    required this.tableNameKey,
    required this.payload,
    this.localFile,
    this.failure,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['table_name_key'] = Variable<String>(tableNameKey);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || localFile != null) {
      map['local_file'] = Variable<String>(localFile);
    }
    if (!nullToAbsent || failure != null) {
      map['failure'] = Variable<String>(failure);
    }
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  SyncTasksCompanion toCompanion(bool nullToAbsent) {
    return SyncTasksCompanion(
      taskId: Value(taskId),
      tableNameKey: Value(tableNameKey),
      payload: Value(payload),
      localFile: localFile == null && nullToAbsent
          ? const Value.absent()
          : Value(localFile),
      failure: failure == null && nullToAbsent
          ? const Value.absent()
          : Value(failure),
      attempts: Value(attempts),
    );
  }

  factory SyncTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTask(
      taskId: serializer.fromJson<String>(json['taskId']),
      tableNameKey: serializer.fromJson<String>(json['tableNameKey']),
      payload: serializer.fromJson<String>(json['payload']),
      localFile: serializer.fromJson<String?>(json['localFile']),
      failure: serializer.fromJson<String?>(json['failure']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'tableNameKey': serializer.toJson<String>(tableNameKey),
      'payload': serializer.toJson<String>(payload),
      'localFile': serializer.toJson<String?>(localFile),
      'failure': serializer.toJson<String?>(failure),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  SyncTask copyWith({
    String? taskId,
    String? tableNameKey,
    String? payload,
    Value<String?> localFile = const Value.absent(),
    Value<String?> failure = const Value.absent(),
    int? attempts,
  }) => SyncTask(
    taskId: taskId ?? this.taskId,
    tableNameKey: tableNameKey ?? this.tableNameKey,
    payload: payload ?? this.payload,
    localFile: localFile.present ? localFile.value : this.localFile,
    failure: failure.present ? failure.value : this.failure,
    attempts: attempts ?? this.attempts,
  );
  SyncTask copyWithCompanion(SyncTasksCompanion data) {
    return SyncTask(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      tableNameKey: data.tableNameKey.present
          ? data.tableNameKey.value
          : this.tableNameKey,
      payload: data.payload.present ? data.payload.value : this.payload,
      localFile: data.localFile.present ? data.localFile.value : this.localFile,
      failure: data.failure.present ? data.failure.value : this.failure,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTask(')
          ..write('taskId: $taskId, ')
          ..write('tableNameKey: $tableNameKey, ')
          ..write('payload: $payload, ')
          ..write('localFile: $localFile, ')
          ..write('failure: $failure, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(taskId, tableNameKey, payload, localFile, failure, attempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTask &&
          other.taskId == this.taskId &&
          other.tableNameKey == this.tableNameKey &&
          other.payload == this.payload &&
          other.localFile == this.localFile &&
          other.failure == this.failure &&
          other.attempts == this.attempts);
}

class SyncTasksCompanion extends UpdateCompanion<SyncTask> {
  final Value<String> taskId;
  final Value<String> tableNameKey;
  final Value<String> payload;
  final Value<String?> localFile;
  final Value<String?> failure;
  final Value<int> attempts;
  final Value<int> rowid;
  const SyncTasksCompanion({
    this.taskId = const Value.absent(),
    this.tableNameKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.localFile = const Value.absent(),
    this.failure = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncTasksCompanion.insert({
    required String taskId,
    required String tableNameKey,
    required String payload,
    this.localFile = const Value.absent(),
    this.failure = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       tableNameKey = Value(tableNameKey),
       payload = Value(payload);
  static Insertable<SyncTask> custom({
    Expression<String>? taskId,
    Expression<String>? tableNameKey,
    Expression<String>? payload,
    Expression<String>? localFile,
    Expression<String>? failure,
    Expression<int>? attempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (tableNameKey != null) 'table_name_key': tableNameKey,
      if (payload != null) 'payload': payload,
      if (localFile != null) 'local_file': localFile,
      if (failure != null) 'failure': failure,
      if (attempts != null) 'attempts': attempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncTasksCompanion copyWith({
    Value<String>? taskId,
    Value<String>? tableNameKey,
    Value<String>? payload,
    Value<String?>? localFile,
    Value<String?>? failure,
    Value<int>? attempts,
    Value<int>? rowid,
  }) {
    return SyncTasksCompanion(
      taskId: taskId ?? this.taskId,
      tableNameKey: tableNameKey ?? this.tableNameKey,
      payload: payload ?? this.payload,
      localFile: localFile ?? this.localFile,
      failure: failure ?? this.failure,
      attempts: attempts ?? this.attempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (tableNameKey.present) {
      map['table_name_key'] = Variable<String>(tableNameKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (localFile.present) {
      map['local_file'] = Variable<String>(localFile.value);
    }
    if (failure.present) {
      map['failure'] = Variable<String>(failure.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTasksCompanion(')
          ..write('taskId: $taskId, ')
          ..write('tableNameKey: $tableNameKey, ')
          ..write('payload: $payload, ')
          ..write('localFile: $localFile, ')
          ..write('failure: $failure, ')
          ..write('attempts: $attempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $CachedRowsTable cachedRows = $CachedRowsTable(this);
  late final $SyncTasksTable syncTasks = $SyncTasksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedRows, syncTasks];
}

typedef $$CachedRowsTableCreateCompanionBuilder =
    CachedRowsCompanion Function({
      required String tableNameKey,
      required String rowId,
      required String payload,
      Value<int> rowid,
    });
typedef $$CachedRowsTableUpdateCompanionBuilder =
    CachedRowsCompanion Function({
      Value<String> tableNameKey,
      Value<String> rowId,
      Value<String> payload,
      Value<int> rowid,
    });

class $$CachedRowsTableFilterComposer
    extends Composer<_$LocalDatabase, $CachedRowsTable> {
  $$CachedRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tableNameKey => $composableBuilder(
    column: $table.tableNameKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedRowsTableOrderingComposer
    extends Composer<_$LocalDatabase, $CachedRowsTable> {
  $$CachedRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tableNameKey => $composableBuilder(
    column: $table.tableNameKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedRowsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $CachedRowsTable> {
  $$CachedRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tableNameKey => $composableBuilder(
    column: $table.tableNameKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$CachedRowsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $CachedRowsTable,
          CachedRow,
          $$CachedRowsTableFilterComposer,
          $$CachedRowsTableOrderingComposer,
          $$CachedRowsTableAnnotationComposer,
          $$CachedRowsTableCreateCompanionBuilder,
          $$CachedRowsTableUpdateCompanionBuilder,
          (
            CachedRow,
            BaseReferences<_$LocalDatabase, $CachedRowsTable, CachedRow>,
          ),
          CachedRow,
          PrefetchHooks Function()
        > {
  $$CachedRowsTableTableManager(_$LocalDatabase db, $CachedRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tableNameKey = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedRowsCompanion(
                tableNameKey: tableNameKey,
                rowId: rowId,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tableNameKey,
                required String rowId,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => CachedRowsCompanion.insert(
                tableNameKey: tableNameKey,
                rowId: rowId,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $CachedRowsTable,
      CachedRow,
      $$CachedRowsTableFilterComposer,
      $$CachedRowsTableOrderingComposer,
      $$CachedRowsTableAnnotationComposer,
      $$CachedRowsTableCreateCompanionBuilder,
      $$CachedRowsTableUpdateCompanionBuilder,
      (CachedRow, BaseReferences<_$LocalDatabase, $CachedRowsTable, CachedRow>),
      CachedRow,
      PrefetchHooks Function()
    >;
typedef $$SyncTasksTableCreateCompanionBuilder =
    SyncTasksCompanion Function({
      required String taskId,
      required String tableNameKey,
      required String payload,
      Value<String?> localFile,
      Value<String?> failure,
      Value<int> attempts,
      Value<int> rowid,
    });
typedef $$SyncTasksTableUpdateCompanionBuilder =
    SyncTasksCompanion Function({
      Value<String> taskId,
      Value<String> tableNameKey,
      Value<String> payload,
      Value<String?> localFile,
      Value<String?> failure,
      Value<int> attempts,
      Value<int> rowid,
    });

class $$SyncTasksTableFilterComposer
    extends Composer<_$LocalDatabase, $SyncTasksTable> {
  $$SyncTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tableNameKey => $composableBuilder(
    column: $table.tableNameKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFile => $composableBuilder(
    column: $table.localFile,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failure => $composableBuilder(
    column: $table.failure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncTasksTableOrderingComposer
    extends Composer<_$LocalDatabase, $SyncTasksTable> {
  $$SyncTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tableNameKey => $composableBuilder(
    column: $table.tableNameKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFile => $composableBuilder(
    column: $table.localFile,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failure => $composableBuilder(
    column: $table.failure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncTasksTableAnnotationComposer
    extends Composer<_$LocalDatabase, $SyncTasksTable> {
  $$SyncTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get tableNameKey => $composableBuilder(
    column: $table.tableNameKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get localFile =>
      $composableBuilder(column: $table.localFile, builder: (column) => column);

  GeneratedColumn<String> get failure =>
      $composableBuilder(column: $table.failure, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$SyncTasksTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $SyncTasksTable,
          SyncTask,
          $$SyncTasksTableFilterComposer,
          $$SyncTasksTableOrderingComposer,
          $$SyncTasksTableAnnotationComposer,
          $$SyncTasksTableCreateCompanionBuilder,
          $$SyncTasksTableUpdateCompanionBuilder,
          (
            SyncTask,
            BaseReferences<_$LocalDatabase, $SyncTasksTable, SyncTask>,
          ),
          SyncTask,
          PrefetchHooks Function()
        > {
  $$SyncTasksTableTableManager(_$LocalDatabase db, $SyncTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> tableNameKey = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> localFile = const Value.absent(),
                Value<String?> failure = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTasksCompanion(
                taskId: taskId,
                tableNameKey: tableNameKey,
                payload: payload,
                localFile: localFile,
                failure: failure,
                attempts: attempts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String tableNameKey,
                required String payload,
                Value<String?> localFile = const Value.absent(),
                Value<String?> failure = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncTasksCompanion.insert(
                taskId: taskId,
                tableNameKey: tableNameKey,
                payload: payload,
                localFile: localFile,
                failure: failure,
                attempts: attempts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $SyncTasksTable,
      SyncTask,
      $$SyncTasksTableFilterComposer,
      $$SyncTasksTableOrderingComposer,
      $$SyncTasksTableAnnotationComposer,
      $$SyncTasksTableCreateCompanionBuilder,
      $$SyncTasksTableUpdateCompanionBuilder,
      (SyncTask, BaseReferences<_$LocalDatabase, $SyncTasksTable, SyncTask>),
      SyncTask,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$CachedRowsTableTableManager get cachedRows =>
      $$CachedRowsTableTableManager(_db, _db.cachedRows);
  $$SyncTasksTableTableManager get syncTasks =>
      $$SyncTasksTableTableManager(_db, _db.syncTasks);
}
