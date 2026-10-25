import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/design.dart';
import '../../core/settings.dart';
import 'call_service.dart';

class CallHost extends ConsumerWidget {
  const CallHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(callProvider);
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (service.call != null)
            AppLockGate(child: CallScreen(service: service)),
        ],
      ),
    );
  }
}

class CallScreen extends StatelessWidget {
  const CallScreen({super.key, required this.service});
  final CallService service;
  @override
  Widget build(BuildContext context) {
    final c = service;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Text(
                  c.echoActive
                      ? (c.echoSession?['state'] == 'human'
                            ? 'Your person is on the call'
                            : 'ECHO is answering as AI')
                      : c.incoming
                      ? 'Your person is calling'
                      : c.call?['state'] == 'ringing'
                      ? 'Calling your person…'
                      : 'Here, together',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(c.video ? 'Private video call' : 'Private voice call'),
                Text(
                  c.connection.isEmpty
                      ? 'Waiting to connect'
                      : c.connection.replaceAll('RTCPeerConnectionState', ''),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: c.echoActive
                      ? EchoCallDetails(service: c)
                      : c.video && !c.incoming
                      ? Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(32),
                                child: RTCVideoView(
                                  c.remote,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.topRight,
                              child: SizedBox(
                                width: 110,
                                height: 160,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: RTCVideoView(c.local, mirror: true),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: FlowerBadge(
                            icon: c.video
                                ? Icons.videocam_rounded
                                : Icons.favorite_rounded,
                            accent: Accent.pink,
                            size: 140,
                          ),
                        ),
                ),
                if (c.error != null)
                  Text(c.error!, style: TextStyle(color: colors.error)),
                if (c.aiRequested && c.incoming)
                  const Text('ECHO requested. You can still answer normally.'),
                if (c.busy) const LinearProgressIndicator(),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (c.incoming)
                      ExpressiveButton.icon(
                        onPressed: c.busy ? null : c.answer,
                        icon: const Icon(Icons.call),
                        label: const Text('Answer'),
                      ),
                    if (c.incoming && !c.video)
                      OutlinedButton.icon(
                        onPressed: c.busy || c.aiRequested
                            ? null
                            : c.requestAiAnswer,
                        icon: const Icon(Icons.support_agent),
                        label: const Text('AI Answer'),
                      ),
                    if (c.echoForMe && c.echoSession?['state'] != 'human')
                      ExpressiveButton.icon(
                        onPressed: c.canTakeOverEcho ? c.takeOverEcho : null,
                        icon: const Icon(Icons.call),
                        label: const Text('Take over call'),
                      ),
                    if (!c.incoming &&
                        (!c.echoForMe ||
                            c.echoSession?['state'] == 'human')) ...[
                      IconButton.filledTonal(
                        tooltip: c.muted ? 'Unmute' : 'Mute',
                        onPressed: c.toggleMute,
                        icon: Icon(c.muted ? Icons.mic_off : Icons.mic),
                      ),
                      IconButton.filledTonal(
                        tooltip: c.speaker ? 'Use earpiece' : 'Use speaker',
                        onPressed: c.toggleSpeaker,
                        icon: Icon(c.speaker ? Icons.volume_up : Icons.hearing),
                      ),
                      if (c.video) ...[
                        IconButton.filledTonal(
                          tooltip: c.cameraEnabled
                              ? 'Turn camera off'
                              : 'Turn camera on',
                          onPressed: c.toggleCamera,
                          icon: Icon(
                            c.cameraEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Switch camera',
                          onPressed: c.switchCamera,
                          icon: const Icon(Icons.cameraswitch),
                        ),
                      ],
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: colors.onError,
                      ),
                      onPressed: () => c.end(c.incoming ? 'declined' : 'ended'),
                      icon: const Icon(Icons.call_end),
                      label: Text(c.incoming ? 'Decline' : 'End call'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EchoCallDetails extends StatelessWidget {
  const EchoCallDetails({super.key, required this.service});
  final CallService service;
  @override
  Widget build(BuildContext context) {
    final echo = service.echoSession ?? const <String, dynamic>{};
    final transcript = (echo['transcript'] as List? ?? const [])
        .whereType<Map>();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        const Icon(Icons.support_agent, size: 64),
        const SizedBox(height: 16),
        Text(
          echo['state'] == 'human'
              ? 'ECHO has handed the conversation to your partner.'
              : 'You are speaking with ECHO, an AI receptionist. A partner can take over this call.',
          textAlign: TextAlign.center,
        ),
        if ('${echo['important'] ?? ''}'.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Flagged caller messages (keyword matches)\n${echo['important']}',
              ),
            ),
          ),
        if (transcript.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No saved transcript. Saving is controlled by the partner receiving this call.',
            ),
          ),
        for (final line in transcript)
          ListTile(
            title: Text('${line['text'] ?? ''}'),
            subtitle: Text(line['role'] == 'caller' ? 'Caller' : 'ECHO · AI'),
          ),
        if (service.echoForMe && transcript.isNotEmpty)
          TextButton.icon(
            onPressed: service.eraseEchoTranscript,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Erase transcript and stop saving'),
          ),
      ],
    );
  }
}
