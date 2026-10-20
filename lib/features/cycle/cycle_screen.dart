import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/space.dart';
import '../../core/ui.dart';
import 'cycle_prediction.dart';

class CycleScreen extends ConsumerStatefulWidget {
  const CycleScreen({super.key});
  @override
  ConsumerState<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends ConsumerState<CycleScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _profiles = [], _logs = [];
  bool _busy = true, _partner = false;
  String? _error;
  Timer? _refresh;
  int _generation = 0;
  bool _foreground = true;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground && _partner) _load();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed)
      _load();
    else if (state == AppLifecycleState.paused && mounted)
      setState(() {
        _generation++;
        _profiles = [];
        _logs = [];
        _busy = true;
      });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final session = ref.read(spaceProvider).session;
    try {
      final profiles = await session.client
          .from('cycle_profiles')
          .select()
          .eq('couple_id', session.coupleId!);
      final logs = await session.client
          .from('cycle_logs')
          .select()
          .eq('couple_id', session.coupleId!)
          .order('start_date', ascending: false);
      if (mounted && generation == _generation && _foreground)
        setState(() {
          _profiles = List<Map<String, dynamic>>.from(profiles);
          _logs = List<Map<String, dynamic>>.from(logs);
          _busy = false;
          _error = null;
        });
    } catch (_) {
      if (mounted && generation == _generation && _foreground)
        setState(() {
          _busy = false;
          _error = 'Could not load cycle history. Tap to retry.';
          _profiles = [];
          _logs = [];
        });
    }
  }

  Map<String, dynamic>? get _mine => _profiles
      .where((p) => p['user_id'] == ref.read(spaceProvider).session.userId)
      .firstOrNull;
  Future<void> _setup() async {
    final yes = await showGlassDialog<bool>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Your cycle, your choice'),
        content: const Text(
          'Set up tracking for yourself on this account. Your dates and symptoms stay private unless you choose to share them with your partner. You can stop sharing or delete your history at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Later'),
          ),
          ExpressiveButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Set up my tracker'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await safely(context, () async {
      final s = ref.read(spaceProvider).session;
      await s.client.from('cycle_profiles').insert({
        'user_id': s.userId,
        'couple_id': s.coupleId,
      });
      await _load();
    });
  }

  Future<void> _log([Map<String, dynamic>? initial]) async {
    final value = await showGlassBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CycleEditor(initial: initial),
    );
    if (value == null || !mounted) return;
    await safely(context, () async {
      final s = ref.read(spaceProvider).session;
      final start = DateTime.parse(value['start_date'] as String),
          end = DateTime.parse(value['end_date'] as String);
      for (final row in _logs.where(
        (r) => r['user_id'] == s.userId && r['id'] != initial?['id'],
      )) {
        final a = DateTime.parse(row['start_date'] as String),
            b = DateTime.parse(row['end_date'] as String);
        if (!start.isAfter(b) && !end.isBefore(a))
          throw StateError(
            'These dates overlap an existing period. Edit that entry instead.',
          );
      }
      if (initial == null) {
        await s.client.from('cycle_logs').insert({
          ...value,
          'user_id': s.userId,
          'couple_id': s.coupleId,
        });
      } else {
        await s.client
            .from('cycle_logs')
            .update(value)
            .eq('id', initial['id'] as String)
            .eq('user_id', s.userId!);
      }
      await _load();
    });
  }

  Future<void> _deleteAll() async {
    final yes = await showGlassDialog<bool>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Delete your cycle history?'),
        content: const Text(
          'This removes your tracker, all logged periods and symptoms, and stops partner sharing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete my history'),
          ),
        ],
      ),
    );
    if (yes == true && mounted)
      await safely(context, () async {
        final s = ref.read(spaceProvider).session;
        await s.client.from('cycle_profiles').delete().eq('user_id', s.userId!);
        await _load();
      });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(spaceProvider).session;
    final uid = _partner ? s.partnerId : s.userId;
    final profile = _profiles.where((p) => p['user_id'] == uid).firstOrNull;
    final logs = _logs.where((p) => p['user_id'] == uid).toList();
    final estimate = estimateCycle(
      logs.map((r) => DateTime.parse(r['start_date'] as String)).toList(),
      fallback: (profile?['cycle_length'] as num?)?.toInt() ?? 28,
    );
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Cycle care')),
      floatingActionButton: !_partner && _mine != null
          ? GlassActionButton.extended(
              onPressed: () => _log(),
              icon: const Icon(Icons.add),
              label: const Text('Log period'),
            )
          : null,
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                children: [
                  const PageHeading(
                    'A little care,\nevery cycle.',
                    'A gentle place to understand your patterns.',
                  ),
                  if (_error != null)
                    TextButton(onPressed: _load, child: Text(_error!)),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('My tracker'),
                        selected: !_partner,
                        onSelected: (_) => setState(() => _partner = false),
                      ),
                      ChoiceChip(
                        label: const Text('Shared with me'),
                        selected: _partner,
                        onSelected: (_) {
                          setState(() => _partner = true);
                          _load();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (profile == null)
                    EmptyCard(
                      _partner
                          ? 'Your partner’s choice'
                          : 'Start with your last period',
                      _partner
                          ? 'Your partner can enable sharing from their own tracker.'
                          : 'Log your dates, flow, symptoms and mood. Sharing starts off.',
                    ),
                  if (profile == null && !_partner)
                    ExpressiveButton(
                      onPressed: _setup,
                      child: const Text('Set up my tracker'),
                    ),
                  if (profile != null) ...[
                    TintedTile(
                      accent: Accent.pink,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            estimate == null
                                ? 'Your story starts here'
                                : 'Next period · estimated',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (estimate != null)
                            Text(
                              estimate.nextStart.toIso8601String().substring(
                                0,
                                10,
                              ),
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                          Text(
                            estimate == null
                                ? 'Add a period to see an estimate.'
                                : '${estimate.length}-day cycle · ${estimate.samples == 0 ? 'your chosen length' : '${estimate.samples} recent cycle intervals'}',
                          ),
                          const Text(
                            'Estimates can change. This tracker does not confirm ovulation or provide contraception.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Previous month',
                                onPressed: () => setState(
                                  () => _month = DateTime(
                                    _month.year,
                                    _month.month - 1,
                                  ),
                                ),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    MaterialLocalizations.of(
                                      context,
                                    ).formatMonthYear(_month),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next month',
                                onPressed: () => setState(
                                  () => _month = DateTime(
                                    _month.year,
                                    _month.month + 1,
                                  ),
                                ),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              for (final d in [
                                'M',
                                'T',
                                'W',
                                'T',
                                'F',
                                'S',
                                'S',
                              ])
                                Expanded(child: Center(child: Text(d))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisSpacing: 4,
                                  crossAxisSpacing: 4,
                                ),
                            itemCount:
                                DateTime(_month.year, _month.month + 1, 0).day +
                                _month.weekday -
                                1,
                            itemBuilder: (context, i) {
                              final n = i - _month.weekday + 2;
                              if (n < 1) return const SizedBox.shrink();
                              final day = DateTime(
                                _month.year,
                                _month.month,
                                n,
                              );
                              final logged = logs.any(
                                (r) => cycleContains(
                                  day,
                                  DateTime.parse(r['start_date'] as String),
                                  DateTime.parse(r['end_date'] as String),
                                ),
                              );
                              final predicted =
                                  estimate != null &&
                                  cycleContains(
                                    day,
                                    estimate.nextStart,
                                    estimate.nextStart.add(
                                      Duration(
                                        days:
                                            (profile['period_length'] as num)
                                                .toInt() -
                                            1,
                                      ),
                                    ),
                                  );
                              final today =
                                  cycleDay(day) == cycleDay(DateTime.now());
                              return Semantics(
                                label:
                                    '$n${logged
                                        ? ', logged period'
                                        : predicted
                                        ? ', estimated period'
                                        : ''}',
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: logged
                                        ? colors.primary
                                        : predicted
                                        ? colors.primaryContainer
                                        : null,
                                    shape: BoxShape.circle,
                                    border: today
                                        ? Border.all(
                                            color: colors.primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Text(
                                    '$n',
                                    style: TextStyle(
                                      color: logged
                                          ? colors.onPrimary
                                          : colors.onSurface,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Filled · logged    Soft · estimated    Ring · today',
                          ),
                        ],
                      ),
                    ),
                    if (!_partner) ...[
                      GlassCard(
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Share with my partner'),
                              subtitle: const Text(
                                'Shares your logged dates, symptoms, mood and notes. Turn off at any time.',
                              ),
                              value: profile['share_with_partner'] == true,
                              onChanged: (value) => safely(context, () async {
                                await s.client
                                    .from('cycle_profiles')
                                    .update({'share_with_partner': value})
                                    .eq('user_id', s.userId!);
                                await _load();
                              }),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Typical cycle · ${profile['cycle_length']} days',
                              ),
                              subtitle: const Text(
                                'Used until you have enough logged history',
                              ),
                              onTap: () async {
                                final value = await askText(
                                  context,
                                  'Typical cycle length',
                                  hint: 'Days, from 15 to 90',
                                  max: 2,
                                );
                                final length = int.tryParse(value ?? '');
                                if (length == null ||
                                    length < 15 ||
                                    length > 90 ||
                                    !context.mounted)
                                  return;
                                await safely(context, () async {
                                  await s.client
                                      .from('cycle_profiles')
                                      .update({'cycle_length': length})
                                      .eq('user_id', s.userId!);
                                  await _load();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text(
                      'Period history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (logs.isEmpty) const Text('No periods logged yet.'),
                    for (final r in logs)
                      GlassCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.water_drop_outlined),
                          title: Text('${r['start_date']} → ${r['end_date']}'),
                          subtitle: Text(
                            '${r['flow']} flow · ${r['mood']}\n${(r['symptoms'] as List).join(', ')}${(r['notes'] as String? ?? '').isEmpty ? '' : '\n${r['notes']}'}',
                          ),
                          onTap: _partner ? null : () => _log(r),
                          trailing: _partner
                              ? null
                              : IconButton(
                                  tooltip: 'Delete period',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final yes = await showGlassDialog<bool>(
                                      context: context,
                                      builder: (c) => GlassDialog(
                                        title: const Text(
                                          'Delete this period?',
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
                                    if (yes == true && context.mounted)
                                      await safely(context, () async {
                                        await s.client
                                            .from('cycle_logs')
                                            .delete()
                                            .eq('id', r['id'] as String)
                                            .eq('user_id', s.userId!);
                                        await _load();
                                      });
                                  },
                                ),
                        ),
                      ),
                    if (!_partner)
                      TextButton.icon(
                        onPressed: _deleteAll,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete my tracker and history'),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class CycleEditor extends StatefulWidget {
  const CycleEditor({super.key, this.initial});
  final Map<String, dynamic>? initial;
  @override
  State<CycleEditor> createState() => _CycleEditorState();
}

class _CycleEditorState extends State<CycleEditor> {
  late DateTime _start, _end;
  late String _flow, _mood;
  late Set<String> _symptoms;
  late final TextEditingController _notes;
  @override
  void initState() {
    super.initState();
    final r = widget.initial ?? {};
    _start = DateTime.tryParse('${r['start_date']}') ?? DateTime.now();
    _end = DateTime.tryParse('${r['end_date']}') ?? _start;
    _flow = r['flow'] as String? ?? 'Medium';
    _mood = r['mood'] as String? ?? 'Okay';
    _symptoms = Set<String>.from(r['symptoms'] as List? ?? []);
    _notes = TextEditingController(text: r['notes'] as String?);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Log a period', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Period dates'),
          subtitle: Text(
            '${_start.toIso8601String().substring(0, 10)} → ${_end.toIso8601String().substring(0, 10)}',
          ),
          leading: const Icon(Icons.date_range),
          onTap: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
              initialDateRange: DateTimeRange(start: _start, end: _end),
            );
            if (range != null && mounted)
              setState(() {
                _start = range.start;
                _end = range.end;
              });
          },
        ),
        const Text(
          'If your period is ongoing, log through today and update the end date later.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _flow,
          decoration: const InputDecoration(labelText: 'Flow'),
          items: [
            for (final f in ['Light', 'Medium', 'Heavy', 'Spotting'])
              DropdownMenuItem(value: f, child: Text(f)),
          ],
          onChanged: (v) => setState(() => _flow = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _mood,
          decoration: const InputDecoration(labelText: 'Mood'),
          items: [
            for (final f in [
              'Okay',
              'Happy',
              'Low',
              'Sensitive',
              'Anxious',
              'Energetic',
            ])
              DropdownMenuItem(value: f, child: Text(f)),
          ],
          onChanged: (v) => setState(() => _mood = v!),
        ),
        const SizedBox(height: 16),
        const Text('Symptoms'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in [
              'Cramps',
              'Headache',
              'Bloating',
              'Fatigue',
              'Backache',
              'Tenderness',
              'Acne',
            ])
              FilterChip(
                label: Text(s),
                selected: _symptoms.contains(s),
                onSelected: (v) => setState(() {
                  if (v) {
                    _symptoms.add(s);
                  } else {
                    _symptoms.remove(s);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _notes,
          maxLength: 1000,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
        ),
        const SizedBox(height: 16),
        ExpressiveButton(
          onPressed: () {
            if (cycleDay(_end).difference(cycleDay(_start)).inDays > 29) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Choose up to 30 days per entry.'),
                ),
              );
              return;
            }
            Navigator.pop(context, {
              'start_date': _start.toIso8601String().substring(0, 10),
              'end_date': _end.toIso8601String().substring(0, 10),
              'flow': _flow,
              'mood': _mood,
              'symptoms': _symptoms.toList(),
              'notes': _notes.text.trim(),
            });
          },
          child: const Text('Save period'),
        ),
      ],
    ),
  );
}
