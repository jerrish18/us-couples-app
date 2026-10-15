import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/ui.dart';

class MemoryDraft {
  const MemoryDraft({
    required this.caption,
    required this.date,
    this.collectionId,
  });
  final String caption;
  final DateTime date;
  final String? collectionId;
}

class MemoryComposer extends StatefulWidget {
  const MemoryComposer({
    super.key,
    required this.file,
    required this.collections,
    required this.onCreateCollection,
    required this.onSave,
    this.initialCollection,
  });
  final String file;
  final List<Map<String, dynamic>> collections;
  final String? initialCollection;
  final Future<String> Function(String title) onCreateCollection;
  final Future<void> Function(MemoryDraft draft) onSave;
  @override
  State<MemoryComposer> createState() => _MemoryComposerState();
}

class _MemoryComposerState extends State<MemoryComposer> {
  final _caption = TextEditingController();
  late List<Map<String, dynamic>> _collections;
  String? _collection, _error;
  DateTime _date = DateTime.now();
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _collections = List.of(widget.collections);
    _collection = _collections.any((c) => c['id'] == widget.initialCollection)
        ? widget.initialCollection
        : null;
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = await askText(
      context,
      'New collection',
      hint: 'Date nights, our travels…',
      max: 100,
    );
    if (title == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.onCreateCollection(title);
      if (mounted)
        setState(() {
          _collections.add({'id': id, 'title': title});
          _collection = id;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not create the collection. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        MemoryDraft(
          caption: _caption.text.trim(),
          date: _date,
          collectionId: _collection,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Your photo is still here. Try saving again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Keep a memory'),
        leading: IconButton(
          tooltip: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const PageHeading(
              'A moment, kept.',
              'Choose where this part of your story belongs.',
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.file(
                File(widget.file),
                height: 210,
                width: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 900,
                errorBuilder: (_, e, st) => const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.photo_outlined, size: 40)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              key: const Key('memory-caption'),
              controller: _caption,
              enabled: !_busy,
              maxLength: 4000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Caption',
                hintText: 'What made this moment yours?',
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today_rounded),
                title: const Text('Memory date'),
                subtitle: Text(displayDate(_date.toIso8601String())),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () async {
                        final date = await pickDateTime(
                          context,
                          initial: _date,
                          time: false,
                        );
                        if (date != null && mounted)
                          setState(() => _date = date);
                      },
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Save to collection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Pick an existing collection, make a new one, or keep it without a collection.',
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('No collection'),
                    value: 'none',
                    groupValue: _collection ?? 'none',
                    onChanged: _busy
                        ? null
                        : (_) => setState(() => _collection = null),
                  ),
                  for (final c in _collections)
                    RadioListTile<String>(
                      title: Text(c['title'] as String),
                      value: c['id'] as String,
                      groupValue: _collection ?? 'none',
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _collection = v),
                    ),
                  ListTile(
                    key: const Key('new-memory-collection'),
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: const Text('Create new collection'),
                    trailing: const Icon(Icons.add),
                    onTap: _busy ? null : _create,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('save-memory'),
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_busy ? 'Saving…' : 'Save memory'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
