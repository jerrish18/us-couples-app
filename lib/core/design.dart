import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'theme.dart';
import 'haptics.dart';
export 'haptics.dart';
export 'theme.dart';

final _glassOverlayDepth = ValueNotifier<int>(0);

Duration usMotion(BuildContext context, [int ms = UsTokens.interaction]) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

class ExpressiveSpring extends Curve {
  const ExpressiveSpring();
  @override
  double transformInternal(double t) => t == 1
      ? 1
      : SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 380, damping: 30),
          0,
          1,
          0,
        ).x(t * .6);
}

class AmbientMesh extends StatefulWidget {
  const AmbientMesh({super.key, required this.child});
  final Widget child;
  @override
  State<AmbientMesh> createState() => _AmbientMeshState();
}

class _AmbientMeshState extends State<AmbientMesh> with WidgetsBindingObserver {
  final _phase = ValueNotifier<double>(0);
  Timer? _timer;
  bool _reduced = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _start();
  }

  void _start() {
    _timer?.cancel();
    if (!_reduced)
      _timer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _phase.value += .004,
      );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      _start();
    else
      _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phase.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BackdropGroup(
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _MeshPainter(
              _phase,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
        widget.child,
      ],
    ),
  );
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.phase, this.dark) : super(repaint: phase);
  final ValueNotifier<double> phase;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(dark ? UsColors.night : UsColors.paper, BlendMode.src);
    final p = phase.value;
    final centers = [
      Offset(
        size.width * (.1 + .12 * math.sin(p)),
        size.height * (.12 + .06 * math.cos(p)),
      ),
      Offset(
        size.width * (.96 + .08 * math.cos(p * .8)),
        size.height * (.45 + .08 * math.sin(p * .9)),
      ),
      Offset(size.width * (.3 + .1 * math.sin(p * .6)), size.height * .93),
    ];
    final colors = [UsColors.lavender, UsColors.coral, UsColors.blue];
    for (var i = 0; i < 3; i++) {
      final radius = size.width * .95;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: dark ? .065 : .5),
            colors[i].withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centers[i], radius: radius));
      canvas.drawCircle(centers[i], radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) => old.dark != dark;
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(UsTokens.s20),
    this.blur = false,
    this.radius = UsTokens.card,
    this.accent,
    this.contrast = true,
    this.overlay = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool blur, contrast, overlay;
  final double radius;
  final Accent? accent;
  @override
  Widget build(BuildContext context) => blur
      ? ValueListenableBuilder<int>(
          valueListenable: _glassOverlayDepth,
          builder: (context, _, _) => _surface(context),
        )
      : _surface(context);
  Widget _surface(BuildContext context) {
    final theme = Theme.of(context), dark = theme.brightness == Brightness.dark;
    final color = UsColors.tint(accent ?? FeatureStyle.of(context), dark);
    final live =
        blur &&
        (overlay || _glassOverlayDepth.value == 0) &&
        VisualCapabilities.sdk >= 31 &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            UsColors.white.withValues(alpha: dark ? .06 : .20),
            UsColors.white.withValues(alpha: dark ? .025 : .12),
          ],
        ),
      ),
      child: Material(
        color: Color.alphaBlend(
          color.withValues(alpha: .13),
          theme.colorScheme.surface,
        ).withValues(alpha: live ? (contrast ? .86 : .32) : .96),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (live)
      body = BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(
          sigmaX: UsTokens.blur,
          sigmaY: UsTokens.blur,
        ),
        child: body,
      );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: dark ? .07 : .19),
            blurRadius: UsTokens.shadow,
            offset: const Offset(0, UsTokens.s8),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(UsTokens.border),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              UsColors.white.withValues(alpha: dark ? .16 : .95),
              color.withValues(alpha: .12),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            math.max(0, radius - UsTokens.border),
          ),
          child: body,
        ),
      ),
    );
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.blur = true,
  });
  final Widget? title, leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading, blur;
  @override
  Size get preferredSize => const Size.fromHeight(UsTokens.s64);
  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    actions: actions,
    leading: leading,
    automaticallyImplyLeading: automaticallyImplyLeading,
    flexibleSpace: GlassCard(
      radius: 0,
      blur: blur,
      padding: EdgeInsets.zero,
      child: SizedBox.expand(),
    ),
  );
}

