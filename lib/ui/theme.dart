import 'package:flutter/material.dart';

/// Single source of color truth for the app. No widget outside this file may
/// contain a raw color literal (Colors.x / Color(0x…) / 0xFF…). See spec §1b.
class AppColors {
  // Brand accent. Injected into ColorScheme.fromSeed so light+dark derive from it.
  static const Color brand = Color(0xFF1565FF); // blue

  // File-type semantics. Named so widgets never hard-code a Color literal.
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
}

/// Blue primary seed; white surfaces in light, pure AMOLED black in dark.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    // Pure white in light; pure AMOLED black in dark.
    surface: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    onSurface: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF101010),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    appBarTheme: AppBarTheme(
      // White in light, pure black in dark. Icon/text use onSurface.
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: isDark ? 0 : 2,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDark
            ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))
            : BorderSide.none,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 6,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}
