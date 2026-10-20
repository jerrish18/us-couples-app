import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design.dart';
import 'space.dart';
import 'ui.dart';

const featureLinks =
    <({String title, String route, IconData icon, Accent accent})>[
      (
        title: 'Home',
        route: '/',
        icon: Icons.home_rounded,
        accent: Accent.yellow,
      ),
      (
        title: 'Chat',
        route: '/chat',
        icon: Icons.chat_bubble_rounded,
        accent: Accent.blue,
      ),
      (
        title: 'Calendar',
        route: '/calendar',
        icon: Icons.calendar_month_rounded,
        accent: Accent.coral,
      ),
      (
        title: 'Memories',
        route: '/memories',
        icon: Icons.photo_library_rounded,
        accent: Accent.pink,
      ),
      (
        title: 'Our lists',
        route: '/lists',
        icon: Icons.checklist_rounded,
        accent: Accent.green,
      ),
      (
        title: 'Journal',
        route: '/journal',
        icon: Icons.auto_stories_rounded,
        accent: Accent.lavender,
      ),
      (
        title: 'Open when letters',
        route: '/letters',
        icon: Icons.mail_rounded,
        accent: Accent.pink,
      ),
      (
        title: 'Shared expenses',
        route: '/expenses',
        icon: Icons.receipt_long_rounded,
        accent: Accent.green,
      ),
      (
        title: 'Collections',
        route: '/collections',
        icon: Icons.collections_bookmark_rounded,
        accent: Accent.coral,
      ),
      (
        title: 'Live location',
        route: '/location',
        icon: Icons.near_me_rounded,
        accent: Accent.blue,
      ),
      (
        title: 'Cycle care',
        route: '/cycle',
        icon: Icons.water_drop_outlined,
        accent: Accent.pink,
      ),
      (
        title: 'Settings',
        route: '/more',
        icon: Icons.tune_rounded,
        accent: Accent.lavender,
      ),
    ];
Future<void> showFeatureSearch(BuildContext context) async {
  final result = await showGlassBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _FeatureSearch(),
  );
  if (result != null && context.mounted) {
    if (const [
      '/',
      '/chat',
      '/calendar',
      '/memories',
      '/more',
    ].contains(result))
      context.go(result);
    else
      context.push(result);
  }
}

class _FeatureSearch extends StatefulWidget {
  const _FeatureSearch();
  @override
  State<_FeatureSearch> createState() => _FeatureSearchState();
}

class _FeatureSearchState extends State<_FeatureSearch> {
  String _query = '';
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .65,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(UsTokens.s20),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Find a feature',
              hintText: 'Chat, memories, journal…',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final feature in featureLinks.where(
                (f) => f.title.toLowerCase().contains(_query),
              ))
                ListTile(
                  leading: FlowerBadge(
                    icon: feature.icon,
                    accent: feature.accent,
                    size: UsTokens.s40,
                  ),
                  title: Text(feature.title),
                  trailing: const Icon(Icons.arrow_outward_rounded),
                  onTap: () => Navigator.pop(context, feature.route),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<void> showPlansOverview(BuildContext context, UsSpace space) =>
    showGlassBottomSheet<void>(
      context: context,
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.all(UsTokens.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeading(
              'For your calendar',
              'Your saved dates and special days.',
            ),
            for (final date in (space.rows['dates'] ?? []).take(5))
              Card(
                child: ListTile(
                  leading: const FlowerBadge(
                    icon: Icons.event_rounded,
                    accent: Accent.coral,
                    size: UsTokens.s40,
                  ),
                  title: Text(date['title'] as String),
                  subtitle: Text(displayDate(date['starts_at'] as String)),
                  onTap: () {
                    Navigator.pop(c);
                    context.go('/calendar');
                  },
                ),
              ),
            for (final day in (space.rows['anniversaries'] ?? []).take(5))
              Card(
                child: ListTile(
                  leading: const FlowerBadge(
                    icon: Icons.cake_rounded,
                    accent: Accent.yellow,
                    size: UsTokens.s40,
                  ),
                  title: Text(day['title'] as String),
                  subtitle: Text(displayDate(day['event_date'] as String)),
                  onTap: () {
                    Navigator.pop(c);
                    context.go('/calendar');
                  },
                ),
              ),
            if ((space.rows['dates'] ?? []).isEmpty &&
                (space.rows['anniversaries'] ?? []).isEmpty)
              const EmptyCard(
                'Room for something lovely',
                'Plan a date or add your first anniversary.',
                icon: Icons.notifications_none_rounded,
              ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                context.go('/more');
              },
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Notification settings'),
            ),
          ],
        ),
      ),
    );
