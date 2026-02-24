import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../widgets/brand_text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    Future.delayed(const Duration(seconds: 2), () => Get.offNamed('/home'));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.green.withValues(alpha: 0.15),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/logo.jpeg', width: 140),
                ),
              ),
              const SizedBox(height: 32),
              const BrandText(fontSize: 32),
              const SizedBox(height: 8),
              Text(
                'MilletsNow',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
