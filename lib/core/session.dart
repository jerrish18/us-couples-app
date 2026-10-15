import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final sessionProvider = Provider<UsSession>((ref) {
  final session = UsSession(Supabase.instance.client);
  ref.onDispose(session.dispose);
  return session;
});

class SecureSessionStorage extends LocalStorage {
  final _storage = const FlutterSecureStorage();
  static const _key = 'us.auth.session';
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);
  @override
  Future<void> persistSession(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

class UsSession extends ChangeNotifier {
  UsSession(this.client) {
    _auth = client.auth.onAuthStateChange.listen((_) {
      ready = false;
      if (!_disposed) notifyListeners();
      // Do not run Supabase requests inside an auth callback.
      unawaited(Future<void>.delayed(Duration.zero, refresh));
    }, onError: (Object _) {
      error = 'Sign-in could not finish. Please try again.';
      ready = true; if (!_disposed) notifyListeners();
    });
    unawaited(refresh());
  }
  final SupabaseClient client;
  StreamSubscription<AuthState>? _auth;
  Map<String, dynamic>? couple;
  String? error;
  bool ready = false;
  bool _disposed = false;
  int _generation = 0;
  String? get userId => client.auth.currentUser?.id;
  String? get coupleId => couple?['id'] as String?;
  String? get partnerId => couple == null ? null
      : (couple!['owner_id'] == userId ? couple!['partner_id'] : couple!['owner_id']) as String?;

  Future<void> refresh() async {
    final generation = ++_generation;
    final uid = userId;
    error = null;
    try {
      final data = uid == null ? null : await client.from('couples')
          .select().or('owner_id.eq.$uid,partner_id.eq.$uid').maybeSingle();
      if (_disposed || generation != _generation) return;
      couple = data;
      if(uid!=null){
        const storage=FlutterSecureStorage();
        if(data==null)await storage.delete(key:'us.couple.$uid');
        else await storage.write(key:'us.couple.$uid',value:jsonEncode(data));
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      try {
        final saved=uid==null?null:await const FlutterSecureStorage().read(key:'us.couple.$uid');
        if (_disposed || generation != _generation) return;
        couple=saved==null?null:Map<String,dynamic>.from(jsonDecode(saved) as Map);
      } catch (_) { couple=null; }
      error = 'Could not connect. Check your internet and try again.';
      if(couple!=null)error=null;
    }
    ready = true;
    if (!_disposed) notifyListeners();
  }

  Future<String> create(String name, DateTime? since) async {
    final result = Map<String, dynamic>.from(await client.rpc('create_couple', params: {
      'p_name': name.trim(), 'p_since': since?.toIso8601String().substring(0, 10),
    }) as Map);
    await refresh();
    return result['invite_code'] as String;
  }
  Future<void> join(String code) async {
    final result = Map<String, dynamic>.from(await client.rpc('join_couple', params: {'p_code': code.trim().toUpperCase()}) as Map);
    if (result['error'] != null) {
      throw StateError(result['error'] == 'try_later' ? 'Please wait 15 minutes before trying again.'
          : result['error'] == 'already_paired' ? 'You already have a couple space.'
          : 'This code is invalid or the space is already locked.');
    }
    await refresh();
  }
  Future<String?> invite() async => await client.rpc('get_invite') as String?;
  @override
  void dispose() {
    _disposed = true;
    _auth?.cancel();
    super.dispose();
  }
}
