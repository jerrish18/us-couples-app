import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/space.dart';
import 'video_source.dart';

class VideoBubble extends StatefulWidget {
  const VideoBubble({super.key, required this.space, required this.message});
  final UsSpace space;
  final Map<String, dynamic> message;
  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> with WidgetsBindingObserver {
  VideoPlayerController? _player;
  String? _error;
  bool _loading = false, _dead = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant VideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The pending -> uploaded transition has the same media_path. Keep a
    // working player, but reset state if this element represents another clip.
    if (oldWidget.message['media_path'] != widget.message['media_path'] ||
        (widget.message['media_path'] == null &&
            oldWidget.message['_local_file'] !=
                widget.message['_local_file'])) {
      _generation++;
      _loading = false;
      _error = null;
      _release();
    }
  }

  void _release() {
    final player = _player;
    _player = null;
    if (player != null) {
      player.removeListener(_changed);
      unawaited(player.dispose());
    }
  }

  @override
  void dispose() {
    _dead = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed)
      unawaited(
        _player?.pause().catchError((Object _) {}) ?? Future<void>.value(),
      );
  }

  Future<VideoPlayerController> _initialize(
    VideoPlayerController player,
  ) async {
    try {
      await player.initialize().timeout(const Duration(seconds: 25));
      return player;
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  Future<VideoPlayerController> _open() async {
    final local = await existingVideoFile(
      widget.message['_local_file'] as String?,
    );
    final remote = widget.message['media_path'] as String?;
    if (local != null) {
      try {
        return await _initialize(VideoPlayerController.file(File(local)));
      } catch (_) {
        if (remote == null) rethrow;
      }
    }
    if (remote == null)
      throw StateError(
        'The recording is no longer available. Please record again.',
      );
    // A new signed URL on every retry avoids stale cached downloads/expired URLs
    // and lets Android request media ranges while the video buffers.
    final url = await widget.space.mediaUrl(remote);
    return _initialize(VideoPlayerController.networkUrl(Uri.parse(url)));
  }

  Future<void> _play() async {
    if (_loading) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    VideoPlayerController? opening;
    try {
      if (_player?.value.hasError == true) _release();
      if (_player == null) {
        opening = await _open();
        if (_dead || generation != _generation) {
          await opening.dispose();
          return;
        }
        _player = opening;
        opening = null;
        _player!.addListener(_changed);
      }
      final player = _player!;
      if (player.value.isPlaying)
        await player.pause();
      else {
        if (player.value.position >= player.value.duration)
          await player.seekTo(Duration.zero);
        await player.play();
      }
    } catch (_) {
      await opening?.dispose();
      if (!_dead && generation == _generation) {
        _release();
        setState(
          () => _error =
              'Could not play this video. Check your connection and tap to retry.',
        );
      }
    } finally {
      if (!_dead && generation == _generation) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_player?.value.hasError == true)
        _error = 'Playback stopped. Tap to retry.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = _player, value = player?.value;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value?.isInitialized == true && value?.hasError != true)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: AspectRatio(
                  aspectRatio: value!.aspectRatio > 0
                      ? value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(player!),
                ),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    value?.isPlaying == true
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                  ),
            title: Text(
              _error ?? '${widget.message['file_name'] ?? 'A video for you'}',
            ),
            subtitle: Text(
              _loading
                  ? 'Loading video…'
                  : player == null
                  ? 'Tap to load and play'
                  : '${value!.position.inSeconds}s / ${value.duration.inSeconds}s',
            ),
            onTap: _loading ? null : _play,
          ),
          if (value?.isInitialized == true && value?.hasError != true)
            VideoProgressIndicator(
              player!,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
        ],
      ),
    );
  }
}
