import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../controllers/main_auth_controller.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _rise;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _rise = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
    _routeAfterIntro();
  }

  Future<void> _routeAfterIntro() async {
    final start = DateTime.now();
    final auth = Get.find<MainAuthController>();
    final authenticated = await auth.hasAnySession();
    final user = Supabase.instance.client.auth.currentUser;
    final serverRole = '${user?.appMetadata['role'] ?? ''}'
        .trim()
        .toLowerCase();
    final userRole = '${user?.userMetadata?['role'] ?? ''}'
        .trim()
        .toLowerCase();
    final role = serverRole.isNotEmpty ? serverRole : userRole;
    final isFarmerSession =
        auth.verifiedFarmer.value != null ||
        role == 'farmer' ||
        role == 'verified_farmer';

    if (authenticated && isFarmerSession) {
      unawaited(auth.syncFarmerData(forceRefresh: true, showLoading: false));
    }

    final elapsed = DateTime.now().difference(start).inMilliseconds;
    final remaining = 1450 - elapsed;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }

    if (!mounted) return;

    if (authenticated) {
      if (isFarmerSession) {
        Get.offAllNamed('/farmer');
      } else if (serverRole == 'admin') {
        Get.offAllNamed('/admin');
      } else if ({'fpc', 'fpo', 'fpo_fpc', 'fpo/fpc'}.contains(role)) {
        Get.offAllNamed('/fpo');
      } else {
        Get.offAllNamed('/home');
      }
    } else {
      Get.offNamed('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoWidth = (size.width - 48).clamp(260.0, 560.0).toDouble();
    final logoCacheWidth = (logoWidth * MediaQuery.devicePixelRatioOf(context))
        .clamp(260.0, 720.0)
        .round();

    return Scaffold(
      backgroundColor: const Color(0xFFE7F0E2),
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _rise,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        BrandAssets.kalsubaiFarmsWithTagline,
                        width: logoWidth,
                        cacheWidth: logoCacheWidth,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _LoadingTrack(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingTrack extends StatelessWidget {
  const _LoadingTrack();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1250),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: AppTheme.greenPale,
              color: AppTheme.green,
            ),
          ),
        );
      },
    );
  }
}
