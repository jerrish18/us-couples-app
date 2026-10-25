import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PhoneModelFile {
  const PhoneModelFile(this.name, this.url, this.bytes, this.hash);
  final String name, url, hash;
  final int bytes;
}

// Immutable upstream revisions and SHA-256 digests. No API account is needed.
const phoneLlmLite = PhoneModelFile(
  'qwen3-0.6b-q4.gguf',
  'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf',
  396705472,
  'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a',
);
const phoneLlmPlus = PhoneModelFile(
  'qwen3-1.7b-q4.gguf',
  'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf',
  1107409472,
  'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
);
const phoneWhisper = [
  PhoneModelFile(
    'base-encoder.int8.onnx',
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-encoder.int8.onnx',
    29120534,
    '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
  ),
  PhoneModelFile(
    'base-decoder.int8.onnx',
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-decoder.int8.onnx',
    130672026,
    '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
  ),
  PhoneModelFile(
    'base-tokens.txt',
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-tokens.txt',
    816730,
    'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
  ),
];

/// Atomic, bounded, resumable downloads. Partial/unverified models are never loaded.
class PhoneModels extends ChangeNotifier {
  PhoneModels({Directory? directory, HttpClient? client})
    : _directory = directory,
      _http = client ?? HttpClient();
  Directory? _directory;
  final HttpClient _http;
  bool busy = false, cancelled = false, _dead = false;
  double? progress;
  String status = 'Download models to use AI on this phone';
  HttpClientRequest? _request;
  Future<Directory> get directory async => _directory ??= await Directory(
    '${(await getApplicationSupportDirectory()).path}/echo-models',
  ).create(recursive: true);
  List<PhoneModelFile> files(bool plus) => [
    plus ? phoneLlmPlus : phoneLlmLite,
    ...phoneWhisper,
  ];
  Future<String> path(PhoneModelFile model) async =>
      '${(await directory).path}/${model.name}';
  void _notify() {
    if (!_dead) notifyListeners();
  }

  Future<bool> available(bool plus) async {
    for (final model in files(plus)) {
      final f = File(await path(model));
      if (!await f.exists() ||
          await f.length() != model.bytes ||
          !await File('${f.path}.verified-${model.hash}').exists())
        return false;
    }
    return true;
  }

  Future<bool> _verify(File file, PhoneModelFile model) async =>
      await file.exists() &&
      await file.length() == model.bytes &&
      (await sha256.bind(file.openRead()).first).toString() == model.hash;
  Future<void> install(bool plus) async {
    if (busy) return;
    busy = true;
    cancelled = false;
    _notify();
    try {
      final selected = files(plus),
          total = files(plus).fold<int>(0, (n, m) => n + m.bytes);
      var completed = 0;
      for (final model in selected) {
        final target = File(await path(model));
        if (await _verify(target, model)) {
          await File(
            '${target.path}.verified-${model.hash}',
          ).writeAsString('verified');
          completed += model.bytes;
          continue;
        }
        final marker = File('${target.path}.verified-${model.hash}');
        if (await marker.exists()) await marker.delete();
        final part = File('${target.path}.part');
        for (var attempt = 0; attempt < 3; attempt++) {
          if (cancelled)
            throw StateError('Download paused. Tap Download to resume.');
          var offset = await part.exists() ? await part.length() : 0;
          if (offset > model.bytes) {
            await part.delete();
            offset = 0;
          }
          status = 'Downloading ${model.name}';
          _notify();
          try {
            if (offset < model.bytes) {
              _http.connectionTimeout = const Duration(seconds: 30);
              final req = await _http.getUrl(Uri.parse(model.url));
              _request = req;
              if (offset > 0)
                req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
              final response = await req.close().timeout(
                const Duration(seconds: 45),
              );
              if (response.statusCode == 200)
                offset = 0;
              else if (response.statusCode != 206 ||
                  !('${response.headers.value(HttpHeaders.contentRangeHeader)}'
                      .startsWith('bytes $offset-'))) {
                await response.drain<void>();
                throw const HttpException('Model server unavailable');
              }
              final sink = part.openWrite(
                mode: offset == 0 ? FileMode.write : FileMode.append,
              );
              var last = DateTime.now();
              try {
                await for (final chunk in response.timeout(
                  const Duration(seconds: 45),
                )) {
                  if (cancelled)
                    throw StateError(
                      'Download paused. Tap Download to resume.',
                    );
                  offset += chunk.length;
                  if (offset > model.bytes)
                    throw StateError('Unexpected model size');
                  sink.add(chunk);
                  if (DateTime.now().difference(last).inMilliseconds > 150) {
                    progress = (completed + offset) / total;
                    last = DateTime.now();
                    _notify();
                  }
                }
              } finally {
                await sink.flush();
                await sink.close();
              }
            }
            status = 'Checking ${model.name}';
            _notify();
            if (!await _verify(part, model)) {
              await part.delete();
              throw StateError('Model verification failed. Please retry.');
            }
            await part.rename(target.path);
            await File(
              '${target.path}.verified-${model.hash}',
            ).writeAsString('verified');
            completed += model.bytes;
            progress = completed / total;
            _notify();
            break;
          } catch (_) {
            if (cancelled || attempt == 2) rethrow;
          }
        }
      }
      status = 'Models downloaded and verified';
      progress = 1;
    } catch (e) {
      status = cancelled
          ? 'Download paused. Tap Download to resume.'
          : e is StateError
          ? '${e.message}'
          : 'Download interrupted. Check your connection and retry to resume.';
      rethrow;
    } finally {
      busy = false;
      _request = null;
      _notify();
    }
  }

  void pause() {
    cancelled = true;
    _request?.abort();
  }

  Future<void> remove(bool plus) async {
    if (busy) throw StateError('Pause the download first');
    for (final model in files(plus)) {
      final file = File(await path(model));
      for (final candidate in [
        file,
        File('${file.path}.part'),
        File('${file.path}.verified-${model.hash}'),
      ]) {
        if (await candidate.exists()) await candidate.delete();
      }
    }
    status = 'Models removed from this phone';
    progress = null;
    _notify();
  }

  @override
  void dispose() {
    _dead = true;
    pause();
    _http.close(force: true);
    super.dispose();
  }
}
