import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:us/features/chat/video_bubble.dart';
import 'package:us/features/chat/video_source.dart';
import 'ui_review_test.dart' as fixtures;

class VideoSpace extends fixtures.PreviewSpace {
  VideoSpace() : super(fixtures.PreviewSession());
  int urls = 0;
  @override
  Future<String> mediaUrl(String path) async {
    urls++;
    return 'https://example.invalid/signed-video?attempt=$urls';
  }
}

class PlayerPlatform extends VideoPlayerPlatform {
  int next = 0, plays = 0;
  bool failFirst = false;
  final sources = <DataSource>[];
  final streams = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> create(DataSource source) async {
    sources.add(source);
    return ++next;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int id) {
    final stream = StreamController<VideoEvent>();
    streams[id] = stream;
    stream.onListen = () {
      scheduleMicrotask(() {
        if (failFirst && id == 1)
          stream.addError(
            PlatformException(
              code: 'decode',
              message: 'Synthetic decoder failure',
            ),
          );
        else
          stream.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 8),
              size: const Size(1920, 1080),
            ),
          );
      });
    };
    return stream.stream;
  }

  @override
  Future<void> dispose(int id) async {
    await streams.remove(id)?.close();
  }

  @override
  Future<void> play(int id) async {
    plays++;
  }

  @override
  Future<void> pause(int id) async {}
  @override
  Future<void> setLooping(int id, bool looping) async {}
  @override
  Future<void> setVolume(int id, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int id, double speed) async {}
  @override
  Future<void> seekTo(int id, Duration position) async {}
  @override
  Future<Duration> getPosition(int id) async => Duration.zero;
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allow) async {}
  @override
  Widget buildView(int id) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('deleted or empty capture files are not playback sources', () async {
    final dir = await Directory.systemTemp.createTemp('us-video-');
    try {
      final file = File('${dir.path}/clip.mp4');
      await file.writeAsBytes([]);
      expect(await existingVideoFile(file.path), isNull);
      await file.writeAsBytes([1, 2, 3]);
      expect(await existingVideoFile(file.path), file.path);
      await file.delete();
      expect(await existingVideoFile(file.path), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  testWidgets(
    'sent video falls back from deleted capture to a fresh signed URL',
    (tester) async {
      final platform = PlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      final space = VideoSpace();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoBubble(
              space: space,
              message: const {
                '_local_file': '/nonexistent/us-capture.mp4',
                'media_path': 'couple/video.mp4',
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Tap to load and play'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(space.urls, 1);
      expect(platform.sources.single.sourceType, DataSourceType.network);
      expect(platform.plays, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('failed decoder is disposed and retry creates a fresh player', (
    tester,
  ) async {
    final platform = PlayerPlatform()..failFirst = true;
    VideoPlayerPlatform.instance = platform;
    final space = VideoSpace();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoBubble(
            space: space,
            message: const {'media_path': 'couple/video.mp4'},
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Tap to load and play'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not play this video'), findsOneWidget);
    await tester.tap(find.textContaining('Could not play this video'));
    await tester.pumpAndSettle();
    expect(space.urls, 2);
    expect(platform.sources.length, 2);
    expect(platform.plays, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
