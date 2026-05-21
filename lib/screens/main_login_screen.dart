import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/brand_text.dart';

class MainLoginScreen extends StatefulWidget {
  const MainLoginScreen({super.key});

  @override
  State<MainLoginScreen> createState() => _MainLoginScreenState();
}

class _MainLoginScreenState extends State<MainLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _isSignup = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final auth = Get.find<MainAuthController>();
    if (_isSignup) {
      auth.signup(_emailCtrl.text.trim(), _passCtrl.text);
    } else {
      auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();

    return Scaffold(
      backgroundColor: AppTheme.green,
      body: SafeArea(
        child: Column(
          children: [
            // Branding
            Expanded(
              flex: 2,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset('assets/logo.jpeg', width: 80),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const BrandText(fontSize: 28),
                    const SizedBox(height: 6),
                    Text(
                      'Precision Agriculture Platform',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Form card
            Expanded(
              flex: 3,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isSignup ? 'Create Account' : 'Sign In',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) => (v?.contains('@') ?? false)
                              ? null
                              : 'Enter a valid email',
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v?.length ?? 0) >= 6
                              ? null
                              : 'Minimum 6 characters',
                        ),
                        Obx(() => auth.errorMessage.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  auth.errorMessage.value,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13),
                                ),
                              )
                            : const SizedBox.shrink()),
                        const SizedBox(height: 16),
                        Obx(() => ElevatedButton(
                              onPressed: auth.isLoading.value ? null : _submit,
                              child: auth.isLoading.value
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : Text(_isSignup
                                      ? 'Create Account'
                                      : 'Sign In'),
                            )),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() {
                            _isSignup = !_isSignup;
                            auth.errorMessage.value = '';
                          }),
                          child: Text(
                            _isSignup
                                ? 'Already have an account? Sign In'
                                : "Don't have an account? Sign Up",
                            style: TextStyle(color: AppTheme.green),
                          ),
                        ),

                        // Divider
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('or',
                                  style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 13)),
                            ),
                            const Expanded(child: Divider()),
                          ]),
                        ),

                        // Guest access
                        Obx(() => OutlinedButton(
                              onPressed: auth.isLoading.value
                                  ? null
                                  : auth.continueAsGuest,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: AppTheme.green.withValues(
                                        alpha: 0.4)),
                              ),
                              child: const Text('Continue without signing in'),
                            )),
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
