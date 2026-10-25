import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Presentation capabilities only. No account, database or preference changes.
class VisualCapabilities {
  static int sdk = 24;
  static Color? seed;
  static Future<void> initialize() async {
    try {
      final values = await const MethodChannel(
        'us/presentation',
      ).invokeMapMethod<String, dynamic>('capabilities');
      sdk = values?['sdk'] as int? ?? 24;
      final value = values?['seed'] as int?;
      if (value != null) seed = Color(value);
    } on PlatformException {
      /* Use the bundled palette. */
    } catch (_) {
      /* Tests and older platforms use the graceful fallback. */
    }
  }
}

enum Accent { yellow, green, pink, blue, lavender, coral }

abstract final class UsColors {
  static const ink = Color(0xff202539),
      night = Color(0xff14121b),
      paper = Color(0xfff8f6f0);
  static const white = Color(0xffffffff),
      clear = Color(0x00000000),
      danger = Color(0xffba3547);
  static const yellow = Color(0xffffdf85),
      green = Color(0xffc7ebca),
      pink = Color(0xffffcbdc),
      blue = Color(0xffc5e8ff),
      lavender = Color(0xffdbd0ff),
      coral = Color(0xffffc6b7);
  static const yellowInk = Color(0xff66501a),
      greenInk = Color(0xff285b3b),
      pinkInk = Color(0xff873d5c),
      blueInk = Color(0xff285878),
      lavenderInk = Color(0xff584184),
      coralInk = Color(0xff8a493a);
  static Color tint(Accent accent, bool dark) =>
      (dark ? _deep : _light)[accent.index];
  static Color foreground(Accent accent, bool dark) =>
      dark ? _light[accent.index] : _strong[accent.index];
  static const _light = [yellow, green, pink, blue, lavender, coral];
  static const _strong = [
    yellowInk,
    greenInk,
    pinkInk,
    blueInk,
    lavenderInk,
    coralInk,
  ];
  static const _deep = [
    Color(0xff3e3422),
    Color(0xff243b2d),
    Color(0xff43283a),
    Color(0xff243547),
    Color(0xff352a48),
    Color(0xff442e29),
  ];
}

/// All geometry, typography and motion values live here, on a 4dp spacing grid.
abstract final class UsTokens {
  static const s0 = 0.0,
      s4 = 4.0,
      s8 = 8.0,
      s12 = 12.0,
      s16 = 16.0,
      s20 = 20.0,
      s24 = 24.0,
      s28 = 28.0,
      s32 = 32.0,
      s36 = 36.0,
      s40 = 40.0,
      s44 = 44.0,
      s48 = 48.0,
      s52 = 52.0,
      s56 = 56.0,
      s60 = 60.0,
      s64 = 64.0,
      s68 = 68.0,
      s72 = 72.0,
      s80 = 80.0,
      s88 = 88.0,
      s96 = 96.0,
      s104 = 104.0,
      s112 = 112.0,
      s120 = 120.0,
      s128 = 128.0,
      s144 = 144.0,
      s152 = 152.0,
      s160 = 160.0,
      s176 = 176.0,
      s180 = 180.0,
      s192 = 192.0,
      s200 = 200.0,
      s208 = 208.0,
      s220 = 220.0,
      s224 = 224.0,
      s240 = 240.0,
      s256 = 256.0,
      s264 = 264.0,
      s280 = 280.0,
      s300 = 300.0,
      s320 = 320.0,
      s336 = 336.0,
      s360 = 360.0,
      s400 = 400.0,
      s440 = 440.0,
      s480 = 480.0;
  static const font10 = 10.0,
      font12 = 12.0,
      font14 = 14.0,
      font18 = 18.0,
      font22 = 22.0,
      font26 = 26.0,
      font34 = 34.0;
  static const previewDecode = 960;
  static const navMaxWidth = 560.0;
  static const card = 32.0,
      pill = 999.0,
      blur = 24.0,
      border = 1.0,
      shadow = 28.0,
      photoDecode = 1080;
  static const fast = 160, interaction = 380, entrance = 560, stagger = 45;
  static const page = EdgeInsetsDirectional.fromSTEB(s20, s16, s20, s32);
  static const gap = SizedBox(height: s16);
}

@immutable
class FeatureStyle extends ThemeExtension<FeatureStyle> {
  const FeatureStyle(this.accent);
  final Accent accent;
  static Accent of(BuildContext context) =>
      Theme.of(context).extension<FeatureStyle>()?.accent ?? Accent.lavender;
  @override
  FeatureStyle copyWith({Accent? accent}) =>
      FeatureStyle(accent ?? this.accent);
  @override
  FeatureStyle lerp(covariant FeatureStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

class FeatureScope extends StatelessWidget {
  const FeatureScope({super.key, required this.accent, required this.child});
  final Accent accent;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), dark = theme.brightness == Brightness.dark;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: UsColors.foreground(accent, dark),
          primaryContainer: UsColors.tint(accent, dark),
          onPrimary: dark ? UsColors.ink : UsColors.white,
          onPrimaryContainer: dark ? UsColors.white : UsColors.ink,
        ),
        extensions: [FeatureStyle(accent)],
      ),
      child: child,
    );
  }
}

