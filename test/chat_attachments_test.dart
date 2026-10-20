import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/design.dart';
import 'package:us/core/session.dart';
import 'package:us/core/settings.dart';
import 'package:us/core/space.dart';
import 'package:us/features/chat/attachment_sheet.dart';
import 'package:us/features/chat/chat_screen.dart';
import 'package:us/features/chat/music_dedication.dart';
import 'package:us/features/location/live_location.dart';
import 'package:us/main.dart';

import 'ui_review_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'audio file messages are music; documents and voice notes remain distinct',
    () {
      for (final mime in ['audio/mpeg', 'audio/mp4', 'audio/x-m4a']) {
        expect(
          isMusicDedication({'media_kind': 'file', 'mime_type': mime}),
          isTrue,
        );
      }
      expect(
        isMusicDedication({'media_kind': 'voice', 'mime_type': 'audio/mp4'}),
        isFalse,
      );
      expect(
        isMusicDedication({
          'media_kind': 'file',
          'mime_type': 'application/pdf',
        }),
        isFalse,
      );
      expect(isMusicDedication({}), isFalse);
    },
  );

  for (final entry in {
    'Gallery': 'photo',
    'Camera': 'camera',
    'Record video': 'video',
    'Video gallery': 'gallery_video',
    'Dedicate a song': 'music',
    'Document': 'file',
    'Poll': 'poll',
  }.entries) {
    testWidgets('${entry.key} selects the matching attachment action', (
      tester,
    ) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatAttachmentSheet(onSelect: (value) => selected = value),
          ),
        ),
      );
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      expect(selected, entry.value);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'chat composer stays above dock and follows keyboard without reserved gap',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final channel in [
        'plugins.it_nomads.com/flutter_secure_storage',
        'com.llfbandit.record',
        'com.llfbandit.record/messages',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              MethodChannel(channel),
              (_) async => null,
            );
      }
      final session = fixtures.PreviewSession();
      final settings = fixtures.PreviewSettings();
      final space = fixtures.PreviewSpace(session);
      final location = fixtures.PreviewLocation(session);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(session),
            settingsProvider.overrideWithValue(settings),
            spaceProvider.overrideWithValue(space),
            locationProvider.overrideWithValue(location),
          ],
          child: MaterialApp(
            theme: usTheme(Brightness.light),
            home: const UsShell(path: '/chat', child: ChatScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final composer = find.widgetWithText(TextField, 'A little hello…');
      expect(composer, findsOneWidget);
      final dockTop = tester.getTopLeft(find.byType(UsDock)).dy;
      final composerBottom = tester.getBottomLeft(composer).dy;
      expect(dockTop - composerBottom, inInclusiveRange(0, 24));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UsDock), findsNothing);
      expect(tester.getBottomLeft(composer).dy, lessThanOrEqualTo(552));
      expect(552 - tester.getBottomLeft(composer).dy, lessThan(24));
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(UsDock), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Add attachment'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatAttachmentSheet), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      // The attachment panel is anchored to the bottom, below the header.
      expect(
        tester.getTopLeft(find.byType(ChatAttachmentSheet)).dy,
        greaterThan(100),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      space.dispose();
      location.dispose();
      settings.dispose();
      session.dispose();
    },
  );
}
