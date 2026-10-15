import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/space.dart';
import '../../core/ui.dart';
import '../../core/design.dart';
import '../../core/reminder_dates.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime? _selected;
  Future<void> _date(UsSpace space) async {
    final value = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const DateEditor(),
    );
    if (value != null && mounted)
      await safely(context, () => space.add('dates', value));
  }

  Future<void> _anniversary(UsSpace space) async {
    final title = await askText(
      context,
      'Anniversary, birthday, or milestone',
      hint: 'Give this day a name',
      max: 120,
    );
    if (title == null || !mounted) return;
    final date = await pickDateTime(context, time: false);
    if (date == null || !mounted) return;
    final yearly = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Repeat every year?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('One time'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Every year'),
          ),
        ],
      ),
    );
    if (yearly != null && mounted)
      await safely(
        context,
        () => space.add('anniversaries', {
          'title': title,
          'event_date': date.toIso8601String().substring(0, 10),
          'yearly': yearly,
        }),
      );
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider);
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final dates = List<Map<String, dynamic>>.from(space.rows['dates'] ?? [])
          ..sort(
            (a, b) =>
                (a['starts_at'] as String).compareTo(b['starts_at'] as String),
          );
        final shown = _selected == null
            ? dates
            : dates.where((d) {
                final value = DateTime.parse(d['starts_at'] as String)
                    .toLocal();
                return value.year == _selected!.year &&
                    value.month == _selected!.month &&
                    value.day == _selected!.day;
              }).toList();
        final anniversaries = space.rows['anniversaries'] ?? [];
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const PageHeading(
              'Our calendar',
              'Make room for your favourite person.',
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _date(space),
                    icon: const Icon(Icons.add),
                    label: const Text('Plan a date'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Add special day',
                  onPressed: () => _anniversary(space),
                  icon: const Icon(Icons.cake_outlined),
                ),
              ],
            ),
            Card(
              child: CalendarDatePicker(
                initialDate: _selected ?? DateTime.now(),
                firstDate: DateTime(1900),
                lastDate: DateTime(2200),
                onDateChanged: (date) => setState(() => _selected = date),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selected == null
                        ? 'Our dates'
                        : '${_selected!.day}/${_selected!.month}/${_selected!.year}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_selected != null)
                  TextButton(
                    onPressed: () => setState(() => _selected = null),
                    child: const Text('Show all'),
                  ),
              ],
            ),
            if (shown.isEmpty)
              const EmptyCard(
                'Make some time for us',
                'A walk, a call, or a little adventure—plan it together.',
                icon: Icons.calendar_month,
              ),
            ...shown.map((date) {
              final mine = date['author_id'] == space.session.userId;
              final response = (space.rows['date_responses'] ?? [])
                  .where(
                    (r) =>
                        r['date_id'] == date['id'] &&
                        r['user_id'] != date['author_id'],
                  )
                  .firstOrNull;
              final authorResponse = (space.rows['date_responses'] ?? [])
                  .where(
                    (r) =>
                        r['date_id'] == date['id'] &&
                        r['user_id'] == date['author_id'],
                  )
                  .firstOrNull;
              final acceptedSuggestion =
                  response?['status'] == 'suggested' &&
                  authorResponse?['status'] == 'accepted' &&
                  DateTime.tryParse(
                        response?['proposed_at'] as String? ?? '',
                      ) ==
                      DateTime.tryParse(date['starts_at'] as String);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date['title'] as String,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${displayDate(date['starts_at'] as String)} · ${displayTime(date['starts_at'] as String)}',
                      ),
                      if ((date['place'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('📍 ${date['place']}'),
                        ),
                      if ((date['notes'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(date['notes'] as String),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        acceptedSuggestion
                            ? 'Accepted ❤️'
                            : response == null
                            ? 'Waiting for a reply'
                            : response['status'] == 'suggested'
                            ? 'Suggested: ${displayDate(response['proposed_at'] as String)} · ${displayTime(response['proposed_at'] as String)}'
                            : response['status'] == 'accepted'
                            ? 'Accepted ❤️'
                            : 'Declined',
                      ),
                      Wrap(
                        spacing: 8,
                        children: mine
                            ? [
                                if (response?['status'] == 'suggested' &&
                                    !acceptedSuggestion)
                                  TextButton(
                                    onPressed: () => safely(context, () async {
                                      await space.update(
                                        'dates',
                                        date['id'] as String,
                                        {'starts_at': response!['proposed_at']},
                                      );
                                      await space.respond(
                                        date['id'] as String,
                                        'accepted',
                                      );
                                    }),
                                    child: const Text('Accept suggested time'),
                                  ),
                                TextButton(
                                  onPressed: () => safely(
                                    context,
                                    () => space.remove(
                                      'dates',
                                      date['id'] as String,
                                    ),
                                  ),
                                  child: const Text('Remove date'),
                                ),
                              ]
                            : [
                                TextButton(
                                  onPressed: () => safely(
                                    context,
                                    () => space.respond(
                                      date['id'] as String,
                                      'accepted',
                                    ),
                                  ),
                                  child: const Text('Accept'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final when = await pickDateTime(context);
                                    if (when != null && context.mounted)
                                      await safely(
                                        context,
                                        () => space.respond(
                                          date['id'] as String,
                                          'suggested',
                                          proposed: when,
                                        ),
                                      );
                                  },
                                  child: const Text('Suggest time'),
                                ),
                                TextButton(
                                  onPressed: () => safely(
                                    context,
                                    () => space.respond(
                                      date['id'] as String,
                                      'declined',
                                    ),
                                  ),
                                  child: const Text('Decline'),
                                ),
                              ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Our special days',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Add special day',
                  onPressed: () => _anniversary(space),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (anniversaries.isEmpty)
              const EmptyCard(
                'Days to remember',
                'Add anniversaries, birthdays, and your own special days.',
                icon: Icons.cake_outlined,
              ),
            ...anniversaries.map((day) {
              final original = DateTime.parse(day['event_date'] as String);
              final next = day['yearly'] == true
                  ? nextAnnualDate(original, DateTime.now())
                  : original;
              final left = daysTogether(DateTime.now(), next);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.favorite_border),
                  title: Text(day['title'] as String),
                  subtitle: Text(
                    '${displayDate(next.toIso8601String())} · ${left >= 0 ? '$left days away' : 'A day in our story'}',
                  ),
                  trailing: day['author_id'] == space.session.userId
                      ? IconButton(
                          tooltip: 'Remove special day',
                          onPressed: () => safely(
                            context,
                            () => space.remove(
                              'anniversaries',
                              day['id'] as String,
                            ),
                          ),
                          icon: const Icon(Icons.close),
                        )
                      : null,
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class DateEditor extends StatefulWidget {
  const DateEditor({super.key});
  @override
  State<DateEditor> createState() => _DateEditorState();
}

class _DateEditorState extends State<DateEditor> {
  final _title = TextEditingController(),
      _place = TextEditingController(),
      _notes = TextEditingController();
  final _form = GlobalKey<FormState>();
  DateTime _when = DateTime.now().add(const Duration(hours: 2));
  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A date, just for us',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _title,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Give your date a title'
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  '${displayDate(_when.toIso8601String())} · ${displayTime(_when.toIso8601String())}',
                ),
                onTap: () async {
                  final value = await pickDateTime(context, initial: _when);
                  if (value != null && mounted) setState(() => _when = value);
                },
              ),
              TextField(
                controller: _place,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: 'Place or call link',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLength: 4000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate())
                    Navigator.pop(context, {
                      'title': _title.text.trim(),
                      'starts_at': _when.toUtc().toIso8601String(),
                      'place': _place.text.trim(),
                      'notes': _notes.text.trim(),
                    });
                },
                child: const Text('Invite my person'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
