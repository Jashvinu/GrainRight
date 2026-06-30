import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import '../widgets/farm_hills_background.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';

class StakeholderLoginScreen extends StatefulWidget {
  const StakeholderLoginScreen({super.key});

  @override
  State<StakeholderLoginScreen> createState() => _StakeholderLoginScreenState();
}

class _StakeholderLoginScreenState extends State<StakeholderLoginScreen> {
  final _phoneController = TextEditingController();
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map) {
      final phone = '${args['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
      final message = '${args['message'] ?? ''}'.trim();
      if (phone.length == 10) {
        _phoneController.text = phone;
      }
      if (message.isNotEmpty) {
        _phoneError = message;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Get.find<MainAuthController>();
      if (auth.verifiedFarmer.value != null) {
        Get.offAllNamed('/stakeholder');
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final auth = Get.find<MainAuthController>();
    if (auth.isLoading.value) return;
    final digits = _digits;
    if (digits.length != 10) {
      setState(() => _phoneError = UiStrings.t('invalid_phone'));
      return;
    }
    FocusScope.of(context).unfocus();
    await auth.continueAsVerifiedFarmer(digits, nextRoute: '/stakeholder');
  }

  void _openSignup() {
    final digits = _digits;
    if (digits.length != 10) {
      setState(() => _phoneError = UiStrings.t('signup_phone_required'));
      return;
    }
    FocusScope.of(context).unfocus();
    Get.toNamed(
      '/farmer/signup',
      arguments: {'phone': digits, 'nextRoute': '/stakeholder'},
    );
  }

  void _useLastFarmer(String phone) {
    if (phone.length != 10) return;
    setState(() {
      _phoneController.text = phone;
      _phoneError = null;
    });
  }

  Future<void> _copySupportContact(String action) async {
    await Clipboard.setData(const ClipboardData(text: '+91 98765 43210'));
    Get.snackbar(
      action,
      UiStrings.f('support_contact_copied', {'phone': '+91 98765 43210'}),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Get.back();
    } else {
      Get.offAllNamed('/login');
    }
  }

  String get _digits => _phoneController.text.replaceAll(RegExp(r'\D'), '');

  bool _isSignupGuidanceError(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('farmer_not_found') ||
        normalized.contains('create a new farmer account') ||
        normalized.contains('no farmer profile found') ||
        normalized.contains('not approved') ||
        normalized.contains('not verified');
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final language = Get.find<LanguageController>();
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 380;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Obx(() {
      language.language.value;
      final lastPhone = auth.lastFarmerLoginPhone.value;
      final hasLastFarmer = lastPhone.length == 10;
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
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 18 : 24,
                    16,
                    compact ? 18 : 24,
                    140 + bottomInset,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              AppBackButton(onPressed: _goBack),
                              const Spacer(),
                              LanguageSelectorButton(
                                code: language.language.value,
                                onChanged: language.setLanguage,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _StakeholderLoginHero(compact: compact),
                          const SizedBox(height: 16),
                          if (hasLastFarmer) ...[
                            _StakeholderLastFarmerCard(
                              name: auth.lastFarmerLoginName.value,
                              phone: lastPhone,
                              farmCount: auth.lastFarmerLoginFarmCount.value,
                              lastSyncAt: auth.lastFarmerLoginSyncAt.value,
                              disabled: auth.isLoading.value,
                              onUse: () => _useLastFarmer(lastPhone),
                              onLogin: () {
                                _useLastFarmer(lastPhone);
                                _continue();
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                          _StakeholderPhoneCard(
                            controller: _phoneController,
                            errorText: _phoneError,
                            onChanged: () {
                              if (_phoneError != null) {
                                setState(() => _phoneError = null);
                              }
                            },
                            onSubmitted: _continue,
                          ),
                          _StakeholderLoginProgress(auth: auth),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: auth.isLoading.value
                                  ? null
                                  : _continue,
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
                                auth.isLoading.value
                                    ? UiStrings.t('please_wait')
                                    : UiStrings.t('stakeholder_continue'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.greenDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          Obx(() {
                            final message = auth.errorMessage.value.trim();
                            if (message.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _StakeholderErrorCard(
                                message: UiStrings.authError(message),
                                showSignup: _isSignupGuidanceError(message),
                                onSignup: _openSignup,
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          _StakeholderSignupCard(onSignup: _openSignup),
                          const SizedBox(height: 12),
                          _StakeholderSecureCard(
                            onCall: () =>
                                _copySupportContact(UiStrings.t('call_support')),
                            onWhatsapp: () =>
                                _copySupportContact(UiStrings.t('whatsapp')),
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
      );
    });
  }
}

class _StakeholderLoginHero extends StatelessWidget {
  final bool compact;

  const _StakeholderLoginHero({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: _stakeholderLoginCardDecoration(AppTheme.greenPale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 76 : 88,
                height: compact ? 76 : 88,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  BrandAssets.kalsubaiFarms,
                  fit: BoxFit.contain,
                  cacheWidth: 220,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.handshake_outlined,
                      color: AppTheme.greenDark,
                      size: 38,
                    );
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.t('stakeholder_login_kicker'),
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      UiStrings.t('stakeholder_login'),
                      style: TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: compact ? 28 : 32,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            UiStrings.t('stakeholder_login_subtitle'),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StakeholderBenefitChip(
                icon: Icons.verified_user_outlined,
                label: UiStrings.t('stakeholder_login_benefit_record'),
              ),
              _StakeholderBenefitChip(
                icon: Icons.currency_rupee_rounded,
                label: UiStrings.t('stakeholder_login_benefit_interest'),
              ),
              _StakeholderBenefitChip(
                icon: Icons.timeline_rounded,
                label: UiStrings.t('stakeholder_login_benefit_review'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StakeholderBenefitChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StakeholderBenefitChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD7E8D2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.greenDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StakeholderPhoneCard extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onChanged;
  final Future<void> Function() onSubmitted;

  const _StakeholderPhoneCard({
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _stakeholderLoginCardDecoration(Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.t('mobile_number'),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => onSubmitted(),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              counterText: '',
              errorText: errorText == null ? null : UiStrings.authError(errorText!),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 14, right: 8),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    '+91',
                    style: TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              hintText: UiStrings.t('enter_mobile'),
              suffixIcon: const Icon(Icons.phone_android_outlined),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            UiStrings.t('stakeholder_login_note'),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StakeholderLoginProgress extends StatelessWidget {
  final MainAuthController auth;

  const _StakeholderLoginProgress({required this.auth});

  @override
  Widget build(BuildContext context) {
    final statusKey = auth.farmerLoginSyncStatusKey.value.trim();
    final state = auth.farmerLoginState.value;
    if (!auth.isLoading.value && statusKey.isEmpty && state == null) {
      return const SizedBox.shrink();
    }
    final message = statusKey.isEmpty
        ? UiStrings.t('stakeholder_login_syncing')
        : UiStrings.t(statusKey).replaceAll(
            '{count}',
            '${auth.farmerLoginSyncedFarmCount.value ?? 0}',
          );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _stakeholderLoginCardDecoration(Colors.white),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StakeholderLastFarmerCard extends StatelessWidget {
  final String name;
  final String phone;
  final int? farmCount;
  final DateTime? lastSyncAt;
  final bool disabled;
  final VoidCallback onUse;
  final VoidCallback onLogin;

  const _StakeholderLastFarmerCard({
    required this.name,
    required this.phone,
    required this.farmCount,
    required this.lastSyncAt,
    required this.disabled,
    required this.onUse,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final syncLabel = lastSyncAt == null
        ? UiStrings.t('last_sync_not_available')
        : UiStrings.f('last_sync_value', {
            'value':
                '${LocaleText.date(lastSyncAt!, pattern: 'dd/MM')} ${LocaleText.time(lastSyncAt!)}',
          });
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFD7E8D2)),
      ),
      child: ListTile(
        leading: const Icon(Icons.history_rounded, color: AppTheme.greenDark),
        title: Text(
          name.trim().isEmpty ? UiStrings.t('last_farmer') : name.trim(),
          style: const TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          '+91 $phone  |  ${UiStrings.f('farm_count_value', {
            'count': farmCount ?? 0,
          })}\n$syncLabel',
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        isThreeLine: true,
        trailing: TextButton(
          onPressed: disabled ? null : onLogin,
          child: Text(UiStrings.t('login')),
        ),
        onTap: disabled ? null : onUse,
      ),
    );
  }
}

class _StakeholderErrorCard extends StatelessWidget {
  final String message;
  final bool showSignup;
  final VoidCallback onSignup;

  const _StakeholderErrorCard({
    required this.message,
    required this.showSignup,
    required this.onSignup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Color(0xFFB91C1C)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (showSignup) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onSignup,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(UiStrings.t('sign_up')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StakeholderSignupCard extends StatelessWidget {
  final VoidCallback onSignup;

  const _StakeholderSignupCard({required this.onSignup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _stakeholderLoginCardDecoration(Colors.white),
      child: Row(
        children: [
          const Icon(Icons.person_add_alt_1_rounded, color: AppTheme.greenDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.t('stakeholder_signup_title'),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  UiStrings.t('stakeholder_signup_body'),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onSignup, child: Text(UiStrings.t('sign_up'))),
        ],
      ),
    );
  }
}

class _StakeholderSecureCard extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onWhatsapp;

  const _StakeholderSecureCard({
    required this.onCall,
    required this.onWhatsapp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _stakeholderLoginCardDecoration(Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: AppTheme.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  UiStrings.t('secure_private'),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            UiStrings.t('stakeholder_login_secure_body'),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.call_outlined),
                label: Text(UiStrings.t('call_support')),
              ),
              OutlinedButton.icon(
                onPressed: onWhatsapp,
                icon: const Icon(Icons.chat_outlined),
                label: Text(UiStrings.t('whatsapp')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

BoxDecoration _stakeholderLoginCardDecoration(Color color) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFFE1E8DE)),
    boxShadow: [
      BoxShadow(
        color: AppTheme.greenDark.withValues(alpha: 0.05),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
  );
}
