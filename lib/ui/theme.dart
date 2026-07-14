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

  // QR codes must stay black-on-white to remain machine-scannable; these are
  // fixed physical colors, not theme colors, but live here per the single-source rule.
  static const Color qrForeground = Color(0xFF000000); // black
  static const Color qrBackground = Color(0xFFFFFFFF); // white
}

/// Blue primary seed; sophisticated Material 3 theme.
ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    surface: isDark ? const Color(0xFF0F1115) : const Color(0xFFF8F9FE),
    surfaceContainer: isDark ? const Color(0xFF1A1D24) : const Color(0xFFFFFFFF),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.1),
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: scheme.onSurface,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: isDark
            ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      elevation: 0,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.1),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary);
        }
        return IconThemeData(color: scheme.onSurfaceVariant);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected) 
            ? scheme.primary 
            : scheme.onSurfaceVariant;
        return TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.w500,
          color: color,
        );
      }),
    ),
    
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
      titleLarge: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}
