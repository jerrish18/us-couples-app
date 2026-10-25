import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/design.dart';
import 'package:us/core/space.dart';
import 'package:us/features/calls/call_host.dart';
import 'package:us/features/calls/call_service.dart';
import 'package:us/features/chat/chat_screen.dart';
import 'package:us/features/location/live_location.dart';
import 'package:us/main.dart' show UsShell;
import 'ui_review_test.dart' as fixtures;

class PreviewEchoCall extends ChangeNotifier implements CallService {
  @override
  Map<String, dynamic>? call = {'callee_id': 'one', 'state': 'connected'};
  @override
  Map<String, dynamic>? echoSession = {
    'state': 'ai',
    'transcript': [
      {'role': 'caller', 'text': 'Please call me tomorrow.'},
      {'role': 'echo', 'text': 'You are speaking with ECHO, an AI assistant.'},
    ],
  };
  @override
  bool get echoActive => true;
  @override
  bool get echoForMe => true;
  @override
  bool get canTakeOverEcho => true;
  @override
  bool get incoming => false;
  @override
  bool get busy => false;
  @override
  bool get video => false;
  @override
  bool get aiRequested => false;
  @override
  String get connection => 'RTCPeerConnectionStateConnected';
  @override
  String? get error => null;
  int takeovers = 0;
  @override
  Future<void> takeOverEcho() async {
    takeovers++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets(
      'ECHO disclosure, transcript and takeover fit ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final call = PreviewEchoCall();
        await tester.pumpWidget(
          MaterialApp(
            theme: usTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.5),
              ),
              child: CallScreen(service: call),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ECHO is answering as AI'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Please call me tomorrow.'),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Please call me tomorrow.'), findsOneWidget);
        await tester.tap(find.text('Take over call'));
        expect(call.takeovers, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'real app shell places chat composer above keyboard and removes dock',
    (tester) async {
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
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final session = fixtures.PreviewSession();
      final space = fixtures.PreviewSpace(session);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceProvider.overrideWithValue(space),
            locationProvider.overrideWithValue(
              fixtures.PreviewLocation(session),
            ),
          ],
          child: MaterialApp(
            theme: usTheme(Brightness.light),
            home: const UsShell(path: '/chat', child: ChatScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UsDock), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(UsDock), findsNothing);
      final composer = find.byKey(const Key('chat-composer'));
      expect(tester.getBottomLeft(composer).dy, closeTo(844 - 300 - 8, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
