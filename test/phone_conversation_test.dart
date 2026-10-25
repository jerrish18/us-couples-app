import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/session.dart';
import 'package:us/features/echo/phone_conversation.dart';
import 'package:us/features/echo/phone_phrases.dart';
import 'package:us/features/echo/phone_runtime.dart';

class _Session extends ChangeNotifier implements UsSession {
  @override
  String get userId => 'callee';
  @override
  String get coupleId => 'couple';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Speech extends PhoneSpeechWorker {
  @override
  Future<String> transcribe(Float32List samples) async =>
      'Please call tomorrow.';
}

class _Text implements PhoneTextModel {
  final output = StreamController<String>.broadcast();
  bool cancelled = false;
  @override
  Stream<String> generate(
    List<Map<String, String>> messages, {
    Map<String, dynamic>? schema,
    int maxTokens = 128,
  }) => output.stream;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> load(String path, {required bool plus}) async {}
}

class _Runtime extends PhoneAiRuntime {
  _Runtime(_Text text) : super(text: text, speech: _Speech());
  final incoming = StreamController<dynamic>.broadcast(sync: true);
  @override
  Stream<dynamic> get audioEvents => incoming.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Runtime runtime;
  late _Text text;
  late PhoneConversation conversation;
  late List<MethodCall> audio;
  late Completer<void> replying, listening;
  setUp(() {
    text = _Text();
    runtime = _Runtime(text);
    audio = [];
    replying = Completer<void>();
    listening = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PhoneAiRuntime.native, (call) async {
          audio.add(call);
          return null;
        });
    conversation = PhoneConversation(
      runtime: runtime,
      session: _Session(),
      callId: 'call',
      coupleId: 'couple',
      preferences: {
        'enabled': true,
        'language': 'English',
        'retain_transcript': false,
        'greeting': 'Hello from your partner.',
      },
      onChanged: () {
        if (conversation.status == 'Replying on this phone' &&
            !replying.isCompleted)
          replying.complete();
        if (conversation.status == 'Listening' && !listening.isCompleted)
          listening.complete();
      },
    );
  });
  tearDown(() async {
    await conversation.close();
    await runtime.incoming.close();
    if (!text.output.isClosed) await text.output.close();
    runtime.models.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PhoneAiRuntime.native, null);
  });
  for (final failure in ['empty', 'error']) {
    test(
      '$failure inference uses truthful prepared fallback and keeps call audio armed',
      () async {
        await conversation.arm();
        runtime.incoming.add({'event': 'utterance', 'audio': Uint8List(320)});
        await replying.future.timeout(const Duration(seconds: 2));
        if (failure == 'error')
          text.output.addError(StateError('Inference failed'));
        await text.output.close();
        await listening.future.timeout(const Duration(seconds: 2));
        final phrases = audio
            .where((c) => c.method == 'speak')
            .map((c) => c.arguments['text']);
        expect(phrases, contains(phoneUnsaved['English']));
        expect(phrases, isNot(contains(phoneSavedAcknowledgement['English'])));
        expect(
          audio.where((c) => c.method == 'release' || c.method == 'takeover'),
          isEmpty,
        );
        expect(runtime.localCall, true);
      },
    );
  }
  test('caller interruption discards a late model response', () async {
    await conversation.arm();
    runtime.incoming.add({'event': 'utterance', 'audio': Uint8List(320)});
    await replying.future.timeout(const Duration(seconds: 2));
    runtime.incoming.add({'event': 'barge'});
    text.output.add('This stale sentence must not be spoken.');
    await text.output.close();
    expect(text.cancelled, true);
    expect(audio.where((c) => c.method == 'speak'), isEmpty);
  });
  test(
    'audible AI disclosure precedes personal greeting; close does not restore mic early',
    () async {
      await conversation.arm();
      conversation.claimed = true;
      await conversation.connected();
      expect(
        audio
            .where((c) => c.method == 'speak')
            .map((c) => c.arguments['text'])
            .toList(),
        [phoneDisclosure['English'], 'Hello from your partner.'],
      );
      await conversation.close();
      expect(audio.last.method, 'interrupt');
      expect(
        audio.where((c) => c.method == 'release' || c.method == 'takeover'),
        isEmpty,
      );
    },
  );
}
