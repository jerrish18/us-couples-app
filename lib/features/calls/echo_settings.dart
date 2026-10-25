import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/session.dart';
import 'echo_history.dart';
import '../echo/phone_runtime.dart';
import '../echo/phone_models.dart';

/// Per-partner settings. Authentication and bridge secrets stay on the Mac.
class EchoSettings extends StatefulWidget {
  const EchoSettings({super.key, required this.session});
  final UsSession session;
  @override
  State<EchoSettings> createState() => _EchoSettingsState();
}

class _EchoSettingsState extends State<EchoSettings> {
  final phone = PhoneAiRuntime.instance;
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
      await phone.initialize();
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
      if (phone.preferPhone &&
          _prefs['enabled'] == true &&
          (!phone.ready ||
              phone.language != _prefs['language'] ||
              phone.voice != _prefs['voice']))
        throw StateError(
          'Download and prepare the selected phone models and language first.',
        );
      await widget.session.client.from('echo_preferences').upsert({
        ..._prefs,
        'host': phone.host,
        'couple_id': _cid,
        'user_id': _uid,
        'greeting': _greeting.text.trim(),
      });
      phone.preferencesChanged?.call();
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

  Future<void> _task(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (_current)
        setState(
          () => _error = e is StateError
              ? '${e.message}'
              : e is PlatformException
              ? (e.message ??
                    'Phone AI is unavailable. Check offline voices and retry.')
              : 'Phone setup did not finish. Check your connection, RAM and storage, then retry.',
        );
    } finally {
      if (_current) setState(() => _saving = false);
    }
  }

  List<Widget> _phoneControls(BuildContext context) {
    final ram = (phone.capabilities['ram'] as num? ?? 0) / 1073741824;
    final ready =
        phone.ready &&
        phone.language == _prefs['language'] &&
        phone.voice == _prefs['voice'];
    final pack = phone.plus ? phoneLlmPlus : phoneLlmLite;
    final mb =
        (pack.bytes + phoneWhisper.fold<int>(0, (n, f) => n + f.bytes)) /
        1000000;
    return [
      Text(
        '${phone.capabilities['model'] ?? 'This Android phone'}${ram > 0 ? ' · ${ram.toStringAsFixed(1)} GB RAM' : ''}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'The AI and speech models run locally after downloading. No Mac or AI subscription is required. Calls still need internet.',
      ),
      if (!phone.supported)
        const Text(
          'Phone AI needs a supported 64-bit Android 9+ device. Normal calls stay available.',
        ),
      const SizedBox(height: 12),
      DropdownButtonFormField<bool>(
        initialValue: phone.plus,
        decoration: const InputDecoration(labelText: 'Phone model pack'),
        items: [
          const DropdownMenuItem(
            value: false,
            child: Text('Light · for 6 GB and 8 GB phones'),
          ),
          DropdownMenuItem(
            value: true,
            enabled: ram >= 7,
            child: const Text('Larger · 8 GB RAM or more'),
          ),
        ],
        onChanged: _saving || phone.preparing
            ? null
            : (value) => _task(() => phone.setPlus(value!)),
      ),
      const SizedBox(height: 8),
      Text(
        'Download: about ${mb.round()} MB, plus Android offline voice data. Use Wi-Fi for the download. Light is the initial choice for both phones; larger models may improve answers but use more RAM.',
      ),
      const SizedBox(height: 8),
      Text(
        phone.preparing
            ? 'Preparing phone AI…'
            : phone.models.busy
            ? phone.models.status
            : ready
            ? 'Ready on this phone'
            : phone.status,
      ),
      if (phone.models.busy)
        LinearProgressIndicator(value: phone.models.progress),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: phone.models.busy
                ? phone.models.pause
                : _saving || !phone.supported
                ? null
                : () => _task(() async {
                    await phone.stopReady();
                    await phone.unload();
                    final cap = Map<String, dynamic>.from(
                      await PhoneAiRuntime.native.invokeMethod('capabilities')
                          as Map,
                    );
                    var needed = 0;
                    for (final f in phone.models.files(phone.plus)) {
                      final path = await phone.models.path(f);
                      final done = File(path),
                          marker = File('$path.verified-${f.hash}'),
                          part = File('$path.part');
                      if (await done.exists() &&
                          await done.length() == f.bytes &&
                          await marker.exists())
                        continue;
                      final existing = await part.exists()
                          ? await part.length()
                          : 0;
                      needed += f.bytes - (existing > f.bytes ? 0 : existing);
                    }
                    if ((cap['freeStorage'] as num? ?? 0) < needed + 250000000)
                      throw StateError(
                        'Free up at least ${((needed + 250000000) / 1000000).ceil()} MB of additional storage, then resume.',
                      );
                    await phone.models.install(phone.plus);
                  }),
            icon: Icon(phone.models.busy ? Icons.pause : Icons.download),
            label: Text(
              phone.models.busy ? 'Pause download' : 'Download / resume models',
            ),
          ),
          OutlinedButton(
            onPressed: _saving || phone.preparing || !phone.supported
                ? null
                : () => _task(
                    () => phone.prepare(
                      '${_prefs['language']}',
                      selectedVoice: '${_prefs['voice']}',
                    ),
                  ),
            child: const Text('Prepare and test phone AI'),
          ),
          TextButton(
            onPressed: _saving || !ready
                ? null
                : () => _task(() async {
                    await PhoneAiRuntime.native.invokeMethod('previewVoice');
                  }),
            child: const Text('Listen to offline voice'),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () => _task(() async {
                    await PhoneAiRuntime.native.invokeMethod('installVoice');
                  }),
            child: const Text('Install offline voice data'),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () => _task(() async {
                    await phone.stopReady();
                    await phone.unload();
                    await phone.models.remove(phone.plus);
                  }),
            child: const Text('Remove downloaded pack'),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Keep ECHO ready in the background'),
        subtitle: const Text(
          'Shows a persistent notification and uses more battery. Start this while Us is open. Android can still stop the app; a force-stopped or offline phone cannot answer.',
        ),
        value: phone.readyService,
        onChanged: _saving || (!ready && !phone.readyService)
            ? null
            : (value) =>
                  _task(() => value ? phone.startReady() : phone.stopReady()),
      ),
      const Text(
        'Tamil and Tanglish accuracy and voice quality need review. On smaller phones, replies may take longer. You can take over without restarting the call.',
      ),
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([phone, phone.models]),
    builder: (context, _) => _page(context),
  );
  Widget _page(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(title: const Text('ECHO receptionist')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              DropdownButtonFormField<String>(
                initialValue: phone.host,
                decoration: const InputDecoration(labelText: 'Run ECHO on'),
                items: const [
                  DropdownMenuItem(
                    value: 'phone',
                    child: Text('This phone · no Mac needed'),
                  ),
                  DropdownMenuItem(
                    value: 'bridge',
                    child: Text('Optional Mac bridge'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) async {
                        await phone.setHost(value!);
                        if (mounted) setState(() {});
                      },
              ),
              const SizedBox(height: 12),
              if (phone.preferPhone)
                ..._phoneControls(context)
              else ...[
                Text(
                  _online
                      ? 'Your Mac bridge is ready'
                      : 'Your selected Mac bridge is offline',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'This optional mode needs your Mac awake and running the ECHO bridge. Select This phone to answer without a Mac.',
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check Mac bridge'),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'ECHO answers Us voice calls as AI. Your caller always hears an AI disclosure. Video calls keep their normal Answer button.',
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