class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => GlassCard(
    blur: true,
    overlay: true,
    radius: UsTokens.s36,
    padding: EdgeInsets.zero,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: UsTokens.s40,
              height: UsTokens.s4,
              margin: const EdgeInsets.all(UsTokens.s12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: .35),
                borderRadius: BorderRadius.circular(UsTokens.pill),
              ),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    ),
  );
}

Future<T?> showGlassBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) async {
  _glassOverlayDepth.value++;
  try {
    return await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: UsColors.clear,
      constraints: BoxConstraints(
        maxWidth: UsTokens.s480,
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: GlassSheet(child: builder(c)),
      ),
    );
  } finally {
    _glassOverlayDepth.value--;
  }
}

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  // Photo viewers remain full-screen routes with the same dismiss behavior.
  if (builder(context) is Dialog)
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<T>(MaterialPageRoute(builder: builder, fullscreenDialog: true));
  return showGlassBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
  );
}

class GlassDialog extends StatelessWidget {
  const GlassDialog({super.key, this.title, this.content, this.actions});
  final Widget? title, content;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(UsTokens.s24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          DefaultTextStyle(
            style: Theme.of(context).textTheme.headlineSmall!,
            child: title!,
          ),
        if (content != null) ...[
          const SizedBox(height: UsTokens.s20),
          content!,
        ],
        if (actions != null) ...[
          const SizedBox(height: UsTokens.s24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: UsTokens.s8,
            runSpacing: UsTokens.s8,
            children: actions!,
          ),
        ],
      ],
    ),
  );
}

class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => setState(() => _down = true) : null,
    onPointerCancel: (_) => setState(() => _down = false),
    onPointerUp: (_) => setState(() => _down = false),
    child: AnimatedScale(
      scale: _down ? .94 : 1,
      duration: usMotion(context, _down ? UsTokens.fast : UsTokens.interaction),
      curve: const ExpressiveSpring(),
      child: widget.child,
    ),
  );
}

class ExpressiveButton extends StatelessWidget {
  const ExpressiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       tonal = false;
  const ExpressiveButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.style,
  }) : child = label,
       tonal = false;
  const ExpressiveButton.tonal({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
  }) : icon = null,
       tonal = true;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool tonal;
  @override
  Widget build(BuildContext context) {
    void action() {
      UsHaptics.selection();
      onPressed?.call();
    }

    return PressScale(
      enabled: onPressed != null,
      child: icon != null
          ? FilledButton.icon(
              onPressed: onPressed == null ? null : action,
              icon: icon!,
              label: child,
              style: style,
            )
          : tonal
          ? FilledButton.tonal(
              onPressed: onPressed == null ? null : action,
              style: style,
              child: child,
            )
          : FilledButton(
              onPressed: onPressed == null ? null : action,
              style: style,
              child: child,
            ),
    );
  }
}

class PageEntrance extends StatelessWidget {
  const PageEntrance({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;
  @override
  Widget build(BuildContext context) {
    final delay = math.min(index * UsTokens.stagger, 180),
        total = math.min(UsTokens.entrance + delay, 600);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: usMotion(context, total),
      builder: (_, raw, child) {
        final value = Interval(
          delay / total,
          1,
          curve: Curves.easeOutCubic,
        ).transform(raw);
        final spatial = const ExpressiveSpring().transform(value);
        return Transform.translate(
          offset: Offset(0, UsTokens.s24 * (1 - spatial)),
          child: Transform.scale(
            scale: .95 + .05 * spatial,
            alignment: Alignment.topCenter,
            child: Opacity(opacity: value, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.trailing});
  final String title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: UsTokens.s24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: UsTokens.s8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: UsTokens.s12),
          trailing!,
        ],
      ],
    ),
  );
}

class TintedTile extends StatelessWidget {
  const TintedTile({
    super.key,
    required this.accent,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(UsTokens.s24),
  });
  final Accent accent;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PressScale(
      enabled: onTap != null,
      child: Material(
        color: UsColors.tint(accent, dark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UsTokens.card),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class StoryPanel extends StatelessWidget {
  const StoryPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => TintedTile(
    accent: FeatureStyle.of(context),
    child: child,
    padding: EdgeInsets.zero,
  );
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.accent = Accent.lavender,
  });
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Accent accent;
  @override
  Widget build(BuildContext context) => TintedTile(
    accent: accent,
    onTap: onTap,
    padding: const EdgeInsets.all(UsTokens.s20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        FlowerBadge(icon: icon, accent: accent, size: UsTokens.s52),
        const SizedBox(height: UsTokens.s12),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Icon(Icons.arrow_outward_rounded, size: UsTokens.s20),
          ],
        ),
      ],
    ),
  );
}

