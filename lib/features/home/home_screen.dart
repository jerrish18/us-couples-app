import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/space.dart';
import '../../core/ui.dart';
import '../../core/design.dart';
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
        final dark = Theme.of(context).brightness == Brightness.dark;
        final type = Theme.of(context).textTheme;
        return UsRefresh(
          onRefresh: space.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: UsTokens.page,
            children: [
              PageEntrance(
                child: PageHeading(
                  'Good to be\nwith you.',
                  'A little space for a love like yours.',
                  trailing: const FlowerBadge(
                    icon: Icons.wb_sunny_rounded,
                    accent: Accent.yellow,
                  ),
                ),
              ),
              if (!space.online)
                const StateBanner(
                  icon: Icons.cloud_off_rounded,
                  message: 'Offline · Your chat sends when you reconnect.',
                  accent: Accent.yellow,
                ),
              if (space.loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: UsTokens.s16),
                  child: ShimmerBox(),
                ),
              PageEntrance(
                index: 1,
                child: TintedTile(
                  accent: Accent.yellow,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AccentChip(
                              label: 'OUR STORY',
                              accent: Accent.yellow,
                              icon: Icons.favorite_rounded,
                            ),
                            const SizedBox(height: UsTokens.s16),
                            if (days != null)
                              AnimatedCounter(value: days)
                            else
                              Text('Just us.', style: type.displaySmall),
                            Text(
                              days == null
                                  ? 'Set your together-since date in More'
                                  : 'days of choosing each other',
                              style: type.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: UsTokens.s12),
                      ProgressRing(
                        value: days == null ? 0 : (days % 365) / 365,
                        size: UsTokens.s88,
                        child: const FlowerBadge(
                          icon: Icons.favorite_rounded,
                          accent: Accent.coral,
                          size: UsTokens.s64,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: UsTokens.s16),
              CelebrationBurst(
                active: _heart,
                child: ExpressiveButton.icon(
                  onPressed: _missBusy ? null : () => _miss(space),
                  icon: AnimatedSwitcher(
                    duration: usMotion(context),
                    child: Icon(
                      _heart
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(_heart),
                    ),
                  ),
                  label: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _missBusy ? 'Sending love…' : 'Miss Me',
                        style: type.titleLarge?.copyWith(
                          color: dark ? UsColors.ink : UsColors.white,
                        ),
                      ),
                      const Icon(Icons.arrow_outward_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: UsTokens.s24),
              if (space.session.partnerId == null)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('One little invite.', style: type.headlineSmall),
                      const SizedBox(height: UsTokens.s12),
                      FutureBuilder<String?>(
                        future: space.session.invite(),
                        builder: (context, snapshot) => SelectableText(
                          snapshot.data ?? '…',
                          style: type.headlineLarge,
                        ),
                      ),
                      const Text(
                        'Your person signs in, chooses Join my person, and enters this code.',
                      ),
                      TextButton(
                        onPressed: space.session.refresh,
                        child: const Text('Check for my person'),
                      ),
                    ],
                  ),
                ),
              PageEntrance(
                index: 2,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final partner = TintedTile(
                      accent: Accent.green,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FlowerBadge(
                            child: space.partner?['avatar_path'] == null
                                ? null
                                : PrivatePhoto(
                                    space,
                                    space.partner!['avatar_path'] as String,
                                    height: UsTokens.s64,
                                  ),
                            icon: Icons.public_rounded,
                            accent: Accent.green,
                          ),
                          const SizedBox(height: UsTokens.s16),
                          Text(name, style: type.titleLarge),
                          Text(
                            '${partnerNow.hour.toString().padLeft(2, '0')}:${partnerNow.minute.toString().padLeft(2, '0')}',
                            style: type.headlineLarge,
                          ),
                          Text(
                            space.partner?['city'] as String? ??
                                'Their local time',
                            style: type.bodyMedium,
                          ),
                          const SizedBox(height: UsTokens.s16),
                          Text('$partnerMood', style: type.titleMedium),
                        ],
                      ),
                    );
                    final plans = Column(
                      children: [
                        TintedTile(
                          accent: Accent.coral,
                          onTap: () => context.go('/calendar'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.calendar_month_rounded,
                                size: UsTokens.s32,
                              ),
                              const SizedBox(height: UsTokens.s12),
                              Text('Time for us', style: type.titleLarge),
                              const SizedBox(height: UsTokens.s8),
                              const Text('Plan a little date ↗'),
                            ],
                          ),
                        ),
                        const SizedBox(height: UsTokens.s12),
                        TintedTile(
                          accent: Accent.blue,
                          onTap: () => context.go('/chat'),
                          child: Row(
                            children: [
                              const Icon(Icons.chat_bubble_rounded),
                              const SizedBox(width: UsTokens.s12),
                              Expanded(
                                child: Text(
                                  'Say hello',
                                  style: type.titleMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3)
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          partner,
                          const SizedBox(height: UsTokens.s12),
                          plans,
                        ],
                      );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: partner),
                        const SizedBox(width: UsTokens.s12),
                        Expanded(child: plans),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: UsTokens.s24),
              PageEntrance(
                index: 3,
                child: TintedTile(
                  accent: Accent.pink,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.format_quote_rounded),
                          const SizedBox(width: UsTokens.s12),
                          Expanded(
                            child: Text(
                              'A note from $name',
                              style: type.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: UsTokens.s20),
                      Text(
                        notes.isEmpty
                            ? 'Little words can make a big day.'
                            : notes.last['body'] as String,
                        style: type.headlineSmall,
                      ),
                      const SizedBox(height: UsTokens.s16),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => _note(space),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: const Text('Write a love note'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: UsTokens.s24),
              Text('How are you, really?', style: type.headlineSmall),
              const SizedBox(height: UsTokens.s12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final mood in [
                      'Happy 😊',
                      'Loved 🥰',
                      'Calm 🌿',
                      'Tired 😴',
                      'Low 💙',
                      'Busy ☕',
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: UsTokens.s8,
                        ),
                        child: ChoiceChip(
                          label: Text(mood),
                          selected:
                              space.me?['mood'] == mood &&
                              space.me?['mood_date'] == today,
                          onSelected: (_) => safely(
                            context,
                            () => space.profile({
                              'mood': mood,
                              'mood_date': today,
                            }),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: UsTokens.s24),
              TintedTile(
                accent: Accent.lavender,
                onTap: () => context.go('/memories'),
                child: Row(
                  children: [
                    const FlowerBadge(
                      icon: Icons.photo_library_rounded,
                      accent: Accent.pink,
                    ),
                    const SizedBox(width: UsTokens.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Moments worth keeping', style: type.titleLarge),
                          Text(
                            '${(space.rows['memories'] ?? []).length} memories, just ours.',
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_outward_rounded),
                  ],
                ),
              ),
              const SizedBox(height: UsTokens.s16),
              GlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.near_me_rounded),
                  title: const Text('Closer, wherever you are'),
                  subtitle: const Text('Live location · shared by choice'),
                  trailing: const Icon(Icons.arrow_outward_rounded),
                  onTap: () => context.push('/location'),
                ),
              ),
              if (DateTime.tryParse(
                    space.partner?['availability_until'] as String? ?? '',
                  )?.isAfter(DateTime.now()) ??
                  false)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.coffee_rounded),
                    title: Text(
                      space.partner?['availability'] as String? ?? '',
                    ),
                    subtitle: Text(
                      'Until ${displayTime(space.partner?['availability_until'] as String?)}',
                    ),
                  ),
                ),
              if (days != null &&
                  [100, 365, 730, 1000, 1095, 1825, 3650].any((v) => v > days))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: UsTokens.s16),
                  child: AccentChip(
                    accent: Accent.yellow,
                    label:
                        '${[100, 365, 730, 1000, 1095, 1825, 3650].firstWhere((v) => v > days) - days} days to your next milestone',
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
              if (taps.isNotEmpty) ...[
                const SizedBox(height: UsTokens.s24),
                Text('Little “I miss you”s', style: type.headlineSmall),
                const SizedBox(height: UsTokens.s12),
                SizedBox(
                  height: UsTokens.s128,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: math.min(5, taps.length),
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: UsTokens.s12),
                    itemBuilder: (context, index) {
                      final tap = taps[index];
                      return SizedBox(
                        width: UsTokens.s240,
                        child: TintedTile(
                          accent: Accent.pink,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tap['sender_id'] == space.session.userId
                                    ? 'You missed your person'
                                    : 'Your person missed you',
                                style: type.titleMedium,
                              ),
                              const SizedBox(height: UsTokens.s8),
                              Text(
                                '${displayDate(tap['created_at'] as String)} · ${displayTime(tap['created_at'] as String)}',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
