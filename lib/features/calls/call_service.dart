import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/session.dart';

final callProvider = Provider<CallService>((ref) {
  final c = CallService(ref.read(sessionProvider));
  ref.onDispose(c.dispose);
  return c;
});
const terminalCallStates = {'ended', 'declined', 'missed', 'failed'};
bool liveCall(Map<String, dynamic> row, DateTime now) =>
    !terminalCallStates.contains(row['state']) &&
    (DateTime.tryParse('${row['expires_at']}')?.isAfter(now) ?? false);

class CallService extends ChangeNotifier with WidgetsBindingObserver {
  CallService(this.session) {
    session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _native.setMethodCallHandler((call) async {
      if (call.method == 'endCall') await end();
    });
    _sessionChanged();
  }
  final UsSession session;
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  Map<String, dynamic>? call;
  RTCPeerConnection? _peer;
  MediaStream? _stream;
  RealtimeChannel? _channel;
  String? _cid, _uid;
  bool _dead = false, _busy = false, _remoteSet = false, _refreshing = false;
  int _epoch = 0, _idlePolls = 0;
  bool _foreground = true;
  bool muted = false, speaker = false, cameraEnabled = true;
  String? error;
  String connection = '';
  Timer? _poll, _timeout, _disconnect;
  final _seen = <String>{};
  final _outbound = <RTCIceCandidate>[];
  Future<void>? _rendering;
  Future<void> _serial = Future.value();
  Future<void> _releasing = Future.value();
  static const _native = MethodChannel('us/presentation');
  bool get incoming =>
      call?['callee_id'] == session.userId && call?['state'] == 'ringing';
  bool get video => call?['video'] == true;
  bool get busy => _busy;
  void _notify() {
    if (!_dead) notifyListeners();
  }

