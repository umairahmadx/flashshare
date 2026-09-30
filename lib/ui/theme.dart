import 'package:flutter/material.dart';

/// Single source of color truth for the app. No widget outside this file may
/// contain a raw color literal (Colors.x / Color(0x…) / 0xFF…).
///
/// The identity is monochrome: near-black ink on paper in light mode, AMOLED
/// black with white ink in dark mode. Brightness-aware roles reach widgets
/// through [InkPalette] so no widget has to branch on brightness.
class AppColors {
  // ── Neutrals: light ────────────────────────────────────────────────────
  static const Color bgLight = Color(0xFFFAFAFA);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color raisedLight = Color(0xFFF1F1F1);
  static const Color lineLight = Color(0xFFE0E0E0);
  static const Color lineSoftLight = Color(0xFFEDEDED);
  static const Color inkLight = Color(0xFF0A0A0A);
  static const Color mutedLight = Color(0xFF6E6E6E);
  static const Color faintLight = Color(0xFF9B9B9B);
  static const Color tileBgLight = Color(0xFF161616);

  // ── Neutrals: dark (AMOLED — pure black base so cards read as raised) ──
  static const Color bgDark = Color(0xFF000000);
  static const Color cardDark = Color(0xFF0E0E0E);
  static const Color raisedDark = Color(0xFF171717);
  static const Color lineDark = Color(0xFF282828);
  static const Color lineSoftDark = Color(0xFF1C1C1C);
  static const Color inkDark = Color(0xFFF2F2F2);
  static const Color mutedDark = Color(0xFF9A9A9A);
  static const Color faintDark = Color(0xFF6B6B6B);
  static const Color tileBgDark = Color(0xFF1A1A1A);

  // ── Fixed pair (no brightness dependency) ──────────────────────────────
  /// Icon color on solid tiles / filled pills.
  static const Color onTile = Color(0xFFFFFFFF);

  /// Fully transparent (theme-neutral, kept here so no widget needs
  /// Colors.transparent).
  static const Color transparent = Color(0x00000000);

  /// The brand mark. Monochrome identity: the bolt is ink, never colored.
  static const Color brand = Color(0xFF0A0A0A);

  /// The single accent — paper-white, reserved for filled pills in dark mode
  /// and anything that must read as "the primary action".
  static const Color accentLight = Color(0xFFF2F2F2);

  // ── Status (the only hues in the app, kept deliberately muted) ─────────
  static const Color dangerLight = Color(0xFFB3261E);
  static const Color dangerDark = Color(0xFFFF6B6B);
  static const Color warning = Color(0xFFB26A00);
  static const Color warningDark = Color(0xFFE9A23B);

  // ── File-type icons ────────────────────────────────────────────────────
  // The UI is monochrome: every tile is filled with the same neutral surface,
  // so this map exists to pick the ICON. The tint is retained because the log
  // screen and option rows still ask for a per-type color.
  static const Map<String, ({IconData icon, Color color})> fileCategories = {
    'image': (icon: Icons.image, color: Color(0xFF9C27B0)), // purple
    'video': (icon: Icons.movie, color: Color(0xFFE53935)), // red
    'audio': (icon: Icons.music_note, color: Color(0xFFEC407A)), // pink
    'pdf': (icon: Icons.picture_as_pdf, color: Color(0xFFEF5350)), // redAccent
    'doc': (icon: Icons.description, color: Color(0xFF1E88E5)), // blue
    'sheet': (icon: Icons.table_chart, color: Color(0xFF43A047)), // green
    'slide': (icon: Icons.slideshow, color: Color(0xFFF4511E)), // deepOrange
    'archive': (icon: Icons.archive, color: Color(0xFF6D4C41)), // brown
    'text': (icon: Icons.article, color: Color(0xFF26A69A)), // teal
    'app': (icon: Icons.apps, color: Color(0xFF3949AB)), // indigo
    'default': (icon: Icons.insert_drive_file, color: Color(0xFF607D8B)), // blueGrey
  };

  static const Color collection = Color(0xFFFFB300); // amber

  // QR codes must stay black-on-white to remain machine-scannable; these are
  // fixed physical colors, not theme colors, but live here per the
  // single-source rule.
  static const Color qrForeground = Color(0xFF000000); // black
  static const Color qrBackground = Color(0xFFFFFFFF); // white
}

/// Brightness-aware ink roles delivered through `Theme.of(context)`.
///
/// Read with [InkPalette.of], which falls back to a sensible default when a
/// widget is pumped under a bare `MaterialApp` (as tests do) instead of
/// throwing on a missing extension.
@immutable
class InkPalette extends ThemeExtension<InkPalette> {
  const InkPalette({
    required this.bg,
    required this.card,
    required this.raised,
    required this.line,
    required this.lineSoft,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.tileBg,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.warn,
    required this.shadow,
  });

  final Color bg;
  final Color card;
  final Color raised;
  final Color line;
  final Color lineSoft;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color tileBg;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color warn;
  final Color shadow;

