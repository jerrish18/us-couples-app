import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/design.dart';
import 'memory_composer.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/space.dart';
import '../../core/media.dart';
import '../../core/ui.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});
  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> {
  String? _collection;
  final Set<String> _deleting = {};
  Future<void> _add(UsSpace space) async {
    await safely(context, () async {
      final path = await pickPhoto(coupleId: space.session.coupleId!);
      if (path == null) return;
      bool saved = false;
      try {
        if (!mounted) return;
        saved =
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => MemoryComposer(
                  file: path,
                  initialCollection: _collection,
                  collections: List.of(space.rows['memory_collections'] ?? []),
                  onCreateCollection: (title) async {
                    final id = const Uuid().v4();
                    await space.add('memory_collections', {
                      'id': id,
                      'title': title,
                    });
                    return id;
                  },
                  onSave: (draft) => space.send(
                    draft.caption,
                    file: path,
                    kind: 'photo',
                    memory: true,
                    caption: draft.caption,
                    memoryDate: draft.date,
                    collectionId: draft.collectionId,
                  ),
                ),
              ),
            ) ??
            false;
      } finally {
        // Once queued, the sync engine owns the photo; cancellation owns cleanup.
        if (!saved && await File(path).exists()) await File(path).delete();
      }
    });
  }

  Future<void> _delete(UsSpace space, Map<String, dynamic> memory) async {
    final id = memory['id'] as String;
    if (_deleting.contains(id)) return;
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Delete this memory?'),
        content: const Text(
          'This permanently removes the photo, caption, and reactions for both of you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep memory'),
          ),
          ExpressiveButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
              foregroundColor: Theme.of(c).colorScheme.onError,
            ),
            child: const Text('Delete memory'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(id));
    await safely(context, () async {
      await space.deleteMemory(id);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Memory deleted')));
    });
    if (mounted) setState(() => _deleting.remove(id));
  }

  Future<void> _move(UsSpace space, Map<String, dynamic> memory) async {
    final collections = space.rows['memory_collections'] ?? [];
    final selected = await showGlassBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Move to collection')),
            ListTile(
              title: const Text('No collection'),
              onTap: () => Navigator.pop(c, 'none'),
            ),
            for (final collection in collections)
              ListTile(
                title: Text(collection['title'] as String),
                onTap: () => Navigator.pop(c, collection['id'] as String),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted)
      await safely(
        context,
        () => space.update('memories', memory['id'] as String, {
          'collection_id': selected == 'none' ? null : selected,
        }),
      );
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider);
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final collections = space.rows['memory_collections'] ?? [];
        final memories =
            (space.rows['memories'] ?? [])
                .where(
                  (m) =>
                      _collection == null || m['collection_id'] == _collection,
                )
                .toList()
              ..sort(
                (a, b) => (b['memory_date'] as String).compareTo(
                  a['memory_date'] as String,
                ),
              );
        return UsRefresh(
          onRefresh: space.refresh,
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: memories.length + 1,
            itemBuilder: (context, index) {
              if (index == 0)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeading(
                      'Memories',
                      '${memories.length} moments · Only the two of you',
                      trailing: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, size: 24),
                      ),
                    ),
                    ExpressiveButton.icon(
                      onPressed: () => _add(space),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Keep a memory'),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All moments'),
                          selected: _collection == null,
                          onSelected: (_) => setState(() => _collection = null),
                        ),
                        for (final c in collections)
                          ChoiceChip(
                            label: Text(c['title'] as String),
                            selected: _collection == c['id'],
                            onSelected: (_) =>
                                setState(() => _collection = c['id'] as String),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('Collection'),
                          onPressed: () => context.push('/collections'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (memories.isEmpty)
                      const EmptyCard(
                        'Our little moments',
                        'Photos and stories, held privately for the two of you.',
                        icon: Icons.photo_library_outlined,
                      ),
                  ],
                );
              final m = memories[index - 1];
              final hearts = (space.rows['reactions'] ?? [])
                  .where((r) => r['memory_id'] == m['id'])
                  .length;
              return Card(
                key: ValueKey(m['id']),
                margin: const EdgeInsets.only(bottom: 20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onDoubleTap: () => safely(
                        context,
                        () => space.react(m['id'] as String, memory: true),
                      ),
                      onTap: () => showGlassDialog<void>(
                        context: context,
                        builder: (c) => Dialog.fullscreen(
                          child: Scaffold(
                            appBar: GlassAppBar(
                              title: const Text('A little moment'),
                            ),
                            body: Center(
                              child: InteractiveViewer(
                                maxScale: 5,
                                child: PrivatePhoto(
                                  space,
                                  m['media_path'] as String,
                                  localFile: m['_local_file'] as String?,
                                  height: MediaQuery.sizeOf(c).height * .75,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: PrivatePhoto(
                        space,
                        m['media_path'] as String,
                        localFile: m['_local_file'] as String?,
                        height: 280,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m['caption'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayDate(m['memory_date'] as String),
                                ),
                              ),
                              if (m['_pending'] == true)
                                const Text('Waiting to sync'),
                              if (m['author_id'] == space.session.userId &&
                                  m['_pending'] != true)
                                PopupMenuButton<String>(
                                  tooltip: 'Memory options',
                                  enabled: !_deleting.contains(m['id']),
                                  onSelected: (v) {
                                    if (v == 'delete')
                                      _delete(space, m);
                                    else
                                      _move(space, m);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'move',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.drive_file_move_outline,
                                        ),
                                        title: Text('Move to collection'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        title: Text(
                                          'Delete memory',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  icon: _deleting.contains(m['id'])
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.more_horiz),
                                ),
                              IconButton(
                                tooltip: 'Heart memory',
                                onPressed: () => safely(
                                  context,
                                  () => space.react(
                                    m['id'] as String,
                                    memory: true,
                                  ),
                                ),
                                icon: const Icon(Icons.favorite_outline),
                              ),
                              Text('$hearts'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
