import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/design.dart';
import 'package:us/core/space.dart';
import 'package:us/features/ai/ai_composer_panel.dart';
import 'package:us/features/ai/ai_draft.dart';
import 'package:us/features/ai/ai_service.dart';
import 'package:us/features/chat/chat_screen.dart';

import 'ui_review_test.dart' as fixtures;

const sampleResult = <String, dynamic>{
  'answer': 'Here are some ideas',
  'suggestions': [
    'I miss you. Can we talk tomorrow?',
    'Thinking of you. Talk tomorrow?',
    'I wish we could talk. Tomorrow?',
  ],
  'draft': {'kind': 'none'},
  'sources': [],
  'coverage': 'Only your text',
};

class ComposerAi extends UsAi {
  ComposerAi(super.space);
  bool enabled = true, history = true, partner = true;
  int requests = 0;
  String? task, prompt, language;
  List<String> ids = [];
  bool? publish;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> result = sampleResult;
  String? failure;
  @override
  Future<List<Map<String, dynamic>>> preferences() async => [
    {'user_id': 'one', 'enabled': enabled, 'share_history': history},
    {'user_id': 'two', 'enabled': partner, 'share_history': partner},
  ];
  @override
  Future<void> consent({required bool enabled, required bool history}) async {
    this.enabled = enabled;
    this.history = enabled && history;
  }

  @override
  Future<Map<String, dynamic>> ask({
    required String task,
    required String prompt,
    required String language,
    List<String> ids = const [],
    DateTime? from,
    DateTime? until,
    double? budget,
    int? minutes,
    bool publish = false,
  }) async {
    requests++;
    this.task = task;
    this.prompt = prompt;
    this.language = language;
    this.ids = ids;
    this.publish = publish;
    if (failure != null) throw StateError(failure!);
    return pending == null ? result : pending!.future;
  }
}

class ChatSpace extends fixtures.PreviewSpace {
  ChatSpace(super.session);
  final sent = <String>[];
  final saved = <String>[];
  @override
  Future<void> send(
    String body, {
    String? file,
    String? kind,
    String? replyTo,
    bool memory = false,
    String? caption,
    DateTime? memoryDate,
    String? collectionId,
    String? fileName,
    String? mime,
  }) async {
    sent.add(body);
  }

  @override
  Future<void> add(String table, Map<String, dynamic> fields) async {
    saved.add(table);
  }
}