  static const InkPalette light = InkPalette(
    bg: AppColors.bgLight,
    card: AppColors.cardLight,
    raised: AppColors.raisedLight,
    line: AppColors.lineLight,
    lineSoft: AppColors.lineSoftLight,
    ink: AppColors.inkLight,
    muted: AppColors.mutedLight,
    faint: AppColors.faintLight,
    tileBg: AppColors.tileBgLight,
    accent: AppColors.inkLight,
    onAccent: AppColors.onTile,
    danger: AppColors.dangerLight,
    warn: AppColors.warning,
    shadow: AppColors.inkLight,
  );

  static const InkPalette dark = InkPalette(
    bg: AppColors.bgDark,
    card: AppColors.cardDark,
    raised: AppColors.raisedDark,
    line: AppColors.lineDark,
    lineSoft: AppColors.lineSoftDark,
    ink: AppColors.inkDark,
    muted: AppColors.mutedDark,
    faint: AppColors.faintDark,
    tileBg: AppColors.tileBgDark,
    accent: AppColors.accentLight,
    onAccent: AppColors.brand,
    danger: AppColors.dangerDark,
    warn: AppColors.warningDark,
    shadow: AppColors.bgDark,
  );

  /// Safe accessor — never null, safe under a default theme in widget tests.
  static InkPalette of(BuildContext context) =>
      Theme.of(context).extension<InkPalette>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? InkPalette.dark
          : InkPalette.light);

  @override
  InkPalette copyWith({
    Color? bg,
    Color? card,
    Color? raised,
    Color? line,
    Color? lineSoft,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? tileBg,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? warn,
    Color? shadow,
  }) =>
      InkPalette(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        raised: raised ?? this.raised,
        line: line ?? this.line,
        lineSoft: lineSoft ?? this.lineSoft,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        faint: faint ?? this.faint,
        tileBg: tileBg ?? this.tileBg,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        danger: danger ?? this.danger,
        warn: warn ?? this.warn,
        shadow: shadow ?? this.shadow,
      );

  @override
  InkPalette lerp(ThemeExtension<InkPalette>? other, double t) {
    if (other is! InkPalette) return this;
    Color m(Color a, Color b) => Color.lerp(a, b, t)!;
    return InkPalette(
      bg: m(bg, other.bg),
      card: m(card, other.card),
      raised: m(raised, other.raised),
      line: m(line, other.line),
      lineSoft: m(lineSoft, other.lineSoft),
      ink: m(ink, other.ink),
      muted: m(muted, other.muted),
      faint: m(faint, other.faint),
      tileBg: m(tileBg, other.tileBg),
      accent: m(accent, other.accent),
      onAccent: m(onAccent, other.onAccent),
      danger: m(danger, other.danger),
      warn: m(warn, other.warn),
      shadow: m(shadow, other.shadow),
    );
  }
}

/// Corner-radius tokens from the reference design — one place to tune.
class AppRadius {
  static const double hero = 28; // hero / drop-zone card
  static const double card = 22; // list cards, bottom sheets, dialogs
  static const double tile = 14; // thumbnails / icon tiles
  static const double field = 14; // inputs, chips, small buttons
  static const double button = 14; // regular buttons
  static const double pill = 100; // stadium pills (tabs, pill buttons)
}

/// Layout rhythm from the reference: 20px gutters, 12px steps.
class AppSpacing {
  static const double gutter = 20;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double xl = 28;
}

/// Typography helpers. The reference labels everything structural in
/// uppercase, letter-spaced micro-type — one helper so every screen agrees.
class AppText {
  static const TextStyle microLabel = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    height: 1.2,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle metric = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
  );
}

/// Monochrome theme: ink-on-paper in light, AMOLED black in dark.
///
/// The [ColorScheme] is built by hand rather than from a seed color, because a
/// seeded scheme reintroduces chroma everywhere (ripples, chips, indicators)
/// and the whole point of this identity is that nothing is colored.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final ink = isDark ? InkPalette.dark : InkPalette.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink.accent,
    onPrimary: ink.onAccent,
    secondary: ink.ink,
    onSecondary: ink.card,
    error: ink.danger,
    onError: AppColors.onTile,
    surface: ink.bg,
    onSurface: ink.ink,
    surfaceContainer: ink.card,
    onSurfaceVariant: ink.muted,
    outline: ink.line,
    outlineVariant: ink.lineSoft,
    shadow: ink.shadow,
    scrim: ink.shadow,
    inverseSurface: ink.ink,
    onInverseSurface: ink.card,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: ink.bg,
    extensions: <ThemeExtension<dynamic>>[ink],

    appBarTheme: AppBarTheme(
      backgroundColor: ink.bg,
      foregroundColor: ink.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: ink.ink,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: ink.card,
      shadowColor: AppColors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: ink.line),
      ),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        backgroundColor: ink.accent,
        foregroundColor: ink.onAccent,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        side: BorderSide(color: ink.line),
        foregroundColor: ink.ink,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink.ink),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: ink.card,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card)),
      elevation: 0,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: ink.card,
      surfaceTintColor: AppColors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.card + 6)),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ink.raised,
      hintStyle: TextStyle(color: ink.faint),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: ink.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: ink.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: BorderSide(color: ink.ink, width: 1.5),
      ),
    ),

    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
      titleLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}

