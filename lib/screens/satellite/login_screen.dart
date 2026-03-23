import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/brand_text.dart';

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

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();

    return Scaffold(
      backgroundColor: AppTheme.greenDark,
      body: SafeArea(
        child: Column(
          children: [
            // Top branding area
            Expanded(
              flex: 2,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.satellite_alt,
                          color: Colors.white, size: 38),
                    ),
                    const SizedBox(height: 14),
                    const BrandText(fontSize: 26),
                    const SizedBox(height: 6),
                    Text(
                      'Satellite Monitoring',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 15),
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Sign In',
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
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) =>
                              (v?.contains('@') ?? false) ? null : 'Enter a valid email',
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscure,
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
                              : 'Password too short',
                        ),
                        const SizedBox(height: 8),
                        Obx(() => auth.errorMessage.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  auth.errorMessage.value,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13),
                                ),
                              )
                            : const SizedBox.shrink()),
                        const SizedBox(height: 8),
                        Obx(() => SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: auth.isLoading.value
                                    ? null
                                    : () {
                                        if (_formKey.currentState!.validate()) {
                                          auth.login(
                                              _emailCtrl.text.trim(),
                                              _passCtrl.text);
                                        }
                                      },
                                child: auth.isLoading.value
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Text('Sign In'),
                              ),
                            )),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              Get.toNamed('/satellite/signup'),
                          child: Text(
                            "Don't have an account? Sign Up",
                            style: TextStyle(color: AppTheme.green),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Get.back(),
                          child: Text(
                            'Back to Home',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
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
