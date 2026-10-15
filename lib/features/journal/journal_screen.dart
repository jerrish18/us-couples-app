import '../../core/design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/space.dart';
import '../../core/ui.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(spaceProvider);
    return Scaffold(
      appBar: GlassAppBar(title: const Text('Our journal')),
      floatingActionButton: GlassActionButton.extended(
        icon: const Icon(Icons.edit_note),
        label: const Text('Write'),
        onPressed: () async {
          final text = await askText(
            context,
            'A page in your story',
            lines: 5,
            max: 20000,
          );
          if (text != null && context.mounted)
            await safely(
              context,
              () =>
                  space.add('journal_entries', {'body': text, 'shared': false}),
            );
        },
      ),
      body: ListenableBuilder(
        listenable: space,
        builder: (context, _) {
          final entries =
              List<Map<String, dynamic>>.from(
                space.rows['journal_entries'] ?? [],
              )..sort(
                (a, b) => (b['entry_date'] as String).compareTo(
                  a['entry_date'] as String,
                ),
              );
          return SpaceBody(
            space: space,
            table: 'journal_entries',
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                UsTokens.s20,
                UsTokens.s20,
                UsTokens.s20,
                UsTokens.s96,
              ),
              children: [
                const PageHeading(
                  'Our unwritten\nchapters.',
                  'New entries are only visible to you. Share a page when you want your person to read it.',
                  trailing: FlowerBadge(
                    icon: Icons.auto_stories_rounded,
                    accent: Accent.lavender,
                  ),
                ),
                if (entries.isEmpty)
                  const EmptyCard(
                    'Some words, just for you',
                    'Write privately, or share a page with your person.',
                    icon: Icons.menu_book_outlined,
                  ),
                ...entries.map((entry) {
                  final mine = entry['author_id'] == space.session.userId;
                  return GlassCard(
                    padding: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(UsTokens.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${displayDate(entry['entry_date'] as String)} · ${entry['shared'] == true ? 'Shared ❤️' : 'Only me 🔒'}',
                          ),
                          const SizedBox(height: UsTokens.s12),
                          SelectableText(
                            entry['body'] as String,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (mine)
                            Wrap(
                              spacing: UsTokens.s8,
                              runSpacing: UsTokens.s8,
                              children: [
                                TextButton(
                                  onPressed: () => safely(
                                    context,
                                    () => space.update(
                                      'journal_entries',
                                      entry['id'] as String,
                                      {'shared': entry['shared'] != true},
                                    ),
                                  ),
                                  child: Text(
                                    entry['shared'] == true
                                        ? 'Make private'
                                        : 'Share with my person',
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit entry',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    final text = await askText(
                                      context,
                                      'Edit your page',
                                      initial: entry['body'] as String,
                                      lines: 5,
                                      max: 20000,
                                    );
                                    if (text != null && context.mounted)
                                      await safely(
                                        context,
                                        () => space.update(
                                          'journal_entries',
                                          entry['id'] as String,
                                          {'body': text},
                                        ),
                                      );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Remove entry',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => safely(
                                    context,
                                    () => space.remove(
                                      'journal_entries',
                                      entry['id'] as String,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
