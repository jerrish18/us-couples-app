import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:llamadart/llamadart.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'phone_models.dart';

abstract interface class PhoneTextModel {
  Future<void> load(String path, {required bool plus});
  Stream<String> generate(
    List<Map<String, String>> messages, {
    Map<String, dynamic>? schema,
    int maxTokens = 128,
  });
  void cancel();
  Future<void> close();
}

class LocalLlamaModel implements PhoneTextModel {
  LlamaEngine? _engine;
  @override
  Future<void> load(String path, {required bool plus}) async {
    await close();
    _engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(path)),
      params: LlamaCppModelParams(
        contextSize: plus ? 4096 : 2048,
        device: ComputeDevice.cpu,
        gpuLayers: 0,
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        batchSize: 128,
        microBatchSize: 64,
      ),
    );
  }

  @override
  Stream<String> generate(
    List<Map<String, String>> messages, {
    Map<String, dynamic>? schema,
    int maxTokens = 128,
  }) async* {
    final engine = _engine;
    if (engine == null)
      throw StateError('Download and prepare phone models first.');
    final history = [
      for (final m in messages)
        LlamaChatMessage.fromText(
          role: switch (m['role']) {
            'system' => LlamaChatRole.system,
            'assistant' => LlamaChatRole.assistant,
            _ => LlamaChatRole.user,
          },
          text: m['content'] ?? '',
        ),
    ];
    await for (final chunk in engine.create(
      history,
      enableThinking: false,
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: .4,
        reusePromptPrefix: false,
      ),
      responseFormat: schema == null
          ? null
          : LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
              schema: schema,
              decoder: (j) => j,
            ).responseFormat,
    )) {
      if (chunk.text.isNotEmpty) yield chunk.text;
    }
  }

  @override
  void cancel() => _engine?.cancelGeneration();
  @override
  Future<void> close() async {
    final e = _engine;
    _engine = null;
    if (e != null) {
      e.cancelGeneration();
      await e.dispose();
    }
  }
}

void _recognizeWorker(Map<String, dynamic> setup) {
  final parent = setup['parent'] as SendPort;
  sherpa.OfflineRecognizer? recognizer;
  final input = ReceivePort();
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: setup['encoder'],
            decoder: setup['decoder'],
            language: setup['language'] == 'English'
                ? 'en'
                : setup['language'] == 'Tamil'
                ? 'ta'
                : '',
            task: 'transcribe',
          ),
          tokens: setup['tokens'],
          modelType: 'whisper',
          numThreads: 2,
          provider: 'cpu',
        ),
      ),
    );
    parent.send({'port': input.sendPort});
  } catch (_) {
    parent.send({'error': 'Could not load offline speech models.'});
    input.close();
    return;
  }
  input.listen((dynamic raw) {
    final m = raw as Map;
    if (m['close'] == true) {
      recognizer?.free();
      input.close();
      parent.send({'closed': true});
      return;
    }
    final id = m['id'];
    final stream = recognizer!.createStream();
    try {
      final bytes = (m['audio'] as TransferableTypedData).materialize();
      stream.acceptWaveform(samples: bytes.asFloat32List(), sampleRate: 16000);
      recognizer.decode(stream);
      parent.send({'id': id, 'text': recognizer.getResult(stream).text.trim()});
    } catch (_) {
      parent.send({'id': id, 'error': 'Offline speech recognition failed.'});
    } finally {
      stream.free();
    }
  });
}

