import '../../core/design.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';

class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});
  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  final _name = TextEditingController(text: 'Us');
  final _code = TextEditingController();
  bool _busy = false;
  DateTime? _since;
  String? _error;
  Future<void> _action(bool create) async {
    if (create && _name.text.trim().isEmpty) return;
    if (!create && !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Enter the six-character invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider);
      if (create) {
        await session.create(_name.text, _since);
      } else {
        await session.join(_code.text);
      }
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : 'Could not pair. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: GlassAppBar(
      title: const Text('Your space'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => ref.read(sessionProvider).client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.favorite_outline_rounded, size: 60),
        const SizedBox(height: 20),
        Text(
          'It starts with two.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        const Text(
          'Create your space and invite your person. Once they join, your space is locked to both of you.',
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _name,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Name of your space'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.favorite),
          title: const Text('Together since'),
          subtitle: Text(
            _since?.toIso8601String().substring(0, 10) ?? 'Choose your date',
          ),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _since ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (date != null && mounted) setState(() => _since = date);
          },
        ),
        ExpressiveButton(
          onPressed: _busy ? null : () => _action(true),
          child: const Text('Create our space'),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 26),
          child: Divider(),
        ),
        Text('Have an invite?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
          ],
          decoration: const InputDecoration(labelText: 'Six-character code'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _action(false),
          child: const Text('Join my person'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      ],
    ),
  );
}
