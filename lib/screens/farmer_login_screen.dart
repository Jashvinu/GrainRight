import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/farm_hills_background.dart';
import '../widgets/language_selector_button.dart';

class FarmerLoginScreen extends StatefulWidget {
  const FarmerLoginScreen({super.key});

  @override
  State<FarmerLoginScreen> createState() => _FarmerLoginScreenState();
}

class _FarmerLoginScreenState extends State<FarmerLoginScreen> {
  final _phoneController = TextEditingController();
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Get.find<MainAuthController>();
      if (auth.verifiedFarmer.value != null) {
        Get.offAllNamed('/farmer');
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      setState(() => _phoneError = 'Enter a valid 10 digit mobile number');
      return;
    }

    FocusScope.of(context).unfocus();
    final auth = Get.find<MainAuthController>();
    await auth.continueAsVerifiedFarmer(digits, nextRoute: '/farmer');
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 380 ? 18.0 : 24.0;

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
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                16,
                horizontalPadding,
                180 + bottomInset,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _RoundIconButton(
                            tooltip: 'Back',
                            icon: Icons.arrow_back_rounded,
                            onPressed: _goBack,
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
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          width: 196,
                          height: 196,
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
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: ColoredBox(
                                color: Colors.white,
                                child: Image.asset(
                                  BrandAssets.farmerLoginAvatar,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.person_rounded,
                                      color: AppTheme.green,
                                      size: 84,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Farmer Login',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMedium,
                          ),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.055),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mobile Number',
                              style: TextStyle(
                                color: AppTheme.greenDark,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              maxLength: 10,
                              onSubmitted: (_) => _continue(),
                              onChanged: (_) {
                                if (_phoneError != null) {
                                  setState(() => _phoneError = null);
                                }
                              },
                              decoration: InputDecoration(
                                counterText: '',
                                errorText: _phoneError,
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.only(left: 14, right: 8),
                                  child: Center(
                                    widthFactor: 1,
                                    child: Text(
                                      '+91',
                                      style: TextStyle(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                hintText: 'Enter mobile number',
                                suffixIcon: const Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const _LoginNote(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Obx(
                        () => SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: auth.isLoading.value ? null : _continue,
                            icon: auth.isLoading.value
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              auth.isLoading.value ? 'Please wait' : 'Continue',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.greenDark,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMedium,
                                ),
                              ),
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
                                padding: const EdgeInsets.only(top: 12),
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
                      const SizedBox(height: 24),
                      const _SecureStrip(),
                      const SizedBox(height: 22),
                      Material(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Get.snackbar(
                            'Support',
                            'Contact your field coordinator for login help.',
                            snackPosition: SnackPosition.BOTTOM,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.support_agent_rounded,
                                  color: AppTheme.green,
                                  size: 26,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Need help? Contact support',
                                    style: TextStyle(
                                      color: AppTheme.textDark,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: AppTheme.green,
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: AppTheme.greenDark, size: 26),
      ),
    );
  }
}

class _LoginNote extends StatelessWidget {
  const _LoginNote();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: const Color(0xFFDDEBD7)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: AppTheme.green,
              size: 24,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Use the mobile number registered with your field coordinator.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecureStrip extends StatelessWidget {
  const _SecureStrip();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: const Color(0xFFE1E8DE)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, color: AppTheme.green, size: 20),
              SizedBox(width: 8),
              Text(
                'Secure & Private',
                style: TextStyle(
                  color: AppTheme.green,
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
