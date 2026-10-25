import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/session.dart';
import '../echo/phone_runtime.dart';
import '../echo/phone_conversation.dart';
import 'package:timezone/timezone.dart' as tz;

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
    phone.addListener(_phoneChanged);
    phone.preferencesChanged = _phonePreferencesChanged;
    unawaited(
      phone
          .initialize()
          .then((_) {
            if (!_dead) _notify();
          })
          .catchError((Object _) {}),
    );
    _sessionChanged();
  }
  final UsSession session;
  final phone = PhoneAiRuntime.instance;
  PhoneConversation? _phoneConversation;
  Map<String, dynamic>? _echoPrefs;
  Timer? _autoAnswer;
  String? _autoAttempt;
  bool _aiAvailable = false;
  String aiAvailability = 'Set up phone AI in ECHO settings';
  bool get canAiAnswer => _aiAvailable && !_busy && !aiRequested;
  void _phonePreferencesChanged() {
    unawaited(_warmPhonePreferences(_epoch).then((_) => refresh()));
  }

  void _phoneChanged() {
    if (!_dead) {
      if (phone.preferPhone)
        _aiAvailable =
            phone.ready &&
            _echoPrefs?['enabled'] == true &&
            _echoPrefs?['host'] == 'phone' &&
            phone.language == _echoPrefs?['language'];
      if (call != null) _schedulePhoneAnswer(call!);
      _notify();
    }
  }

  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  Map<String, dynamic>? call;
  Map<String, dynamic>? echoSession;
  bool _echoTakingOver = false, _signalingReady = false;
  bool aiRequested = false;
  bool get echoActive =>
      echoSession != null && echoSession!['state'] != 'ended';
  bool get echoForMe => echoActive && call?['callee_id'] == session.userId;
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
  bool get canTakeOverEcho =>
      echoForMe &&
      !_busy &&
      (_phoneConversation != null
          ? !_phoneConversation!.human
          : echoSession?['host'] != 'phone' && _peer == null);
  void _notify() {
    if (!_dead) notifyListeners();
  }

  void _sessionChanged() {
    final cid = session.coupleId;
    if (cid == _cid && _uid == session.userId) return;
    if (_uid != null &&
        (_uid != session.userId || (_cid != null && cid != _cid)))
      unawaited(phone.shutdown().catchError((Object _) {}));
    _uid = session.userId;
    _cid = cid;
    _echoPrefs = null;
    _aiAvailable = false;
    _autoAttempt = null;
    _autoAnswer?.cancel();
    _epoch++;
    if (_channel != null) unawaited(session.client.removeChannel(_channel!));
    _channel = null;
    _poll?.cancel();
    call = null;
    echoSession = null;
    aiRequested = false;
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
        if ((_foreground || phone.readyService) &&
            (call != null || ++_idlePolls % 6 == 0))
          refresh();
      });
      unawaited(refresh());
      unawaited(_warmPhonePreferences(_epoch));
    }
    _notify();
  }

  Future<void> _warmPhonePreferences(int epoch) async {
    try {
      await phone.initialize();
      if (!phone.preferPhone ||
          session.coupleId == null ||
          _dead ||
          epoch != _epoch)
        return;
      final prefs = await session.client
          .from('echo_preferences')
          .select()
          .eq('couple_id', session.coupleId!)
          .eq('user_id', session.userId!)
          .maybeSingle();
      if (_dead || epoch != _epoch || prefs == null) return;
      _echoPrefs = Map<String, dynamic>.from(prefs);
      if (prefs['enabled'] == true &&
          prefs['host'] == 'phone' &&
          _foreground &&
          await phone.models.available(phone.plus)) {
        await phone.prepare('${prefs['language']}');
        if (_dead || epoch != _epoch) return;
        if (phone.keepReady && _foreground) await phone.startReady();
        _phoneChanged();
      }
    } catch (_) {
      /* Keep normal calls available when models/voices are unavailable. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) refresh();
  }

  Future<void> refresh() async {
    if (_dead || _cid == null || _refreshing) return;
    _refreshing = true;
    final cid = _cid, epoch = _epoch;
    try {
      final rows = await session.client
          .from('calls')
          .select()
          .eq('couple_id', cid!)
          .order('created_at', ascending: false)
          .limit(1);
      if (_dead || epoch != _epoch || cid != _cid || rows.isEmpty) return;
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
      if (call?['id'] != row['id']) {
        echoSession = null;
        aiRequested = false;
      }
      call = row;
      if (row['callee_id'] == session.userId) {
        try {
          final prefs = await session.client
              .from('echo_preferences')
              .select()
              .eq('couple_id', cid)
              .eq('user_id', session.userId!)
              .maybeSingle();
          if (_dead || epoch != _epoch) return;
          _echoPrefs = prefs == null ? null : Map<String, dynamic>.from(prefs);
          if (_phoneConversation != null && prefs != null)
            await _phoneConversation!.updatePreferences(
              Map<String, dynamic>.from(prefs),
            );
          if (phone.preferPhone) {
            _aiAvailable =
                phone.ready &&
                prefs?['enabled'] == true &&
                prefs?['host'] == 'phone' &&
                phone.language == prefs?['language'];
            aiAvailability = phone.ready
                ? 'Enable and save phone answering in ECHO settings'
                : 'Download and prepare models in ECHO settings';
          } else {
            final device = await session.client
                .from('echo_devices')
                .select()
                .eq('user_id', session.userId!)
                .maybeSingle();
            final beat = DateTime.tryParse('${device?['heartbeat']}');
            _aiAvailable =
                device?['ready'] == true &&
                beat != null &&
                DateTime.now().toUtc().difference(beat.toUtc()).inSeconds <
                    20 &&
                prefs?['enabled'] == true &&
                prefs?['host'] == 'bridge';
            aiAvailability = _aiAvailable
                ? 'Your Mac bridge is ready'
                : 'Your selected Mac bridge is offline';
          }
          _schedulePhoneAnswer(row);
        } catch (_) {
          _aiAvailable = false;
        }
      }
      try {
        final echo = await session.client
            .from('echo_sessions')
            .select()
            .eq('call_id', row['id'] as String)
            .maybeSingle();
        if (_dead || epoch != _epoch || call?['id'] != row['id']) return;
        echoSession = _phoneConversation != null
            ? _phoneConversation!.snapshot(
                echo == null ? null : Map<String, dynamic>.from(echo),
              )
            : echo == null
            ? null
            : Map<String, dynamic>.from(echo);
        if (_echoTakingOver &&
            _peer != null &&
            !_remoteSet &&
            echoSession?['human_answer'] != null) {
          await _peer!.setRemoteDescription(
            RTCSessionDescription(
              echoSession!['human_answer'] as String,
              'answer',
            ),
          );
          _remoteSet = true;
        }
      } catch (_) {
        /* Older databases keep their existing call behavior. */
      }
      if (_peer != null &&
          !_remoteSet &&
          row['caller_id'] == session.userId &&
          row['answer'] != null) {
        await _peer!.setRemoteDescription(
          RTCSessionDescription(row['answer'] as String, 'answer'),
        );
        _remoteSet = true;
      }
      if (_remoteSet && !_echoTakingOver) _queueCandidates();
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
    if (_dead || epoch != _epoch) throw StateError('Session changed');
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
          'channelCount': 1,
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
        if (candidate.candidate == null || _echoTakingOver) return;
        if (call == null || !_signalingReady) {
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
          if (_phoneConversation != null)
            unawaited(_phoneConversation!.connected());
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
          _disconnect = Timer(
            const Duration(seconds: 20),
            () => _connectionFailed(),
          );
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed)
          unawaited(_connectionFailed());
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
      _signalingReady = true;
      for (final c in _outbound) {
        await _candidate(c);
      }
      _outbound.clear();
      _timeout = Timer(const Duration(seconds: 60), () {
        // Connection can complete while candidate writes are still awaiting I/O,
        // before this timer is assigned. Never end an already connected call.
        if (call?['id'] == row['id'] &&
            connection != 'RTCPeerConnectionStateConnected')
          unawaited(end('missed'));
      });
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
      final row = Map<String, dynamic>.from(call!), epoch = _epoch;
      final id = row['id'] as String;
      await _setup(video);
      if (_dead || epoch != _epoch || call?['id'] != id || !incoming) {
        await _release();
        return;
      }
      await _peer!.setRemoteDescription(
        RTCSessionDescription(row['offer'] as String, 'offer'),
      );
      _remoteSet = true;
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      final claimed = await session.client
          .from('calls')
          .update({'answer': answer.sdp, 'state': 'connecting'})
          .eq('id', id)
          .eq('state', 'ringing')
          .select('id');
      if (claimed.isEmpty) {
        await _release();
        await refresh();
        return;
      }
      _signalingReady = true;
      for (final c in _outbound) {
        await _candidate(c);
      }
      _outbound.clear();
      _timeout = Timer(const Duration(seconds: 45), () {
        if (call?['id'] == id &&
            connection != 'RTCPeerConnectionStateConnected')
          unawaited(end('failed'));
      });
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

  Future<void> _connectionFailed() async {
    if (_echoTakingOver && echoForMe) {
      await _release();
      error =
          'The takeover connection stopped. The original caller remains with the bridge.';
      _notify();
    } else {
      await end('failed');
    }
  }

  Future<void> requestAiAnswer() async {
    if (phone.preferPhone) {
      await _answerOnPhone();
      return;
    }
    if (!incoming || video || _busy) return;
    final id = call!['id'] as String, epoch = _epoch;
    _busy = true;
    error = null;
    _notify();
    try {
      final device = await session.client
          .from('echo_devices')
          .select()
          .eq('user_id', session.userId!)
          .maybeSingle();
      final beat = DateTime.tryParse('${device?['heartbeat']}');
      if (device?['ready'] != true ||
          beat == null ||
          DateTime.now().toUtc().difference(beat.toUtc()).inSeconds >= 20) {
        throw StateError(
          'Your ECHO bridge is offline. Start it on your Mac, or answer normally.',
        );
      }
      final prefs = await session.client
          .from('echo_preferences')
          .select('enabled')
          .eq('couple_id', session.coupleId!)
          .eq('user_id', session.userId!)
          .maybeSingle();
      if (prefs?['enabled'] != true)
        throw StateError('Enable ECHO in Profile and settings first.');
      if (_dead || epoch != _epoch || call?['id'] != id || !incoming) return;
      await session.client.from('echo_requests').upsert({
        'call_id': id,
        'user_id': session.userId,
      });
      aiRequested = true;
    } catch (e) {
      if (epoch == _epoch)
        error = e is StateError
            ? '${e.message}'
            : 'Could not request ECHO. You can answer normally.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _schedulePhoneAnswer(Map<String, dynamic> row) {
    _autoAnswer?.cancel();
    final prefs = _echoPrefs;
    if (!incoming ||
        video ||
        !phone.preferPhone ||
        !_aiAvailable ||
        prefs == null ||
        prefs['rule'] == 'manual' ||
        !(_foreground || phone.readyService) ||
        _autoAttempt == row['id'])
      return;
    if (prefs['rule'] == 'schedule') {
      try {
        final local = tz.TZDateTime.from(
          DateTime.now(),
          tz.getLocation('${prefs['timezone']}'),
        );
        final minute = local.hour * 60 + local.minute,
            start = prefs['start_minute'] as int,
            end = prefs['end_minute'] as int;
        if (!(start == end ||
            (start < end
                ? minute >= start && minute < end
                : minute >= start || minute < end)))
          return;
      } catch (_) {
        return;
      }
    }
    final created = DateTime.tryParse('${row['created_at']}');
    if (created == null) return;
    final delay = created
        .add(Duration(seconds: prefs['delay_seconds'] as int))
        .difference(DateTime.now());
    final id = row['id'];
    _autoAnswer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!_dead &&
          call?['id'] == id &&
          incoming &&
          (_foreground || phone.readyService)) {
        _autoAttempt = '$id';
        unawaited(requestAiAnswer());
      }
    });
  }

  Future<void> _answerOnPhone() async {
    if (!incoming || video || _busy) return;
    final row = Map<String, dynamic>.from(call!), epoch = _epoch;
    final id = row['id'] as String;
    _busy = true;
    error = null;
    _notify();
    try {
      if (!phone.ready)
        throw StateError(
          'Download and prepare phone AI in ECHO settings first.',
        );
      final prefs = await session.client
          .from('echo_preferences')
          .select()
          .eq('couple_id', session.coupleId!)
          .eq('user_id', session.userId!)
          .maybeSingle();
      if (prefs?['enabled'] != true || prefs?['host'] != 'phone')
        throw StateError(
          'Enable and save phone answering in ECHO settings first.',
        );
      if (phone.language != prefs?['language'])
        throw StateError('Prepare the selected language in ECHO settings.');
      if (_dead || epoch != _epoch || call?['id'] != id || !incoming) return;
      await _setup(false);
      if (_dead || epoch != _epoch || call?['id'] != id || !incoming) {
        await _release();
        return;
      }
      final conversation = PhoneConversation(
        runtime: phone,
        session: session,
        callId: id,
        coupleId: session.coupleId!,
        preferences: Map<String, dynamic>.from(prefs!),
        onChanged: () {
          if (!_dead && call?['id'] == id) {
            echoSession = _phoneConversation?.snapshot(echoSession);
            _notify();
          }
        },
      );
      _phoneConversation = conversation;
      await conversation.arm();
      await _peer!.setRemoteDescription(
        RTCSessionDescription(row['offer'] as String, 'offer'),
      );
      _remoteSet = true;
      await _peer!.setLocalDescription(await _peer!.createAnswer());
      final description = await _peer!.getLocalDescription();
      final claimed = await session.client.rpc(
        'echo_answer_phone',
        params: {'p_call': id, 'p_answer': description!.sdp},
      );
      if (claimed != true) {
        await _release();
        await refresh();
        return;
      }
      conversation.claimed = true;
      echoSession = conversation.snapshot(null);
      _signalingReady = true;
      for (final candidate in _outbound) {
        await _candidate(candidate);
      }
      _outbound.clear();
      if (connection == 'RTCPeerConnectionStateConnected')
        unawaited(conversation.connected());
      _timeout = Timer(const Duration(seconds: 45), () {
        if (call?['id'] == id &&
            connection != 'RTCPeerConnectionStateConnected')
          unawaited(end('failed'));
      });
      await refresh();
      _queueCandidates();
    } catch (e) {
      await _release();
      if (epoch == _epoch)
        error = e is StateError
            ? '${e.message}'
            : 'Could not start phone AI. You can answer normally.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> takeOverEcho() async {
    if (_phoneConversation != null) {
      if (_busy) return;
      _busy = true;
      _notify();
      try {
        await _phoneConversation!.takeOver();
        echoSession = _phoneConversation!.snapshot(echoSession);
      } catch (_) {
        error =
            'Your call is still connected. Check the takeover status and try again.';
      } finally {
        _busy = false;
        _notify();
      }
      return;
    }
    if (!echoForMe || _busy || _peer != null) return;
    final id = call!['id'] as String, epoch = _epoch;
    _busy = true;
    error = null;
    _echoTakingOver = true;
    _notify();
    try {
      await _setup(false);
      if (_dead || epoch != _epoch || call?['id'] != id) {
        await _release();
        return;
      }
      final peer = _peer!;
      final gathered = Completer<void>();
      peer.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
            !gathered.isCompleted)
          gathered.complete();
      };
      await peer.setLocalDescription(await peer.createOffer());
      if (peer.iceGatheringState !=
          RTCIceGatheringState.RTCIceGatheringStateComplete) {
        await gathered.future.timeout(const Duration(seconds: 12));
      }
      if (_dead || epoch != _epoch || call?['id'] != id) {
        await _release();
        return;
      }
      final offer = await peer.getLocalDescription();
      await session.client
          .from('echo_sessions')
          .update({'human_offer': offer!.sdp, 'human_answer': null})
          .eq('call_id', id);
      await refresh();
      // A failed takeover releases only this phone's new leg. The original
      // caller-to-bridge media connection continues answering with ECHO.
      _timeout = Timer(const Duration(seconds: 30), () async {
        if (_peer == peer && connection != 'RTCPeerConnectionStateConnected') {
          await _release();
          error =
              'Takeover did not connect. ECHO is still on the call; try again.';
          _notify();
        }
      });
    } catch (_) {
      await _release();
      error = 'Could not take over. ECHO remains on the call. Please retry.';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> eraseEchoTranscript() async {
    if (!echoForMe) return;
    try {
      // Disable future saves before clearing existing records.
      await session.client
          .from('echo_preferences')
          .update({'retain_transcript': false})
          .eq('couple_id', session.coupleId!)
          .eq('user_id', session.userId!);
      await session.client
          .from('echo_sessions')
          .update({'transcript': [], 'summary': '', 'important': ''})
          .eq('call_id', call!['id'] as String);
      await refresh();
    } catch (_) {
      error =
          'Could not erase the transcript. Check your connection and retry.';
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
    echoSession = null;
    aiRequested = false;
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
    _autoAnswer?.cancel();
    final conversation = _phoneConversation;
    _phoneConversation = null;
    await conversation?.close();
    final peer = _peer, stream = _stream;
    _peer = null;
    _stream = null;
    _remoteSet = false;
    _echoTakingOver = false;
    _signalingReady = false;
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
    if (conversation != null) {
      try {
        await PhoneAiRuntime.native.invokeMethod('release');
      } catch (_) {}
    }
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
    phone.removeListener(_phoneChanged);
    if (phone.preferencesChanged == _phonePreferencesChanged)
      phone.preferencesChanged = null;
    _autoAnswer?.cancel();
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