Future<void> showPanel(
  WidgetTester tester,
  ComposerAi ai,
  TextEditingController text, {
  String task = 'rewrite',
  String? messageId,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: usTheme(brightness),
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: AiComposerPanel(
                space: ai.space,
                controller: text,
                initialTask: task,
                messageId: messageId,
                service: ai,
                onClose: () {},
                onInserted: () {},
              ),
            ),
            TextField(controller: text),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> generate(WidgetTester tester) async {
  final button = find.byKey(const Key('ai-generate'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Outfit')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Outfit.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    for (final channel in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'com.llfbandit.record',
      'com.llfbandit.record/messages',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  test('structured dates, expenses and tasks produce useful chat drafts', () {
    expect(
      aiDraftText({
        'draft': {
          'kind': 'expense',
          'title': 'Dinner',
          'amount': 850,
          'category': 'Food',
          'spent_on': '2026-10-23',
          'outing': 'Our evening',
          'notes': 'Split equally',
        },
      }),
      'Dinner\n₹850 · Food\n2026-10-23\nOur evening\nSplit equally',
    );
    final date = aiDraftText({
      'answer': 'Our date',
      'draft': {'kind': 'none'},
      'itinerary': [
        {'activity': 'Coffee', 'minutes': 45, 'estimated_cost': 300},
      ],
      'budget': {'total': 300, 'total_minutes': 45},
    });
    expect(date, contains('Coffee · 45 min'));
    expect(date, contains('Estimated total: ₹300'));
    expect(
      aiDraftText({
        'draft': {
          'kind': 'todo',
          'title': 'Book tickets',
          'notes': 'For Saturday',
        },
      }),
      'Book tickets\nFor Saturday',
    );
  });

  test('UTF-8 and summary validation fail before a provider call', () {
    expect(
      aiInputError(task: 'rewrite', prompt: 'அ' * 501),
      contains('1,500 bytes'),
    );
    expect(aiInputError(task: 'rewrite', prompt: 'அ' * 500), isNull);
    expect(
      aiInputError(
        task: 'summary',
        prompt: 'Summary',
        from: DateTime(2026, 10, 1),
        until: DateTime(2026, 9, 1),
      ),
      contains('31 days'),
    );
  });

  testWidgets(
    'result goes into the real composer, alternatives replace it, undo restores original',
    (tester) async {
      final space = ChatSpace(fixtures.PreviewSession()),
          ai = ComposerAi(space);
      final text = TextEditingController(text: 'I miss you');
      await showPanel(tester, ai, text);
      await generate(tester);
      expect(text.text, sampleResult['suggestions'][0]);
      expect(ai.prompt, 'I miss you');
      expect(space.sent, isEmpty);
      await tester.ensureVisible(find.byTooltip('Option 2'));
      await tester.tap(find.byTooltip('Option 2'));
      await tester.pumpAndSettle();
      expect(text.text, sampleResult['suggestions'][1]);
      await tester.tap(find.byKey(const Key('ai-undo')));
      await tester.pumpAndSettle();
      expect(text.text, 'I miss you');
      expect(tester.takeException(), isNull);
    },
  );

  for (final task in aiTasks.keys) {
    testWidgets(
      '$task is accessible in the composer and generates an editable draft',
      (tester) async {
        final space = ChatSpace(fixtures.PreviewSession()),
            ai = ComposerAi(space);
        final text = TextEditingController(text: 'Help with our evening');
        await showPanel(tester, ai, text, task: task, messageId: 'message-1');
        await generate(tester);
        expect(ai.requests, 1);
        expect(ai.task, task);
        expect(ai.publish, false);
        if (['reply', 'plans'].contains(task)) expect(ai.ids, ['message-1']);
        expect(text.text, sampleResult['suggestions'][0]);
        expect(space.sent, isEmpty);
        expect(space.saved, isEmpty);
      },
    );
  }

  testWidgets(
    'a late response preserves newer typing and can be inserted explicitly',
    (tester) async {
      final ai = ComposerAi(ChatSpace(fixtures.PreviewSession()))
        ..pending = Completer();
      final text = TextEditingController(text: 'Original');
      await showPanel(tester, ai, text);
      await tester.ensureVisible(find.byKey(const Key('ai-generate')));
      await tester.tap(find.byKey(const Key('ai-generate')));
      await tester.pump();
      text.text = 'Something I typed while waiting';
      ai.pending!.complete(sampleResult);
      await tester.pumpAndSettle();
      expect(text.text, 'Something I typed while waiting');
      await tester.ensureVisible(find.text('Use result'));
      await tester.tap(find.text('Use result'));
      await tester.pumpAndSettle();
      expect(text.text, sampleResult['suggestions'][0]);
      await tester.ensureVisible(find.byKey(const Key('ai-undo')));
      await tester.tap(find.byKey(const Key('ai-undo')));
      expect(text.text, 'Something I typed while waiting');
    },
  );

  testWidgets('closing during generation discards the response', (
    tester,
  ) async {
    final ai = ComposerAi(ChatSpace(fixtures.PreviewSession()))
      ..pending = Completer();
    final text = TextEditingController(text: 'Original');
    await showPanel(tester, ai, text);
    await tester.ensureVisible(find.byKey(const Key('ai-generate')));
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    ai.pending!.complete(sampleResult);
    await tester.pumpAndSettle();
    expect(text.text, 'Original');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'provider failures preserve draft and show a useful retry message',
    (tester) async {
      final ai = ComposerAi(ChatSpace(fixtures.PreviewSession()))
        ..failure = 'Wait 30 seconds between requests.';
      final text = TextEditingController(text: 'Keep this draft');
      await showPanel(tester, ai, text);
      await generate(tester);
      expect(text.text, 'Keep this draft');
      expect(find.text('Wait 30 seconds between requests.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-generate')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'no shared context without both partners consent; private tools still work',
    (tester) async {
      final ai = ComposerAi(ChatSpace(fixtures.PreviewSession()))
        ..partner = false;
      final text = TextEditingController(text: 'A question');
      await showPanel(tester, ai, text, task: 'together');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-generate')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('ai-task-rewrite')));
      await tester.tap(find.byKey(const Key('ai-task-rewrite')));
      await tester.pumpAndSettle();
      await generate(tester);
      expect(ai.requests, 1);
    },
  );

  testWidgets(
    'empty request, missing selection and invalid budget do not call AI',
    (tester) async {
      final ai = ComposerAi(ChatSpace(fixtures.PreviewSession()));
      final text = TextEditingController();
      await showPanel(tester, ai, text);
      await generate(tester);
      expect(ai.requests, 0);
      await tester.pumpWidget(const SizedBox());
      await showPanel(tester, ai, text, task: 'reply');
      await generate(tester);
      expect(ai.requests, 0);
      await tester.pumpWidget(const SizedBox());
      text.text = 'A date';
      await showPanel(tester, ai, text, task: 'date');
      await tester.enterText(find.byKey(const Key('ai-budget')), '0');
      await generate(tester);
      expect(ai.requests, 0);
    },
  );

  testWidgets(
    'saved-message picker excludes pending, hidden, deleted and media messages',
    (tester) async {
      final space = ChatSpace(fixtures.PreviewSession());
      space.rows['messages'] = [
        {
          'id': 'valid',
          'body': 'A saved message',
          'sender_id': 'two',
          'created_at': '2026-10-23',
        },
        {'id': 'pending', 'body': 'Pending secret', '_pending': true},
        {'id': 'deleted', 'body': 'Deleted secret', 'deleted_at': '2026-10-23'},
        {'id': 'hidden', 'body': 'Hidden secret'},
        {'id': 'media', 'body': 'Media secret', 'media_kind': 'photo'},
      ];
      space.rows['message_states'] = [
        {'user_id': 'one', 'message_id': 'hidden', 'hidden': true},
      ];
      final ai = ComposerAi(space), text = TextEditingController();
      await showPanel(tester, ai, text, task: 'reply');
      await tester.tap(find.text('0 messages selected'));
      await tester.pumpAndSettle();
      expect(find.text('A saved message'), findsOneWidget);
      for (final secret in [
        'Pending secret',
        'Deleted secret',
        'Hidden secret',
        'Media secret',
      ]) {
        expect(find.text(secret), findsNothing);
      }
      await tester.tap(find.text('A saved message'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use selected messages'));
      await tester.pumpAndSettle();
      await generate(tester);
      expect(ai.ids, ['valid']);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'message picker is opaque with visible selection in ${brightness.name}',
      (tester) async {
        final space = ChatSpace(fixtures.PreviewSession());
        space.rows['messages'] = [
          {
            'id': 'valid',
            'body': 'Dinner tomorrow?',
            'sender_id': 'two',
            'created_at': '2026-10-23',
          },
        ];
        final ai = ComposerAi(space), text = TextEditingController();
        await showPanel(
          tester,
          ai,
          text,
          task: 'reply',
          brightness: brightness,
        );
        await tester.tap(find.text('0 messages selected'));
        await tester.pumpAndSettle();
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.backgroundColor!.a, 1);
        final row = find.byKey(const ValueKey('ai-context-valid'));
        expect(tester.widget<CheckboxListTile>(row).selected, false);
        await tester.tap(row);
        await tester.pumpAndSettle();
        final tile = tester.widget<CheckboxListTile>(row);
        expect(tile.selected, true);
        expect(tile.value, true);
        expect(tile.selectedTileColor!.a, 1);
        expect(tile.activeColor, isNot(tile.selectedTileColor));
        await tester.tap(find.text('Use selected messages'));
        await tester.pumpAndSettle();
        await generate(tester);
        expect(ai.ids, ['valid']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a task draft requires explicit review and saves only once', (
    tester,
  ) async {
    final space = ChatSpace(fixtures.PreviewSession()), ai = ComposerAi(space);
    ai.result = {
      'answer': 'A draft only',
      'suggestions': [],
      'draft': {'kind': 'todo', 'title': 'Book tickets', 'notes': ''},
    };
    final text = TextEditingController(text: 'Make a task');
    await showPanel(tester, ai, text, task: 'plans', messageId: 'message-1');
    await generate(tester);
    expect(text.text, 'Book tickets');
    expect(space.saved, isEmpty);
    await tester.ensureVisible(find.text('Review & save to Us'));
    await tester.tap(find.text('Review & save to Us'));
    await tester.pumpAndSettle();
    expect(find.text('Review your task'), findsOneWidget);
    expect(space.saved, isEmpty);
    await tester.tap(find.text('Save to Us'));
    await tester.pumpAndSettle();
    expect(space.saved, ['list_items']);
    await tester.ensureVisible(find.text('Saved to Us'));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Saved to Us'))
          .onPressed,
      isNull,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'chat AI fits a narrow ${brightness.name} screen, large text and keyboard; sends only on tap',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final space = ChatSpace(fixtures.PreviewSession()),
            ai = ComposerAi(space);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [spaceProvider.overrideWithValue(space)],
            child: MaterialApp(
              theme: usTheme(brightness),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 740),
                  textScaler: TextScaler.linear(1.5),
                ),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: boundary,
                    child: ChatScreen(aiService: ai),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('chat-message')),
          'I miss you',
        );
        await tester.tap(find.byTooltip('AI writing tools'));
        await tester.pumpAndSettle();
        expect(find.byType(AiComposerPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
        await generate(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('chat-message')))
              .controller!
              .text,
          sampleResult['suggestions'][0],
        );
        expect(space.sent, isEmpty);
        // A compact viewport represents the remaining space above a phone keyboard.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [spaceProvider.overrideWithValue(space)],
            child: MaterialApp(
              theme: usTheme(brightness),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 740),
                  textScaler: TextScaler.linear(1.5),
                  viewInsets: EdgeInsets.only(bottom: 280),
                ),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: boundary,
                    child: ChatScreen(aiService: ai),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('ui-review').createSync();
          File(
            'ui-review/chat-ai-${brightness.name}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.byTooltip('Send message'));
        await tester.pumpAndSettle();
        expect(space.sent, [sampleResult['suggestions'][0]]);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('chat-message')))
              .controller!
              .text,
          isEmpty,
        );
        expect(find.byType(AiComposerPanel), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
