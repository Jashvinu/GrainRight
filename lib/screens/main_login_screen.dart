import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/farm_hills_background.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';

class MainLoginScreen extends StatefulWidget {
  const MainLoginScreen({super.key});

  @override
  State<MainLoginScreen> createState() => _MainLoginScreenState();
}

class _MainLoginScreenState extends State<MainLoginScreen> {
  String? _activeRole;

  Future<void> _continueAnonymously(
    String role, {
    String nextRoute = '/home',
  }) async {
    final auth = Get.find<MainAuthController>();
    setState(() => _activeRole = role);
    await auth.continueAsGuest(nextRoute: nextRoute);
    if (mounted) setState(() => _activeRole = null);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeArea = MediaQuery.paddingOf(context);
    final minHeight = screenHeight - safeArea.top - safeArea.bottom;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _RoleSelectionBackground()),
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 188),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Obx(() {
                          final language = Get.find<LanguageController>();
                          return LanguageSelectorButton(
                            code: language.language.value,
                            onChanged: language.setLanguage,
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      const _AnimatedEntrance(delay: 0, child: _BrandHeader()),
                      const SizedBox(height: 26),
                      Text(
                        UiStrings.t('welcome'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        UiStrings.t('choose_continue'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _AnimatedEntrance(
                        delay: 90,
                        child: _RoleCard(
                          icon: Icons.agriculture_outlined,
                          title: UiStrings.t('role_farmer'),
                          subtitle: UiStrings.t('role_farmer_sub'),
                          color: const Color(0xFF0B7A3B),
                          tint: const Color(0xFFE8F5E9),
                          isDisabled: false,
                          onTap: () => Get.toNamed('/farmer/login'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AnimatedEntrance(
                        delay: 160,
                        child: _RoleCard(
                          icon: Icons.groups_2_outlined,
                          title: UiStrings.t('role_fpo'),
                          subtitle: UiStrings.t('role_fpo_sub'),
                          color: const Color(0xFF1976D2),
                          tint: const Color(0xFFE3F2FD),
                          isDisabled: false,
                          onTap: () => Get.toNamed('/fpc/login'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AnimatedEntrance(
                        delay: 230,
                        child: _RoleCard(
                          icon: Icons.admin_panel_settings_outlined,
                          title: UiStrings.t('role_admin'),
                          subtitle: UiStrings.t('role_admin_sub'),
                          color: const Color(0xFF673AB7),
                          tint: const Color(0xFFF1E8FF),
                          isDisabled: false,
                          onTap: () => Get.toNamed('/satellite/login'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AnimatedEntrance(
                        delay: 300,
                        child: _RoleCard(
                          icon: Icons.handshake_outlined,
                          title: UiStrings.t('role_stakeholder'),
                          subtitle: UiStrings.t('role_stakeholder_sub'),
                          color: const Color(0xFF00897B),
                          tint: const Color(0xFFE0F2F1),
                          isDisabled: false,
                          onTap: () => Get.toNamed('/stakeholder/login'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _DividerLabel(label: UiStrings.t('or')),
                      const SizedBox(height: 24),
                      Obx(
                        () => _AnimatedEntrance(
                          delay: 370,
                          child: _RoleCard(
                            icon: Icons.person_outline_rounded,
                            title: UiStrings.t('guest'),
                            subtitle: UiStrings.t('guest_sub'),
                            color: const Color(0xFFB8860B),
                            tint: const Color(0xFFFFF8E1),
                            isLoading:
                                auth.isLoading.value && _activeRole == 'guest',
                            isDisabled: auth.isLoading.value,
                            onTap: () => _continueAnonymously('guest'),
                          ),
                        ),
                      ),
                      Obx(
                        () => auth.errorMessage.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  auth.errorMessage.value,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 28),
                      const _SecurityStrip(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 680),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.green.withValues(alpha: 0.20),
                  blurRadius: 34,
                  spreadRadius: 2,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                BrandAssets.logo,
                width: 292,
                height: 164,
                cacheWidth: (292 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 74,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.green.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSelectionBackground extends StatelessWidget {
  const _RoleSelectionBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF7FBF5), Color(0xFFEAF5E7), Color(0xFFFDFCF6)],
              stops: [0, 0.58, 1],
            ),
          ),
        ),
        Positioned(
          top: 18,
          right: -68,
          child: _SoftCircle(
            size: 180,
            color: AppTheme.green.withValues(alpha: 0.08),
          ),
        ),
        Positioned(
          top: 150,
          left: -72,
          child: _SoftCircle(
            size: 150,
            color: const Color(0xFFF9A825).withValues(alpha: 0.09),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 230,
          child: IgnorePointer(child: FarmHillsBackground()),
        ),
      ],
    );
  }
}

class _SoftCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _SoftCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _AnimatedEntrance extends StatelessWidget {
  final int delay;
  final Widget child;

  const _AnimatedEntrance({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color tint;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tint,
    required this.onTap,
    this.isLoading = false,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.54 : 1,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDisabled ? 0.02 : 0.05),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            onTap: isDisabled ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    alignment: Alignment.center,
                    child: isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: color,
                            ),
                          )
                        : Icon(icon, color: color, size: 42),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: color,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    isDisabled
                        ? Icons.lock_outline_rounded
                        : Icons.chevron_right_rounded,
                    color: color,
                    size: 32,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  final String label;

  const _DividerLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
      ],
    );
  }
}

class _SecurityStrip extends StatelessWidget {
  const _SecurityStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.verified_user_rounded,
          color: Color(0xFF52B788),
          size: 22,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            UiStrings.t('data_safe'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
