import '../../core/design.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;

import 'attachment_sheet.dart';
import 'music_dedication.dart';

import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../core/space.dart';
import '../../core/media.dart';
import '../../core/ui.dart';
import '../../core/share_inbox.dart';
import 'voice_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController(), _search = TextEditingController();
  final _scroll = ScrollController(), _focus = FocusNode();
  final _recorder = AudioRecorder();
  Timer? _recordLimit, _draftTimer, _typingDebounce, _searchDebounce;
  int _searchGeneration = 0;
  List<Map<String, dynamic>>? _remoteMatches;
  bool _searchBusy = false;
  StreamSubscription<dynamic>? _shares;
  bool _choosing = false;
  bool _recording = false,
      _sending = false,
      _searching = false,
      _starred = false,
      _foreground = true;
  String? _draftKey;
  Map<String, dynamic>? _reply;
  final Set<String> _marking = {};
  List<SharedMediaFile> _inbound = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final space = ref.read(spaceProvider);
    _draftKey = 'us.draft.${space.session.userId}.${space.session.coupleId}';
    unawaited(
      const FlutterSecureStorage().read(key: _draftKey!).then((v) {
        if (mounted && _text.text.isEmpty) _text.text = v ?? '';
      }),
    );
    _shares = ShareInbox.changes.stream.listen((_) {
      if (mounted) setState(() => _inbound = List.from(ShareInbox.pending));
    });
    _inbound = List.from(ShareInbox.pending);
    if (Platform.isAndroid)
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPhoto());
    _text.addListener(() {
      _draftTimer?.cancel();
      _draftTimer = Timer(const Duration(milliseconds: 400), () {
        if (_draftKey != null)
          unawaited(
            const FlutterSecureStorage().write(
              key: _draftKey!,
              value: _text.text,
            ),
          );
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    _searchDebounce?.cancel();
    _typingDebounce?.cancel();
    _recordLimit?.cancel();
    _shares?.cancel();
    _recorder.dispose();
    _text.dispose();
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(
    UsSpace space, {
    String? file,
    String? kind,
    String? fileName,
    String? mime,
  }) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await space.send(
        _text.text,
        file: file,
        kind: kind,
        replyTo: _reply?['id'] as String?,
        fileName: fileName,
        mime: mime,
      );
      _text.clear();
      unawaited(space.typing(false));
      if (mounted) setState(() => _reply = null);
      HapticFeedback.lightImpact();
    } catch (_) {
      if (mounted) _notice('Could not save this message. Please try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _attachments(UsSpace space) async {
    _focus.unfocus();
    final choice = await showGlassBottomSheet<String>(
      context: context,
      builder: (sheet) =>
          ChatAttachmentSheet(onSelect: (value) => Navigator.pop(sheet, value)),
    );
    if (!mounted || choice == null) return;
    // Let the sheet finish closing before Android launches its picker activity.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    switch (choice) {
      case 'photo':
        await _photo(space, ImageSource.gallery);
      case 'camera':
        await _photo(space, ImageSource.camera);
      case 'music':
        await _music(space);
      case 'file':
        await safely(context, () => _document(space));
      case 'poll':
        _poll(space);
    }
  }

  Future<void> _recoverPhoto() async {
    try {
      final result = await ImagePicker().retrieveLostData();
      if (!mounted) return;
      if (result.exception != null) {
        _notice('The photo could not be recovered. Please choose it again.');
        return;
      }
      final picked = result.files?.firstOrNull;
      if (picked == null) return;
      final space = ref.read(spaceProvider);
      final path = await preparePhoto(
        picked.path,
        coupleId: space.session.coupleId!,
      );
      if (mounted) await _previewPhoto(space, path);
    } catch (_) {
      if (mounted)
        _notice('Could not recover the photo. Please choose it again.');
    }
  }

  Future<void> _photo(UsSpace space, ImageSource source) async {
    if (_choosing || _sending || _recording) return;
    setState(() => _choosing = true);
    _focus.unfocus();
    try {
      final path = await pickPhoto(
        coupleId: space.session.coupleId!,
        source: source,
      );
      if (path != null && mounted) await _previewPhoto(space, path);
    } on PlatformException catch (error) {
      if (mounted)
        _notice(
          error.code.contains('denied')
              ? 'Photo access was denied. Allow access in Android Settings → Apps → Us → Permissions.'
              : 'Could not open the camera or photos. Please try again.',
        );
    } catch (_) {
      if (mounted)
        _notice('Could not prepare this photo. Try a different photo.');
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _previewPhoto(UsSpace space, String path) async {
    final send = await showGlassDialog<bool>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Send this photo?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(UsTokens.s20),
          child: Image.file(File(path), height: 280, fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ExpressiveButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Send photo'),
          ),
        ],
      ),
    );
    if (send == true && mounted) {
      await _send(space, file: path, kind: 'photo');
    } else {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _music(UsSpace space) async {
    if (_choosing) return;
    setState(() => _choosing = true);
    String? copyPath;
    bool queued = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a'],
      );
      if (result == null || !mounted) return;
      final picked = result.files.single;
      final path = picked.path;
      final ext = picked.name.split('.').last.toLowerCase();
      if (path == null ||
          !['mp3', 'm4a'].contains(ext) ||
          picked.size <= 0 ||
          picked.size > 5242880) {
        _notice('Choose an MP3 or M4A song up to 5 MB.');
        return;
      }
      final note = await askText(
        context,
        'A song for you',
        hint: 'Why this song reminds me of you…',
        initial: 'This one is for you ❤️',
        max: 500,
        lines: 3,
      );
      if (note == null || !mounted) return;
      final root = await getApplicationSupportDirectory();
      final folder = await Directory(
        '${root.path}/us-media/${space.session.coupleId}',
      ).create(recursive: true);
      copyPath = '${folder.path}/${const Uuid().v4()}.$ext';
      await File(path).copy(copyPath);
      final name = picked.name.length > 180
          ? picked.name.substring(picked.name.length - 180)
          : picked.name;
      await space.send(
        note,
        file: copyPath,
        kind: 'file',
        fileName: name,
        mime: ext == 'mp3' ? 'audio/mpeg' : 'audio/mp4',
        replyTo: _reply?['id'] as String?,
      );
      queued = true;
      if (mounted) setState(() => _reply = null);
      HapticFeedback.lightImpact();
    } catch (_) {
      if (mounted) _notice('Could not dedicate this song. Please try again.');
    } finally {
      if (!queued && copyPath != null) {
        try {
          await File(copyPath).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _choosing = false);
    }
  }

  Future<void> _voice(UsSpace space) async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        _recordLimit?.cancel();
        if (mounted) setState(() => _recording = false);
        if (path == null || !mounted) return;
        final send = await showGlassDialog<bool>(
          context: context,
          builder: (c) => GlassDialog(
            title: const Text('Your voice, a little closer'),
            content: VoiceBubble(space: space, message: {'_local_file': path}),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Discard'),
              ),
              ExpressiveButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Send'),
              ),
            ],
          ),
        );
        if (send == true)
          await _send(space, file: path, kind: 'voice');
        else
          try {
            await File(path).delete();
          } catch (_) {}
        return;
      }
      if (!await _recorder.hasPermission()) return;
      final root = await getApplicationSupportDirectory();
      final folder = await Directory(
        '${root.path}/us-media/${space.session.coupleId}',
      ).create(recursive: true);
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: '${folder.path}/${const Uuid().v4()}.m4a',
      );
      if (mounted) setState(() => _recording = true);
      _recordLimit = Timer(const Duration(minutes: 3), () => _voice(space));
    } catch (_) {
      if (mounted) _notice('Could not record. Check microphone permission.');
    }
  }

  static const _mimes = {
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  Future<void> _document(UsSpace space, {String? path, String? name}) async {
    if (path == null) {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _mimes.keys.toList(),
      );
      if (selected == null) return;
      path = selected.files.single.path;
      name = selected.files.single.name;
    }
    if (path == null || !mounted) return;
    name ??= path.split('/').last;
    final ext = name.split('.').last.toLowerCase();
    if (!_mimes.containsKey(ext) || await File(path).length() > 5242880) {
      if (mounted) _notice('Choose a PDF, text or Office document under 5 MB.');
      return;
    }
    final root = await getApplicationSupportDirectory();
    final folder = await Directory(
      '${root.path}/us-media/${space.session.coupleId}',
    ).create(recursive: true);
    final copy = await File(path)
        .copy('${folder.path}/${const Uuid().v4()}.$ext');
    await _send(
      space,
      file: copy.path,
      kind: 'file',
      fileName: name.length > 180 ? name.substring(name.length - 180) : name,
      mime: _mimes[ext],
    );
  }

  Future<void> _shared(UsSpace space) async {
    final files = List<SharedMediaFile>.from(_inbound);
    setState(() => _inbound = []);
    ShareInbox.clear();
    for (final f in files) {
      if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
        _text.text = [_text.text, f.path].where((v) => v.isNotEmpty).join('\n');
        continue;
      }
      if (f.type == SharedMediaType.image) {
        final root = await getApplicationSupportDirectory();
        final folder = await Directory(
          '${root.path}/us-media/${space.session.coupleId}',
        ).create(recursive: true);
        final compressed = await FlutterImageCompress.compressAndGetFile(
          f.path,
          '${folder.path}/${const Uuid().v4()}.jpg',
          quality: 78,
          minWidth: 1600,
          minHeight: 1600,
          keepExif: false,
        );
        if (compressed != null)
          await _send(space, file: compressed.path, kind: 'photo');
      } else {
        await _document(space, path: f.path, name: f.path.split('/').last);
      }
    }
  }

  void _find(UsSpace space) {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final query = _search.text.trim();
    if (query.isEmpty) {
      setState(() {
        _remoteMatches = null;
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final pages = await Future.wait(
          ['body', 'file_name'].map(
            (field) => space.session.client
                .from('messages')
                .select()
                .eq('couple_id', space.session.coupleId!)
                .ilike(field, '%$query%')
                .order('created_at', ascending: false)
                .limit(100),
          ),
        );
        if (!mounted || generation != _searchGeneration) return;
        final merged = <String, Map<String, dynamic>>{};
        for (final page in pages) {
          for (final row in page) {
            merged[row['id'] as String] = Map<String, dynamic>.from(row);
          }
        }
        setState(() => _remoteMatches = merged.values.toList());
      } catch (_) {
        if (mounted && generation == _searchGeneration) {
          setState(() => _remoteMatches = null);
          _notice('Offline · searching messages saved on this phone.');
        }
      } finally {
        if (mounted && generation == _searchGeneration)
          setState(() => _searchBusy = false);
      }
    });
  }

  Future<void> _poll(UsSpace space) async {
    final question = await askText(
      context,
      'Ask your person',
      hint: 'What should we cook?',
      max: 300,
    );
    if (question == null || !mounted) return;
    final options = await askText(
      context,
      'Options, one per line',
      initial: 'Option one\nOption two',
      lines: 4,
      max: 600,
    );
    if (options == null || !mounted) return;
    final choices = options
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .take(6)
        .toList();
    if (choices.length < 2) {
      _notice('Add at least two different options.');
      return;
    }
    await safely(
      context,
      () => space.add('polls', {'question': question, 'options': choices}),
    );
  }

  Future<void> _mutate(
    UsSpace space,
    Map<String, dynamic> m,
    String action, {
    String? body,
  }) async {
    await space.session.client.rpc(
      'mutate_message',
      params: {'p_id': m['id'], 'p_action': action, 'p_body': body},
    );
    final patch = <String, dynamic>{
      if (action == 'edit') ...{
        'body': body,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      },
      if (action == 'pin' || action == 'unpin') 'pinned': action == 'pin',
      if (action == 'delete') ...{
        'body': 'This message was deleted',
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'media_path': null,
        'media_kind': null,
        'pinned': false,
      },
    };
    final index = space.items.indexWhere((r) => r['id'] == m['id']);
    if (index >= 0) space.items[index] = {...m, ...patch};
    if (mounted) setState(() {});
  }

  Future<void> _actions(UsSpace space, Map<String, dynamic> m) async {
    final mine = m['sender_id'] == space.session.userId,
        pending = m['_pending'] == true,
        deleted = m['deleted_at'] != null;
    final star = (space.rows['message_states'] ?? []).any(
      (s) =>
          s['message_id'] == m['id'] &&
          s['user_id'] == space.session.userId &&
          s['starred'] == true,
    );
    await showGlassBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!deleted && !pending)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in ['❤️', '😂', '🥰', '👍', '😢', '🔥'])
                      IconButton(
                        tooltip: 'React $emoji',
                        onPressed: () {
                          Navigator.pop(sheet);
                          safely(
                            context,
                            () => space.react(m['id'] as String, emoji: emoji),
                          );
                        },
                        icon: Text(
                          emoji,
                          style: const TextStyle(fontSize: UsTokens.s24),
                        ),
                      ),
                  ],
                ),
              if (!deleted)
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(sheet);
                    setState(() => _reply = m);
                    _focus.requestFocus();
                  },
                ),
              if (m['body'] != null && !deleted)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy text'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: m['body'] as String));
                    Navigator.pop(sheet);
                  },
                ),
              if (!pending && !deleted) ...[
                ListTile(
                  leading: Icon(star ? Icons.star : Icons.star_border),
                  title: Text(star ? 'Unstar' : 'Star message'),
                  onTap: () {
                    Navigator.pop(sheet);
                    safely(
                      context,
                      () =>
                          space.messageState(m['id'] as String, starred: !star),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.push_pin_outlined),
                  title: Text(
                    m['pinned'] == true ? 'Unpin for both' : 'Pin for both',
                  ),
                  onTap: () {
                    Navigator.pop(sheet);
                    safely(
                      context,
                      () => _mutate(
                        space,
                        m,
                        m['pinned'] == true ? 'unpin' : 'pin',
                      ),
                    );
                  },
                ),
                if (m['body'] != null && m['media_path'] == null)
                  ListTile(
                    leading: const Icon(Icons.forward_outlined),
                    title: const Text('Forward to our chat'),
                    onTap: () {
                      Navigator.pop(sheet);
                      safely(context, () => space.send('↪ ${m['body']}'));
                    },
                  ),
                if (mine && m['media_path'] == null)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit message'),
                    onTap: () async {
                      Navigator.pop(sheet);
                      final body = await askText(
                        context,
                        'Edit message',
                        initial: m['body'] as String? ?? '',
                        max: 8000,
                        lines: 3,
                      );
                      if (body != null && mounted)
                        await safely(
                          context,
                          () => _mutate(space, m, 'edit', body: body),
                        );
                    },
                  ),
                if (mine)
                  ListTile(
                    leading: const Icon(Icons.delete_forever_outlined),
                    title: const Text('Delete for everyone'),
                    onTap: () async {
                      Navigator.pop(sheet);
                      final yes = await showGlassDialog<bool>(
                        context: context,
                        builder: (c) => GlassDialog(
                          title: const Text('Delete for both of you?'),
                          content: const Text(
                            'This replaces the message with a deletion notice. Your partner may already have saved a copy.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel'),
                            ),
                            ExpressiveButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true && mounted)
                        await safely(context, () async {
                          if (m['media_path'] != null)
                            await space.session.client.storage
                                .from('couple-media')
                                .remove([m['media_path'] as String]);
                          await _mutate(space, m, 'delete');
                        });
                    },
                  ),
              ],
              if (!pending)
                ListTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: const Text('Delete for me'),
                  onTap: () {
                    Navigator.pop(sheet);
                    safely(
                      context,
                      () => space.messageState(m['id'] as String, hidden: true),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _read(UsSpace space, Map<String, dynamic> m) {
    if (!_foreground ||
        m['sender_id'] == space.session.userId ||
        m['_pending'] == true)
      return;
    final id = m['id'] as String, states = space.rows['message_states'] ?? [];
    if (_marking.contains(id) ||
        states.any(
          (s) =>
              s['message_id'] == id &&
              s['user_id'] == space.session.userId &&
              s['read_at'] != null,
        ))
      return;
    _marking.add(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foreground)
        unawaited(
          space.messageState(id).catchError((_) {
            _marking.remove(id);
          }),
        );
    });
  }

  Widget _pollCard(UsSpace space, Map<String, dynamic> p) {
    final options = List<String>.from(p['options'] as List),
        votes = space.rows['poll_votes'] ?? [];
    final own = votes
        .where(
          (v) =>
              v['poll_id'] == p['id'] && v['user_id'] == space.session.userId,
        )
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: UsTokens.s12),
      child: Padding(
        padding: const EdgeInsets.all(UsTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p['question'] as String,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < options.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  own?['choice'] == i
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(options[i]),
                trailing: Text(
                  '${votes.where((v) => v['poll_id'] == p['id'] && v['choice'] == i).length}',
                ),
                onTap: () => safely(context, () async {
                  if (own == null)
                    await space.session.client.from('poll_votes').insert({
                      'couple_id': space.session.coupleId,
                      'poll_id': p['id'],
                      'user_id': space.session.userId,
                      'choice': i,
                    });
                  else
                    await space.session.client
                        .from('poll_votes')
                        .update({'choice': i})
                        .eq('poll_id', p['id'] as String)
                        .eq('user_id', space.session.userId!);
                  await space.refresh();
                }),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider),
        colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final states = space.rows['message_states'] ?? [];
        final hidden = states
                .where(
                  (s) =>
                      s['user_id'] == space.session.userId &&
                      s['hidden'] == true,
                )
                .map((s) => s['message_id'])
                .toSet(),
            stars = states
                .where(
                  (s) =>
                      s['user_id'] == space.session.userId &&
                      s['starred'] == true,
                )
                .map((s) => s['message_id'])
                .toSet();
        final searchable = <String, Map<String, dynamic>>{
          for (final m in space.items) m['id'] as String: m,
          if (_searching && _remoteMatches != null)
            for (final m in _remoteMatches!) m['id'] as String: m,
        };
        final messages =
            searchable.values
                .where(
                  (m) =>
                      !hidden.contains(m['id']) &&
                      (!_starred || stars.contains(m['id'])) &&
                      (!_searching ||
                          '${m['body'] ?? ''} ${m['file_name'] ?? ''}'
                              .toLowerCase()
                              .contains(_search.text.toLowerCase())),
                )
                .toList()
              ..sort(
                (a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'),
              );
        final pins = space.items
            .where((m) => m['pinned'] == true && m['deleted_at'] == null)
            .toList();
        final polls = space.rows['polls'] ?? [];
        return Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(
                UsTokens.s20,
                UsTokens.s4,
                UsTokens.s12,
                UsTokens.s12,
              ),
              leading: Badge(
                backgroundColor: space.partnerOnline
                    ? UsColors.greenInk
                    : colors.outline,
                smallSize: 10,
                child: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: const Icon(Icons.favorite_outline),
                ),
              ),
              title: Text(
                space.me?['nickname'] as String? ??
                    space.partner?['display_name'] as String? ??
                    'Your person',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                space.partnerTyping
                    ? 'typing…'
                    : space.partnerOnline
                    ? 'Here with you'
                    : space.queued > 0
                    ? '${space.queued} waiting to sync'
                    : space.partner?['last_seen'] == null
                    ? 'Your private conversation'
                    : 'Last seen ${displayDate(space.partner!['last_seen'] as String)} ${displayTime(space.partner!['last_seen'] as String)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Search conversation',
                    onPressed: () => setState(() => _searching = !_searching),
                    icon: Icon(_searching ? Icons.close : Icons.search),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'stars') setState(() => _starred = !_starred);
                      if (v == 'poll') _poll(space);
                      if (v == 'sync') space.sync();
                      if (v == 'polls')
                        showGlassBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          builder: (c) => SafeArea(
                            child: ListenableBuilder(
                              listenable: space,
                              builder: (c, _) => ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(UsTokens.s20),
                                children: [
                                  Text(
                                    'Our polls',
                                    style: Theme.of(c).textTheme.titleLarge,
                                  ),
                                  if (polls.isEmpty)
                                    const Text(
                                      'Create a poll from the chat menu.',
                                    ),
                                  ...polls.map((p) => _pollCard(space, p)),
                                ],
                              ),
                            ),
                          ),
                        );
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'stars',
                        child: Text(
                          _starred ? 'Show all messages' : 'Starred messages',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'poll',
                        child: Text('Create a poll'),
                      ),
                      const PopupMenuItem(
                        value: 'polls',
                        child: Text('Our polls'),
                      ),
                      const PopupMenuItem(
                        value: 'sync',
                        child: Text('Retry sending'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  UsTokens.s16,
                  UsTokens.s0,
                  UsTokens.s16,
                  UsTokens.s8,
                ),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) {
                    setState(() {});
                    _find(space);
                  },
                  maxLength: 100,
                  buildCounter: (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
                  decoration: const InputDecoration(
                    hintText: 'Search messages or documents',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
            if (_searchBusy) const LinearProgressIndicator(minHeight: 2),
            if (_starred)
              const Padding(
                padding: EdgeInsets.all(UsTokens.s8),
                child: Text('★ Your starred messages'),
              ),
            if (pins.isNotEmpty)
              SizedBox(
                height: UsTokens.s44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: UsTokens.s16),
                  children: pins
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.only(right: UsTokens.s8),
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.push_pin,
                              size: UsTokens.s16,
                            ),
                            label: SizedBox(
                              width: UsTokens.s152,
                              child: Text(
                                m['body'] as String? ?? 'Pinned attachment',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onPressed: () => _actions(space, m),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: EmptyCard(
                        _searching || _starred
                            ? 'Nothing here yet'
                            : 'Say something sweet',
                        _searching
                            ? 'Try another word.'
                            : 'Your conversation begins here.',
                        icon: Icons.chat_bubble_outline,
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: UsTokens.s16,
                        vertical: UsTokens.s12,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[messages.length - index - 1],
                            mine = m['sender_id'] == space.session.userId,
                            deleted = m['deleted_at'] != null;
                        _read(space, m);
                        final reacts = (space.rows['reactions'] ?? [])
                            .where((r) => r['message_id'] == m['id'])
                            .map((r) => r['emoji'] ?? '❤️')
                            .join(' ');
                        final read = states.any(
                              (s) =>
                                  s['message_id'] == m['id'] &&
                                  s['user_id'] == space.session.partnerId &&
                                  s['read_at'] != null,
                            ),
                            replied = space.items
                                .where((r) => r['id'] == m['reply_to'])
                                .firstOrNull;
                        final older = index + 1 < messages.length
                            ? messages[messages.length - index - 2]
                            : null;
                        final day = '${m['created_at']}'.substring(0, 10);
                        final showDay =
                            older == null ||
                            '${older['created_at']}'.substring(0, 10) != day;
                        final text = m['body'] as String? ?? '';
                        final link = RegExp(r'https?://[^\s<>]+')
                            .firstMatch(text)
                            ?.group(0);
                        return Column(
                          children: [
                            if (showDay)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: UsTokens.s16,
                                ),
                                child: Text(
                                  displayDate(day),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium,
                                ),
                              ),
                            Dismissible(
                              key: ValueKey(m['id']),
                              direction: DismissDirection.startToEnd,
                              confirmDismiss: (_) async {
                                if (!deleted) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _reply = m);
                                  _focus.requestFocus();
                                }
                                return false;
                              },
                              background: const Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Icon(Icons.reply),
                              ),
                              child: Align(
                                alignment: mine
                                    ? AlignmentDirectional.centerEnd
                                    : AlignmentDirectional.centerStart,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * .82,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: UsTokens.s8,
                                    ),
                                    child: GestureDetector(
                                      onLongPress: () => _actions(space, m),
                                      onDoubleTap:
                                          deleted || m['_pending'] == true
                                          ? null
                                          : () => safely(
                                              context,
                                              () => space.react(
                                                m['id'] as String,
                                              ),
                                            ),
                                      child: MessageSurface(
                                        mine: mine,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (m['reply_to'] != null)
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  UsTokens.s8,
                                                ),
                                                margin: const EdgeInsets.only(
                                                  bottom: UsTokens.s8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: colors.surface
                                                      .withValues(alpha: .45),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        UsTokens.s8,
                                                      ),
                                                  border: Border(
                                                    left: BorderSide(
                                                      color: colors.primary,
                                                      width: UsTokens.s4,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  replied?['body'] as String? ??
                                                      'Attachment',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            if (!deleted &&
                                                m['media_kind'] == 'photo')
                                              GestureDetector(
                                                onTap: () => showGlassDialog<void>(
                                                  context: context,
                                                  builder: (c) => Dialog.fullscreen(
                                                    child: Scaffold(
                                                      appBar: GlassAppBar(
                                                        title: const Text(
                                                          'Your photo',
                                                        ),
                                                      ),
                                                      body: Center(
                                                        child: InteractiveViewer(
                                                          maxScale: 5,
                                                          child: Hero(
                                                            tag:
                                                                'message-${m['id']}',
                                                            child: PrivatePhoto(
                                                              space,
                                                              m['media_path']
                                                                  as String,
                                                              localFile:
                                                                  m['_local_file']
                                                                      as String?,
                                                              height:
                                                                  MediaQuery.sizeOf(
                                                                    c,
                                                                  ).height *
                                                                  .7,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                child: Hero(
                                                  tag: 'message-${m['id']}',
                                                  child: PrivatePhoto(
                                                    space,
                                                    m['media_path'] as String,
                                                    localFile:
                                                        m['_local_file']
                                                            as String?,
                                                  ),
                                                ),
                                              ),
                                            if (!deleted &&
                                                m['media_kind'] == 'voice')
                                              VoiceBubble(
                                                key: ValueKey(
                                                  'voice-${m['id']}',
                                                ),
                                                space: space,
                                                message: m,
                                              ),
                                            if (!deleted &&
                                                m['media_kind'] == 'file' &&
                                                !isMusicDedication(m))
                                              TextButton.icon(
                                                onPressed: () => safely(context, () async {
                                                  final path =
                                                      m['_local_file']
                                                          as String? ??
                                                      await space.mediaFile(
                                                        m['media_path']
                                                            as String,
                                                      );
                                                  await SharePlus.instance.share(
                                                    ShareParams(
                                                      files: [
                                                        XFile(
                                                          path,
                                                          name:
                                                              m['file_name']
                                                                  as String?,
                                                          mimeType:
                                                              m['mime_type']
                                                                  as String?,
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                                icon: const Icon(
                                                  Icons.description_outlined,
                                                ),
                                                label: Text(
                                                  '${m['file_name'] ?? 'Document'}\n${((m['file_size'] as num? ?? 0) / 1024).round()} KB · Tap to open or save',
                                                ),
                                              ),
                                            if (!deleted &&
                                                isMusicDedication(m))
                                              MusicDedicationCard(
                                                key: ValueKey(
                                                  'music-${m['id']}',
                                                ),
                                                space: space,
                                                message: m,
                                              ),
                                            if (text.isNotEmpty)
                                              Text(
                                                text,
                                                style: TextStyle(
                                                  fontSize: UsTokens.s16,
                                                  height: 1.4,
                                                  fontStyle: deleted
                                                      ? FontStyle.italic
                                                      : null,
                                                  color: deleted
                                                      ? colors.onSurfaceVariant
                                                      : null,
                                                ),
                                              ),
                                            if (link != null && !deleted)
                                              TextButton.icon(
                                                onPressed: () => launchUrl(
                                                  Uri.parse(link),
                                                  mode: LaunchMode
                                                      .externalApplication,
                                                ),
                                                icon: const Icon(
                                                  Icons.open_in_new,
                                                  size: UsTokens.s16,
                                                ),
                                                label: const Text('Open link'),
                                              ),
                                            if (reacts.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: UsTokens.s4,
                                                ),
                                                child: Text(
                                                  reacts,
                                                  style: const TextStyle(
                                                    fontSize: UsTokens.font18,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: UsTokens.s4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (stars.contains(m['id']))
                                                  const Icon(
                                                    Icons.star,
                                                    size: UsTokens.s12,
                                                  ),
                                                if (m['pinned'] == true)
                                                  const Icon(
                                                    Icons.push_pin,
                                                    size: UsTokens.s12,
                                                  ),
                                                Text(
                                                  '${displayTime(m['created_at'] as String)}${m['edited_at'] != null ? ' · edited' : ''}${mine ? ' · ${m['_pending'] == true
                                                            ? 'Waiting'
                                                            : read
                                                            ? 'Read'
                                                            : 'Sent'}' : ''}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelSmall,
                                                ),
                                                if (mine &&
                                                    m['_pending'] != true)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: UsTokens.s4,
                                                        ),
                                                    child: Icon(
                                                      read
                                                          ? Icons.done_all
                                                          : Icons.done,
                                                      size: UsTokens.s12,
                                                      color: read
                                                          ? colors.primary
                                                          : colors
                                                                .onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_inbound.isNotEmpty)
              Material(
                color: colors.secondaryContainer,
                child: ListTile(
                  title: Text('${_inbound.length} item(s) shared to Us'),
                  subtitle: const Text(
                    'Review text as a draft, or send selected photos/documents to your person.',
                  ),
                  leading: IconButton(
                    tooltip: 'Discard incoming share',
                    onPressed: () {
                      ShareInbox.clear();
                      setState(() => _inbound = []);
                    },
                    icon: const Icon(Icons.close),
                  ),
                  trailing: TextButton(
                    onPressed: _sending
                        ? null
                        : () => safely(context, () => _shared(space)),
                    child: Text(
                      _inbound.every(
                            (f) =>
                                f.type == SharedMediaType.text ||
                                f.type == SharedMediaType.url,
                          )
                          ? 'Add to draft'
                          : 'Send attachments',
                    ),
                  ),
                ),
              ),
            if (_reply != null)
              ListTile(
                dense: true,
                leading: const Icon(Icons.reply),
                title: const Text('Replying to'),
                subtitle: Text(
                  _reply!['body'] as String? ?? 'Attachment',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  onPressed: () => setState(() => _reply = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_recording)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.fiber_manual_record,
                    color: UsColors.danger,
                    size: UsTokens.s12,
                  ),
                  const Text(' Recording · up to 3 minutes'),
                  TextButton(
                    onPressed: () async {
                      await _recorder.cancel();
                      _recordLimit?.cancel();
                      if (mounted) setState(() => _recording = false);
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  UsTokens.s8,
                  UsTokens.s8,
                  UsTokens.s8,
                  UsTokens.s8,
                ),
                child: GlassCard(
                  blur: true,
                  radius: UsTokens.s36,
                  padding: const EdgeInsets.all(UsTokens.s4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Add attachment',
                        onPressed: _sending || _recording || _choosing
                            ? null
                            : () => _attachments(space),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      IconButton(
                        tooltip: 'Take a photo',
                        onPressed: _sending || _recording || _choosing
                            ? null
                            : () => _photo(space, ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 8000,
                          textCapitalization: TextCapitalization.sentences,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                          onChanged: (_) {
                            _typingDebounce?.cancel();
                            _typingDebounce = Timer(
                              const Duration(milliseconds: 200),
                              () => space.typing(_text.text.isNotEmpty),
                            );
                          },
                          decoration: const InputDecoration(
                            hintText: 'A little hello…',
                            hintMaxLines: 1,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: UsTokens.s16,
                              vertical: UsTokens.s12,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _recording
                            ? 'Stop and preview'
                            : 'Record voice note',
                        onPressed: _sending || _choosing
                            ? null
                            : () => _voice(space),
                        icon: Icon(
                          _recording ? Icons.stop_circle : Icons.mic_none,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: _sending || _recording || _choosing
                            ? null
                            : () => _send(space),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
