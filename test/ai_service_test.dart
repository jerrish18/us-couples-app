import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:us/features/ai/ai_service.dart';

import 'ui_review_test.dart' as fixtures;

class ApiSession extends fixtures.PreviewSession {
  ApiSession(this.client);
  @override
  final SupabaseClient client;
}

void main() {
  test(
    'private together requests use a fail-closed action; sharing remains explicit',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      final listener = server.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'answer': 'A draft',
            'suggestions': [],
            'draft': {'kind': 'none'},
          }),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public-key',
      );
      addTearDown(() async {
        await listener.cancel();
        await server.close(force: true);
        await client.dispose();
      });
      final ai = UsAi(fixtures.PreviewSpace(ApiSession(client)));
      await ai.ask(
        task: 'together',
        prompt: 'An idea for us?',
        language: 'English',
      );
      expect(requests.single['task'], 'ask');
      expect(requests.single['publish'], false);
      await ai.ask(
        task: 'together',
        prompt: 'Share an idea for us',
        language: 'English',
        publish: true,
      );
      expect(requests.last['task'], 'together');
      expect(requests.last['publish'], true);
    },
  );

  test(
    'Edge Function errors become readable messages without losing server details',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listener = server.listen((request) async {
        await request.drain<void>();
        request.response.statusCode = 429;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'error': 'Wait 30 seconds; 20 requests daily.'}),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public-key',
      );
      addTearDown(() async {
        await listener.cancel();
        await server.close(force: true);
        await client.dispose();
      });
      final ai = UsAi(fixtures.PreviewSpace(ApiSession(client)));
      await expectLater(
        ai.ask(task: 'rewrite', prompt: 'Hello', language: 'English'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Wait 30 seconds'),
          ),
        ),
      );
    },
  );
}
