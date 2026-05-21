import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color background;
  final Color surface;
  final Color field;
  final Color primary;
  final Color onPrimary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color subtleBorder;
  final Color expense;
  final Color transfer;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.field,
    required this.primary,
    required this.onPrimary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.subtleBorder,
    required this.expense,
    required this.transfer,
  });

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? field,
    Color? primary,
    Color? onPrimary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? subtleBorder,
    Color? expense,
    Color? transfer,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      field: field ?? this.field,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      subtleBorder: subtleBorder ?? this.subtleBorder,
      expense: expense ?? this.expense,
      transfer: transfer ?? this.transfer,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      field: Color.lerp(field, other.field, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
    );
  }
}

class AppTheme {
  static const String themeModeKey = 'app_theme_mode';

  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.dark,
  );

  static const AppThemeColors darkColors = AppThemeColors(
    background: Color(0xFF061414),
    surface: Color(0xFF111D1D),
    field: Color(0xFF0B1818),
    primary: Color(0xFF34EAB9),
    onPrimary: Color(0xFF061414),
    textPrimary: Colors.white,
    textSecondary: Color(0xCCFFFFFF),
    textMuted: Color(0xFF8B9494),
    subtleBorder: Color(0x1FFFFFFF),
    expense: Color(0xFFFF6B6B),
    transfer: Color(0xFF3B82F6),
  );

  static const AppThemeColors lightColors = AppThemeColors(
    background: Color(0xFFBDFFDD),
    surface: Color(0xFFF6FFF9),
    field: Color(0xFFE4F9EC),
    primary: Color(0xFF008E73),
    onPrimary: Colors.white,
    textPrimary: Color(0xFF12211F),
    textSecondary: Color(0xFF415451),
    textMuted: Color(0xFF6A7A77),
    subtleBorder: Color(0x1F12211F),
    expense: Color(0xFFD94B4B),
    transfer: Color(0xFF2563EB),
  );

  static bool get isLightMode => themeMode.value == ThemeMode.light;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(themeModeKey);
    themeMode.value = savedMode == 'light' ? ThemeMode.light : ThemeMode.dark;
    await prefs.setString(
      themeModeKey,
      themeMode.value == ThemeMode.light ? 'light' : 'dark',
    );
  }

  static Future<void> setLightMode(bool enabled) async {
    final nextMode = enabled ? ThemeMode.light : ThemeMode.dark;
    if (themeMode.value != nextMode) {
      themeMode.value = nextMode;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModeKey, enabled ? 'light' : 'dark');
  }

  static ThemeData darkTheme = _buildTheme(
    brightness: Brightness.dark,
    colors: darkColors,
  );

  static ThemeData lightTheme = _buildTheme(
    brightness: Brightness.light,
    colors: lightColors,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppThemeColors colors,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: colors.primary,
      brightness: brightness,
      primary: colors.primary,
      surface: colors.surface,
      error: colors.expense,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      primaryColor: colors.primary,
      colorScheme: scheme.copyWith(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: colors.expense,
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.background,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.textMuted,
        type: BottomNavigationBarType.fixed,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.primary
              : colors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.primary.withValues(alpha: 0.32)
              : colors.field;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.field,
        labelStyle: TextStyle(color: colors.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: colors.subtleBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: colors.primary),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontFamily: 'Times New Roman',
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: colors.textPrimary,
        ),
        bodyMedium: TextStyle(color: colors.textPrimary),
        bodySmall: TextStyle(color: colors.textSecondary),
      ),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppThemeColors get themeColors {
    final colors = Theme.of(this).extension<AppThemeColors>();
    return colors ?? AppTheme.darkColors;
  }
}