ThemeData usTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: VisualCapabilities.seed ?? UsColors.lavenderInk,
        brightness: brightness,
      ).copyWith(
        surface: dark ? UsColors.night : UsColors.paper,
        surfaceContainerLowest: dark
            ? const Color(0xff100f15)
            : const Color(0xffffffff),
        surfaceContainer: dark
            ? const Color(0xff25222e)
            : const Color(0xfff1eef5),
        surfaceContainerHighest: dark
            ? const Color(0xff393340)
            : const Color(0xffe5e1eb),
        outline: dark ? const Color(0xff9d94ab) : const Color(0xff787080),
        outlineVariant: dark
            ? const Color(0xff4d4459)
            : const Color(0xffcdc5d3),
        primary: dark ? UsColors.lavender : UsColors.lavenderInk,
        onPrimary: dark ? const Color(0xff302047) : UsColors.white,
        primaryContainer: dark ? const Color(0xff413054) : UsColors.lavender,
        onPrimaryContainer: dark
            ? const Color(0xffecdcff)
            : const Color(0xff302047),
        onSurface: dark ? const Color(0xfff5f4fb) : UsColors.ink,
        onSurfaceVariant: dark
            ? const Color(0xffd0c5dc)
            : const Color(0xff52596a),
        surfaceContainerLow: dark
            ? const Color(0xff201d28)
            : const Color(0xfffcfaf5),
        surfaceContainerHigh: dark
            ? const Color(0xff302b39)
            : const Color(0xffedeaf4),
        error: dark ? const Color(0xffffb3bd) : UsColors.danger,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: 'Outfit',
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(UsTokens.card),
    side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
  );
  TextStyle type(
    double size,
    FontWeight weight, {
    double height = 1.2,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: 'Outfit',
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: spacing,
    color: colors.onSurface,
  );
  return base.copyWith(
    scaffoldBackgroundColor: UsColors.clear,
    extensions: [const FeatureStyle(Accent.lavender)],
    textTheme: base.textTheme.copyWith(
      displayLarge: type(72, FontWeight.w800, spacing: -3),
      displayMedium: type(56, FontWeight.w800, spacing: -2),
      displaySmall: type(44, FontWeight.w800, spacing: -1.5),
      headlineLarge: type(36, FontWeight.w800, spacing: -1.2),
      headlineMedium: type(28, FontWeight.w800, spacing: -.8),
      headlineSmall: type(24, FontWeight.w700, spacing: -.5),
      titleLarge: type(20, FontWeight.w700),
      titleMedium: type(16, FontWeight.w600),
      bodyLarge: type(16, FontWeight.w400, height: 1.5),
      bodyMedium: type(14, FontWeight.w400, height: 1.5),
      labelLarge: type(14, FontWeight.w700),
      labelSmall: type(12, FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: UsColors.clear,
      surfaceTintColor: UsColors.clear,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle:
          (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: UsColors.clear,
                systemNavigationBarColor: UsColors.clear,
              ),
      toolbarHeight: UsTokens.s64,
      centerTitle: false,
      titleSpacing: UsTokens.s20,
      titleTextStyle: type(18, FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: UsTokens.s12),
      shape: shape,
      color: colors.surfaceContainerLow.withValues(alpha: .90),
      surfaceTintColor: UsColors.clear,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? UsColors.lavender : UsColors.ink,
        foregroundColor: dark ? UsColors.ink : UsColors.white,
        minimumSize: const Size(UsTokens.s48, UsTokens.s56),
        padding: const EdgeInsets.symmetric(
          horizontal: UsTokens.s24,
          vertical: UsTokens.s16,
        ),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(UsTokens.s48, UsTokens.s52),
        shape: const StadiumBorder(),
        side: BorderSide(color: colors.outlineVariant),
        backgroundColor: colors.surface.withValues(alpha: .45),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.onSurface,
        minimumSize: const Size(UsTokens.s48, UsTokens.s48),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(UsTokens.s48, UsTokens.s48),
        padding: const EdgeInsets.all(UsTokens.s12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow.withValues(alpha: .85),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UsTokens.s24),
        borderSide: BorderSide(
          color: colors.outlineVariant.withValues(alpha: .5),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UsTokens.s24),
        borderSide: BorderSide(
          color: colors.outlineVariant.withValues(alpha: .5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UsTokens.s24),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(UsTokens.s20),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
      backgroundColor: colors.surfaceContainerLow.withValues(alpha: .72),
      selectedColor: colors.primaryContainer,
      shape: const StadiumBorder(),
      labelStyle: type(14, FontWeight.w600),
      padding: const EdgeInsets.symmetric(
        horizontal: UsTokens.s12,
        vertical: UsTokens.s8,
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(
        UsTokens.s20,
        UsTokens.s8,
        UsTokens.s16,
        UsTokens.s8,
      ),
      iconColor: colors.primary,
      minVerticalPadding: UsTokens.s12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UsTokens.s24),
      ),
    ),
    // Native sheets need an opaque surface. Glass sheets opt into transparency.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: UsColors.clear,
      showDragHandle: false,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      shape: shape,
      backgroundColor: colors.surfaceContainerLow,
    ),
    datePickerTheme: DatePickerThemeData(
      shape: shape,
      backgroundColor: colors.surfaceContainerLow,
      headerBackgroundColor: colors.primaryContainer,
    ),
    timePickerTheme: TimePickerThemeData(
      shape: shape,
      backgroundColor: colors.surfaceContainerLow,
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UsTokens.s24),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UsTokens.s32),
      ),
      extendedPadding: const EdgeInsets.all(UsTokens.s24),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceContainerLow.withValues(alpha: .98),
      surfaceTintColor: UsColors.clear,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UsTokens.s24),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
      backgroundColor: UsColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: 'Outfit',
        color: UsColors.white,
        fontSize: 14,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant.withValues(alpha: .35),
      space: UsTokens.s32,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
