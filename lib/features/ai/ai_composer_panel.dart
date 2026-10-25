import 'package:flutter/material.dart';

import '../../core/space.dart';
import '../../core/ui.dart';
import '../expenses/expense_groups.dart';
import '../expenses/expenses_screen.dart';
import 'ai_draft.dart';
import 'ai_screen.dart' show AiPlanEditor;
import 'ai_service.dart';

/// Lives above the real message field. Only the normal chat Send button sends.
class AiComposerPanel extends StatefulWidget {
  const AiComposerPanel({
    super.key,
    required this.space,
    required this.controller,
    required this.onClose,
    required this.onInserted,
    this.initialTask = 'rewrite',
    this.messageId,
    this.service,
  });
  final UsSpace space;
  final TextEditingController controller;
  final VoidCallback onClose, onInserted;
  final String initialTask;
  final String? messageId;
  final UsAi? service;

  @override
  State<AiComposerPanel> createState() => _AiComposerPanelState();
}

class _AiComposerPanelState extends State<AiComposerPanel> {
  late final _ai = widget.service ?? UsAi(widget.space);
  late String _task = widget.initialTask;
  String _language = 'English';
  final _budget = TextEditingController(text: '1500');
  final _minutes = TextEditingController(text: '180');
  late final Set<String> _ids = {
    if (widget.messageId != null) widget.messageId!,
  };
  DateTime _from = DateTime.now().subtract(const Duration(days: 7)),
      _until = DateTime.now();
  bool _loading = true,
      _busy = false,
      _enabled = false,
      _history = false,
      _partner = false,
      _settings = false,
      _saved = false,
      _inserted = false;
  int _revision = 0, _request = 0, _choice = 0;
  String _lastText = '';
  String? _error;
  Map<String, dynamic>? _result;
  TextEditingValue? _original;
  final _resultKey = GlobalKey();
  String? _uid, _cid;
  bool get _current =>
      mounted &&
      _uid == widget.space.session.userId &&
      _cid == widget.space.session.coupleId;
  bool get _needsHistory => aiHistoryTasks.contains(_task);
  bool get _allowed => _enabled && (!_needsHistory || (_history && _partner));

  @override
  void initState() {
    super.initState();
    _uid = widget.space.session.userId;
    _cid = widget.space.session.coupleId;
    _lastText = widget.controller.text;
    widget.controller.addListener(_edited);
    widget.space.session.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (!_current) widget.onClose();
  }

  void _edited() {
    if (_lastText == widget.controller.text) return;
    _lastText = widget.controller.text;
    _revision++;
  }

  @override
  void dispose() {
    _request++;
    widget.controller.removeListener(_edited);
    widget.space.session.removeListener(_accountChanged);
    _budget.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _ai.preferences();
      if (!_current) return;
      final own = rows.where((r) => r['user_id'] == _uid).firstOrNull;
      setState(() {
        _enabled = own?['enabled'] == true;
        _history = own?['share_history'] == true;
        _partner = rows.any(
          (r) =>
              r['user_id'] == widget.space.session.partnerId &&
              r['enabled'] == true &&
              r['share_history'] == true,
        );
        if (!_enabled) _settings = true;
      });
    } catch (_) {
      if (_current)
        setState(() {
          _enabled = false;
          _history = false;
          _partner = false;
          _settings = true;
          _error =
              'Could not load AI permissions. Check your connection and refresh.';
        });
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<void> _consent(bool enabled, bool history) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ai.consent(enabled: enabled, history: history);
      if (!_current) return;
      setState(() {
        _enabled = enabled;
        _history = enabled && history;
        _result = null;
      });
    } catch (_) {
      if (_current)
        setState(
          () => _error = 'Could not update AI permissions. Please retry.',
        );
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  String get _prompt {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) return text;
    return switch (_task) {
      'reply' => 'Suggest three replies: sweet, playful and reassuring.',
      'summary' =>
        'Summarise our plans, decisions and things still to discuss.',
      'plans' =>
        'Prepare a draft date, task or expense from the selected messages.',
      _ => '',
    };
  }

