import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';

import 'bindings/app_bindings.dart';
import 'routes/app_pages.dart';

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
      title: 'Kalsubai Farms',
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
      initialBinding: StartupBinding(
        loadStartupControllers: loadStartupControllers,
      ),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
    );
  }
}