  void _sessionChanged() {
    final cid = session.coupleId;
    if (cid == _cid && _uid == session.userId) return;
    _uid = session.userId;
    _cid = cid;
    _epoch++;
    if (_channel != null) unawaited(session.client.removeChannel(_channel!));
    _channel = null;
    _poll?.cancel();
    call = null;
    unawaited(_release());
    if (cid != null) {
      _channel = session.client
          .channel('calls:$cid:${session.userId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'couple_id',
              value: cid,
            ),
            callback: (_) => refresh(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'call_candidates',
            callback: (_) => _queueCandidates(),
          )
          .subscribe();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_foreground && (call != null || ++_idlePolls % 6 == 0)) refresh();
      });
      unawaited(refresh());
    }
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) refresh();
  }

  Future<void> refresh() async {
    if (_dead || _cid == null || _refreshing) return;
    _refreshing = true;
    final cid = _cid;
    try {
      final rows = await session.client
          .from('calls')
          .select()
          .eq('couple_id', cid!)
          .order('created_at', ascending: false)
          .limit(1);
      if (_dead || cid != _cid || rows.isEmpty) return;
      final row = Map<String, dynamic>.from(rows.first);
      if (call != null && call!['id'] != row['id'] && _peer != null) return;
      if (!liveCall(row, DateTime.now().toUtc())) {
        if (call?['id'] == row['id']) {
          if (!terminalCallStates.contains(row['state']))
            unawaited(
              session.client
                  .from('calls')
                  .update({'state': 'missed'})
                  .eq('id', row['id'] as String)
                  .then((_) {})
                  .catchError((_) {}),
            );
          call = null;
          await _release();
          _notify();
        }
        return;
      }
      call = row;
      if (_peer != null &&
          !_remoteSet &&
          row['caller_id'] == session.userId &&
          row['answer'] != null) {
        await _peer!.setRemoteDescription(
          RTCSessionDescription(row['answer'] as String, 'answer'),
        );
        _remoteSet = true;
      }
      if (_remoteSet) _queueCandidates();
      _notify();
    } catch (_) {
      /* Poll again after a network interruption. */
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _setup(bool useVideo) async {
    await _releasing;
    final epoch = _epoch;
    try {
      await _native.invokeMethod('callPermissions');
    } catch (_) {}
    _rendering ??= Future.wait([local.initialize(), remote.initialize()]);
    await _rendering;
    // TURN credentials can be provided by the authenticated edge endpoint.
    // No long-lived relay credentials are embedded in the app.
    final ice = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
    try {
      final result = await session.client.functions
          .invoke('call-relay')
          .timeout(const Duration(seconds: 5));
      final servers = (result.data as Map?)?['iceServers'];
      if (servers is List)
        ice.addAll(servers.map((x) => Map<String, dynamic>.from(x as Map)));
    } catch (_) {
      /* Direct connections remain available without a relay. */
    }
    _peer = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
    });
    try {
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': useVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 30, 'max': 30},
              }
            : false,
      });
      if (_dead || epoch != _epoch) {
        await _release();
        throw StateError('Session changed');
      }
      local.srcObject = _stream;
      for (final track in _stream!.getTracks()) {
        await _peer!.addTrack(track, _stream!);
      }
      final activePeer = _peer;
      _peer!.onTrack = (event) {
        if (_peer != activePeer) return;
        if (event.streams.isNotEmpty) {
          remote.srcObject = event.streams.first;
          _notify();
        }
      };
      _peer!.onIceCandidate = (candidate) {
        if (_peer != activePeer) return;
        if (candidate.candidate == null) return;
        if (call == null) {
          _outbound.add(candidate);
        } else {
          unawaited(_candidate(candidate));
        }
      };
      _peer!.onConnectionState = (state) {
        if (_peer != activePeer) return;
        connection = state.name;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _timeout?.cancel();
          _disconnect?.cancel();
          if (call != null)
            unawaited(
              session.client
                  .from('calls')
                  .update({'state': 'connected'})
                  .eq('id', call!['id'] as String)
                  .then((_) {})
                  .catchError((_) {}),
            );
        }
        if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _disconnect?.cancel();
          _disconnect = Timer(const Duration(seconds: 20), () => end('failed'));
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed)
          unawaited(end('failed'));
        _notify();
      };
      speaker = useVideo;
      await Helper.setSpeakerphoneOn(speaker);
      try {
        await _native.invokeMethod('startCall', {'video': useVideo});
      } catch (_) {}
    } catch (_) {
      await _release();
      rethrow;
    }
  }

  Future<void> start({required bool video}) async {
    if (_busy || call != null || session.partnerId == null) return;
    _busy = true;
    error = null;
    _notify();
    try {
      final epoch = _epoch;
      await _setup(video);
      if (_dead || epoch != _epoch) return;
      final offer = await _peer!.createOffer();
      await _peer!.setLocalDescription(offer);
      final row = await session.client
          .from('calls')
          .insert({
            'couple_id': session.coupleId,
            'caller_id': session.userId,
            'callee_id': session.partnerId,
            'video': video,
            'offer': offer.sdp,
          })
          .select()
          .single();
      if (_dead || epoch != _epoch) {
        await _release();
        return;
      }
      call = Map<String, dynamic>.from(row);
      for (final c in _outbound) {
        await _candidate(c);
      }
      _outbound.clear();
      _timeout = Timer(const Duration(seconds: 60), () => end('missed'));
    } catch (_) {
      error =
          'Could not start the call. Check microphone/camera permissions and your connection.';
      await _release();
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> answer() async {
    if (!incoming || _busy) return;
    _busy = true;
    error = null;
    _notify();
    try {
      final id = call!['id'] as String;
      await _setup(video);
      await _peer!.setRemoteDescription(
        RTCSessionDescription(call!['offer'] as String, 'offer'),
      );
      _remoteSet = true;
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await session.client
          .from('calls')
          .update({'answer': answer.sdp, 'state': 'connecting'})
          .eq('id', id);
      for (final c in _outbound) {
        await _candidate(c);
      }
      _outbound.clear();
      _timeout = Timer(const Duration(seconds: 45), () => end('failed'));
      await refresh();
      _queueCandidates();
    } catch (_) {
      error = 'Could not connect. Check permissions and try again.';
      await end('failed');
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _candidate(RTCIceCandidate c) async {
    try {
      if (call != null)
        await session.client.from('call_candidates').insert({
          'call_id': call!['id'],
          'sender_id': session.userId,
          'candidate': c.toMap(),
        });
    } catch (_) {
      /* Reconnection may fail; the connection timeout handles this. */
    }
  }

  void _queueCandidates() {
    _serial = _serial.then((_) => _readCandidates()).catchError((_) {});
  }

  Future<void> _readCandidates() async {
    final peer = _peer, id = call?['id'];
    if (peer == null || id == null || !_remoteSet) return;
    final rows = await session.client
        .from('call_candidates')
        .select()
        .eq('call_id', id)
        .neq('sender_id', session.userId!);
    for (final r in rows) {
      if (_peer != peer) return;
      if (_seen.contains(r['id'])) continue;
      final c = Map<String, dynamic>.from(r['candidate'] as Map);
      await peer.addCandidate(
        RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        ),
      );
      _seen.add(r['id'] as String);
    }
  }

  Future<void> toggleMute() async {
    muted = !muted;
    for (final t in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    _notify();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    _notify();
  }

  Future<void> toggleCamera() async {
    cameraEnabled = !cameraEnabled;
    for (final t in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = cameraEnabled;
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final track = _stream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  Future<void> end([String state = 'ended']) async {
    final id = call?['id'];
    call = null;
    await _release();
    _notify();
    if (id != null) {
      try {
        await session.client
            .from('calls')
            .update({'state': state})
            .eq('id', id);
      } catch (_) {
        /* Server expiry repairs an unreachable call. */
      }
    }
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> _release() {
    _releasing = _releasing.then((_) => _releaseNow()).catchError((_) {});
    return _releasing;
  }

  Future<void> _releaseNow() async {
    _timeout?.cancel();
    _disconnect?.cancel();
    final peer = _peer, stream = _stream;
    _peer = null;
    _stream = null;
    _remoteSet = false;
    _seen.clear();
    _outbound.clear();
    if (_rendering != null) {
      local.srcObject = null;
      remote.srcObject = null;
    }
    for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await stream?.dispose();
    await peer?.close();
    await peer?.dispose();
    muted = false;
    speaker = false;
    cameraEnabled = true;
    connection = '';
    try {
      await _native.invokeMethod('stopCall');
    } catch (_) {}
  }

  @override
  void dispose() {
    _dead = true;
    _native.setMethodCallHandler(null);
    session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    if (_channel != null) unawaited(session.client.removeChannel(_channel!));
    unawaited(
      _release().then((_) async {
        if (_rendering != null) {
          await _rendering;
          await local.dispose();
          await remote.dispose();
        }
      }),
    );
    super.dispose();
  }
}
