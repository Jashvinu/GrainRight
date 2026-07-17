import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../../controllers/auth_controller.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import '../../widgets/farm_hills_background.dart';
import 'auth_alternatives.dart';

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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeArea = MediaQuery.paddingOf(context);
    final minHeight = screenHeight - safeArea.top - safeArea.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFDFB),
      body: SafeArea(
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
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppBackButton(onPressed: _goBack),
                        ),
                        const SizedBox(height: 32),
                        _AuthHeader(
                          icon: Icons.admin_panel_settings_outlined,
                          title: UiStrings.t('admin_login'),
                          subtitle: UiStrings.t('sign_in_satellite_monitoring'),
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
                              onPressed: auth.isLoading.value ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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
                                        const Icon(Icons.arrow_forward_rounded),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _SecureLabel(),
                        const SizedBox(height: 18),
                        const SatelliteAuthAlternatives(
                          phoneNextRoute: '/satellite/shell',
                          googleNextRoute: '/satellite/shell',
                        ),
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
          width: 112,
          height: 112,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppTheme.green, size: 58),
        ),
        const SizedBox(height: 26),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 18,
            height: 1.35,
            fontWeight: FontWeight.w600,
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
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 26,
            offset: const Offset(0, 12),
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
      color: const Color(0xFFF4FAF4),
      borderRadius: BorderRadius.circular(18),
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
