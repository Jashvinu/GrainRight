import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/farm_hills_background.dart';
import '../widgets/language_selector_button.dart';

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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppTheme.surface,
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(24, 18, 24, 190 + bottomInset),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: _goBack,
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: AppTheme.greenDark,
                            size: 30,
                          ),
                        ),
                        const Spacer(),
                        Obx(() {
                          final code = language.language.value;
                          return LanguageSelectorButton(
                            code: code,
                            onChanged: (value) {
                              language.setLanguage(value);
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _FpcHeader(),
                    const SizedBox(height: 24),
                    const _FpcInfoStrip(),
                    const SizedBox(height: 18),
                    _FpcFormCard(
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'Enter registered FPC email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            final valid =
                                RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(text);
                            return valid ? null : 'Enter a valid email';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter FPC login password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip:
                                  _obscure ? 'Show password' : 'Hide password',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) >= 6
                              ? null
                              : 'Password must be at least 6 characters',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Obx(
                      () => SizedBox(
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: auth.isLoading.value ? null : _submit,
                          icon: auth.isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            auth.isLoading.value
                                ? 'Verifying'
                                : 'Login to FPC Dashboard',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            textStyle: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FpcHeader extends StatelessWidget {
  const _FpcHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _FpcIcon(),
        SizedBox(height: 20),
        Text(
          'FPC Login',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.greenDark,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 10),
        Text(
          'Login with your registered FPC account to access farmer verification, procurement and field tools.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FpcIcon extends StatelessWidget {
  const _FpcIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 98,
      height: 98,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4FF),
        borderRadius: BorderRadius.circular(26),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.groups_2_outlined,
        color: Color(0xFF1976D2),
        size: 54,
      ),
    );
  }
}

class _FpcInfoStrip extends StatelessWidget {
  const _FpcInfoStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_user_outlined, color: Color(0xFF1976D2)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Use the email and password configured in Supabase for your FPC account.',
              style: TextStyle(
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

class _FpcFormCard extends StatelessWidget {
  final List<Widget> children;

  const _FpcFormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}