class AccentChip extends StatelessWidget {
  const AccentChip({
    super.key,
    required this.label,
    required this.accent,
    this.icon,
  });
  final String label;
  final Accent accent;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: UsTokens.s12,
      vertical: UsTokens.s8,
    ),
    decoration: BoxDecoration(
      color: UsColors.tint(
        accent,
        Theme.of(context).brightness == Brightness.dark,
      ),
      borderRadius: BorderRadius.circular(UsTokens.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: UsTokens.s16),
          const SizedBox(width: UsTokens.s8),
        ],
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.labelSmall),
        ),
      ],
    ),
  );
}

class FlowerClipper extends CustomClipper<Path> {
  const FlowerClipper();
  @override
  Path getClip(Size size) {
    final path = Path(),
        center = Offset(size.width / 2, size.height / 2),
        radius = math.min(size.width, size.height) / 2;
    for (var i = 0; i <= 240; i++) {
      final a = 2 * math.pi * i / 240,
          r = radius * (.90 + .10 * math.cos(10 * a)),
          p = center + Offset(math.cos(a) * r, math.sin(a) * r);
      if (i == 0)
        path.moveTo(p.dx, p.dy);
      else
        path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant FlowerClipper old) => false;
}

class FlowerBadge extends StatelessWidget {
  const FlowerBadge({
    super.key,
    this.icon = Icons.favorite_rounded,
    this.accent = Accent.pink,
    this.size = UsTokens.s64,
    this.child,
  });
  final IconData icon;
  final Accent accent;
  final double size;
  final Widget? child;
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const FlowerClipper(),
    child: Container(
      width: size,
      height: size,
      color: UsColors.tint(
        accent,
        Theme.of(context).brightness == Brightness.dark,
      ),
      alignment: Alignment.center,
      child:
          child ??
          Icon(
            icon,
            size: size * .42,
            color: UsColors.foreground(
              accent,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
    ),
  );
}

class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({super.key, required this.value, this.style});
  final int value;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$value',
    excludeSemantics: true,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: usMotion(context, 500),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          '${v.round()}',
          style: style ?? Theme.of(context).textTheme.displayLarge,
        ),
      ),
    ),
  );
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.child,
    this.size = UsTokens.s120,
  });
  final double value, size;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.clamp(0, 1)),
    duration: usMotion(context, 500),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(v, Theme.of(context).colorScheme.primary),
        child: Center(child: child),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color);
  final double value;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromLTWH(
      UsTokens.s4,
      UsTokens.s4,
      s.width - UsTokens.s8,
      s.height - UsTokens.s8,
    );
    c.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = color.withValues(alpha: .12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = UsTokens.s4,
    );
    c.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = UsTokens.s4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, this.height = UsTokens.s120});
  final double height;
  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context))
      _controller.stop();
    else
      _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(UsTokens.card),
            gradient: LinearGradient(
              begin: Alignment(-3 + 6 * _controller.value, 0),
              end: Alignment(-1 + 6 * _controller.value, 0),
              colors: [
                Theme.of(context).colorScheme.surfaceContainerHigh,
                Theme.of(context).colorScheme.surfaceContainerLow,
                Theme.of(context).colorScheme.surfaceContainerHigh,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class UsRefresh extends StatefulWidget {
  const UsRefresh({super.key, required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  State<UsRefresh> createState() => _UsRefreshState();
}

class _UsRefreshState extends State<UsRefresh> {
  double _pull = 0;
  bool _busy = false;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is OverscrollNotification && n.overscroll < 0)
            setState(
              () => _pull = (_pull - n.overscroll).clamp(0, UsTokens.s80),
            );
          if (n is ScrollEndNotification) setState(() => _pull = 0);
          return false;
        },
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                setState(() => _busy = true);
                UsHaptics.confirm();
                try {
                  await widget.onRefresh();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              color: UsColors.clear,
              backgroundColor: UsColors.clear,
              elevation: 0,
              child: widget.child,
            ),
            if (_busy || _pull > 0)
              PositionedDirectional(
                top: UsTokens.s8,
                start: 0,
                end: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Transform.rotate(
                      angle: _pull / UsTokens.s20,
                      child: FlowerBadge(
                        icon: _busy
                            ? Icons.sync_rounded
                            : Icons.arrow_downward_rounded,
                        size: UsTokens.s48,
                        accent: FeatureStyle.of(context),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

class MessageSurface extends StatelessWidget {
  const MessageSurface({super.key, required this.mine, required this.child});
  final bool mine;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: UsTokens.s16,
      vertical: UsTokens.s12,
    ),
    decoration: BoxDecoration(
      borderRadius: BorderRadiusDirectional.only(
        topStart: const Radius.circular(UsTokens.s28),
        topEnd: const Radius.circular(UsTokens.s28),
        bottomStart: Radius.circular(mine ? UsTokens.s28 : UsTokens.s8),
        bottomEnd: Radius.circular(mine ? UsTokens.s8 : UsTokens.s28),
      ),
      gradient: mine
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                UsColors.tint(
                  Accent.blue,
                  Theme.of(context).brightness == Brightness.dark,
                ),
                UsColors.tint(
                  Accent.lavender,
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ],
            )
          : null,
      color: mine
          ? null
          : Theme.of(context).colorScheme.surfaceContainerLow
                .withValues(alpha: .86),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .32),
      ),
    ),
    child: child,
  );
}

class CelebrationBurst extends StatelessWidget {
  const CelebrationBurst({
    super.key,
    required this.active,
    required this.child,
  });
  final bool active;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      child,
      if (active && !MediaQuery.disableAnimationsOf(context))
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: usMotion(context, 360),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => CustomPaint(painter: _ParticlePainter(v)),
            ),
          ),
        ),
    ],
  );
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    for (var i = 0; i < 18; i++) {
      final a = i * math.pi * 2 / 18, r = UsTokens.s80 * t;
      final p = Offset(
        s.width / 2 + math.cos(a) * r,
        s.height / 2 + math.sin(a) * r,
      );
      c.drawCircle(
        p,
        (1 - t) * UsTokens.s4,
        Paint()
          ..color = UsColors.tint(
            Accent.values[i % 6],
            false,
          ).withValues(alpha: 1 - t),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
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
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: GlassCard(
        blur: true,
        radius: 32,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: selected == i,
                  label: labels[i],
                  excludeSemantics: true,
                  child: Tooltip(
                    message: labels[i],
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        if (selected != i) {
                          UsHaptics.selection();
                          onSelect(i);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: usMotion(context, 360),
                              curve: const ExpressiveSpring(),
                              width: 56,
                              height: 32,
                              decoration: BoxDecoration(
                                color: selected == i
                                    ? colors.primaryContainer
                                    : UsColors.clear,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: AnimatedScale(
                                scale: selected == i ? 1.08 : 1,
                                duration: usMotion(context),
                                curve: const ExpressiveSpring(),
                                child: Icon(
                                  icons[i],
                                  size: 24,
                                  color: selected == i
                                      ? colors.onPrimaryContainer
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labels[i],
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: selected == i
                                            ? colors.onSurface
                                            : colors.onSurfaceVariant,
                                        fontWeight: selected == i
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
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
    );
  }
}

class StateBanner extends StatelessWidget {
  const StateBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.accent = Accent.yellow,
  });
  final String message;
  final IconData icon;
  final Accent accent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: UsTokens.s16),
    child: TintedTile(
      accent: accent,
      padding: const EdgeInsets.all(UsTokens.s16),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: UsTokens.s12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: UsTokens.s400),
    child: const GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowerBadge(
            icon: Icons.auto_awesome_rounded,
            accent: Accent.lavender,
          ),
          SizedBox(height: UsTokens.s24),
          ShimmerBox(height: UsTokens.s24),
          SizedBox(height: UsTokens.s16),
          ShimmerBox(height: UsTokens.s80),
        ],
      ),
    ),
  );
}

class GlassActionButton extends StatelessWidget {
  const GlassActionButton.extended({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });
  final VoidCallback? onPressed;
  final Widget icon, label;
  @override
  Widget build(BuildContext context) => GlassCard(
    blur: true,
    radius: UsTokens.pill,
    padding: const EdgeInsets.all(UsTokens.s4),
    child: ExpressiveButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
    ),
  );
}
