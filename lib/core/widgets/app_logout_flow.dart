import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';

class AppLogoutFlow {
  const AppLogoutFlow._();

  static bool _isRunning = false;

  static Future<void> run(
    BuildContext context, {
    required Future<void> Function() onLogout,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    final navigatorContext = Get.context ?? context;
    unawaited(_showLogoutDialog(navigatorContext));
    await Future<void>.delayed(AppMotion.fast);
    try {
      await onLogout();
    } finally {
      if (Get.isDialogOpen == true) {
        Get.back<void>();
      }
      _isRunning = false;
    }
  }

  static Future<void> _showLogoutDialog(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: UiStrings.t('logout_in_progress'),
      barrierColor: AppTheme.greenDark.withValues(alpha: 0.20),
      transitionDuration: AppMotion.page,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const Center(child: _LogoutProgressCard());
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _LogoutProgressCard extends StatelessWidget {
  const _LogoutProgressCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 236,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFCF5), Colors.white],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: const Color(0xFFDDE8D4)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.greenDark.withValues(alpha: 0.18),
              blurRadius: 34,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.92, end: 1),
              duration: const Duration(milliseconds: 680),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Container(
                width: 84,
                height: 84,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(
                    colors: [
                      AppTheme.greenDark,
                      AppTheme.gold,
                      AppTheme.green,
                      AppTheme.greenDark,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.green.withValues(alpha: 0.16),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppTheme.gold,
                          backgroundColor: AppTheme.greenPale,
                        ),
                      ),
                      ClipOval(
                        child: ColoredBox(
                          color: Colors.white,
                          child: Image.asset(
                            BrandAssets.kalsubaiFarms,
                            width: 44,
                            height: 44,
                            fit: BoxFit.contain,
                            cacheWidth: 96,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.agriculture_rounded,
                                color: AppTheme.greenDark,
                                size: 34,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 56,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              UiStrings.t('logout_in_progress'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
