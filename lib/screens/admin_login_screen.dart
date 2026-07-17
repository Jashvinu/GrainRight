import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';

import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/role_login_shell.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(
    text: MainAuthController.adminLoginEmail,
  );
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await Get.find<MainAuthController>().loginAdmin(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Get.back();
    } else {
      Get.offAllNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final language = Get.find<LanguageController>();

    return Obx(() {
      return RoleLoginShell(
        title: UiStrings.t('admin_login'),
        subtitle: UiStrings.t('admin_login_subtitle'),
        languageCode: language.language.value,
        onLanguageChanged: language.setLanguage,
        onBack: _goBack,
        fallbackIcon: Icons.admin_panel_settings_outlined,
        form: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t('admin_email'),
                  hintText: MainAuthController.adminLoginEmail.isNotEmpty
                      ? MainAuthController.adminLoginEmail
                      : UiStrings.t('admin_email_hint'),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                      ? null
                      : UiStrings.t('enter_valid_email');
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: UiStrings.t('password'),
                  hintText: UiStrings.t('enter_password'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? UiStrings.t('show_password')
                        : UiStrings.t('hide_password'),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) => (value?.length ?? 0) >= 6
                    ? null
                    : UiStrings.t('password_min_six_chars'),
              ),
              const SizedBox(height: 14),
              RoleLoginInfoStrip(
                icon: Icons.verified_user_rounded,
                text: UiStrings.t('admin_login_note'),
              ),
            ],
          ),
        ),
        action: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RoleLoginButton(
              loading: auth.isLoading.value,
              onPressed: _submit,
              label: UiStrings.t('admin_login_cta'),
              loadingLabel: UiStrings.t('admin_login_verifying'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: auth.isLoading.value
                  ? null
                  : () => Get.offAllNamed('/admin/signup'),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(UiStrings.t('create_admin_account')),
            ),
          ],
        ),
        error: auth.errorMessage.isEmpty
            ? null
            : RoleLoginErrorText(
                message: UiStrings.authError(auth.errorMessage.value),
              ),
      );
    });
  }
}
