import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/brand_text.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Image.asset(
                    BrandAssets.logo,
                    width: 40,
                    height: 40,
                    cacheWidth: 120,
                  ),
                  const SizedBox(width: 10),
                  const BrandText(fontSize: 22),
                  const Spacer(),
                  AppBackButton(onPressed: () => Get.offAllNamed('/login')),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Kalsubai Farms Platform',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 48),
              Text(
                'Choose a module',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),
              _ModuleCard(
                icon: Icons.assignment_outlined,
                title: 'Survey Form',
                subtitle: 'Collect farmer baseline data',
                color: AppTheme.green,
                onTap: () => Get.toNamed('/surveys'),
              ),
              // Satellite module disabled for now
              // const SizedBox(height: 14),
              // _ModuleCard(
              //   icon: Icons.satellite_alt_outlined,
              //   title: 'Satellite Monitoring',
              //   ...
              // ),
              const Spacer(),
              Center(
                child: Text(
                  'Kalsubai Farms',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
