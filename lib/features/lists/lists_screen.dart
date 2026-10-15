import '../../core/design.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/space.dart';
import '../../core/ui.dart';

class ListsScreen extends ConsumerStatefulWidget {
  const ListsScreen({super.key});
  @override
  ConsumerState<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends ConsumerState<ListsScreen> {
  String _kind = 'bucket';
  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider);
    return Scaffold(
      appBar: GlassAppBar(title: const Text('Our lists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final title = await askText(
            context,
            'Something for our list',
            max: 500,
          );
          if (title != null && context.mounted)
            await safely(
              context,
              () =>
                  space.add('list_items', {'list_kind': _kind, 'title': title}),
            );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: ListenableBuilder(
        listenable: space,
        builder: (context, _) {
          final items = (space.rows['list_items'] ?? [])
              .where((r) => r['list_kind'] == _kind)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bucket', label: Text('Bucket')),
                  ButtonSegment(value: 'todo', label: Text('To-do')),
                  ButtonSegment(value: 'grocery', label: Text('Grocery')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              const SizedBox(height: 24),
              if (items.isEmpty)
                const EmptyCard(
                  'Make a little plan',
                  'Both of you can add, edit, and check off items.',
                  icon: Icons.checklist,
                ),
              ...items.map(
                (item) => Card(
                  child: CheckboxListTile(
                    value: item['completed'] == true,
                    onChanged: (value) => safely(
                      context,
                      () => space.update('list_items', item['id'] as String, {
                        'completed': value,
                      }),
                    ),
                    title: Text(
                      item['title'] as String,
                      style: TextStyle(
                        decoration: item['completed'] == true
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    secondary: PopupMenuButton<String>(
                      onSelected: (action) async {
                        if (action == 'delete') {
                          await safely(
                            context,
                            () => space.remove(
                              'list_items',
                              item['id'] as String,
                            ),
                          );
                          return;
                        }
                        final title = await askText(
                          context,
                          'Edit item',
                          initial: item['title'] as String,
                          max: 500,
                        );
                        if (title != null && context.mounted)
                          await safely(
                            context,
                            () => space.update(
                              'list_items',
                              item['id'] as String,
                              {'title': title},
                            ),
                          );
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Remove')),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
