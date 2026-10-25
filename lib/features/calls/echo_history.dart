import 'package:flutter/material.dart';
import '../../core/session.dart';

class EchoHistory extends StatefulWidget {
  const EchoHistory({super.key, required this.session});
  final UsSession session;
  @override
  State<EchoHistory> createState() => _EchoHistoryState();
}

class _EchoHistoryState extends State<EchoHistory> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  late final _uid = widget.session.userId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _current => mounted && _uid == widget.session.userId;
  Future<void> _load() async {
    try {
      final rows = await widget.session.client
          .from('echo_sessions')
          .select()
          .eq('callee_id', _uid!)
          .order('updated_at', ascending: false)
          .limit(20);
      if (_current)
        setState(() {
          _rows = List<Map<String, dynamic>>.from(rows);
          _error = null;
        });
    } catch (_) {
      if (_current)
        setState(() => _error = 'Could not load ECHO messages. Please retry.');
    }
  }

  Future<void> _erase(String id) async {
    try {
      await widget.session.client
          .from('echo_sessions')
          .delete()
          .eq('call_id', id)
          .eq('state', 'ended');
      if (_current) await _load();
    } catch (_) {
      if (_current)
        setState(() => _error = 'Could not erase the record. Please retry.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(
      title: const Text('ECHO messages'),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: _rows == null && _error == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Caller messages are quoted verbatim in the recap. “Important” flags are keyword matches, not an urgency assessment. Records follow the existing one-day call retention policy.',
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_rows?.isEmpty == true)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No ECHO records yet. Enable saving before a call to keep its messages.',
                  ),
                ),
              for (final row in _rows ?? <Map<String, dynamic>>[])
                Card(
                  child: ExpansionTile(
                    title: Text(
                      DateTime.tryParse(
                            '${row['updated_at']}',
                          )?.toLocal().toString().split('.').first ??
                          'ECHO call',
                    ),
                    subtitle: Text(
                      row['state'] == 'ended'
                          ? 'Call ended'
                          : 'Call in progress',
                    ),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      if ('${row['summary'] ?? ''}'.isNotEmpty)
                        ListTile(
                          title: const Text('Caller message recap'),
                          subtitle: Text('${row['summary']}'),
                        ),
                      if ('${row['important'] ?? ''}'.isNotEmpty)
                        ListTile(
                          title: const Text('Flagged caller messages'),
                          subtitle: Text('${row['important']}'),
                        ),
                      for (final line
                          in (row['transcript'] as List? ?? const [])
                              .whereType<Map>())
                        ListTile(
                          title: Text('${line['text'] ?? ''}'),
                          subtitle: Text(
                            line['role'] == 'caller' ? 'Caller' : 'ECHO · AI',
                          ),
                        ),
                      if (row['state'] == 'ended')
                        TextButton.icon(
                          onPressed: () => _erase(row['call_id'] as String),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Erase this call record'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
  );
}
