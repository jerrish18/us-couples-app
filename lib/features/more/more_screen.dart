import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/settings.dart';
import '../../core/space.dart';
import '../../core/ui.dart';
import '../../core/design.dart';
import '../../core/media.dart';
import '../../core/notifications.dart';
import 'backup.dart';
import '../location/live_location.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});
  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  bool _exporting = false;
  Future<void> _text(
    UsSpace space,
    String field,
    String title, {
    int max = 60,
  }) async {
    final value = await askText(
      context,
      title,
      initial: space.me?[field] as String? ?? '',
      max: max,
    );
    if (value != null && mounted)
      await safely(context, () => space.profile({field: value}));
  }

  Future<void> _timezone(UsSpace space) async {
    final controller = TextEditingController();
    String query = '';
    final result = await showGlassBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(UsTokens.s20),
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Find a time zone',
                      hintText: 'Kolkata, London, New York…',
                    ),
                    onChanged: (v) =>
                        set(() => query = v.toLowerCase().replaceAll(' ', '_')),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: tz.timeZoneDatabase.locations.keys
                        .where((z) => z.toLowerCase().contains(query))
                        .map(
                          (z) => ListTile(
                            title: Text(z.replaceAll('_', ' ')),
                            onTap: () => Navigator.pop(c, z),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (result != null && mounted)
      await safely(context, () async {
        await space.profile({'timezone': result});
        await space.setPreferences({'timezone': result});
      });
  }

  Future<void> _quiet(UsSpace space) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 22, minute: 0),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (end == null || !mounted) return;
    String value(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
    await safely(
      context,
      () => space.setPreferences({
        'quiet_start': value(start),
        'quiet_end': value(end),
      }),
    );
  }

  Future<void> _delete(UsSpace space) async {
    final yes = await showGlassDialog<bool>(
      context: context,
      builder: (c) => GlassDialog(
        title: const Text('Delete our space?'),
        content: const Text(
          'This permanently removes both people’s shared messages, memories, lists, dates, journal entries, and uploaded files. Your sign-in accounts remain. Export a backup first if you want to keep your story.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep our space'),
          ),
          ExpressiveButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete all space data'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await safely(context, () async {
      await ref.read(locationProvider).stop();
      final response = await space.session.client.functions.invoke(
        'delete-space',
        body: {'couple_id': space.session.coupleId},
      );
      if (response.status != 200 && response.status != 202)
        throw StateError('Deletion not completed');
      await space.eraseLocal();
      await space.session.refresh();
      try {
        await UsNotifications.unregister(space.session);
      } catch (_) {
        /* Retry cleanup on the next launch. */
      }
      if (response.status == 202 && mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Deletion started. Remaining files will be removed automatically.',
            ),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceProvider),
        settings = ref.watch(settingsProvider);
    return ListenableBuilder(
      listenable: space,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(
          UsTokens.s20,
          UsTokens.s8,
          UsTokens.s20,
          UsTokens.s28,
        ),
        children: [
          const PageHeading(
            'Made for\nthe two of us.',
            'The little things that make it yours.',
          ),
          LayoutBuilder(
            builder: (context, constraints) => GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount:
                  constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.25
                  ? 1
                  : 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(1) > 1.25
                  ? 185
                  : 150,
              children: [
                FeatureTile(
                  title: 'Live location',
                  accent: Accent.blue,
                  icon: Icons.near_me_rounded,
                  onTap: () => context.push('/location'),
                ),
                FeatureTile(
                  title: 'Open when…',
                  accent: Accent.pink,
                  icon: Icons.mail_outline_rounded,
                  onTap: () => context.push('/letters'),
                ),
                FeatureTile(
                  title: 'Expenses',
                  accent: Accent.green,
                  icon: Icons.receipt_long_rounded,
                  onTap: () => context.push('/expenses'),
                ),
                FeatureTile(
                  title: 'Collections',
                  accent: Accent.coral,
                  icon: Icons.collections_bookmark_rounded,
                  onTap: () => context.push('/collections'),
                ),
                FeatureTile(
                  title: 'Our lists',
                  accent: Accent.yellow,
                  icon: Icons.checklist_rounded,
                  onTap: () => context.push('/lists'),
                ),
                FeatureTile(
                  title: 'Our journal',
                  accent: Accent.lavender,
                  icon: Icons.auto_stories_rounded,
                  onTap: () => context.push('/journal'),
                ),
              ],
            ),
          ),
          const SizedBox(height: UsTokens.s16),
          Text('Make it yours', style: Theme.of(context).textTheme.titleLarge),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.do_not_disturb_on_outlined),
              title: const Text('My availability'),
              subtitle: Text(
                space.me?['availability'] as String? ?? 'No status',
              ),
              onTap: () async {
                final value = await askText(
                  context,
                  'Let your person know',
                  hint: 'Working, free to talk, need a little quiet…',
                  max: 80,
                );
                if (value != null && mounted)
                  await safely(
                    context,
                    () => space.profile({
                      'availability': value,
                      'availability_until': DateTime.now()
                          .add(const Duration(hours: 4))
                          .toUtc()
                          .toIso8601String(),
                    }),
                  );
              },
              trailing: IconButton(
                tooltip: 'Clear status',
                icon: const Icon(Icons.close),
                onPressed: () => safely(
                  context,
                  () => space.profile({
                    'availability': null,
                    'availability_until': null,
                  }),
                ),
              ),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My name'),
              subtitle: Text(
                space.me?['display_name'] as String? ?? 'Your person',
              ),
              onTap: () => _text(space, 'display_name', 'Your name'),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: const Text('Partner nickname'),
              subtitle: Text(
                space.me?['nickname'] as String? ?? 'What I call my person',
              ),
              onTap: () =>
                  _text(space, 'nickname', 'What do you call your person?'),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('My profile photo'),
              onTap: () => safely(context, () async {
                final file = await pickPhoto(coupleId: space.session.coupleId!);
                if (file == null) return;
                final path =
                    '${space.session.coupleId}/${space.session.userId}/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
                await space.session.client.storage
                    .from('couple-media')
                    .uploadBinary(
                      path,
                      await File(file).readAsBytes(),
                      fileOptions: const FileOptions(contentType: 'image/jpeg'),
                    );
                await space.profile({'avatar_path': path});
              }),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Space name'),
              subtitle: Text(space.session.couple?['name'] as String? ?? 'Us'),
              onTap: () async {
                final name = await askText(
                  context,
                  'Our space name',
                  initial: space.session.couple?['name'] as String? ?? 'Us',
                  max: 60,
                );
                if (name != null && mounted)
                  await safely(context, () async {
                    await space.session.client
                        .from('couples')
                        .update({'name': name})
                        .eq('id', space.session.coupleId!);
                    await space.session.refresh();
                  });
              },
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Together since'),
              subtitle: Text(
                displayDate(space.session.couple?['together_since'] as String?),
              ),
              onTap: () async {
                final date = await pickDateTime(context, time: false);
                if (date != null && mounted)
                  await safely(context, () async {
                    await space.session.client
                        .from('couples')
                        .update({
                          'together_since': date.toIso8601String().substring(
                            0,
                            10,
                          ),
                        })
                        .eq('id', space.session.coupleId!);
                    await space.session.refresh();
                  });
              },
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.location_city),
              title: const Text('My city'),
              subtitle: Text(space.me?['city'] as String? ?? 'Chennai'),
              onTap: () => _text(space, 'city', 'Your city'),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('My time zone'),
              subtitle: Text(
                space.me?['timezone'] as String? ?? 'Asia/Kolkata',
              ),
              onTap: () => _timezone(space),
            ),
          ),
          const Divider(),
          Text(
            'Comfort and privacy',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => Column(
                children: [
                  DropdownButtonFormField<ThemeMode>(
                    initialValue: settings.theme,
                    decoration: const InputDecoration(labelText: 'Theme'),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text('Follow my phone'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text('Light'),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text('Dark'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) settings.setTheme(v);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('App lock'),
                    subtitle: const Text(
                      'Device security or your private app PIN',
                    ),
                    value: settings.locked,
                    onChanged: (v) async {
                      if (v) {
                        final pin = await askText(
                          context,
                          'Choose a 4–8 digit app PIN',
                          max: 8,
                          obscure: true,
                        );
                        if (pin == null || !RegExp(r'^\d{4,8}$').hasMatch(pin))
                          return;
                        await settings.setLock(true, newPin: pin);
                      } else
                        await settings.setLock(false);
                    },
                  ),
                ],
              ),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Add our home-screen widget'),
              subtitle: const Text('Days together and today’s mood'),
              onTap: () => safely(context, () async {
                if (await HomeWidget.isRequestPinWidgetSupported() == true)
                  await HomeWidget.requestPinWidget(
                    androidName: 'UsWidgetProvider',
                  );
                else if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Long press your home screen, tap Widgets, then choose Us.',
                      ),
                    ),
                  );
              }),
            ),
          ),
          ...{
            'messages': 'Message notifications',
            'miss_me': 'Miss Me notifications',
            'dates': 'Date invitations and replies',
            'reminders': 'Dates and anniversary reminders',
            'nudges': 'Gentle daily nudge (optional)',
          }.entries.map(
            (e) => SwitchListTile(
              title: Text(e.value),
              value: space.preferences[e.key] as bool? ?? e.key != 'nudges',
              onChanged: (v) =>
                  safely(context, () => space.setPreferences({e.key: v})),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('Quiet hours'),
              subtitle: Text(
                space.preferences['quiet_start'] == null
                    ? 'Off'
                    : '${space.preferences['quiet_start']} – ${space.preferences['quiet_end']}',
              ),
              onTap: () => _quiet(space),
              trailing: space.preferences['quiet_start'] == null
                  ? null
                  : IconButton(
                      tooltip: 'Turn quiet hours off',
                      onPressed: () => safely(
                        context,
                        () => space.setPreferences({
                          'quiet_start': null,
                          'quiet_end': null,
                        }),
                      ),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const Divider(),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(
                _exporting ? 'Saving your story…' : 'Export chat and memories',
              ),
              subtitle: const Text(
                'Includes photos and voice notes. Save the backup privately.',
              ),
              onTap: _exporting
                  ? null
                  : () async {
                      setState(() => _exporting = true);
                      await safely(context, () => exportBackup(space));
                      if (mounted) setState(() => _exporting = false);
                    },
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => safely(context, () async {
                await ref.read(locationProvider).stop();
                await UsNotifications.unregister(space.session);
                await space.session.client.auth.signOut();
              }),
            ),
          ),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.link_off, color: UsColors.danger),
              title: const Text('Unlink and delete our space'),
              onTap: () => _delete(space),
            ),
          ),
          const SizedBox(height: UsTokens.s20),
          const Text(
            'Just the two of you. No ads, analytics, games, or public profiles.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
