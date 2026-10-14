import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
    _timer = Timer.periodic(const Duration(seconds: 25), (_) async { if(!_foreground)return;await _lastSeen();await session.refresh();await sync(); });
    unawaited(_sessionChanged());
  }
  final UsSession session;
  final Map<String, List<Map<String, dynamic>>> rows = {};
  static const tables = ['profiles','messages','message_states','memories','reactions','dates',
    'date_responses','anniversaries','list_items','love_notes','journal_entries','miss_me'];
  LocalDatabase? _db;
  Timer? _timer, _typingTimer;
  RealtimeChannel? _updates, _selfChannel, _partnerChannel;
  String? _uid, _cid, _subscribedPartner;
  bool _foreground=true;
  bool loading = true, online = true, partnerOnline = false, partnerTyping = false;
  bool syncing = false, _dead = false;
  int queued = 0;
  String? error;
  Map<String,dynamic> preferences = {};
  List<Map<String,dynamic>> get items => rows['messages'] ?? [];
  Map<String,dynamic>? get partner => (rows['profiles'] ?? [])
    .where((p) => p['user_id'] == session.partnerId).firstOrNull;
  Map<String,dynamic>? get me => (rows['profiles'] ?? [])
    .where((p) => p['user_id'] == session.userId).firstOrNull;
  void _notify() { if (!_dead) notifyListeners(); }
  bool _current(String uid,String cid) => !_dead && session.userId == uid && session.coupleId == cid && _uid == uid && _cid == cid;
  Future<void> _sessionChanged() async {
    if (_dead) return;
    final uid = session.userId, cid = session.coupleId;
    if (uid == _uid && cid == _cid) {
      if(uid!=null&&cid!=null&&_subscribedPartner!=session.partnerId){
        if(_partnerChannel!=null)await session.client.removeChannel(_partnerChannel!);
        _partnerChannel=null;_subscribePartner(uid,cid);
      }
      _notify();return;
    }
    if(uid==_uid && cid==null && _cid!=null)await eraseLocal();
    await _disconnect();
    _uid = uid; _cid = cid; rows.clear(); queued = 0; partnerOnline = false; partnerTyping = false;
    if (uid == null || cid == null) { await UsWidget.clear(); loading = false; _notify(); return; }
    final db = LocalDatabase(uid); _db = db;
    for (final table in tables) {
      final cached = await db.readRows(table);
      if (!_current(uid,cid)) return;
      rows[table] = cached.where((r) => r['couple_id'] == cid).toList();
    }
    await _mergePending(); loading = false; _notify();
    _subscribe(uid,cid);
    unawaited(_lastSeen());
    await refresh(); await sync();
  }
  Future<void> _disconnect() async {
    for (final channel in [_updates,_selfChannel,_partnerChannel]) {
      if (channel != null) await session.client.removeChannel(channel);
    }
    _updates = null; _selfChannel = null; _partnerChannel = null;
    final old = _db; _db = null; if (old != null) await old.close();
  }
  void _subscribe(String uid,String cid) {
    _updates = session.client.channel('db:$cid:$uid');
    for (final table in tables) {
      _updates!.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: table,
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,column:'couple_id',value:cid),
        callback: (_) { if (_current(uid,cid)) unawaited(refresh()); });
    }
    _updates!.onPostgresChanges(event: PostgresChangeEvent.all,schema:'public',table:'couples',
      filter:PostgresChangeFilter(type:PostgresChangeFilterType.eq,column:'id',value:cid),
      callback: (_) => session.refresh());
    _updates!.subscribe();
    _selfChannel = session.client.channel('couple:$cid:user:$uid',opts:const RealtimeChannelConfig(private:true,enabled:true));
    _selfChannel!.subscribe((status,_) {
      if (status == RealtimeSubscribeStatus.subscribed&&_foreground) unawaited(_selfChannel!.track({'online':true}));
    });
    _subscribePartner(uid,cid);
  }
  void _subscribePartner(String uid,String cid){
    final partnerId = session.partnerId;
    _subscribedPartner=partnerId;partnerOnline=false;partnerTyping=false;
    if (partnerId != null) {
      _partnerChannel = session.client.channel('couple:$cid:user:$partnerId',opts:const RealtimeChannelConfig(private:true,enabled:true));
      _partnerChannel!.onPresenceSync((_) {
        if (!_current(uid,cid)) return;
        partnerOnline = _partnerChannel!.presenceState().isNotEmpty; _notify();
      }).onBroadcast(event:'typing',callback:(payload) {
        if (!_current(uid,cid)) return;
        partnerTyping = payload['typing'] == true; _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds:5),() {partnerTyping=false;_notify();});_notify();
      }).subscribe();
    }
  }
  Future<void> _lastSeen() async {
    final uid=_uid,cid=_cid;if(uid==null||cid==null)return;
    try{await session.client.from('profiles').update({'last_seen':DateTime.now().toUtc().toIso8601String()}).eq('user_id',uid).eq('couple_id',cid);}catch(_){}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused){_foreground=false;unawaited(_selfChannel?.untrack());unawaited(_lastSeen());}
    if(state==AppLifecycleState.resumed){_foreground=true;unawaited(_selfChannel?.track({'online':true}));
      unawaited(_lastSeen());unawaited(session.refresh());unawaited(sync());unawaited(UsNotifications.requestPermission(session));}
  }
  Future<void> typing(bool value) async {
    try { await _selfChannel?.sendBroadcastMessage(event:'typing',payload:{'typing':value}); } catch (_) { /* Ephemeral signal only. */ }
  }
  Future<void> refresh() async {
    final uid = _uid, cid = _cid, db = _db;
    if (uid == null || cid == null || db == null) return;
    try {
      final next = <String,List<Map<String,dynamic>>>{};
      for (final table in tables) {
        var query = session.client.from(table).select().eq('couple_id',cid);
        // Keep cached chat bounded; backup export fetches the entire history separately.
        final data = table == 'messages' ? await query.order('created_at',ascending:false).limit(500) : await query;
        next[table] = List<Map<String,dynamic>>.from(data);
      }
      final prefs = await session.client.from('notification_preferences').select().eq('user_id',uid).maybeSingle();
      if (!_current(uid,cid)) return;
      preferences = prefs ?? {'timezone': me?['timezone'] ?? 'Asia/Kolkata'};
      for (final entry in next.entries) {
        await db.replaceRows(entry.key,entry.value);
        if (!_current(uid,cid)) return;
      }
      rows.addAll(next); await _mergePending(); online=true;error=null;
      try {
        await UsWidget.update(session.couple,partner);
        await UsNotifications.reminders(rows,preferences,me?['timezone'] as String? ?? 'Asia/Kolkata',couple:session.couple);
      } catch (_) { /* Device scheduling failures do not turn a successful sync into an offline state. */ }
    } catch (_) {
      if (!_current(uid,cid)) return;
      online=false;error='You are offline. Chat stays here and sends when you reconnect.';
    }
    loading=false;_notify();
  }
  Future<void> _mergePending() async {
    final db=_db; if(db==null)return;
    final pending=await db.pending();queued=0;
    for(final task in pending) {
      final value=Map<String,dynamic>.from(jsonDecode(task.payload) as Map);
      if(value['couple_id'] != _cid) continue;
      queued++;
      value['_pending']=true;value['_local_file']=task.localFile;value['_failure']=task.failure;
      final list=rows.putIfAbsent(task.tableNameKey,()=>[]);
      list.removeWhere((r)=>r['id']==task.taskId);list.add(value);
    }
  }
  Future<void> eraseLocal() async {
    final db=_db;
    if(db!=null){for(final task in await db.pending()){if(task.localFile!=null){try{await File(task.localFile!).delete();}catch(_){}}}await db.clear();}
    rows.clear();queued=0;await UsWidget.clear();
    await UsNotifications.plugin.cancelAll();
  }
  Future<void> send(String body,{String? file,String? kind,String? replyTo,bool memory=false,String? caption,DateTime? memoryDate}) async {
    final cid=_cid,uid=_uid,db=_db;
    if(cid==null||uid==null||db==null)throw StateError('Sign in and pair first.');
    if(body.trim().isEmpty && file==null) return;
    final id=const Uuid().v4();
    final row=<String,dynamic>{'id':id,'couple_id':cid,memory?'author_id':'sender_id':uid,
      'created_at':DateTime.now().toUtc().toIso8601String()};
    if(memory) { row['caption']=caption??body;row['memory_date']=(memoryDate??DateTime.now()).toIso8601String().substring(0,10); }
    else { row['body']=body.trim().isEmpty?null:body.trim();if(replyTo!=null)row['reply_to']=replyTo; }
    if(file!=null){row['media_path']='$cid/$uid/$id.${kind=='voice'?'m4a':'jpg'}';if(!memory)row['media_kind']=kind;}
    await db.enqueue(memory?'memories':'messages',row,file:file);
    await _mergePending();_notify();unawaited(sync());
  }
  Future<void> sync() async {
    if(syncing || _dead || _db==null || _uid==null || _cid==null)return;
    final db=_db!,uid=_uid!,cid=_cid!;syncing=true;
    try {
      for(final task in await db.pending()) {
        if(!_current(uid,cid))break;
        final row=Map<String,dynamic>.from(jsonDecode(task.payload) as Map);
        if(row['couple_id']!=cid)continue;
        try {
          if(task.localFile!=null){
            final file=File(task.localFile!);
            if(!await file.exists())throw StateError('Media file is missing.');
            if(await file.length()>5242880)throw StateError('Keep media below 5 MB.');
            try {await session.client.storage.from('couple-media').upload(row['media_path'] as String,file,
              fileOptions:FileOptions(contentType:(row['media_kind']=='voice')?'audio/mp4':'image/jpeg'));}
            on StorageException catch(e) {if(e.statusCode!='409' && e.statusCode!='400')rethrow;
              // A deterministic path may already exist after an interrupted upload. Verify access before retrying the row.
              await session.client.storage.from('couple-media').createSignedUrl(row['media_path'] as String,60);}
          }
          if(!_current(uid,cid))break;
          await session.client.from(task.tableNameKey).upsert(row,onConflict:'id',ignoreDuplicates:true);
          if(!_current(uid,cid))break;
          await db.complete(task.taskId);
          if(task.localFile!=null){try{await File(task.localFile!).delete();}catch(_){}}
        }catch(e){
          await db.fail(task.taskId,e is StateError?e.message.toString():'Waiting for connection',task.attempts+1);
          online=false;break;
        }
      }
    }finally{syncing=false;if(_current(uid,cid)){await _mergePending();_notify();}}
    if(_current(uid,cid))await refresh();
  }
  Future<void> add(String table,Map<String,dynamic> fields) async {
    if(_uid==null||_cid==null)throw StateError('Pair first.');
    await session.client.from(table).insert({'id':const Uuid().v4(),'couple_id':_cid,
      table=='reactions'?'user_id':'author_id':_uid,...fields});await refresh();
  }
  Future<void> update(String table,String id,Map<String,dynamic> fields) async {
    await session.client.from(table).update(fields).eq('id',id).eq('couple_id',_cid!);await refresh();
  }
  Future<void> remove(String table,String id) async {
    await session.client.from(table).delete().eq('id',id).eq('couple_id',_cid!);await refresh();
  }
  Future<Map<String,dynamic>> missMe() async => Map<String,dynamic>.from(
    await session.client.rpc('send_miss_me',params:{'p_couple':_cid}) as Map);
  Future<void> profile(Map<String,dynamic> values) async {
    await session.client.from('profiles').update(values).eq('user_id',_uid!).eq('couple_id',_cid!);await refresh();
  }
  Future<void> setPreferences(Map<String,dynamic> values) async {
    final newPrefs={...preferences,...values,'user_id':_uid};
    final existing=await session.client.from('notification_preferences').select('user_id').eq('user_id',_uid!).maybeSingle();
    if(existing==null)await session.client.from('notification_preferences').insert(newPrefs);
    else {newPrefs.remove('user_id');await session.client.from('notification_preferences').update(newPrefs).eq('user_id',_uid!);}
    await refresh();
  }
  Future<void> messageState(String id,{bool hidden=false}) async {
    final value=<String,dynamic>{'message_id':id,'couple_id':_cid,'user_id':_uid};
    value[hidden?'hidden':'read_at']=hidden?true:DateTime.now().toUtc().toIso8601String();
    final existing=await session.client.from('message_states').select('user_id').eq('message_id',id).eq('user_id',_uid!).maybeSingle();
    if(existing==null){
      try{await session.client.from('message_states').insert(value);return;}
      on PostgrestException catch(e){if(e.code!='23505')rethrow;}
    }
    await session.client.from('message_states').update({hidden?'hidden':'read_at':value[hidden?'hidden':'read_at']}).eq('message_id',id).eq('user_id',_uid!);
  }
  Future<void> react(String id,{bool memory=false}) async {
    final existing=(rows['reactions']??[]).where((r)=>r['user_id']==_uid&&r[memory?'memory_id':'message_id']==id).firstOrNull;
    if(existing!=null)await remove('reactions',existing['id'] as String);
    else await add('reactions',{memory?'memory_id':'message_id':id});
  }
  Future<String> mediaUrl(String path) => session.client.storage.from('couple-media').createSignedUrl(path,300);
  Future<void> respond(String dateId,String status,{DateTime? proposed}) async {
    final fields={'status':status,'proposed_at':proposed?.toUtc().toIso8601String(),'updated_at':DateTime.now().toUtc().toIso8601String()};
    final existing=await session.client.from('date_responses').select('user_id').eq('date_id',dateId).eq('user_id',_uid!).maybeSingle();
    if(existing==null)await session.client.from('date_responses').insert({'date_id':dateId,'couple_id':_cid,'user_id':_uid,...fields});
    else await session.client.from('date_responses').update(fields).eq('date_id',dateId).eq('user_id',_uid!);
    await refresh();
  }
  @override
  void dispose(){_dead=true;WidgetsBinding.instance.removeObserver(this);session.removeListener(_sessionChanged);_timer?.cancel();_typingTimer?.cancel();unawaited(_disconnect());super.dispose();}
}
