import 'package:flutter/material.dart';
import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';

import 'farm_hills_background.dart';

class RoleLoginShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onBack;
  final Widget form;
  final Widget action;
  final Widget? info;
  final Widget? error;
  final IconData fallbackIcon;
  final String avatarAsset;

  const RoleLoginShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.languageCode,
    required this.onLanguageChanged,
    required this.onBack,
    required this.form,
    required this.action,
    this.info,
    this.error,
    this.fallbackIcon = Icons.verified_user_outlined,
    this.avatarAsset = BrandAssets.kalsubaiFarms,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final horizontalPadding = compact ? 18.0 : 24.0;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFCF5), AppTheme.surface],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 170,
                child: IgnorePointer(child: FarmHillsBackground()),
              ),
              SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  (compact ? 136 : 166) + bottomInset,
                ),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: AppMotion.page,
                    curve: AppMotion.emphasized,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 16),
                          child: child,
                        ),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              AppBackButton(onPressed: onBack),
                              const Spacer(),
                              LanguageSelectorButton(
                                code: languageCode,
                                onChanged: onLanguageChanged,
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 16 : 20),
                          _RoleLoginHeader(
                            title: title,
                            subtitle: subtitle,
                            compact: compact,
                            fallbackIcon: fallbackIcon,
                            avatarAsset: avatarAsset,
                          ),
                          SizedBox(height: compact ? 18 : 22),
                          if (info != null) ...[
                            info!,
                            const SizedBox(height: 14),
                          ],
                          RoleLoginCard(child: form),
                          const SizedBox(height: 18),
                          action,
                          if (error != null) ...[
                            const SizedBox(height: 12),
                            error!,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleLoginCard extends StatelessWidget {
  final Widget child;

  const RoleLoginCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE3EADD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class RoleLoginInfoStrip extends StatelessWidget {
  final IconData icon;
  final String text;

  const RoleLoginInfoStrip({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3EADD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textMuted,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RoleLoginErrorText extends StatelessWidget {
  final String message;

  const RoleLoginErrorText({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.red.shade700,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class RoleLoginButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  final String label;
  final String loadingLabel;

  const RoleLoginButton({
    super.key,
    required this.loading,
    required this.onPressed,
    required this.label,
    required this.loadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.2,
                ),
              )
            : const Icon(Icons.arrow_forward_rounded),
        label: Text(loading ? loadingLabel : label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.greenDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _RoleLoginHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool compact;
  final IconData fallbackIcon;
  final String avatarAsset;

  const _RoleLoginHeader({
    required this.title,
    required this.subtitle,
    required this.compact,
    required this.fallbackIcon,
    required this.avatarAsset,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 124.0 : 156.0;
    return Column(
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
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
                color: AppTheme.green.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: ColoredBox(
                color: Colors.white,
                child: Image.asset(
                  avatarAsset,
                  fit: BoxFit.contain,
                  cacheWidth: 320,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      fallbackIcon,
                      color: AppTheme.greenDark,
                      size: 76,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 12 : 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.greenDark,
            fontSize: compact ? 30 : 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