class PhoneSpeechWorker {
  Isolate? _isolate;
  ReceivePort? _receive;
  SendPort? _send;
  final _pending = <int, Completer<String>>{};
  int _next = 0;
  Completer<void>? _closed;
  Future<void> load(PhoneModels models, String language) async {
    await close();
    final ready = Completer<void>();
    _receive = ReceivePort();
    _closed = Completer<void>();
    _receive!.listen((dynamic raw) {
      final m = raw as Map;
      if (m['closed'] == true) {
        _closed?.complete();
        return;
      }
      if (m['port'] is SendPort) {
        _send = m['port'];
        if (!ready.isCompleted) ready.complete();
      } else if (m['id'] is int) {
        final c = _pending.remove(m['id']);
        if (c != null) {
          if (m['error'] != null)
            c.completeError(StateError('${m['error']}'));
          else
            c.complete('${m['text'] ?? ''}');
        }
      } else if (m['error'] != null && !ready.isCompleted)
        ready.completeError(StateError('${m['error']}'));
    });
    _isolate = await Isolate.spawn(_recognizeWorker, {
      'parent': _receive!.sendPort,
      'encoder': await models.path(phoneWhisper[0]),
      'decoder': await models.path(phoneWhisper[1]),
      'tokens': await models.path(phoneWhisper[2]),
      'language': language,
    });
    try {
      await ready.future.timeout(const Duration(seconds: 45));
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<String> transcribe(Float32List samples) async {
    final send = _send;
    if (send == null) throw StateError('Offline speech is not ready.');
    final id = ++_next, c = Completer<String>();
    _pending[id] = c;
    send.send({
      'id': id,
      'audio': TransferableTypedData.fromList([
        samples.buffer.asUint8List(
          samples.offsetInBytes,
          samples.lengthInBytes,
        ),
      ]),
    });
    try {
      return await c.future.timeout(const Duration(seconds: 30));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    if (_isolate == null) {
      _receive?.close();
      _receive = null;
      return;
    }
    final send = _send;
    if (send != null) {
      send.send({'close': true});
      // Wait for native decode to finish and free its model before another load.
      await _closed!.future.timeout(const Duration(seconds: 45));
    } else {
      _isolate!.kill(priority: Isolate.immediate);
    }
    _send = null;
    _isolate = null;
    _receive?.close();
    _receive = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Speech cancelled.'));
    }
    _pending.clear();
  }
}

class PhoneAiRuntime extends ChangeNotifier {
  PhoneAiRuntime({PhoneModels? models, PhoneTextModel? text})
    : models = models ?? PhoneModels(),
      text = text ?? LocalLlamaModel();
  static final instance = PhoneAiRuntime();
  static const native = MethodChannel('us/echo-phone');
  static const events = EventChannel('us/echo-phone-events');
  static const storage = FlutterSecureStorage();
  final PhoneModels models;
  final PhoneTextModel text;
  final speech = PhoneSpeechWorker();
  bool plus = false,
      ready = false,
      preparing = false,
      localCall = false,
      readyService = false;
  bool keepReady = false;
  String host = 'phone',
      language = 'English',
      status = 'Phone models are not prepared';
  Map<String, dynamic> capabilities = {};
  Stream<dynamic>? _events;
  StreamSubscription<dynamic>? _statusSubscription;
  VoidCallback? preferencesChanged;
  bool _dead = false;
  void _notify() {
    if (!_dead) notifyListeners();
  }

  Future<void>? _initializing;
  Stream<dynamic> get audioEvents =>
      _events ??= events.receiveBroadcastStream().asBroadcastStream();
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    host = await storage.read(key: 'echo.host') ?? 'phone';
    plus = await storage.read(key: 'echo.plus') == 'true';
    keepReady = await storage.read(key: 'echo.keepReady') == 'true';
    try {
      capabilities = Map<String, dynamic>.from(
        await native.invokeMethod('capabilities') as Map,
      );
      readyService = capabilities['readyService'] == true;
    } catch (_) {
      capabilities = {};
    }
    if (supported) {
      _statusSubscription = audioEvents.listen(
        (dynamic raw) {
          if (raw is Map && raw['event'] == 'ready') {
            readyService = raw['running'] == true;
            if (!readyService) {
              keepReady = false;
              unawaited(
                storage
                    .write(key: 'echo.keepReady', value: 'false')
                    .catchError((Object _) {}),
              );
            }
            _notify();
          }
        },
        onError: (Object _) {
          readyService = false;
          _notify();
        },
      );
    }
    _notify();
  }

  bool get supported => capabilities['supported'] == true;
  bool get preferPhone => host == 'phone';
  Future<void> setHost(String value) async {
    if (localCall) throw StateError('Finish the call first.');
    if (value != 'phone') {
      await stopReady();
      await unload();
    }
    host = value;
    await storage.write(key: 'echo.host', value: value);
    _notify();
  }

  Future<void> setPlus(bool value) async {
    if (localCall || preparing)
      throw StateError('Finish the current task first.');
    await unload();
    plus = value;
    await storage.write(key: 'echo.plus', value: '$value');
    _notify();
  }

  Future<void> prepare(String selectedLanguage) async {
    if (preparing) return;
    if (ready && language == selectedLanguage) return;
    if (!supported)
      throw StateError(
        'On-phone AI needs a supported 64-bit Android phone (Android 9 or later).',
      );
    if (!await models.available(plus))
      throw StateError('Download the phone models in ECHO settings first.');
    capabilities = Map<String, dynamic>.from(
      await native.invokeMethod('capabilities') as Map,
    );
    final available = capabilities['availableRam'] as num?;
    if (available != null && available < (plus ? 2200 : 1400) * 1024 * 1024)
      throw StateError(
        'Not enough free RAM. Close other apps or choose the smaller model.',
      );
    preparing = true;
    ready = false;
    status = 'Preparing offline speech and AI';
    _notify();
    try {
      capabilities = Map<String, dynamic>.from(
        await native.invokeMethod('capabilities') as Map,
      );
      await native.invokeMethod('prepareVoice', {'language': selectedLanguage});
      await native.invokeMethod('testVoice');
      await speech.load(models, selectedLanguage);
      await text.load(
        await models.path(plus ? phoneLlmPlus : phoneLlmLite),
        plus: plus,
      );
      // A short real generation proves the runtime can run before answering.
      final probe = await text
          .generate([
            {'role': 'user', 'content': 'Say hello in one word.'},
          ], maxTokens: 12)
          .join()
          .timeout(const Duration(seconds: 40));
      if (probe.trim().isEmpty)
        throw StateError(
          'The phone model returned no text. Try the smaller model.',
        );
      language = selectedLanguage;
      ready = true;
      status = 'Ready on this phone';
    } catch (e) {
      await text.close();
      await speech.close();
      status = e is StateError
          ? '${e.message}'
          : 'Could not prepare phone AI. Try the smaller model.';
      rethrow;
    } finally {
      preparing = false;
      _notify();
    }
  }

  Future<void> startReady() async {
    if (!ready) throw StateError('Prepare and test phone AI first.');
    final permissions = await const MethodChannel(
      'us/presentation',
    ).invokeMethod('callPermissions');
    if (permissions != true)
      throw StateError(
        'Allow call permissions before keeping ECHO ready in the background.',
      );
    final cap = Map<String, dynamic>.from(
      await native.invokeMethod('capabilities') as Map,
    );
    if (cap['notificationsAllowed'] != true)
      throw StateError(
        'Enable Us notifications in Android Settings before background answering.',
      );
    final stream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
    final confirmed = audioEvents.firstWhere(
      (dynamic e) => e is Map && e['event'] == 'ready' && e['running'] == true,
    );
    await native.invokeMethod('startReady');
    await confirmed.timeout(const Duration(seconds: 5));
    readyService = true;
    keepReady = true;
    await storage.write(key: 'echo.keepReady', value: 'true');
    _notify();
  }

  Future<void> stopReady() async {
    await native.invokeMethod('stopReady').catchError((_) => null);
    readyService = false;
    keepReady = false;
    await storage.write(key: 'echo.keepReady', value: 'false');
    _notify();
  }

  Future<void> unload() async {
    if (localCall) throw StateError('Finish the ECHO call first.');
    ready = false;
    text.cancel();
    await text.close();
    await speech.close();
    status = 'Phone models are not prepared';
    _notify();
  }

  Future<void> shutdown() async {
    await stopReady();
    localCall = false;
    await unload();
  }

  @override
  void dispose() {
    _dead = true;
    unawaited(_statusSubscription?.cancel() ?? Future<void>.value());
    unawaited(shutdown().catchError((Object _) {}));
    models.dispose();
    super.dispose();
  }
}
