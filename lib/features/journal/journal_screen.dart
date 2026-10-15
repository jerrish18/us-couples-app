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
      appBar: AppBar(title: const Text('Our journal')),
      floatingActionButton: FloatingActionButton.extended(
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            children: [
              const Text(
                'New entries are only visible to you. Share an entry when you want your person to read it.',
              ),
              const SizedBox(height: 20),
              if (entries.isEmpty)
                const EmptyCard(
                  'Some words, just for you',
                  'Write privately, or share a page with your person.',
                  icon: Icons.menu_book_outlined,
                ),
              ...entries.map((entry) {
                final mine = entry['author_id'] == space.session.userId;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${displayDate(entry['entry_date'] as String)} · ${entry['shared'] == true ? 'Shared ❤️' : 'Only me 🔒'}',
                        ),
                        const SizedBox(height: 14),
                        SelectableText(entry['body'] as String),
                        if (mine)
                          Row(
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
          );
        },
      ),
    );
  }
}