  Future<void> _generate() async {
    if (_busy || _loading || !_allowed) return;
    final prompt = _prompt;
    final problem = aiInputError(
      task: _task,
      prompt: prompt,
      ids: _ids.toList(),
      from: _from,
      until: _until,
      budget: double.tryParse(_budget.text),
      minutes: int.tryParse(_minutes.text),
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final revision = _revision,
        original = widget.controller.value,
        request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _saved = false;
      _inserted = false;
    });
    try {
      final data = await _ai.ask(
        task: _task,
        prompt: prompt,
        language: _language,
        ids: ['reply', 'plans'].contains(_task) ? _ids.toList() : [],
        from: _from,
        until: _until,
        budget: double.tryParse(_budget.text),
        minutes: int.tryParse(_minutes.text),
        publish: false,
      );
      if (!_current || request != _request) return;
      final text = aiDraftText(data);
      if (text.isEmpty)
        throw StateError('AI returned no usable text. Your draft is safe.');
      setState(() {
        _result = data;
        _choice = 0;
        _original = original;
      });
      // A delayed response must never erase something typed or sent meanwhile.
      if (revision == _revision) _insert(text);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _resultKey.currentContext;
        if (_current && target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
          );
        }
      });
    } catch (e) {
      if (_current && request == _request)
        setState(
          () => _error = e is StateError
              ? '${e.message}'
              : 'Could not reach AI. Your draft is safe. Please try later.',
        );
    } finally {
      if (_current && request == _request) setState(() => _busy = false);
    }
  }

  void _insert(String text) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _inserted = true);
    widget.onInserted();
  }

  Future<void> _chooseMessages() async {
    final hidden = (widget.space.rows['message_states'] ?? [])
        .where((r) => r['user_id'] == _uid && r['hidden'] == true)
        .map((r) => r['message_id'])
        .toSet();
    final rows =
        widget.space.items
            .where(
              (m) =>
                  m['deleted_at'] == null &&
                  m['_pending'] != true &&
                  m['media_path'] == null &&
                  m['media_kind'] == null &&
                  !hidden.contains(m['id']) &&
                  '${m['body'] ?? ''}'.trim().isNotEmpty,
            )
            .toList()
          ..sort(
            (a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'),
          );
    final available = rows.map((m) => m['id']).toSet();
    final selected = _ids.where(available.contains).toSet();
    final value = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Select saved text · ${selected.length}/30'),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No saved text messages yet. Pending messages and attachments are excluded.',
                  ),
                ),
              Expanded(
                child: ListView(
                  children: [
                    for (final m in rows.take(150))
                      CheckboxListTile(
                        key: ValueKey('ai-context-${m['id']}'),
                        value: selected.contains(m['id']),
                        selected: selected.contains(m['id']),
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        activeColor: Theme.of(context).colorScheme.primary,
                        checkColor: Theme.of(context).colorScheme.onPrimary,
                        tileColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        title: Text(
                          '${m['body']}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          m['sender_id'] == _uid ? 'You' : 'Your person',
                        ),
                        onChanged:
                            selected.length >= 30 && !selected.contains(m['id'])
                            ? null
                            : (v) => update(() {
                                if (v == true) {
                                  selected.add(m['id'] as String);
                                } else {
                                  selected.remove(m['id']);
                                }
                              }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheet, selected),
                  child: const Text('Use selected messages'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (_current && value != null)
      setState(() {
        _ids
          ..clear()
          ..addAll(value);
        _result = null;
      });
  }

  Future<void> _save() async {
    if (_result == null || _busy || _saved) return;
    final d = Map<String, dynamic>.from(
      _result!['draft'] as Map? ?? {'kind': 'none'},
    );
    if (_task == 'date') {
      d['kind'] = 'date';
      d['starts_at'] = '';
      if ('${d['title'] ?? ''}'.trim().isEmpty) d['title'] = 'Our date';
      d['notes'] = aiDraftText(_result!);
    }
    final expense = d['kind'] == 'expense';
    // Lock throughout review and save; repeated taps must not open duplicate editors.
    setState(() => _busy = true);
    try {
      final value = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => expense
            ? ExpenseEditor(
                initial: {
                  'title': d['title'],
                  'amount': d['amount'],
                  'category': expenseCategories.contains(d['category'])
                      ? d['category']
                      : 'Other',
                  'outing': d['outing'],
                  'notes': d['notes'],
                  'spent_on': d['spent_on'],
                },
              )
            : AiPlanEditor(draft: d),
      );
      if (!_current || value == null) return;
      await widget.space.add(
        expense
            ? 'expenses'
            : d['kind'] == 'todo'
            ? 'list_items'
            : 'dates',
        value,
      );
      if (_current) setState(() => _saved = true);
    } catch (_) {
      if (_current)
        setState(
          () => _error =
              'Could not save. Your message draft is still here. Please retry.',
        );
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _source(Map source) async {
    try {
      final row = await widget.space.session.client
          .from('messages')
          .select('body,created_at')
          .eq('couple_id', _cid!)
          .eq('id', source['id'] as String)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (!_current) return;
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
      if (_current)
        setState(() => _error = 'Could not open the source message.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final result = _result;
    final suggestions = (result?['suggestions'] as List? ?? [])
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final draft = result?['draft'] as Map?;
    return Material(
      key: const Key('ai-composer-panel'),
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Us AI',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'AI privacy and settings',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _settings = !_settings),
                  icon: const Icon(Icons.tune, size: 20),
                ),
                IconButton(
                  tooltip: 'Close AI tools',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            if (result == null) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in aiTasks.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('ai-task-${entry.key}'),
                          label: Text(entry.value),
                          selected: _task == entry.key,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                  _task = entry.key;
                                  _result = null;
                                  _error = null;
                                }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(switch (_task) {
                'reply' =>
                  'Choose messages to reply to. Add a direction below, or leave it empty.',
                'rewrite' =>
                  'Write your message below. Us will suggest a few ways to say it.',
                'together' =>
                  'Ask a question below. The answer becomes a draft for you to review and send.',
                'summary' =>
                  'Catch up on your chosen dates. Add a focus below if you like.',
                'plans' =>
                  'Choose messages to turn into a plan. Add a direction below if you like.',
                'search' =>
                  'Type words or a phrase below to find in your saved conversations.',
                'date' =>
                  'Describe your date below, with your area and preferences.',
                'expense' =>
                  'Describe the expense below, including amount and date.',
                _ =>
                  'Describe your memory below. Only your words are used, not the photo.',
              }, style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: _language,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final l in ['English', 'Tamil', 'Tanglish'])
                        DropdownMenuItem(value: l, child: Text(l)),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _language = v!),
                  ),
                  if (['reply', 'plans'].contains(_task))
                    TextButton.icon(
                      onPressed: _busy ? null : _chooseMessages,
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: Text('${_ids.length} messages selected'),
                    ),
                ],
              ),
              if (_language != 'English')
                const Text(
                  'Tamil and Tanglish are in beta. Review the wording.',
                ),
              if (_task == 'date')
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('ai-budget'),
                        controller: _budget,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Budget for two (₹)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _minutes,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutes incl. travel',
                        ),
                      ),
                    ),
                  ],
                ),
              if (_task == 'summary')
                Wrap(
                  spacing: 8,
                  children: [
                    for (final start in [true, false])
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          '${start ? 'From' : 'Until'} ${displayDate((start ? _from : _until).toIso8601String())}',
                        ),
                        onPressed: _busy
                            ? null
                            : () async {
                                final date = await pickDateTime(
                                  context,
                                  initial: start ? _from : _until,
                                );
                                if (_current && date != null)
                                  setState(() {
                                    if (start) {
                                      _from = date;
                                    } else {
                                      _until = date;
                                    }
                                  });
                              },
                      ),
                  ],
                ),
            ],
            if (_loading) const LinearProgressIndicator(),
            if (_settings) ...[
              const Text(
                'Groq processes your request and indicated text context. Photos, voice, location and cycle records are excluded. Nothing is sent or saved until you choose. 20 requests per couple daily (UTC), at least 30 seconds apart. No paid fallback.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable my AI assistance'),
                value: _enabled,
                onChanged: _busy || _loading
                    ? null
                    : (v) => _consent(v, _history),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow shared chat context'),
                value: _history,
                subtitle: Text(
                  _partner
                      ? 'Your partner has opted in too.'
                      : 'Your partner must opt in on their phone.',
                ),
                onChanged: _busy || _loading || !_enabled
                    ? null
                    : (v) => _consent(_enabled, v),
              ),
              TextButton.icon(
                onPressed: _busy || _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh AI permissions'),
              ),
            ],
            if (!_loading && !_allowed)
              Text(
                !_enabled
                    ? 'Enable AI in privacy settings to get started.'
                    : 'Both partners must allow chat context for this action. Rewrites, dates, expenses and captions use only your text.',
              ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
              ),
            if (result == null)
              FilledButton.icon(
                key: const Key('ai-generate'),
                onPressed: _busy || _loading || !_allowed ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_busy ? 'Working on it…' : 'Draft in message box'),
              ),
            if (result != null) ...[
              Semantics(
                key: _resultKey,
                liveRegion: true,
                child: Text(
                  _inserted
                      ? 'Draft ready · edit below, then send.'
                      : 'Your message changed while AI was working. Your new text is safe.',
                ),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!_inserted)
                    TextButton(
                      onPressed: () {
                        _original = widget.controller.value;
                        _insert(aiDraftText(result));
                      },
                      child: const Text('Use result'),
                    ),
                  for (var i = 0; i < suggestions.length; i++)
                    ChoiceChip(
                      label: Text('${i + 1}'),
                      tooltip: 'Option ${i + 1}',
                      selected: _inserted && _choice == i,
                      onSelected: _busy
                          ? null
                          : (_) {
                              if (!_inserted)
                                _original = widget.controller.value;
                              setState(() => _choice = i);
                              _insert(aiDraftText(result, suggestion: i));
                            },
                    ),
                  if (_inserted && _original != null)
                    TextButton.icon(
                      key: const Key('ai-undo'),
                      onPressed: () {
                        widget.controller.value = _original!;
                        setState(() {
                          _result = null;
                          _inserted = false;
                          _original = null;
                        });
                        widget.onInserted();
                      },
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Undo'),
                    ),
                  if (draft != null &&
                      (draft['kind'] != 'none' ||
                          (_task == 'date' && result['budget'] != null)))
                    TextButton.icon(
                      onPressed: _busy || _saved ? null : _save,
                      icon: const Icon(Icons.event_note, size: 18),
                      label: Text(
                        _saved ? 'Saved to Us' : 'Review & save to Us',
                      ),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _result = null;
                        _error = null;
                      }),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('More AI tools'),
              ),
              if (result['coverage'] != null ||
                  (result['sources'] as List? ?? []).isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'Context used',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    Text('${result['coverage'] ?? ''}'),
                    for (final source
                        in (result['sources'] as List? ?? []).whereType<Map>())
                      ListTile(
                        title: Text(
                          '${source['text']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: const Icon(Icons.format_quote),
                        onTap: () => _source(source),
                      ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
