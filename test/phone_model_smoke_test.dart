import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:us/features/echo/phone_models.dart';
import 'package:us/features/echo/phone_runtime.dart';

void main() {
  test(
    'actual local GGUF generation and multilingual Whisper runtime',
    () async {
      final root = await Directory(
        Platform.environment['ECHO_MODEL_DIR'] ?? '/tmp/us-echo-model-smoke',
      ).create(recursive: true);
      print('Real model smoke directory: ${root.path}');
      final models = PhoneModels(directory: root);
      final text = LocalLlamaModel();
      final speech = PhoneSpeechWorker();
      try {
        await models.install(false);
        expect(await models.available(false), true);
        await text.load(await models.path(phoneLlmLite), plus: false);
        final reply = await text.generate([
          {'role': 'user', 'content': 'Reply only with the single word Hello.'},
        ], maxTokens: 24).join();
        expect(reply.toLowerCase(), contains('hello'));
        final tamil = await text.generate([
          {
            'role': 'user',
            'content': 'Write only a short Tamil greeting in Tamil script.',
          },
        ], maxTokens: 32).join();
        expect(RegExp(r'[\u0B80-\u0BFF]').hasMatch(tamil), true);
        print(
          'Local Tamil text generation produced Tamil script; linguistic quality still needs human review.',
        );
        final wavePath = Platform.environment['ECHO_SPEECH_FIXTURE'];
        if (wavePath == null)
          throw StateError(
            'Set ECHO_SPEECH_FIXTURE to the synthetic English WAV fixture',
          );
        sherpa.initBindings();
        final wave = sherpa.readWave(wavePath);
        await speech.load(models, 'English');
        final transcript = await speech.transcribe(wave.samples);
        expect(transcript.toLowerCase(), contains('tomorrow'));
      } finally {
        await speech.close();
        await text.close();
        models.dispose();
      }
    },
    skip: const bool.fromEnvironment('ECHO_REAL_MODELS')
        ? false
        : 'Opt-in test downloads real public models; no network/model results are simulated.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
