import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/space.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _dead = true;
    WidgetsBinding.instance.removeObserver(this);
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player?.pause();
  }

  Future<void> _play() async {
    if (_loading) return;
    if (_player != null) {
      if (_player!.value.isPlaying) {
        await _player!.pause();
      } else {
        await _player!.play();
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    VideoPlayerController? player;
    try {
      final local =
          widget.message['_local_file'] as String? ??
          await widget.space.mediaFile(widget.message['media_path'] as String);
      if (_dead) return;
      player = VideoPlayerController.file(File(local));
      await player.initialize();
      if (_dead) {
        await player.dispose();
        return;
      }
      _player = player;
      player.addListener(_changed);
      await player.play();
    } catch (_) {
      await player?.dispose();
      if (mounted)
        setState(() => _error = 'Could not load video. Tap to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 340),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_player?.value.isInitialized == true)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: _player!.value.aspectRatio,
              child: VideoPlayer(_player!),
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
                  _player?.value.isPlaying == true
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                ),
          title: Text(
            _error ?? '${widget.message['file_name'] ?? 'A video for you'}',
          ),
          subtitle: Text(
            _player == null
                ? 'Tap to load and play'
                : '${_player!.value.position.inSeconds}s / ${_player!.value.duration.inSeconds}s',
          ),
          onTap: _play,
        ),
        if (_player?.value.isInitialized == true)
          VideoProgressIndicator(
            _player!,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
      ],
    ),
  );
}
