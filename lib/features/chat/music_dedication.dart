import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/design.dart';
import '../../core/space.dart';

bool isMusicDedication(Map<String, dynamic> message) =>
    message['media_kind'] == 'file' &&
    const [
      'audio/mpeg',
      'audio/mp4',
      'audio/x-m4a',
    ].contains(message['mime_type']);

class MusicDedicationCard extends StatefulWidget {
  const MusicDedicationCard({
    super.key,
    required this.space,
    required this.message,
  });
  final UsSpace space;
  final Map<String, dynamic> message;
  @override
  State<MusicDedicationCard> createState() => _MusicDedicationCardState();
}

class _MusicDedicationCardState extends State<MusicDedicationCard>
    with WidgetsBindingObserver {
  static AudioPlayer? _active;
  final _player = AudioPlayer();
  bool _loaded = false, _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_player.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(_active, _player)) _active = null;
    unawaited(_player.dispose());
    super.dispose();
  }

  void _error() {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not play this song. Check your connection or try another audio file.',
          ),
        ),
      );
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_loaded) {
        final path =
            widget.message['_local_file'] as String? ??
            await widget.space.mediaFile(
              widget.message['media_path'] as String,
            );
        if (!mounted) return;
        await _player.setFilePath(path);
        _loaded = true;
      }
      if (!mounted) return;
      if (_player.playing) {
        await _player.pause();
      } else {
        final previous = _active;
        if (previous != null && !identical(previous, _player))
          await previous.pause();
        if (!mounted) return;
        _active = _player;
        if (_player.processingState == ProcessingState.completed)
          await _player.seek(Duration.zero);
        unawaited(_player.play().catchError((Object _) => _error()));
      }
    } catch (_) {
      _error();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: TintedTile(
      accent: Accent.pink,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.music_note_rounded),
              SizedBox(width: 8),
              Expanded(child: Text('A song for you ♡')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.message['file_name'] as String? ?? 'Our song',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, state) => Row(
              children: [
                IconButton(
                  tooltip: 'Play or pause song',
                  onPressed: _busy ? null : _toggle,
                  icon: _busy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          state.data?.playing == true &&
                                  state.data?.processingState !=
                                      ProcessingState.completed
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_fill,
                        ),
                ),
                Expanded(
                  child: Text(
                    _busy ? 'Loading your song…' : 'Just for the two of you',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snapshot) {
              final total = _player.duration ?? Duration.zero;
              final position = snapshot.data ?? Duration.zero;
              return Column(
                children: [
                  Slider(
                    semanticFormatterCallback: (value) =>
                        _time(Duration(milliseconds: value.round())),
                    value: position.inMilliseconds.toDouble().clamp(
                      0,
                      total.inMilliseconds.toDouble(),
                    ),
                    max: total.inMilliseconds > 0
                        ? total.inMilliseconds.toDouble()
                        : 1,
                    onChanged: !_loaded
                        ? null
                        : (value) => _player.seek(
                            Duration(milliseconds: value.round()),
                          ),
                  ),
                  Text(
                    '${_time(position)} / ${_time(total)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
