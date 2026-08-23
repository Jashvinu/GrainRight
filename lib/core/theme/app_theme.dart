import 'package:flutter/material.dart';

class AppTheme {
  // Earthy premium brand palette. Status colours remain semantic so a
  // weather or disease warning is never confused with a decorative accent.
  static const Color green = Color(0xFF4F6A3A);
  static const Color greenDark = Color(0xFF2F4930);
  static const Color greenLight = Color(0xFF8AA565);
  static const Color gold = Color(0xFFC38B3A);
  static const Color earth = Color(0xFFA96845);
  static const Color greenPale = Color(0xFFF0F3E7);
  static const Color surface = Color(0xFFFAF6EC);
  static const Color surfaceWarm = Color(0xFFF4EBDD);
  static const Color surfaceElevated = Color(0xFFFFFDF8);
  static const Color textDark = Color(0xFF2A3027);
  static const Color textMuted = Color(0xFF6F7568);
  static const Color border = Color(0xFFE4DDCE);

  static const Color weather = Color(0xFF327D85);
  static const Color weatherPale = Color(0xFFE7F3F1);
  static const Color warning = Color(0xFFB97820);
  static const Color warningPale = Color(0xFFFFF1D8);
  static const Color danger = Color(0xFFB64A3D);
  static const Color dangerPale = Color(0xFFFBE9E5);
  static const Color monitoring = Color(0xFF76558F);
  static const Color monitoringPale = Color(0xFFF1EAF6);
  static const Color success = Color(0xFF547E46);
  static const Color successPale = Color(0xFFEAF2E6);
  static const Color error = danger;

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
      secondary: earth,
      tertiary: weather,
      surface: surfaceElevated,
      onPrimary: Colors.white,
      onSurface: textDark,
      error: error,
    ),
    scaffoldBackgroundColor: surface,
    cardColor: surfaceElevated,
    dividerColor: border,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: greenDark,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      toolbarHeight: 66,
      titleTextStyle: TextStyle(
        color: greenDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => const IconThemeData(size: 22),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: surfaceElevated,
      indicatorColor: greenPale,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: surfaceElevated,
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
      color: surfaceElevated,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: border),
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
      fillColor: surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: border),
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
    dividerTheme: const DividerThemeData(color: border),
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
      // Explicit colors: without them M3 falls back to labelLarge (white),
      // which renders invisibly on the pale chip background (e.g. the add-farm
      // answer chips). Unselected = dark text; selected (green fill) = white.
      labelStyle: const TextStyle(color: textDark, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: Color(0xFFD5DDC8)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
      showCheckmark: false,
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surfaceElevated),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      backgroundColor: surfaceElevated,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: textDark,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: textDark,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(color: textDark, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: textDark, fontSize: 16),
      bodyMedium: TextStyle(color: textDark),
      labelLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: textDark, fontWeight: FontWeight.w600),
    ),
  );
}
