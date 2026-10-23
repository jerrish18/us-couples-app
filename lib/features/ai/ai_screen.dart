import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/design.dart';
import '../../core/space.dart';
import '../../core/ui.dart';
import '../expenses/expenses_screen.dart';
import '../expenses/expense_groups.dart';
import 'ai_service.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({
    super.key,
    required this.space,
    this.initialTask = 'together',
    this.initialText = '',
    this.messageId,
    this.service,
  });
  final UsSpace space;
  final String initialTask, initialText;
  final String? messageId;
  final UsAi? service;
  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  late final _prompt = TextEditingController(
    text: widget.initialText.isNotEmpty
        ? widget.initialText
        : switch (widget.initialTask) {
            'reply' => 'Suggest three replies: sweet, playful and reassuring.',
            'summary' =>
              'Summarise our plans, decisions and things still to discuss.',
            'plans' =>
              'Prepare a draft date, task or expense from these messages.',
            _ => '',
          },
  );
  late String _task = widget.initialTask;
  String _language = 'English';
  final _budget = TextEditingController(text: '1500'),
      _minutes = TextEditingController(text: '180');
  late final Set<String> _ids = {
    if (widget.messageId != null) widget.messageId!,
  };
  DateTime _from = DateTime.now().subtract(const Duration(days: 7)),
      _until = DateTime.now();
  bool _enabled = false,
      _history = false,
      _partner = false,
      _loading = true,
      _busy = false,
      _saved = false;
  String? _error;
  Map<String, dynamic>? _result;
  late final _ai = widget.service ?? UsAi(widget.space);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _budget.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _ai.preferences();
      final own = rows
          .where((r) => r['user_id'] == widget.space.session.userId)
          .firstOrNull;
      if (mounted)
        setState(() {
          _enabled = own?['enabled'] == true;
          _history = own?['share_history'] == true;
          _partner = rows.any(
            (r) =>
                r['user_id'] == widget.space.session.partnerId &&
                r['enabled'] == true &&
                r['share_history'] == true,
          );
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load AI permissions. Please retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _consent(bool enabled, bool history) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ai.consent(enabled: enabled, history: history);
      if (mounted)
        setState(() {
          _enabled = enabled;
          _history = enabled && history;
          _result = null;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not update AI permission. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _needsHistory =>
      ['reply', 'together', 'summary', 'plans', 'search'].contains(_task);
  Future<void> _ask() async {
    if (_task == 'date') {
      final budget = double.tryParse(_budget.text),
          minutes = int.tryParse(_minutes.text);
      if (budget == null ||
          !budget.isFinite ||
          budget < 1 ||
          budget > 100000 ||
          minutes == null ||
          minutes < 30 ||
          minutes > 1440) {
        setState(
          () => _error =
              'Enter a budget from ₹1 to ₹100,000 and 30 to 1,440 minutes.',
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _saved = false;
    });
    try {
      final data = await _ai.ask(
        task: _task,
        prompt: _prompt.text,
        language: _language,
        ids: ['reply', 'plans'].contains(_task) ? _ids.toList() : [],
        from: _from,
        until: _until,
        budget: double.tryParse(_budget.text),
        minutes: int.tryParse(_minutes.text),
        publish: _task == 'together',
      );
      if (mounted) setState(() => _result = data);
    } on FunctionException catch (e) {
      if (mounted)
        setState(
          () => _error = e.details is Map
              ? '${e.details['error'] ?? 'AI unavailable'}'
              : 'Could not reach AI. Please try again.',
        );
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose() async {
    final rows = widget.space.items
        .where(
          (m) =>
              m['deleted_at'] == null &&
              m['_pending'] != true &&
              m['media_path'] == null,
        )
        .toList()
        .reversed
        .take(150)
        .toList();
    final selected = Set<String>.of(_ids);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Select up to 30 saved text messages (${selected.length})',
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final m in rows)
                        CheckboxListTile(
                          value: selected.contains(m['id']),
                          title: Text(
                            '${m['body']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${m['created_at']}'),
                          onChanged: (v) => update(() {
                            if (v == true && selected.length < 30)
                              selected.add(m['id'] as String);
                            else if (v == false)
                              selected.remove(m['id']);
                          }),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Use selection'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted)
      setState(() {
        _ids
          ..clear()
          ..addAll(selected);
        _result = null;
      });
  }

  Future<void> _source(Map<String, dynamic> source) async {
    try {
      final row = await widget.space.session.client
          .from('messages')
          .select('body,created_at')
          .eq('couple_id', widget.space.session.coupleId!)
          .eq('id', source['id'] as String)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(row == null ? 'Message unavailable' : 'Original message'),
          content: SelectableText(
            row == null
                ? 'This message may have been deleted.'
                : '${row['body']}\n\n${row['created_at']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not open the source message.');
    }
  }

  Future<void> _saveDraft() async {
    final d = Map<String, dynamic>.from(_result!['draft'] as Map);
    if (_task == 'date' && _result!['budget'] != null) {
      d['kind'] = 'date';
      if ('${d['title'] ?? ''}'.trim().isEmpty) d['title'] = 'Our date';
      d['notes'] = [
        for (final item in _result!['itinerary'] as List)
          '${item['activity']} · ${item['minutes']} min · estimated INR ${item['estimated_cost']} for two',
        'Estimated total INR ${_result!['budget']['total']}',
      ].join('\n');
    }
    if (d['kind'] == 'expense') {
      final initial = {
        'title': d['title'],
        'amount': d['amount'],
        'category': expenseCategories.contains(d['category'])
            ? d['category']
            : 'Other',
        'outing': d['outing'],
        'notes': d['notes'],
        'spent_on': d['spent_on'],
      };
      final saved = await showGlassBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ExpenseEditor(initial: initial),
      );
      if (saved == null || !mounted) return;
      setState(() => _busy = true);
      try {
        await widget.space.add('expenses', saved);
        if (mounted) setState(() => _saved = true);
      } catch (_) {
        if (mounted)
          setState(() => _error = 'Could not save the expense. Try again.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final saved = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiPlanEditor(draft: d),
    );
    if (saved == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.space.add(
        d['kind'] == 'todo' ? 'list_items' : 'dates',
        saved,
      );
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not save the plan. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result, draft = result?['draft'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Us AI ✨'),
        actions: [
          IconButton(
            tooltip: 'Refresh AI permissions',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'A little help, on your terms.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'Suggestions are yours to edit. Nothing is sent or saved without your choice.',
          ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Privacy & free usage'),
            children: [
              Text(
                'Groq · GPT-OSS 120B. Your request and the indicated text context are sent to Groq. Photos, voice, location and cycle records are excluded. Private suggestions stay on this screen. Shared answers remain in your chat. Limit: 20 requests per couple daily (UTC), 30 seconds apart. No paid fallback.',
              ),
            ],
          ),
          if (_loading)
            const LinearProgressIndicator()
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable my AI assistance'),
              subtitle: const Text(
                'Allow the text I submit to be processed by Groq.',
              ),
              value: _enabled,
              onChanged: _busy ? null : (v) => _consent(v, _history),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow selected shared chat context'),
              subtitle: Text(
                _partner
                    ? 'Your partner has opted in too.'
                    : 'Your partner must opt in on their phone for shared-chat features.',
              ),
              value: _history,
              onChanged: _busy || !_enabled
                  ? null
                  : (v) => _consent(_enabled, v),
            ),
          ],
          const Divider(),
          DropdownButtonFormField<String>(
            initialValue: _task,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'AI action'),
            items: [
              for (final e in aiTasks.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _task = v!;
                    _result = null;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tamil and Tanglish are in beta. Review wording before using it.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final language in ['English', 'Tamil', 'Tanglish'])
                ChoiceChip(
                  label: Text(language),
                  selected: _language == language,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _language = language),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_task == 'date') ...[
            TextField(
              key: const Key('ai-budget'),
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Total budget for both (INR)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Available time in minutes (including travel)',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_task == 'summary') ...[
            ListTile(
              title: const Text('From'),
              subtitle: Text(displayDate(_from.toIso8601String())),
              onTap: _busy
                  ? null
                  : () async {
                      final v = await pickDateTime(context, initial: _from);
                      if (v != null && mounted) setState(() => _from = v);
                    },
            ),
            ListTile(
              title: const Text('Until (exclusive)'),
              subtitle: Text(displayDate(_until.toIso8601String())),
              onTap: _busy
                  ? null
                  : () async {
                      final v = await pickDateTime(context, initial: _until);
                      if (v != null && mounted) setState(() => _until = v);
                    },
            ),
          ],
          if (['reply', 'plans'].contains(_task))
            OutlinedButton.icon(
              onPressed: _busy ? null : _choose,
              icon: const Icon(Icons.checklist),
              label: Text('${_ids.length} messages selected'),
            ),
          TextField(
            controller: _prompt,
            enabled: !_busy,
            maxLength: 1500,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: switch (_task) {
                'rewrite' => 'Your unsent draft',
                'caption' => 'Describe the memory (text only)',
                'search' => 'Words or phrase to find',
                'date' => 'Budget, date, time, area and preferences',
                _ => 'What would you like help with?',
              },
              helperText: _needsHistory
                  ? 'Uses saved text only; both partners must opt in.'
                  : 'Uses only the text you type here.',
              helperMaxLines: 2,
            ),
          ),
          if (_task == 'together')
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ask & share publishes a labelled AI answer for both partners. Other actions remain private.',
              ),
            ),
          FilledButton.icon(
            key: const Key('ai-generate'),
            onPressed:
                _busy ||
                    _loading ||
                    !_enabled ||
                    (_needsHistory && !(_history && _partner))
                ? null
                : _ask,
            icon: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _task == 'together'
                  ? 'Ask & share with partner'
                  : 'Generate privately',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (result != null) ...[
            const SizedBox(height: 20),
            SelectableText(
              '${result['answer']}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (result['budget'] != null) ...[
              for (final item in result['itinerary'] as List)
                ListTile(
                  title: Text('${item['activity']}'),
                  subtitle: Text(
                    '${item['minutes']} min · estimated ₹${item['estimated_cost']} for two',
                  ),
                ),
              Text(
                'Calculated total: ₹${result['budget']['total']} / ₹${result['budget']['limit']} · ${result['budget']['total_minutes']} / ${result['budget']['minutes_limit']} minutes',
              ),
            ],
            for (final suggestion in (result['suggestions'] as List? ?? []))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText('$suggestion'),
                      TextButton(
                        onPressed: () => Navigator.pop(context, '$suggestion'),
                        child: const Text('Use this text'),
                      ),
                    ],
                  ),
                ),
              ),
            if (draft != null &&
                (draft['kind'] != 'none' ||
                    (_task == 'date' && result['budget'] != null))) ...[
              const SizedBox(height: 12),
              Text(
                _task == 'date'
                    ? 'Draft date plan'
                    : 'Draft ${draft['kind']}: ${draft['title']}',
              ),
              Text('${draft['notes']}'),
              OutlinedButton(
                onPressed: _busy || _saved ? null : _saveDraft,
                child: Text(_saved ? 'Saved' : 'Review, edit & save draft'),
              ),
            ],
            Text(
              '${result['coverage'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final source in (result['sources'] as List? ?? []))
              ListTile(
                leading: const Icon(Icons.format_quote),
                title: Text(
                  '${source['text']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${source['at']}'),
                onTap: () => _source(Map<String, dynamic>.from(source as Map)),
              ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Date ideas use estimates; verify venue details. Recall uses keyword matches and limited context, so it can miss earlier conversations.',
          ),
        ],
      ),
    );
  }
}

class AiPlanEditor extends StatefulWidget {
  const AiPlanEditor({super.key, required this.draft});
  final Map<String, dynamic> draft;
  @override
  State<AiPlanEditor> createState() => _AiPlanEditorState();
}

class _AiPlanEditorState extends State<AiPlanEditor> {
  late final _title = TextEditingController(text: '${widget.draft['title']}'),
      _place = TextEditingController(text: '${widget.draft['place']}'),
      _notes = TextEditingController(text: '${widget.draft['notes']}');
  late DateTime? _date = DateTime.tryParse(
    '${widget.draft['starts_at']}',
  )?.toLocal();
  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.draft['kind'] == 'todo';
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review your ${todo ? 'task' : 'date'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            if (!todo) ...[
              TextField(
                controller: _place,
                maxLength: 250,
                decoration: const InputDecoration(labelText: 'Place'),
              ),
              TextField(
                controller: _notes,
                maxLength: 4000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              ListTile(
                title: Text(
                  _date == null ? 'Choose a date and time' : _date.toString(),
                ),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final v = await pickDateTime(
                    context,
                    initial: _date ?? DateTime.now(),
                  );
                  if (v != null && mounted) setState(() => _date = v);
                },
              ),
            ],
            FilledButton(
              onPressed: _title.text.trim().isEmpty || (!todo && _date == null)
                  ? null
                  : () => Navigator.pop(
                      context,
                      todo
                          ? {
                              'list_kind': 'todo',
                              'title': _title.text.trim(),
                              'completed': false,
                            }
                          : {
                              'title': _title.text.trim(),
                              'starts_at': _date!.toUtc().toIso8601String(),
                              'place': _place.text.trim(),
                              'notes': _notes.text.trim(),
                            },
                    ),
              child: const Text('Save to Us'),
            ),
          ],
        ),
      ),
    );
  }
}
