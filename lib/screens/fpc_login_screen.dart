import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';

import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/role_login_shell.dart';

class FpcLoginScreen extends StatefulWidget {
  const FpcLoginScreen({super.key});

  @override
  State<FpcLoginScreen> createState() => _FpcLoginScreenState();
}

class _FpcLoginScreenState extends State<FpcLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
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
    await Get.find<MainAuthController>().loginFpc(
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
      nextRoute: '/fpo',
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

    final arguments = Get.arguments;
    final notice = arguments is Map
        ? '${arguments['notice'] ?? ''}'.trim()
        : '';
    return Obx(() {
      return RoleLoginShell(
        dense: true,
        title: UiStrings.t('fpc_login'),
        subtitle: UiStrings.t('fpc_login_desc'),
        languageCode: language.language.value,
        onLanguageChanged: language.setLanguage,
        onBack: _goBack,
        fallbackIcon: Icons.groups_2_outlined,
        info: RoleLoginInfoStrip(
          icon: notice.isEmpty
              ? Icons.verified_user_outlined
              : Icons.info_outline_rounded,
          text: notice.isEmpty ? UiStrings.t('fpc_login_info') : notice,
        ),
        form: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t('email_address'),
                  hintText: UiStrings.t('enter_registered_fpc_email'),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  final valid = RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(text);
                  return valid ? null : UiStrings.t('enter_valid_email');
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
                  hintText: UiStrings.t('enter_fpc_login_password'),
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
            ],
          ),
        ),
        action: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RoleLoginButton(
              loading: auth.isLoading.value,
              onPressed: _submit,
              label: UiStrings.t('login_to_fpc_dashboard'),
              loadingLabel: UiStrings.t('verifying'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: auth.isLoading.value
                  ? null
                  : () => Get.offAllNamed('/fpc/signup'),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(UiStrings.t('create_fpc_account')),
            ),
          ],
        ),
        error: auth.errorMessage.isEmpty
            ? null
            : RoleLoginErrorText(message: auth.errorMessage.value),
      );
    });
  }
}
