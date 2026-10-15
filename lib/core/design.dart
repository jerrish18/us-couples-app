import 'package:flutter/material.dart';

Duration usMotion(BuildContext context, [int ms = 240]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// One short entrance per mounted page; scrolling and realtime edits do not restart it.
class PageEntrance extends StatelessWidget {
  const PageEntrance({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: usMotion(context, 280),
    curve: Curves.easeOutCubic,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.trailing});
  final String title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class StoryPanel extends StatelessWidget {
  const StoryPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  const Color(0xff343968),
                  const Color(0xff23243b),
                  const Color(0xff36293c),
                ]
              : [
                  const Color(0xffe1e6ff),
                  const Color(0xffeeebfc),
                  const Color(0xffffe4e8),
                ],
        ),
        border: Border.all(
          color: (dark ? Colors.white : Colors.white).withValues(
            alpha: dark ? .13 : .9,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff6960ae).withValues(alpha: .08),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class UsDock extends StatelessWidget {
  const UsDock({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  static const labels = ['Home', 'Chat', 'Calendar', 'Memories', 'More'];
  static const icons = [
    Icons.home_rounded,
    Icons.chat_bubble_rounded,
    Icons.calendar_month_rounded,
    Icons.photo_library_rounded,
    Icons.more_horiz_rounded,
  ];
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .09),
              blurRadius: 22,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    selected: selected == i,
                    button: true,
                    label: labels[i],
                    child: Tooltip(
                      message: labels[i],
                      child: InkWell(
                        borderRadius: BorderRadius.circular(27),
                        onTap: () => onSelect(i),
                        child: AnimatedContainer(
                          duration: usMotion(context, 200),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected == i
                                ? colors.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(27),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icons[i],
                                size: 22,
                                color: selected == i
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                child: Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: selected == i
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected == i
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 23),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.arrow_outward_rounded, size: 16),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
