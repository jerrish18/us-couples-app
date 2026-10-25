import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/features/echo/phone_models.dart';

class TestModels extends PhoneModels {
  TestModels(Directory root, this.model) : super(directory: root);
  final PhoneModelFile model;
  @override
  List<PhoneModelFile> files(bool plus) => [model];
}

void main() {
  test(
    'model downloads resume and are verified before becoming available',
    () async {
      final dir = await Directory.systemTemp.createTemp('echo-models-test-');
      final bytes = utf8.encode('A real checksum-verified model fixture.');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      String? range;
      server.listen((request) async {
        requests++;
        range = request.headers.value(HttpHeaders.rangeHeader);
        final offset = range == null
            ? 0
            : int.parse(range!.substring(6).replaceAll('-', ''));
        if (offset > 0) {
          request.response.statusCode = 206;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $offset-${bytes.length - 1}/${bytes.length}',
          );
        }
        request.response.add(bytes.sublist(offset));
        await request.response.close();
      });
      final model = PhoneModelFile(
        'fixture.gguf',
        'http://127.0.0.1:${server.port}/model',
        bytes.length,
        sha256.convert(bytes).toString(),
      );
      final models = TestModels(dir, model);
      try {
        expect(await models.available(false), false);
        await File(
          '${await models.path(model)}.part',
        ).writeAsBytes(bytes.take(8).toList());
        await models.install(false);
        expect(await models.available(false), true);
        expect(requests, 1);
        expect(range, 'bytes=8-');
        expect(await File(await models.path(model)).readAsBytes(), bytes);
        await models.remove(false);
        expect(await models.available(false), false);
      } finally {
        models.dispose();
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    },
  );
  test('corrupted bytes never become a loadable model', () async {
    final dir = await Directory.systemTemp.createTemp('echo-models-test-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response.add([1, 2, 3]);
      await r.response.close();
    });
    final model = PhoneModelFile(
      'fixture.gguf',
      'http://127.0.0.1:${server.port}/model',
      3,
      sha256.convert([3, 2, 1]).toString(),
    );
    final models = TestModels(dir, model);
    try {
      await expectLater(models.install(false), throwsStateError);
      expect(await models.available(false), false);
      expect(await File(await models.path(model)).exists(), false);
    } finally {
      models.dispose();
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
  test(
    'phone catalog is pinned and the lighter pack is materially smaller',
    () {
      expect(phoneLlmLite.bytes, lessThan(500000000));
      expect(phoneLlmPlus.bytes, greaterThan(1000000000));
      for (final file in [phoneLlmLite, phoneLlmPlus, ...phoneWhisper]) {
        expect(file.url, startsWith('https://huggingface.co/'));
        expect(file.hash, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(file.url, matches(RegExp(r'/resolve/[a-f0-9]{40}/')));
      }
    },
  );
}
