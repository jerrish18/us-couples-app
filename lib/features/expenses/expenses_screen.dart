import '../ai/ai_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/space.dart';
import '../../core/ui.dart';
import 'expense_groups.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ExpenseGrouping _grouping = ExpenseGrouping.date;
  String _query = '';
  Future<void> _edit(UsSpace space, [Map<String, dynamic>? row]) async {
    final saved = await showGlassBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExpenseEditor(initial: row),
    );
    if (saved == null || !mounted) return;
    await safely(context, () async {
      if (row == null) {
        await space.add('expenses', saved);
      } else {
        await space.session.client
            .from('expenses')
            .update(saved)
            .eq('id', row['id'] as String)
            .eq('author_id', space.session.userId!);
        await space.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider);
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Shared expenses'),
        actions: [
          IconButton(
            tooltip: 'Draft expense with AI',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AiScreen(space: space, initialTask: 'expense'),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: GlassActionButton.extended(
        onPressed: () => _edit(space),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: ListenableBuilder(
        listenable: space,
        builder: (context, _) {
          final rows = (space.rows['expenses'] ?? [])
              .where((r) => r['currency'] == 'INR')
              .toList();
          final groups = groupExpenses(rows, _grouping, query: _query);
          final total = rows.fold<int>(0, (n, r) => n + expensePaise(r));
          final mine = rows
              .where((r) => r['author_id'] == space.session.userId)
              .fold<int>(0, (n, r) => n + expensePaise(r));
          final balance = (mine - (total - mine)) / 200;
          return UsRefresh(
            onRefresh: space.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              children: [
                const PageHeading(
                  'Every little\nadventure.',
                  'When you spent it. What it was for.',
                ),
                TintedTile(
                  accent: Accent.green,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${(total / 100).toStringAsFixed(2)} together',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        balance.abs() < .01
                            ? 'You’re even'
                            : balance > 0
                            ? 'Your person owes you ₹${balance.toStringAsFixed(2)}'
                            : 'You owe ₹${(-balance).toStringAsFixed(2)}',
                      ),
                      const Text('Split equally · records only'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search a meal, trip or category',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in ExpenseGrouping.values)
                      ChoiceChip(
                        label: Text(switch (g) {
                          ExpenseGrouping.date => 'By date',
                          ExpenseGrouping.category => 'By category',
                          ExpenseGrouping.outing => 'By outing',
                        }),
                        selected: _grouping == g,
                        onSelected: (_) => setState(() => _grouping = g),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (groups.isEmpty)
                  const EmptyCard(
                    'Room for your next adventure',
                    'Add an expense with a date, category and optional outing.',
                  ),
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.key,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          '₹${(group.value.fold<int>(0, (n, r) => n + expensePaise(r)) / 100).toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ),
                  for (final r in group.value)
                    GlassCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long_rounded),
                        title: Text(r['title'] as String),
                        subtitle: Text(
                          '${expenseDate(r)} · ${r['category'] ?? 'Other'}\n${r['outing'] ?? 'Everyday'} · ${r['author_id'] == space.session.userId ? 'Paid by you' : 'Paid by your person'}',
                        ),
                        trailing: Text(
                          '₹${(r['amount'] as num).toStringAsFixed(2)}',
                        ),
                        onTap: () => showGlassBottomSheet<void>(
                          context: context,
                          builder: (sheet) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: Text(r['title'] as String),
                                subtitle: Text(
                                  r['notes'] as String? ?? 'No extra notes',
                                ),
                              ),
                              if (r['author_id'] == space.session.userId) ...[
                                ListTile(
                                  leading: const Icon(Icons.edit_outlined),
                                  title: const Text('Edit expense'),
                                  onTap: () {
                                    Navigator.pop(sheet);
                                    _edit(space, r);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: const Text('Delete expense'),
                                  onTap: () async {
                                    Navigator.pop(sheet);
                                    final yes = await showGlassDialog<bool>(
                                      context: context,
                                      builder: (c) => GlassDialog(
                                        title: const Text(
                                          'Delete this expense?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Keep'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (yes == true && mounted)
                                      await safely(
                                        context,
                                        () => space.remove(
                                          'expenses',
                                          r['id'] as String,
                                        ),
                                      );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class ExpenseEditor extends StatefulWidget {
  const ExpenseEditor({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<ExpenseEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _amount, _outing, _notes;
  late DateTime _date;
  late String _category;
  @override
  void initState() {
    super.initState();
    final r = widget.initial ?? {};
    _title = TextEditingController(text: r['title'] as String?);
    _amount = TextEditingController(text: r['amount']?.toString());
    _outing = TextEditingController(text: r['outing'] as String?);
    _notes = TextEditingController(text: r['notes'] as String?);
    _date = DateTime.tryParse(expenseDate(r)) ?? DateTime.now();
    _category = r['category'] as String? ?? 'Other';
  }

  @override
  void dispose() {
    for (final c in [_title, _amount, _outing, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.initial == null ? 'A little spending' : 'Edit expense',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _title,
            maxLength: 140,
            decoration: const InputDecoration(labelText: 'What was it for?'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Add a description' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount in ₹'),
            validator: (v) =>
                !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(v?.trim() ?? '') ||
                    (double.tryParse(v ?? '') ?? 0) <= 0
                ? 'Enter a positive amount, up to 2 decimal places'
                : null,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text('Spent on ${_date.toIso8601String().substring(0, 10)}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (d != null && mounted) setState(() => _date = d);
            },
          ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in expenseCategories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _outing,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Outing or purpose (optional)',
              hintText: 'Dinner date, weekend trip…',
            ),
          ),
          TextFormField(
            controller: _notes,
            maxLength: 1000,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 16),
          ExpressiveButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(context, {
                'title': _title.text.trim(),
                'amount': double.parse(_amount.text.trim()),
                'currency': 'INR',
                'spent_on': _date.toIso8601String().substring(0, 10),
                'category': _category,
                'outing': _outing.text.trim().isEmpty
                    ? null
                    : _outing.text.trim(),
                'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              });
            },
            child: const Text('Save expense'),
          ),
        ],
      ),
    ),
  );
}
