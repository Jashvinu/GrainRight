import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../config/theme.dart';
import '../../config/ui_strings.dart';
import '../../controllers/auth_controller.dart';

class SatelliteAuthAlternatives extends StatelessWidget {
  final String phoneNextRoute;
  final String googleNextRoute;

  const SatelliteAuthAlternatives({
    super.key,
    required this.phoneNextRoute,
    required this.googleNextRoute,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                UiStrings.t('or'),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
          ],
        ),
        const SizedBox(height: 16),
        Obx(
          () => _AuthOptionButton(
            icon: Icons.g_mobiledata_rounded,
            label: 'Continue with Google',
            disabled: auth.isLoading.value,
            onTap: () => auth.signInWithGoogle(nextRoute: googleNextRoute),
          ),
        ),
        const SizedBox(height: 12),
        Obx(
          () => _AuthOptionButton(
            icon: Icons.sms_outlined,
            label: 'Continue with SMS',
            disabled: auth.isLoading.value,
            onTap: () => _showPhoneOtpDialog(context, phoneNextRoute),
          ),
        ),
      ],
    );
  }

  Future<void> _showPhoneOtpDialog(BuildContext context, String nextRoute) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PhoneOtpDialog(nextRoute: nextRoute),
    );
  }
}

class _AuthOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  const _AuthOptionButton({
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: disabled ? null : onTap,
      icon: Icon(icon, size: 24),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.greenDark,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: Color(0xFFD7E4D3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PhoneOtpDialog extends StatefulWidget {
  final String nextRoute;

  const _PhoneOtpDialog({required this.nextRoute});

  @override
  State<_PhoneOtpDialog> createState() => _PhoneOtpDialogState();
}

class _PhoneOtpDialogState extends State<_PhoneOtpDialog> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _codeSent = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final auth = Get.find<AuthController>();
    await auth.sendPhoneOtp(_phoneCtrl.text);
    if (auth.pendingPhoneOtp.value.isNotEmpty && auth.errorMessage.isEmpty) {
      setState(() => _codeSent = true);
    }
  }

  Future<void> _verifyCode() {
    return Get.find<AuthController>().verifyPhoneOtp(
      _phoneCtrl.text,
      _otpCtrl.text,
      nextRoute: widget.nextRoute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return AlertDialog(
      title: const Text('SMS sign in'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !_codeSent,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              hintText: '+91 98765 43210',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _verifyCode(),
              decoration: const InputDecoration(
                labelText: 'SMS code',
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
          ],
          Obx(
            () => auth.errorMessage.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
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
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Cancel')),
        Obx(
          () => FilledButton(
            onPressed: auth.isLoading.value
                ? null
                : _codeSent
                ? _verifyCode
                : _sendCode,
            child: auth.isLoading.value
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_codeSent ? 'Verify' : 'Send code'),
          ),
        ),
      ],
    );
  }
}
