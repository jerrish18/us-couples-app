import 'package:flutter/material.dart';

import '../../core/design.dart';

class ChatAttachmentSheet extends StatelessWidget {
  const ChatAttachmentSheet({super.key, required this.onSelect});
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Share a little moment',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        for (final item in const [
          (
            'photo',
            Icons.photo_library_outlined,
            'Gallery',
            'Choose from your photos',
          ),
          ('camera', Icons.camera_alt_outlined, 'Camera', 'Take a photo now'),
          (
            'music',
            Icons.music_note_rounded,
            'Dedicate a song',
            'MP3 or M4A · up to 5 MB',
          ),
          (
            'file',
            Icons.description_outlined,
            'Document',
            'PDF, text or Office · up to 5 MB',
          ),
          ('poll', Icons.poll_outlined, 'Poll', 'Decide something together'),
        ]) ...[
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UsTokens.s20),
            ),
            leading: Icon(item.$2),
            title: Text(item.$3),
            subtitle: Text(item.$4),
            onTap: () => onSelect(item.$1),
          ),
          const SizedBox(height: 8),
        ],
      ],
    ),
  );
}
