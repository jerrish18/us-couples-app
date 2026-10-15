import 'design.dart';

import 'package:flutter/material.dart';

import 'dart:io';

import 'space.dart';

Future<void> safely(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save. Check your connection and try again.'),
        ),
      );
  }
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String hint = '',
  String initial = '',
  int max = 500,
  int lines = 1,
  bool obscure = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showGlassDialog<String>(
    context: context,
    builder: (context) => GlassDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: max,
        minLines: obscure ? 1 : lines,
        maxLines: obscure ? 1 : lines + 2,
        obscureText: obscure,
        autocorrect: !obscure,
        enableSuggestions: !obscure,
        keyboardType: obscure ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ExpressiveButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.pop(context, text);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // Dispose after the dialog's exit animation no longer uses the controller.
  Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
  return result;
}

Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
  bool time = true,
}) async {
  final seed = initial ?? DateTime.now().add(const Duration(hours: 2));
  final day = await showDatePicker(
    context: context,
    initialDate: seed,
    firstDate: DateTime(1900),
    lastDate: DateTime(2200),
  );
  if (day == null || !context.mounted) return null;
  if (!time) return day;
  final clock = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  return clock == null
      ? null
      : DateTime(day.year, day.month, day.day, clock.hour, clock.minute);
}

String displayDate(String? text) {
  final d = DateTime.tryParse(text ?? '')?.toLocal();
  if (d == null) return '';
  return '${d.day}/${d.month}/${d.year}';
}

String displayTime(String? text) {
  final d = DateTime.tryParse(text ?? '')?.toLocal();
  if (d == null) return '';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class EmptyCard extends StatelessWidget {
  const EmptyCard(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.favorite_outline,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      children: [
        FlowerBadge(
          icon: icon,
          accent: FeatureStyle.of(context),
          size: UsTokens.s80,
        ),
        const SizedBox(height: UsTokens.s24),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: UsTokens.s12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class PrivatePhoto extends StatefulWidget {
  const PrivatePhoto(
    this.space,
    this.path, {
    super.key,
    this.localFile,
    this.height = UsTokens.s220,
  });
  final UsSpace space;
  final String path;
  final String? localFile;
  final double height;
  @override
  State<PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends State<PrivatePhoto> {
  late Future<String> _url;
  late bool _online;
  Future<String> _source() =>
      widget.localFile != null && File(widget.localFile!).existsSync()
      ? Future.value(widget.localFile!)
      : widget.space.mediaFile(widget.path);
  @override
  void initState() {
    super.initState();
    _online = widget.space.online;
    _url = _source();
  }

  @override
  void didUpdateWidget(covariant PrivatePhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.localFile != widget.localFile ||
        (!_online && widget.space.online))
      _url = _source();
    _online = widget.space.online;
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(UsTokens.s20),
    child: widget.localFile != null && File(widget.localFile!).existsSync()
        ? Image.file(
            File(widget.localFile!),
            height: widget.height,
            width: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: UsTokens.photoDecode,
          )
        : FutureBuilder<String>(
            future: _url,
            builder: (context, snapshot) => snapshot.hasData
                ? Image.file(
                    File(snapshot.data!),
                    height: widget.height,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    cacheWidth: UsTokens.photoDecode,
                    errorBuilder: (_, e, st) => _placeholder(),
                  )
                : snapshot.connectionState == ConnectionState.waiting
                ? ShimmerBox(height: widget.height)
                : _placeholder(),
          ),
  );
  Widget _placeholder() => SizedBox(
    height: widget.height,
    child: Center(
      child: TextButton.icon(
        onPressed: () => setState(() => _url = _source()),
        icon: const Icon(Icons.image_outlined),
        label: const Text('Load photo'),
      ),
    ),
  );
}

/// Shared presentation for missing data and offline state. Services are untouched.
class SpaceBody extends StatelessWidget {
  const SpaceBody({
    super.key,
    required this.space,
    required this.child,
    this.table,
  });
  final UsSpace space;
  final Widget child;
  final String? table;
  @override
  Widget build(BuildContext context) {
    if (space.loading && (table == null || (space.rows[table] ?? []).isEmpty))
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(UsTokens.s24),
          child: LoadingPanel(),
        ),
      );
    if (space.online) return child;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(UsTokens.s12),
          child: StateBanner(
            message:
                space.error ?? 'Offline · Your saved moments are still here.',
            icon: Icons.cloud_off_rounded,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
