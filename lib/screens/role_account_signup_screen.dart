import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';

import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/role_login_shell.dart';

enum RoleAccountSignupKind { admin, fpc }

class AdminSignupScreen extends StatelessWidget {
  const AdminSignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleAccountSignupScreen(kind: RoleAccountSignupKind.admin);
  }
}

class FpcSignupScreen extends StatelessWidget {
  const FpcSignupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleAccountSignupScreen(kind: RoleAccountSignupKind.fpc);
  }
}

class RoleAccountSignupScreen extends StatefulWidget {
  final RoleAccountSignupKind kind;

  const RoleAccountSignupScreen({super.key, required this.kind});

  @override
  State<RoleAccountSignupScreen> createState() =>
      _RoleAccountSignupScreenState();
}

class _RoleAccountSignupScreenState extends State<RoleAccountSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _organizationCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;

  bool get _isAdmin => widget.kind == RoleAccountSignupKind.admin;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _organizationCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final auth = Get.find<MainAuthController>();
    if (_isAdmin) {
      await auth.signupAdmin(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        displayName: _nameCtrl.text,
        organizationName: _organizationCtrl.text,
        phone: _phoneCtrl.text,
      );
      return;
    }
    await auth.signupFpc(
      email: _emailCtrl.text,
      password: _passwordCtrl.text,
      displayName: _nameCtrl.text,
      organizationName: _organizationCtrl.text,
      phone: _phoneCtrl.text,
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Get.back();
      return;
    }
    Get.offAllNamed(_isAdmin ? '/admin/login' : '/fpc/login');
  }

  String? _required(String? value, String message) {
    return (value ?? '').trim().isEmpty ? message : null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final language = Get.find<LanguageController>();
    final titleKey = _isAdmin ? 'admin_signup' : 'fpc_signup';
    final subtitleKey = _isAdmin
        ? 'admin_signup_subtitle'
        : 'fpc_signup_subtitle';
    final noteKey = _isAdmin ? 'admin_signup_note' : 'fpc_signup_note';
    final organizationKey = _isAdmin ? 'organization_name' : 'fpc_name';
    final loginRoute = _isAdmin ? '/admin/login' : '/fpc/login';

    return Obx(() {
      return RoleLoginShell(
        title: UiStrings.t(titleKey),
        subtitle: UiStrings.t(subtitleKey),
        languageCode: language.language.value,
        onLanguageChanged: language.setLanguage,
        onBack: _goBack,
        fallbackIcon: _isAdmin
            ? Icons.admin_panel_settings_outlined
            : Icons.groups_2_outlined,
        info: RoleLoginInfoStrip(
          icon: Icons.verified_user_outlined,
          text: UiStrings.t(noteKey),
        ),
        form: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t('full_name'),
                  hintText: UiStrings.t('full_name_hint'),
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (value) =>
                    _required(value, UiStrings.t('enter_full_name')),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _organizationCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t(organizationKey),
                  hintText: _isAdmin
                      ? UiStrings.t('organization_name_hint')
                      : UiStrings.t('fpc_name_hint'),
                  prefixIcon: const Icon(Icons.business_outlined),
                ),
                validator: (value) => _required(
                  value,
                  _isAdmin
                      ? UiStrings.t('enter_organization_name')
                      : UiStrings.t('enter_fpc_name'),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t('mobile_number'),
                  hintText: UiStrings.t('mobile_number_hint'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
                validator: (value) {
                  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length >= 10
                      ? null
                      : UiStrings.t('enter_valid_mobile_number');
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t('email_address'),
                  hintText: UiStrings.t('enter_email_address'),
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
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: UiStrings.t('password'),
                  hintText: UiStrings.t('create_password'),
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
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: UiStrings.t('confirm_password'),
                  hintText: UiStrings.t('confirm_password'),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
                validator: (value) => value == _passwordCtrl.text
                    ? null
                    : UiStrings.t('passwords_do_not_match'),
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
              label: UiStrings.t('create_account'),
              loadingLabel: UiStrings.t('creating_account'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: auth.isLoading.value
                  ? null
                  : () => Get.offAllNamed(loginRoute),
              icon: const Icon(Icons.login_rounded),
              label: Text(UiStrings.t('sign_in_to_account')),
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
