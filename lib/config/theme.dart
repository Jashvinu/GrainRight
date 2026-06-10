import 'package:flutter/material.dart';

class AppTheme {
  static const Color green = Color(0xFF0B5D2A);
  static const Color greenDark = Color(0xFF0C4A24);
  static const Color greenLight = Color(0xFF4CAF50);
  static const Color gold = Color(0xFFCDA434);
  static const Color earth = Color(0xFF7A5230);
  static const Color greenPale = Color(0xFFEEF7ED);
  static const Color surface = Color(0xFFFAF7F0);
  static const Color textDark = Color(0xFF1B231B);
  static const Color textMuted = Color(0xFF667066);
  static const Color error = Color(0xFFB91C1C);

  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 24;
  static const double radiusXl = 32;

  static ThemeData get theme => ThemeData(
    fontFamily: 'Inter',
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      primary: green,
      secondary: greenLight,
      tertiary: gold,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: textDark,
      error: error,
    ),
    scaffoldBackgroundColor: surface,
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE4E9E0),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: greenDark,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: greenDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      iconTheme: MaterialStateProperty.resolveWith(
        (states) => const IconThemeData(size: 22),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: Colors.white,
      indicatorColor: greenPale,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white,
      useIndicator: true,
      indicatorShape: StadiumBorder(),
      labelType: NavigationRailLabelType.all,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: green,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        minimumSize: const Size(160, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: green,
        side: const BorderSide(color: Color(0xFFD9E8D6)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: Color(0xFFE5ECE2)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(160, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: green,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: Color(0xFFD9E0D6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: Color(0xFFD9E0D6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: green, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
      labelStyle: const TextStyle(color: textMuted, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: green),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE2E7DC)),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: greenDark,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: greenPale,
      selectedColor: green,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      side: const BorderSide(color: Color(0xFFD9E8D6)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
      showCheckmark: false,
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.white),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      backgroundColor: Colors.white,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: textDark,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.3,
      ),
      headlineMedium: TextStyle(
        color: textDark,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: textDark,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: textDark, fontSize: 16),
      bodyMedium: TextStyle(color: textDark),
      labelLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: TextStyle(color: textDark, fontWeight: FontWeight.w600),
    ),
  );
}
