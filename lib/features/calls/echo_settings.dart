import 'package:flutter/material.dart';
import '../../core/session.dart';
import 'echo_history.dart';

/// Per-partner settings. Authentication and bridge secrets stay on the Mac.
class EchoSettings extends StatefulWidget {
  const EchoSettings({super.key, required this.session});
  final UsSession session;
  @override
  State<EchoSettings> createState() => _EchoSettingsState();
}

class _EchoSettingsState extends State<EchoSettings> {
  final _greeting = TextEditingController();
  Map<String, dynamic> _prefs = {
    'enabled': false,
    'rule': 'manual',
    'delay_seconds': 20,
    'language': 'English',
    'voice': 'default',
    'timezone': 'Asia/Kolkata',
    'start_minute': 0,
    'end_minute': 0,
    'retain_transcript': false,
  };
  late final String? _uid = widget.session.userId,
      _cid = widget.session.coupleId;
  bool _loading = true, _saving = false, _online = false;
  String? _error;
  bool get _current =>
      mounted &&
      widget.session.userId == _uid &&
      widget.session.coupleId == _cid;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _greeting.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.session.client
          .from('echo_preferences')
          .select()
          .eq('couple_id', _cid!)
          .eq('user_id', _uid!);
      final device = await widget.session.client
          .from('echo_devices')
          .select()
          .eq('user_id', _uid)
          .maybeSingle();
      if (!_current) return;
      final beat = DateTime.tryParse('${device?['heartbeat']}');
      setState(() {
        if (rows.isNotEmpty) _prefs = Map<String, dynamic>.from(rows.first);
        _greeting.text = '${_prefs['greeting'] ?? ''}';
        _online =
            device?['ready'] == true &&
            beat != null &&
            DateTime.now().toUtc().difference(beat.toUtc()).inSeconds < 20;
      });
    } catch (_) {
      if (_current)
        setState(
          () => _error =
              'Could not load ECHO. Check your connection and that the ECHO database upgrade is installed.',
        );
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.client.from('echo_preferences').upsert({
        ..._prefs,
        'couple_id': _cid,
        'user_id': _uid,
        'greeting': _greeting.text.trim(),
      });
      if (_current)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ECHO settings saved for your account')),
        );
    } catch (_) {
      if (_current)
        setState(() => _error = 'Could not save ECHO settings. Please retry.');
    } finally {
      if (_current) setState(() => _saving = false);
    }
  }

  Future<void> _time(String field) async {
    final minute = _prefs[field] as int;
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (_current && value != null)
      setState(() => _prefs[field] = value.hour * 60 + value.minute);
  }

  String _display(String field) {
    final value = _prefs[field] as int;
    return TimeOfDay(hour: value ~/ 60, minute: value % 60).format(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(title: const Text('ECHO receptionist')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _online
                    ? 'Your voice bridge is ready'
                    : 'Your voice bridge is offline',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'ECHO answers Us voice calls as AI. Your caller always hears an AI disclosure. Your Mac must be awake, online and running the bridge. Video calls keep their normal Answer button.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Start the free bridge from services/echo_bridge in the project. Authorize it with its own Us sign-in session on your trusted Mac. No API key or app session needs to be copied from this phone.',
              ),
              TextButton.icon(
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Check bridge status'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EchoHistory(session: widget.session),
                  ),
                ),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Review ECHO messages'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow ECHO to answer for me'),
                value: _prefs['enabled'] == true,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _prefs['enabled'] = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: _prefs['rule'] as String,
                decoration: const InputDecoration(labelText: 'Answering rule'),
                items: const [
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text('Only when I tap AI Answer'),
                  ),
                  DropdownMenuItem(
                    value: 'always',
                    child: Text('Automatically after a delay'),
                  ),
                  DropdownMenuItem(
                    value: 'schedule',
                    child: Text('During my chosen hours'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _prefs['rule'] = v!),
              ),
              if (_prefs['rule'] != 'manual') ...[
                const SizedBox(height: 12),
                Text('Answer after ${_prefs['delay_seconds']} seconds'),
                Slider(
                  value: (_prefs['delay_seconds'] as num).toDouble(),
                  min: 0,
                  max: 40,
                  divisions: 8,
                  label: '${_prefs['delay_seconds']} seconds',
                  onChanged: _saving
                      ? null
                      : (v) =>
                            setState(() => _prefs['delay_seconds'] = v.round()),
                ),
              ],
              if (_prefs['rule'] == 'schedule') ...[
                Text(
                  'Time zone: ${_prefs['timezone']}. Matching start and end means all day. Overnight ranges are supported.',
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => _time('start_minute'),
                      child: Text('From ${_display('start_minute')}'),
                    ),
                    TextButton(
                      onPressed: _saving ? null : () => _time('end_minute'),
                      child: Text('Until ${_display('end_minute')}'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _prefs['language'] as String,
                decoration: const InputDecoration(
                  labelText: 'Conversation language',
                ),
                items: [
                  for (final l in ['English', 'Tamil', 'Tanglish'])
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _prefs['language'] = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _prefs['voice'] as String,
                decoration: const InputDecoration(
                  labelText: 'Offline voice style',
                ),
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('Default')),
                  DropdownMenuItem(value: 'soft', child: Text('Gentle')),
                  DropdownMenuItem(value: 'bright', child: Text('Lively')),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _prefs['voice'] = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _greeting,
                enabled: !_saving,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Personal greeting after AI disclosure',
                  hintText: 'Use Tamil script for Tamil speech.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save transcripts and messages'),
                subtitle: const Text(
                  'Enables live transcripts and a verbatim message recap for both call participants. Calls and transcripts expire under the existing one-day retention policy. You can erase them earlier. Audio recordings are not stored.',
                ),
                value: _prefs['retain_transcript'] == true,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _prefs['retain_transcript'] = v),
              ),
              const Text(
                'Free offline speech can sound robotic. Tamil and Tanglish transcription may be inaccurate; review important messages. If inference fails, ECHO keeps the call connected and takes a message when transcription and saving are available.',
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save ECHO settings'),
              ),
            ],
          ),
  );
}
