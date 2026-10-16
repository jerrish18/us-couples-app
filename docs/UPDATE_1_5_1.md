# Us 1.5.1 — layout, attachments and music

## Changes
- Shell lays pages out above the real navigation dock rather than reserving a fixed 96 pixels. Keyboard resizing is handled by Scaffold and the dock hides while typing.
- Settings cards and sections have 12-pixel gaps; feature tiles have 16-pixel grid gaps. Theme controls have inner padding.
- Chat text line height is 1.4 rather than zero.
- Attachment actions live in a scrollable bottom sheet. It closes before launching an Android activity.
- Gallery uses Android's photo picker. Camera uses the native capture activity from a direct chat button or the attachment sheet. No broad media-library permission is requested.
- Photos are compressed to private application storage, previewed before sending, and discarded if cancelled. Android picker results lost after process death are recovered into an explicit preview.
- Music dedication: Chat → + → Dedicate a song → select MP3/M4A up to 5 MB → write a note → Save. The received message contains a music card with play/pause, seek and elapsed/total time. Existing message reactions and pinning apply. Music pauses when the app leaves the foreground or the card is disposed.

## Implementation map
- `lib/main.dart`: shell/dock and keyboard geometry.
- `lib/features/more/more_screen.dart`: settings spacing.
- `lib/core/media.dart`: selectable gallery/camera source and persistent photo preparation.
- `lib/features/chat/attachment_sheet.dart`: attachment action UI.
- `lib/features/chat/chat_screen.dart`: picker lifecycle, photo preview/recovery, music selection and enqueueing.
- `lib/features/chat/music_dedication.dart`: private audio playback UI and MIME classification.
- `supabase/music_storage.sql`: idempotent MP3 allowlist addition, applied to Uss project during implementation.
- `test/chat_attachments_test.dart`: attachment action mapping, file classification, composer keyboard/dock geometry and sheet position.

## Data compatibility
Music uses the existing `media_kind=file`, `file_name`, `mime_type`, `file_size`, `body`, `media_path` fields. MP3 uses `audio/mpeg`; M4A uses `audio/mp4`. UsSpace and offline queuing are unchanged. No new tables or navigation destinations are added. Existing RLS, signed URLs, deletion and backup paths continue to apply. Older versions display a normal file attachment.

## Limits
This version plays selected local audio files. It does not include a licensed music search catalogue, Spotify/YouTube playback integration, or downloaded tracks from subscription apps. Audio stays within the current 5 MB per-file cap. No autoplay. Only one dedication card plays at a time; voice-note playback remains independent.

## Validation
The release must pass Flutter analyze, all widget/unit tests, signed APK certificate/architecture checks, and the existing Android 7/15 install/launch checks. A successful emulator smoke test confirms startup and auth callback routing; it does not establish successful partner-to-partner photo/audio delivery on physical phones. On-device checks still needed: Pixel gallery selection/cancellation, front/rear camera capture/cancellation, picker process recovery, partner audio download/playback and keyboard opening/closing using gesture and three-button navigation.

## Scope guard
This update explicitly authorizes picker behavior and music uploads. The media helper hash in docs/ui-scope.json is updated accordingly; unrelated frozen services and existing routes remain checked. Release version is 1.5.1+5, signed with the existing certificate to preserve installation upgrades.
