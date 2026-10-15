import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

import 'local_database.dart';
import 'session.dart';
import 'notifications.dart';
import 'widget.dart';

final spaceProvider = Provider<UsSpace>((ref) {
  final space = UsSpace(ref.read(sessionProvider));
  ref.onDispose(space.dispose);
  return space;
});

class UsSpace extends ChangeNotifier with WidgetsBindingObserver {
  UsSpace(this.session) {
    session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (!_foreground) return;
      await _lastSeen();
      await session.refresh();
      await sync();
    });
    unawaited(_sessionChanged());
  }
  final UsSession session;
  final Map<String, List<Map<String, dynamic>>> rows = {};
  static const tables = [
    'profiles',
    'messages',
    'message_states',
    'memories',
    'reactions',
    'dates',
    'date_responses',
    'anniversaries',
    'list_items',
    'love_notes',
    'journal_entries',
    'miss_me',
    'letters',
    'expenses',
    'memory_collections',
    'polls',
    'poll_votes',
  ];
  LocalDatabase? _db;
  Timer? _timer, _typingTimer, _sideEffectsTimer;
  Future<void>? _refreshing;
  final Map<String, Timer> _cacheTimers = {};
  final Map<String, int> _revisions = {};
  RealtimeChannel? _updates, _selfChannel, _partnerChannel;
  String? _uid, _cid, _subscribedPartner;
  bool _foreground = true;
  bool loading = true,
      online = true,
      partnerOnline = false,
      partnerTyping = false;
  bool syncing = false, _dead = false;
  int queued = 0;
  String? error;
  Map<String, dynamic> preferences = {};
  final Map<String, Future<String>> _downloads = {};
  List<Map<String, dynamic>> get items => rows['messages'] ?? [];
  Map<String, dynamic>? get partner => (rows['profiles'] ?? [])
      .where((p) => p['user_id'] == session.partnerId)
      .firstOrNull;
  Map<String, dynamic>? get me => (rows['profiles'] ?? [])
      .where((p) => p['user_id'] == session.userId)
      .firstOrNull;
  void _notify() {
    if (!_dead) notifyListeners();
  }

  bool _current(String uid, String cid) =>
      !_dead &&
      session.userId == uid &&
      session.coupleId == cid &&
      _uid == uid &&
      _cid == cid &&
      session.couple?['deleting_at'] == null;
  Future<void> _sessionChanged() async {
    if (_dead) return;
    final uid = session.userId, cid = session.coupleId;
    if (uid == _uid && cid == _cid) {
      if (uid != null &&
          cid != null &&
          _subscribedPartner != session.partnerId) {
        if (_partnerChannel != null)
          await session.client.removeChannel(_partnerChannel!);
        _partnerChannel = null;
        _subscribePartner(uid, cid);
      }
      _notify();
      return;
    }
    if (uid == _uid && cid == null && _cid != null) await eraseLocal();
    await _disconnect();
    _uid = uid;
    _cid = cid;
    rows.clear();
    queued = 0;
    partnerOnline = false;
    partnerTyping = false;
    if (uid == null || cid == null) {
      await UsWidget.clear();
      loading = false;
      _notify();
      return;
    }
    final db = LocalDatabase(uid);
    _db = db;
    for (final table in tables) {
      final cached = await db.readRows(table);
      if (!_current(uid, cid)) return;
      rows[table] = cached.where((r) => r['couple_id'] == cid).toList();
    }
    await _mergePending();
    loading = false;
    _notify();
    _subscribe(uid, cid);
    unawaited(_lastSeen());
    await refresh();
    await sync();
  }

  Future<void> _disconnect() async {
    for (final channel in [_updates, _selfChannel, _partnerChannel]) {
      if (channel != null) await session.client.removeChannel(channel);
    }
    _updates = null;
    _selfChannel = null;
    _partnerChannel = null;
    for (final timer in _cacheTimers.values) {
      timer.cancel();
    }
    _cacheTimers.clear();
    _sideEffectsTimer?.cancel();
    final old = _db;
    _db = null;
    if (old != null) await old.close();
  }

  void _subscribe(String uid, String cid) {
    _updates = session.client.channel('db:$cid:$uid');
    for (final table in tables) {
      _updates!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'couple_id',
          value: cid,
        ),
        callback: (payload) {
          if (_current(uid, cid)) _applyChange(table, payload);
        },
      );
    }
    _updates!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'couples',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: cid,
      ),
      callback: (_) => session.refresh(),
    );
    _updates!.subscribe();
    _selfChannel = session.client.channel(
      'couple:$cid:user:$uid',
      opts: const RealtimeChannelConfig(private: true, enabled: true),
    );
    _selfChannel!.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed && _foreground)
        unawaited(_selfChannel!.track({'online': true}));
    });
    _subscribePartner(uid, cid);
  }

  void _subscribePartner(String uid, String cid) {
    final partnerId = session.partnerId;
    _subscribedPartner = partnerId;
    partnerOnline = false;
    partnerTyping = false;
    if (partnerId != null) {
      _partnerChannel = session.client.channel(
        'couple:$cid:user:$partnerId',
        opts: const RealtimeChannelConfig(private: true, enabled: true),
      );
      _partnerChannel!
          .onPresenceSync((_) {
            if (!_current(uid, cid)) return;
            partnerOnline = _partnerChannel!.presenceState().isNotEmpty;
            _notify();
          })
          .onBroadcast(
            event: 'typing',
            callback: (payload) {
              if (!_current(uid, cid)) return;
              partnerTyping = payload['typing'] == true;
              _typingTimer?.cancel();
              _typingTimer = Timer(const Duration(seconds: 5), () {
                partnerTyping = false;
                _notify();
              });
              _notify();
            },
          )
          .subscribe();
    }
  }

  Future<void> _lastSeen() async {
    final uid = _uid, cid = _cid;
    if (uid == null || cid == null) return;
    try {
      await session.client
          .from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid)
          .eq('couple_id', cid);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _foreground = false;
      unawaited(_selfChannel?.untrack());
      unawaited(_lastSeen());
    }
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(_selfChannel?.track({'online': true}));
      unawaited(_lastSeen());
      unawaited(session.refresh());
      unawaited(sync());
      unawaited(UsNotifications.requestPermission(session));
    }
  }

  Future<void> typing(bool value) async {
    try {
      await _selfChannel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'typing': value},
      );
    } catch (_) {
      /* Ephemeral signal only. */
    }
  }

  static String rowKey(String table, Map<String, dynamic> row) {
    if (table == 'profiles') return '${row['user_id']}';
    if (table == 'message_states')
      return '${row['message_id']}:${row['user_id']}';
    if (table == 'date_responses') return '${row['date_id']}:${row['user_id']}';
    if (table == 'poll_votes') return '${row['poll_id']}:${row['user_id']}';
    return '${row['id']}';
  }

  void _applyChange(String table, PostgresChangePayload payload) {
    _revisions[table] = (_revisions[table] ?? 0) + 1;
    final data = payload.eventType == PostgresChangeEvent.delete
        ? payload.oldRecord
        : payload.newRecord;
    final key = rowKey(table, data), list = rows.putIfAbsent(table, () => []);
    // Deletes without the complete key are repaired by the next foreground refresh.
    list.removeWhere((r) => rowKey(table, r) == key);
    if (payload.eventType != PostgresChangeEvent.delete)
      list.add(Map<String, dynamic>.from(data));
    _notify();
    _cacheLater(table);
    _sideEffects(table);
  }

  void _cacheLater(String table) {
    _cacheTimers[table]?.cancel();
    _cacheTimers[table] = Timer(const Duration(milliseconds: 400), () {
      final db = _db;
      if (db != null)
        unawaited(
          db
              .replaceRows(
                table,
                List<Map<String, dynamic>>.from(rows[table] ?? []),
              )
              .catchError((_) {}),
        );
    });
  }

  void _sideEffects(String table) {
    if (![
      'profiles',
      'dates',
      'date_responses',
      'anniversaries',
    ].contains(table))
      return;
    _sideEffectsTimer?.cancel();
    _sideEffectsTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        await UsWidget.update(session.couple, partner);
        if (table != 'profiles')
          await UsNotifications.reminders(
            rows,
            preferences,
            me?['timezone'] as String? ?? 'Asia/Kolkata',
            couple: session.couple,
          );
      } catch (_) {}
    });
  }

  Future<void> refresh() {
    final active = _refreshing;
    if (active != null) return active;
    final task = _fetch();
    _refreshing = task;
    return task.whenComplete(() => _refreshing = null);
  }

  Future<void> _fetch() async {
    final uid = _uid, cid = _cid, db = _db;
    if (uid == null || cid == null || db == null) return;
    try {
      final revisions = Map<String, int>.from(_revisions);
      final results = await Future.wait(
        tables.map((table) async {
          final query = session.client
              .from(table)
              .select()
              .eq('couple_id', cid);
          final data = table == 'messages'
              ? await query.order('created_at', ascending: false).limit(500)
              : await query;
          return MapEntry(table, List<Map<String, dynamic>>.from(data));
        }),
      );
      if (!_current(uid, cid)) return;
      for (final entry in results) {
        if ((_revisions[entry.key] ?? 0) == (revisions[entry.key] ?? 0))
          rows[entry.key] = entry.value;
      }
      await _mergePending();
      online = true;
      error = null;
      loading = false;
      _notify();
      // Disk writes and reminder scheduling never delay displaying fresh data.
      for (final table in tables) {
        _cacheLater(table);
      }
      final prefs = await session.client
          .from('notification_preferences')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (!_current(uid, cid)) return;
      preferences = prefs ?? {'timezone': me?['timezone'] ?? 'Asia/Kolkata'};
      _notify();
      _sideEffects('dates');
    } catch (_) {
      if (!_current(uid, cid)) return;
      online = false;
      error = 'You are offline. Chat stays here and sends when you reconnect.';
    }
    loading = false;
    _notify();
  }

  Future<void> _mergePending() async {
    final db = _db;
    if (db == null) return;
    final pending = await db.pending();
    queued = 0;
    for (final task in pending) {
      final value = Map<String, dynamic>.from(jsonDecode(task.payload) as Map);
      if (value['couple_id'] != _cid) continue;
      queued++;
      value['_pending'] = true;
      value['_local_file'] = task.localFile;
      value['_failure'] = task.failure;
      final list = rows.putIfAbsent(task.tableNameKey, () => []);
      list.removeWhere((r) => r['id'] == task.taskId);
      list.add(value);
    }
  }

  Future<void> eraseLocal() async {
    final db = _db;
    if (db != null) {
      for (final task in await db.pending()) {
        if (task.localFile != null) {
          try {
            await File(task.localFile!).delete();
          } catch (_) {}
        }
      }
      await db.clear();
    }
    rows.clear();
    queued = 0;
    await UsWidget.clear();
    final cid = _cid;
    if (cid != null) {
      final root = await getApplicationSupportDirectory();
      final media = Directory('${root.path}/us-media/$cid');
      if (await media.exists()) await media.delete(recursive: true);
    }
    await UsNotifications.plugin.cancelAll();
  }

  Future<void> send(
    String body, {
    String? file,
    String? kind,
    String? replyTo,
    bool memory = false,
    String? caption,
    DateTime? memoryDate,
    String? collectionId,
    String? fileName,
    String? mime,
  }) async {
    final cid = _cid, uid = _uid, db = _db;
    if (cid == null || uid == null || db == null)
      throw StateError('Sign in and pair first.');
    if (body.trim().isEmpty && file == null) return;
    final id = const Uuid().v4();
    final row = <String, dynamic>{
      'id': id,
      'couple_id': cid,
      memory ? 'author_id' : 'sender_id': uid,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (memory) {
      if (collectionId != null) row['collection_id'] = collectionId;
      row['caption'] = caption ?? body;
      row['memory_date'] = (memoryDate ?? DateTime.now())
          .toIso8601String()
          .substring(0, 10);
    } else {
      row['body'] = body.trim().isEmpty ? null : body.trim();
      if (replyTo != null) row['reply_to'] = replyTo;
    }
    if (file != null) {
      final ext = kind == 'file'
          ? (fileName ?? 'file.txt').split('.').last.toLowerCase()
          : kind == 'voice'
          ? 'm4a'
          : 'jpg';
      row['media_path'] = '$cid/$uid/$id.$ext';
      if (!memory) {
        row['media_kind'] = kind;
        if (kind == 'file') {
          row['file_name'] = fileName;
          row['mime_type'] = mime ?? 'application/octet-stream';
          row['file_size'] = await File(file).length();
        }
      }
    }
    await db.enqueue(memory ? 'memories' : 'messages', row, file: file);
    await _mergePending();
    _notify();
    unawaited(sync());
  }

  Future<void> sync() async {
    if (syncing || _dead || _db == null || _uid == null || _cid == null) return;
    final db = _db!, uid = _uid!, cid = _cid!;
    syncing = true;
    try {
      for (final task in await db.pending()) {
        if (!_current(uid, cid)) break;
        final row = Map<String, dynamic>.from(jsonDecode(task.payload) as Map);
        if (row['couple_id'] != cid) continue;
        try {
          if (task.localFile != null) {
            final file = File(task.localFile!);
            if (!await file.exists())
              throw StateError('Media file is missing.');
            if (await file.length() > 5242880)
              throw StateError('Keep media below 5 MB.');
            try {
              await session.client.storage
                  .from('couple-media')
                  .upload(
                    row['media_path'] as String,
                    file,
                    fileOptions: FileOptions(
                      contentType: row['media_kind'] == 'file'
                          ? (row['mime_type'] as String? ??
                                'application/octet-stream')
                          : (row['media_kind'] == 'voice')
                          ? 'audio/mp4'
                          : 'image/jpeg',
                    ),
                  );
            } on StorageException catch (e) {
              if (e.statusCode != '409' && e.statusCode != '400') rethrow;
              // A deterministic path may already exist after an interrupted upload. Verify access before retrying the row.
              await session.client.storage
                  .from('couple-media')
                  .createSignedUrl(row['media_path'] as String, 60);
            }
          }
          if (!_current(uid, cid)) break;
          await session.client
              .from(task.tableNameKey)
              .upsert(row, onConflict: 'id', ignoreDuplicates: true);
          if (!_current(uid, cid)) break;
          await db.complete(task.taskId);
          final list = rows[task.tableNameKey] ?? [];
          list.removeWhere((r) => r['id'] == task.taskId);
          list.add(row);
          _notify();
          _cacheLater(task.tableNameKey);
          if (task.localFile != null) {
            try {
              await File(task.localFile!).delete();
            } catch (_) {}
          }
        } catch (e) {
          await db.fail(
            task.taskId,
            e is StateError ? e.message.toString() : 'Waiting for connection',
            task.attempts + 1,
          );
          online = false;
          break;
        }
      }
    } finally {
      syncing = false;
      if (_current(uid, cid)) {
        await _mergePending();
        _notify();
      }
    }
    if (_current(uid, cid)) await refresh();
  }

  Future<void> add(String table, Map<String, dynamic> fields) async {
    if (_uid == null || _cid == null) throw StateError('Pair first.');
    final value = <String, dynamic>{
      'id': const Uuid().v4(),
      'couple_id': _cid,
      table == 'reactions' ? 'user_id' : 'author_id': _uid,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      ...fields,
    };
    // Not every existing table has a creation timestamp.
    if (['reactions', 'list_items', 'journal_entries'].contains(table))
      value.remove('created_at');
    _revisions[table] = (_revisions[table] ?? 0) + 1;
    final list = rows.putIfAbsent(table, () => []);
    list.add(value);
    _notify();
    try {
      await session.client.from(table).insert(value);
      _cacheLater(table);
      _sideEffects(table);
    } catch (_) {
      list.removeWhere((r) => r['id'] == value['id']);
      _notify();
      rethrow;
    }
  }

  Future<void> update(
    String table,
    String id,
    Map<String, dynamic> fields,
  ) async {
    _revisions[table] = (_revisions[table] ?? 0) + 1;
    final list = rows[table] ?? [],
        old = list.where((r) => r['id'] == id).firstOrNull;
    if (old != null) {
      list.remove(old);
      list.add({...old, ...fields});
    }
    _notify();
    try {
      await session.client
          .from(table)
          .update(fields)
          .eq('id', id)
          .eq('couple_id', _cid!);
      _cacheLater(table);
      _sideEffects(table);
    } catch (_) {
      if (old != null) {
        list.removeWhere((r) => r['id'] == id);
        list.add(old);
      }
      _notify();
      rethrow;
    }
  }

  Future<void> deleteMemory(String id) async {
    final memory = (rows['memories'] ?? [])
        .where((m) => m['id'] == id)
        .firstOrNull;
    if (memory == null ||
        memory['author_id'] != session.userId ||
        memory['_pending'] == true)
      throw StateError('Only your uploaded memories can be deleted.');
    final cid = _cid, uid = _uid;
    if (cid == null || uid == null) throw StateError('Sign in first.');
    final response = await session.client.functions.invoke(
      'delete-memory',
      body: {'memory_id': id},
    );
    if (response.status != 200 || response.data?['deleted'] != true)
      throw StateError('Memory deletion did not finish. Please retry.');
    if (!_current(uid, cid)) return;
    _revisions['memories'] = (_revisions['memories'] ?? 0) + 1;
    rows['memories']?.removeWhere((m) => m['id'] == id);
    rows['reactions']?.removeWhere((r) => r['memory_id'] == id);
    _notify();
    _cacheLater('memories');
    _cacheLater('reactions');
    final path = memory['media_path'] as String;
    final download = _downloads[path];
    if (download != null) {
      try {
        await download;
      } catch (_) {}
    }
    try {
      final root = await getApplicationSupportDirectory();
      final cached = File(
        '${root.path}/us-media/$cid/received/${const Uuid().v5(Uuid.NAMESPACE_URL, path)}.${path.split('.').last}',
      );
      if (await cached.exists()) await cached.delete();
    } catch (_) {
      /* The server deletion already succeeded. */
    }
  }

  Future<void> remove(String table, String id) async {
    _revisions[table] = (_revisions[table] ?? 0) + 1;
    final list = rows[table] ?? [],
        old = list.where((r) => r['id'] == id).firstOrNull;
    list.removeWhere((r) => r['id'] == id);
    _notify();
    try {
      await session.client
          .from(table)
          .delete()
          .eq('id', id)
          .eq('couple_id', _cid!);
      _cacheLater(table);
    } catch (_) {
      if (old != null) list.add(old);
      _notify();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> missMe() async => Map<String, dynamic>.from(
    await session.client.rpc('send_miss_me', params: {'p_couple': _cid}) as Map,
  );
  Future<void> profile(Map<String, dynamic> values) async {
    final old = me;
    if (old != null) {
      rows['profiles']!.remove(old);
      rows['profiles']!.add({...old, ...values});
    }
    _notify();
    try {
      await session.client
          .from('profiles')
          .update(values)
          .eq('user_id', _uid!)
          .eq('couple_id', _cid!);
      _cacheLater('profiles');
      _sideEffects('profiles');
    } catch (_) {
      if (old != null) {
        rows['profiles']!.removeWhere((r) => r['user_id'] == _uid);
        rows['profiles']!.add(old);
      }
      _notify();
      rethrow;
    }
  }

  Future<void> setPreferences(Map<String, dynamic> values) async {
    final newPrefs = {...preferences, ...values, 'user_id': _uid};
    final existing = await session.client
        .from('notification_preferences')
        .select('user_id')
        .eq('user_id', _uid!)
        .maybeSingle();
    if (existing == null)
      await session.client.from('notification_preferences').insert(newPrefs);
    else {
      newPrefs.remove('user_id');
      await session.client
          .from('notification_preferences')
          .update(newPrefs)
          .eq('user_id', _uid!);
    }
    await refresh();
  }

  Future<void> messageState(
    String id, {
    bool hidden = false,
    bool? starred,
  }) async {
    final value = <String, dynamic>{
      'message_id': id,
      'couple_id': _cid,
      'user_id': _uid,
    };
    final field = starred != null
        ? 'starred'
        : hidden
        ? 'hidden'
        : 'read_at';
    value[field] =
        starred ?? (hidden ? true : DateTime.now().toUtc().toIso8601String());
    final list = rows.putIfAbsent('message_states', () => []),
        old = list
            .where((r) => r['message_id'] == id && r['user_id'] == _uid)
            .firstOrNull;
    list.removeWhere((r) => r['message_id'] == id && r['user_id'] == _uid);
    list.add({...?old, ...value});
    _notify();
    _cacheLater('message_states');
    try {
      final existing = await session.client
          .from('message_states')
          .select('user_id')
          .eq('message_id', id)
          .eq('user_id', _uid!)
          .maybeSingle();
      if (existing == null) {
        try {
          await session.client.from('message_states').insert(value);
          return;
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow;
        }
      }
      await session.client
          .from('message_states')
          .update({field: value[field]})
          .eq('message_id', id)
          .eq('user_id', _uid!);
    } catch (_) {
      list.removeWhere((r) => r['message_id'] == id && r['user_id'] == _uid);
      if (old != null) list.add(old);
      _notify();
      _cacheLater('message_states');
      rethrow;
    }
  }

  Future<void> react(
    String id, {
    bool memory = false,
    String emoji = '❤️',
  }) async {
    final existing = (rows['reactions'] ?? [])
        .where(
          (r) =>
              r['user_id'] == _uid &&
              r[memory ? 'memory_id' : 'message_id'] == id,
        )
        .firstOrNull;
    if (existing != null) {
      await remove('reactions', existing['id'] as String);
      if ((existing['emoji'] ?? '❤️') == emoji) return;
    }
    await add('reactions', {
      memory ? 'memory_id' : 'message_id': id,
      'emoji': emoji,
    });
  }

  Future<String> mediaUrl(String path) =>
      session.client.storage.from('couple-media').createSignedUrl(path, 300);
  Future<String> mediaFile(String path) async {
    final active = _downloads[path];
    if (active != null) return active;
    final task = _cacheMedia(path);
    _downloads[path] = task;
    try {
      return await task;
    } finally {
      _downloads.remove(path);
    }
  }

  Future<String> _cacheMedia(String path) async {
    final uid = _uid, cid = _cid;
    if (uid == null || cid == null || !path.startsWith('$cid/'))
      throw StateError('Photo is outside this space');
    final root = await getApplicationSupportDirectory();
    final folder = await Directory('${root.path}/us-media/$cid/received')
        .create(recursive: true);
    final file = File(
      '${folder.path}/${const Uuid().v5(Uuid.NAMESPACE_URL, path)}.${path.split('.').last}',
    );
    if (await file.exists() && await file.length() > 0) return file.path;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final temp = File('${file.path}.part');
    try {
      final url = await mediaUrl(path);
      final response = await (await client.getUrl(Uri.parse(url)))
          .close()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.contentLength > 5242880)
        throw StateError('Media could not be loaded');
      final sink = temp.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 20),
        )) {
          bytes += chunk.length;
          if (bytes > 5242880) throw StateError('Media is too large');
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      if (!_current(uid, cid)) throw StateError('Space changed');
      await temp.rename(file.path);
      return file.path;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> respond(
    String dateId,
    String status, {
    DateTime? proposed,
  }) async {
    final fields = {
      'status': status,
      'proposed_at': proposed?.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final existing = await session.client
        .from('date_responses')
        .select('user_id')
        .eq('date_id', dateId)
        .eq('user_id', _uid!)
        .maybeSingle();
    if (existing == null)
      await session.client.from('date_responses').insert({
        'date_id': dateId,
        'couple_id': _cid,
        'user_id': _uid,
        ...fields,
      });
    else
      await session.client
          .from('date_responses')
          .update(fields)
          .eq('date_id', dateId)
          .eq('user_id', _uid!);
    await refresh();
  }

  @override
  void dispose() {
    _dead = true;
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_sessionChanged);
    _timer?.cancel();
    _typingTimer?.cancel();
    _sideEffectsTimer?.cancel();
    unawaited(_disconnect());
    super.dispose();
  }
}
