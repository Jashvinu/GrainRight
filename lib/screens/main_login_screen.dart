import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/farm_hills_background.dart';

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
      backgroundColor: const Color(0xFFF4FAF2),
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
                      const _AnimatedEntrance(delay: 0, child: _BrandHeader()),
                      const SizedBox(height: 26),
                      const Text(
                        'Welcome!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose how you want to continue',
                        textAlign: TextAlign.center,
                        style: TextStyle(
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
                          title: 'Farmer',
                          subtitle: 'Login with mobile',
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
                          title: 'FPO / FPC',
                          subtitle: 'Access dashboard',
                          color: const Color(0xFF1976D2),
                          tint: const Color(0xFFE3F2FD),
                          isDisabled: false,
                          onTap: () =>
                              _continueAnonymously('fpo', nextRoute: '/fpo'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _AnimatedEntrance(
                        delay: 230,
                        child: _RoleCard(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Admin',
                          subtitle: 'System administration',
                          color: const Color(0xFF673AB7),
                          tint: const Color(0xFFF1E8FF),
                          isDisabled: false,
                          onTap: () => Get.toNamed('/satellite/login'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _DividerLabel(label: 'or'),
                      const SizedBox(height: 24),
                      Obx(
                        () => _AnimatedEntrance(
                          delay: 300,
                          child: _RoleCard(
                            icon: Icons.person_outline_rounded,
                            title: 'Continue as Guest',
                            subtitle: 'Fill survey form only\n(Limited Access)',
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
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            BrandAssets.logo,
            width: 196,
            height: 112,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Farm Intelligence & Traceability',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_rounded, color: Color(0xFF52B788), size: 22),
        SizedBox(width: 10),
        Flexible(
          child: Text(
            'Your data is safe and secure with us',
            textAlign: TextAlign.center,
            style: TextStyle(
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
