import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:us/core/design.dart';
import 'package:us/core/session.dart';
import 'package:us/core/space.dart';
import 'package:us/core/settings.dart';
import 'package:us/main.dart';
import 'package:us/features/home/home_screen.dart';
import 'package:us/features/chat/chat_screen.dart';
import 'package:us/features/calendar/calendar_screen.dart';
import 'package:us/features/memories/memories_screen.dart';
import 'package:us/features/memories/memory_composer.dart';
import 'package:us/features/more/more_screen.dart';
import 'package:us/features/auth/auth_screen.dart';
import 'package:us/features/pairing/pair_screen.dart';
import 'package:us/features/lists/lists_screen.dart';
import 'package:us/features/journal/journal_screen.dart';
import 'package:us/features/together/together_screen.dart';
import 'package:us/features/expenses/expenses_screen.dart';
import 'package:us/features/location/location_screen.dart';
import 'package:us/features/location/live_location.dart';

class PreviewSession extends ChangeNotifier implements UsSession {
  @override
  String? get userId => 'one';
  @override
  String? get partnerId => 'two';
  @override
  String? get coupleId => 'preview';
  @override
  Map<String, dynamic>? couple = {
    'id': 'preview',
    'owner_id': 'one',
    'partner_id': 'two',
    'name': 'Us',
    'together_since': '2026-01-01',
  };
  @override
  bool ready = true;
  @override
  String? error;
  @override
  Future<void> refresh() async {}
  @override
  Future<String?> invite() async => 'A1B2C3';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewSettings extends ChangeNotifier implements DeviceSettings {
  @override
  ThemeMode theme = ThemeMode.system;
  @override
  bool ready = true, locked = false;
  @override
  String? pin;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewLocation extends ChangeNotifier implements LiveLocation {
  PreviewLocation(this.session);
  @override
  final UsSession session;
  @override
  bool get sharing => false;
  @override
  bool starting = false;
  @override
  String? error;
  @override
  DateTime? until;
  @override
  List<Map<String, dynamic>> get active => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PreviewSpace extends ChangeNotifier implements UsSpace {
  PreviewSpace(this.session) {
    final today = DateTime.now().toIso8601String().substring(0, 10),
        now = DateTime.now().toUtc().toIso8601String();
    rows['profiles'] = [
      {
        'user_id': 'one',
        'display_name': 'Alex',
        'nickname': 'My person',
        'mood': 'Loved 🥰',
        'mood_date': today,
        'timezone': 'Asia/Kolkata',
      },
      {
        'user_id': 'two',
        'display_name': 'Jamie',
        'mood': 'Calm 🌿',
        'mood_date': today,
        'timezone': 'Asia/Kolkata',
        'city': 'Chennai',
      },
    ];
    rows['memories'] = [
      {
        'id': 'memory',
        'author_id': 'one',
        'media_path': 'preview.jpg',
        '_local_file': 'test/fixtures/moment.jpg',
        'caption': 'The days we want to remember.',
        'memory_date': today,
      },
    ];
    rows['memory_collections'] = [
      {
        'id': 'collection',
        'title': 'Date nights',
        'author_id': 'one',
        'created_at': now,
      },
    ];
    rows['messages'] = [
      for (var i = 0; i < 6; i++)
        {
          'id': 'message-$i',
          'sender_id': i.isEven ? 'one' : 'two',
          'body': i.isEven
              ? 'Can we keep today forever?'
              : 'Every little moment with you.',
          'created_at': now,
        },
    ];
    rows['dates'] = [
      {
        'id': 'date',
        'author_id': 'one',
        'title': 'Coffee, then the coast',
        'place': 'Our favourite café',
        'notes': 'Just the two of us.',
        'starts_at': DateTime.now()
            .add(const Duration(days: 2))
            .toUtc()
            .toIso8601String(),
      },
    ];
    rows['anniversaries'] = [
      {
        'id': 'anniversary',
        'title': 'Our day',
        'event_date': '2026-10-27',
        'yearly': true,
      },
    ];
    rows['list_items'] = [
      {
        'id': 'list',
        'title': 'Watch a sunrise together',
        'list_kind': 'bucket',
        'completed': false,
        'author_id': 'one',
      },
    ];
    rows['journal_entries'] = [
      {
        'id': 'journal',
        'author_id': 'one',
        'body':
            'Today felt like a little pause from the world. Just us, a long walk, and no hurry to be anywhere.',
        'entry_date': today,
        'shared': false,
      },
    ];
    rows['letters'] = [
      {
        'id': 'letter',
        'title': 'A little reminder',
        'open_when': 'you miss me',
        'author_id': 'one',
        'created_at': now,
      },
    ];
    rows['expenses'] = [
      {
        'id': 'expense',
        'title': 'Dinner together',
        'amount': 640,
        'currency': 'INR',
        'author_id': 'one',
        'created_at': now,
      },
    ];
  }
  @override
  final UsSession session;
  @override
  final Map<String, List<Map<String, dynamic>>> rows = {};
  @override
  bool loading = false,
      online = true,
      syncing = false,
      partnerOnline = true,
      partnerTyping = false;
  @override
  int queued = 0;
  @override
  String? error;
  @override
  Map<String, dynamic> preferences = {};
  @override
  Map<String, dynamic>? get me => rows['profiles']!.first;
  @override
  Map<String, dynamic>? get partner => rows['profiles']!.last;
  @override
  List<Map<String, dynamic>> get items => rows['messages'] ?? [];
  @override
  Future<void> refresh() async {}
  @override
  Future<void> sync() async {}
  @override
  Future<void> typing(bool value) async {}
  @override
  Future<void> messageState(
    String id, {
    bool hidden = false,
    bool? starred,
  }) async {}
  @override
  Future<String> mediaFile(String path) async => 'test/fixtures/moment.jpg';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    tz.initializeTimeZones();
    Directory('ui-review').createSync();
    final font = FontLoader('Outfit')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Outfit.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (file.existsSync())
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
    }
    for (final channel in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'com.llfbandit.record',
      'com.llfbandit.record/messages',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });
  final screens = <String, Widget>{
    'lock': const AppLockGate(child: SizedBox()),
    'home': const UsShell(path: '/', child: HomeScreen()),
    'chat': const UsShell(path: '/chat', child: ChatScreen()),
    'calendar': const UsShell(path: '/calendar', child: CalendarScreen()),
    'memories': const UsShell(path: '/memories', child: MemoriesScreen()),
    'more': const UsShell(path: '/more', child: MoreScreen()),
    'auth': const AuthScreen(),
    'pair': const PairScreen(),
    'lists': const ListsScreen(),
    'journal': const JournalScreen(),
    'letters': const TogetherScreen(kind: 'letters'),
    'expenses': const ExpensesScreen(),
    'collections': const TogetherScreen(kind: 'collections'),
    'location': const LocationScreen(),
    'composer': MemoryComposer(
      file: 'test/fixtures/moment.jpg',
      collections: const [
        {'id': 'one', 'title': 'Date nights'},
      ],
      onCreateCollection: (_) async => 'new',
      onSave: (_) async {},
    ),
  };
  for (final entry in screens.entries) {
    for (final dark in [false, true]) {
      for (final variant in [0, 1, 2]) {
        testWidgets(
          '1.5 ${entry.key} ${dark ? 'dark' : 'light'} variant $variant layout and snapshot',
          (tester) async {
            tester.view.physicalSize = variant == 1
                ? const Size(320, 740)
                : variant == 2
                ? const Size(840, 960)
                : const Size(393, 852);
            tester.view.devicePixelRatio = 1;
            VisualCapabilities.sdk = variant == 0 ? 35 : 24;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final session = PreviewSession(), settings = PreviewSettings();
            settings.locked = entry.key == 'lock';
            settings.pin = '1234';
            final space = PreviewSpace(session),
                location = PreviewLocation(session);
            final key = GlobalKey();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  sessionProvider.overrideWithValue(session),
                  spaceProvider.overrideWithValue(space),
                  settingsProvider.overrideWithValue(settings),
                  locationProvider.overrideWithValue(location),
                ],
                child: MaterialApp(
                  theme: usTheme(dark ? Brightness.dark : Brightness.light),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(variant == 1 ? 1.4 : 1),
                    ),
                    child: Directionality(
                      textDirection: variant == 1
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: RepaintBoundary(
                        key: key,
                        child: AmbientMesh(child: child!),
                      ),
                    ),
                  ),
                  home: entry.value,
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            await tester.runAsync(() async {
              for (final width in [
                UsTokens.photoDecode,
                UsTokens.previewDecode,
              ]) {
                await precacheImage(
                  ResizeImage(
                    FileImage(File('test/fixtures/moment.jpg')),
                    width: width,
                  ),
                  key.currentContext!,
                );
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            });
            await tester.pump();
            expect(tester.takeException(), isNull, reason: entry.key);
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'ui-review/${entry.key}-${dark ? 'dark' : 'light'}-$variant.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
            space.dispose();
            location.dispose();
            settings.dispose();
            session.dispose();
          },
        );
      }
    }
  }
  test('All feature accents retain AA body contrast in light and dark', () {
    for (final dark in [false, true])
      for (final accent in Accent.values) {
        final bg = UsColors.tint(accent, dark),
            fg = dark ? const Color(0xfff5f4fb) : UsColors.ink;
        final contrast =
            (fg.computeLuminance() + .05) / (bg.computeLuminance() + .05);
        expect(
          contrast > 1 ? contrast : 1 / contrast,
          greaterThanOrEqualTo(4.5),
        );
      }
  });
}
