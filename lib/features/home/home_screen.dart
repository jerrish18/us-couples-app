import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/space.dart';
import '../../core/ui.dart';
import '../../core/notifications.dart';
import '../../core/reminder_dates.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _missBusy = false, _heart = false;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UsNotifications.requestPermission(ref.read(spaceProvider).session)
          .catchError((_) {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _miss(UsSpace space) async {
    if (_missBusy) return;
    setState(() => _missBusy = true);
    try {
      final result = await space.missMe();
      if (!mounted) return;
      if (result['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['error'] == 'cooldown'
                  ? 'A little pause—try again after ${displayTime(result['retry_at'] as String?)}.'
                  : 'Invite your partner first.',
            ),
          ),
        );
      } else {
        await HapticFeedback.lightImpact();
        setState(() => _heart = true);
        await space.refresh();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A little love is on its way ❤️')),
          );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect to the internet to send Miss Me.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _missBusy = false);
    }
  }

  Future<void> _note(UsSpace space) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final existing = (space.rows['love_notes'] ?? [])
        .where(
          (r) =>
              r['author_id'] == space.session.userId && r['note_date'] == today,
        )
        .firstOrNull;
    final text = await askText(
      context,
      'A note for your person',
      initial: existing?['body'] as String? ?? '',
      lines: 3,
      max: 2000,
    );
    if (text == null || !mounted) return;
    await safely(context, () async {
      if (existing == null)
        await space.add('love_notes', {'body': text, 'note_date': today});
      else
        await space.update('love_notes', existing['id'] as String, {
          'body': text,
        });
    });
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider);
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) {
        final couple = space.session.couple!,
            since = DateTime.tryParse(
              couple['together_since'] as String? ?? '',
            );
        final days = since == null ? null : daysTogether(since, DateTime.now());
        final name =
            space.me?['nickname'] as String? ??
            space.partner?['display_name'] as String? ??
            'Your person';
        final partnerZone =
            space.partner?['timezone'] as String? ?? 'Asia/Kolkata';
        tz.TZDateTime partnerNow;
        try {
          partnerNow = tz.TZDateTime.now(tz.getLocation(partnerZone));
        } catch (_) {
          partnerNow = tz.TZDateTime.now(tz.UTC);
        }
        final partnerMood =
            space.partner?['mood_date'] ==
                partnerNow.toIso8601String().substring(0, 10)
            ? (space.partner?['mood'] ?? 'Not checked in yet')
            : 'Not checked in yet';
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final notes =
            (space.rows['love_notes'] ?? [])
                .where((r) => r['author_id'] == space.session.partnerId)
                .toList()
              ..sort(
                (a, b) => (a['created_at'] as String).compareTo(
                  b['created_at'] as String,
                ),
              );
        final taps =
            List<Map<String, dynamic>>.from(space.rows['miss_me'] ?? [])..sort(
              (a, b) => (b['created_at'] as String).compareTo(
                a['created_at'] as String,
              ),
            );
        return RefreshIndicator(
          onRefresh: space.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            children: [
              Text(
                'Your little world.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              if (!space.online)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Offline · Your chat will sync when you reconnect.',
                  ),
                ),
              if (space.loading) const LinearProgressIndicator(),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    children: [
                      const Icon(Icons.favorite_rounded, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        days?.toString() ?? 'Our story',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                      Text(
                        days == null
                            ? 'Set your together-since date in More'
                            : 'days together',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (days != null &&
                          [
                            100,
                            365,
                            730,
                            1000,
                            1095,
                            1825,
                            3650,
                          ].where((v) => v > days).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            '${[100, 365, 730, 1000, 1095, 1825, 3650].firstWhere((v) => v > days) - days} days to your next milestone',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (space.session.partnerId == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite your person',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<String?>(
                          future: space.session.invite(),
                          builder: (context, snapshot) => SelectableText(
                            snapshot.data ?? '…',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'They sign in, choose Join my person, and enter this code.',
                        ),
                        TextButton(
                          onPressed: space.session.refresh,
                          child: const Text('Check for my person'),
                        ),
                      ],
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: 'Send Miss Me to your partner',
                child: AnimatedScale(
                  scale: _heart ? 1.025 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: FilledButton(
                    onPressed: _missBusy ? null : () => _miss(space),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(26),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _heart ? Icons.favorite : Icons.favorite_outline,
                          size: 34,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          _missBusy ? 'Sending love…' : 'Miss Me',
                          style: const TextStyle(fontSize: 24),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A note from $name',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        notes.isEmpty
                            ? 'Little words can make a big day.'
                            : notes.last['body'] as String,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _note(space),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Write a love note'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'How does today feel?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                          'Happy 😊',
                          'Loved 🥰',
                          'Calm 🌿',
                          'Tired 😴',
                          'Low 💙',
                          'Busy ☕',
                        ]
                        .map(
                          (m) => ChoiceChip(
                            label: Text(m),
                            selected:
                                space.me?['mood'] == m &&
                                space.me?['mood_date'] == today,
                            onSelected: (_) => safely(
                              context,
                              () => space.profile({
                                'mood': m,
                                'mood_date': today,
                              }),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: space.partner?['avatar_path'] == null
                      ? const Icon(Icons.public)
                      : ClipOval(
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: PrivatePhoto(
                              space,
                              space.partner!['avatar_path'] as String,
                              height: 44,
                            ),
                          ),
                        ),
                  title: Text(name),
                  subtitle: Text(
                    '${space.partner?['city'] ?? 'Their time'} · ${partnerNow.hour.toString().padLeft(2, '0')}:${partnerNow.minute.toString().padLeft(2, '0')}\nMood: $partnerMood',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (DateTime.tryParse(
                    space.partner?['availability_until'] as String? ?? '',
                  )?.isAfter(DateTime.now()) ??
                  false)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.coffee_outlined),
                    title: Text(
                      space.partner?['availability'] as String? ?? '',
                    ),
                    subtitle: Text(
                      'Your person · until ${displayTime(space.partner?['availability_until'] as String?)}',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.push('/location'),
                icon: const Icon(Icons.near_me_outlined),
                label: const Text('Find each other · Live location'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/calendar'),
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Plan a date'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/chat'),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Say hello'),
                    ),
                  ),
                ],
              ),
              if (taps.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Little moments of missing',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...taps
                    .take(5)
                    .map(
                      (tap) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.favorite,
                          color: Color(0xffb94d65),
                        ),
                        title: Text(
                          tap['sender_id'] == space.session.userId
                              ? 'You missed your person'
                              : 'Your person missed you',
                        ),
                        subtitle: Text(
                          '${displayDate(tap['created_at'] as String)} · ${displayTime(tap['created_at'] as String)}',
                        ),
                      ),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }
}
