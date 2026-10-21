import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/space.dart';

/// Live only. Polling is intentional: consent and deletion changes are not cached.
class SharedAiAnswers extends StatefulWidget {
  const SharedAiAnswers({super.key, required this.space});
  final UsSpace space;
  @override
  State<SharedAiAnswers> createState() => _SharedAiAnswersState();
}

class _SharedAiAnswersState extends State<SharedAiAnswers> {
  List<Map<String, dynamic>> _answers = [];
  Timer? _timer;
  String? _uid, _cid;
  bool _fetching = false;
  @override
  void initState() {
    super.initState();
    _uid = widget.space.session.userId;
    _cid = widget.space.session.coupleId;
    widget.space.session.addListener(_changed);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  void _changed() {
    if (_uid != widget.space.session.userId ||
        _cid != widget.space.session.coupleId) {
      _uid = widget.space.session.userId;
      _cid = widget.space.session.coupleId;
      if (mounted) setState(() => _answers = []);
      _load();
    }
  }

  Future<void> _load() async {
    if (_fetching || _cid == null) return;
    _fetching = true;
    final uid = _uid, cid = _cid;
    try {
      final data = await widget.space.session.client
          .from('ai_answers')
          .select('prompt,answer,created_at')
          .eq('couple_id', cid!)
          .order('created_at', ascending: false)
          .limit(5);
      if (mounted && uid == _uid && cid == _cid)
        setState(() => _answers = List<Map<String, dynamic>>.from(data));
    } catch (_) {
      if (mounted) setState(() => _answers = []);
    } finally {
      _fetching = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.space.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _answers.isEmpty
      ? const SizedBox.shrink()
      : Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ExpansionTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Ask Us · shared AI answers'),
            subtitle: Text(
              '${_answers.first['answer']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final answer in _answers)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'You asked: ${answer['prompt']}',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            SelectableText('${answer['answer']}'),
                            Text(
                              'AI generated · ${answer['created_at']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
}
