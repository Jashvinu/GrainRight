import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';

import 'bindings/app_bindings.dart';
import 'routes/app_pages.dart';
import '../screens/whatsapp_farm_boundary_screen.dart';
import '../screens/whatsapp_service_screen.dart';

class KalsubaiFarmsApp extends StatelessWidget {
  final Locale initialLocale;
  final bool loadStartupControllers;

  const KalsubaiFarmsApp({
    super.key,
    this.initialLocale = const Locale('en'),
    this.loadStartupControllers = true,
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      onGenerateTitle: (_) => UiStrings.t('kalsubai_farms'),
      theme: AppTheme.theme,
      locale: initialLocale,
      fallbackLocale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('mr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      defaultTransition: Transition.cupertino,
      transitionDuration: AppMotion.page,
      initialBinding: StartupBinding(
        loadStartupControllers: loadStartupControllers,
      ),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
    );
  }
}

class WhatsappBoundaryApp extends StatelessWidget {
  final String token;
  final Locale initialLocale;

  const WhatsappBoundaryApp({
    super.key,
    required this.token,
    this.initialLocale = const Locale('en'),
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'GrainRight Farm Boundary',
      theme: AppTheme.theme,
      locale: initialLocale,
      fallbackLocale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('mr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: WhatsappFarmBoundaryScreen(token: token),
    );
  }
}

class WhatsappServiceApp extends StatelessWidget {
  final String token;
  final Locale initialLocale;

  const WhatsappServiceApp({
    super.key,
    required this.token,
    this.initialLocale = const Locale('en'),
  });

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'GrainRight WhatsApp Service',
      theme: AppTheme.theme,
      locale: initialLocale,
      fallbackLocale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('hi'), Locale('mr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      home: WhatsappServiceScreen(token: token),
    );
  }
}
