import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/language_controller.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';
import '../../widgets/farm_hills_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Get.find<AuthController>().login(_emailCtrl.text.trim(), _passCtrl.text);
  }

  void _goBack() {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back();
      return;
    }
    Get.offAllNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final language = Get.find<LanguageController>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeArea = MediaQuery.paddingOf(context);
    final minHeight = screenHeight - safeArea.top - safeArea.bottom;

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
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 180),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              AppBackButton(onPressed: _goBack),
                              const Spacer(),
                              Obx(() {
                                final code = language.language.value;
                                return LanguageSelectorButton(
                                  code: code,
                                  onChanged: language.setLanguage,
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _AuthHeader(
                            icon: Icons.admin_panel_settings_outlined,
                            title: UiStrings.t('admin_login'),
                            subtitle: UiStrings.t(
                              'sign_in_satellite_monitoring',
                            ),
                          ),
                          const SizedBox(height: 42),
                          _FormCard(
                            children: [
                              Text(
                                UiStrings.t('email_address'),
                                style: const TextStyle(
                                  color: AppTheme.green,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  hintText: UiStrings.t('enter_email_address'),
                                  prefixIcon: const Icon(Icons.email_outlined),
                                ),
                                validator: (v) => (v?.contains('@') ?? false)
                                    ? null
                                    : UiStrings.t('enter_valid_email'),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                UiStrings.t('password'),
                                style: const TextStyle(
                                  color: AppTheme.green,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  hintText: UiStrings.t('enter_password'),
                                  prefixIcon: const Icon(Icons.lock_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v?.length ?? 0) >= 6
                                    ? null
                                    : UiStrings.t('password_too_short'),
                              ),
                              Obx(
                                () => auth.errorMessage.isEmpty
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: Text(
                                          auth.errorMessage.value,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          Obx(
                            () => SizedBox(
                              height: 58,
                              child: ElevatedButton(
                                onPressed: auth.isLoading.value
                                    ? null
                                    : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.greenDark,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                ),
                                child: auth.isLoading.value
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            UiStrings.t('sign_in'),
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const _SecureLabel(),
                          const SizedBox(height: 18),
                          _HelpCard(
                            title: UiStrings.t('need_access'),
                            subtitle: UiStrings.t('create_satellite_account'),
                            icon: Icons.person_add_alt_1_outlined,
                            onTap: () => Get.toNamed('/satellite/signup'),
                          ),
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

class _AuthHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AuthHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 156,
          height: 156,
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
                  BrandAssets.kalsubaiFarms,
                  fit: BoxFit.contain,
                  cacheWidth: 320,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(icon, color: AppTheme.greenDark, size: 76);
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 10),
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

class _FormCard extends StatelessWidget {
  final List<Widget> children;

  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3EADD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SecureLabel extends StatelessWidget {
  const _SecureLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppTheme.green),
              const SizedBox(width: 8),
              Text(
                UiStrings.t('secure_private'),
                style: const TextStyle(
                  color: AppTheme.green,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
      ],
    );
  }
}

class _HelpCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _HelpCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.green, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.green,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
