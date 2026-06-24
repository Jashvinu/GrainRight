import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../config/brand_assets.dart';
import '../config/locale_text.dart';
import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/app_back_button.dart';
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
    final auth = Get.find<MainAuthController>();
    if (auth.isLoading.value) return;
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      setState(() => _phoneError = 'Enter a valid 10 digit mobile number');
      return;
    }

    FocusScope.of(context).unfocus();
    await auth.continueAsVerifiedFarmer(digits, nextRoute: '/farmer');
  }

  void _useLastFarmer(String phone) {
    if (phone.length != 10) return;
    setState(() {
      _phoneController.text = phone;
      _phoneError = null;
    });
  }

  Future<void> _openSupportCall() {
    return _copySupportContact(UiStrings.t('call_support'));
  }

  Future<void> _openSupportWhatsapp() {
    return _copySupportContact(UiStrings.t('whatsapp'));
  }

  Future<void> _copySupportContact(String action) async {
    await Clipboard.setData(const ClipboardData(text: '+91 98765 43210'));
    Get.snackbar(
      action,
      UiStrings.f('support_contact_copied', {'phone': '+91 98765 43210'}),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  bool _isSignupGuidanceError(String message) {
    final normalized = message.trim().toLowerCase();
    return normalized.contains('no farmer profile found') ||
        normalized.contains('no approved farmer profile') ||
        normalized.contains('create a new farmer account') ||
        normalized.contains('redirecting to sign up') ||
        normalized.contains('not verified') ||
        normalized.contains('not approved') ||
        normalized.contains('create account') ||
        normalized.contains('farmer_not_found');
  }

  void _openSignup() {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      setState(() => _phoneError = 'Enter 10 digit mobile number to sign up');
      return;
    }
    FocusScope.of(context).unfocus();
    Get.toNamed('/farmer/signup', arguments: {'phone': digits});
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
    final compact = screenWidth < 380;
    final avatarSize = compact ? 124.0 : 160.0;
    final horizontalPadding = screenWidth < 380 ? 18.0 : 24.0;

    return Obx(() {
      language.language.value;
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
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    (compact ? 132 : 164) + bottomInset,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              AppBackButton(onPressed: _goBack),
                              const Spacer(),
                              Obx(() {
                                final code = language.language.value;
                                return LanguageSelectorButton(
                                  code: code,
                                  onChanged: language.setLanguage,
                                );
                              }),
                            ],
                          ),
                          SizedBox(height: compact ? 16 : 20),
                          Center(
                            child: Container(
                              width: avatarSize,
                              height: avatarSize,
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
                                    color: AppTheme.green.withValues(
                                      alpha: 0.18,
                                    ),
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
                                      cacheWidth: 320,
                                      errorBuilder:
                                          (context, error, stackTrace) {
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
                          SizedBox(height: compact ? 12 : 16),
                          Text(
                            UiStrings.t('farmer_login'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.greenDark,
                              fontSize: compact ? 30 : 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Obx(() {
                            final phone = auth.lastFarmerLoginPhone.value;
                            if (phone.length != 10) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _LastFarmerLoginCard(
                                name: auth.lastFarmerLoginName.value,
                                phone: phone,
                                farmCount: auth.lastFarmerLoginFarmCount.value,
                                lastSyncAt: auth.lastFarmerLoginSyncAt.value,
                                disabled: auth.isLoading.value,
                                onUse: () => _useLastFarmer(phone),
                                onLogin: () {
                                  _useLastFarmer(phone);
                                  _continue();
                                },
                              ),
                            );
                          }),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: const Color(0xFFE3EADD),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.greenDark.withValues(
                                    alpha: 0.07,
                                  ),
                                  blurRadius: 26,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  UiStrings.t('mobile_number'),
                                  style: const TextStyle(
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
                                    errorText: _phoneError == null
                                        ? null
                                        : UiStrings.authError(_phoneError!),
                                    prefixIcon: const Padding(
                                      padding: EdgeInsets.only(
                                        left: 14,
                                        right: 8,
                                      ),
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
                                    hintText: UiStrings.t('enter_mobile'),
                                    suffixIcon: const Icon(
                                      Icons.phone_outlined,
                                    ),
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
                                      : UiStrings.t('continue_'),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.greenDark,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
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
                                    child:
                                        _isSignupGuidanceError(
                                          auth.errorMessage.value,
                                        )
                                        ? _SignupErrorCard(
                                            message: UiStrings.authError(
                                              auth.errorMessage.value,
                                            ),
                                            onSignup: _openSignup,
                                          )
                                        : Text(
                                            UiStrings.authError(
                                              auth.errorMessage.value,
                                            ),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _SignupPrompt(onTap: _openSignup),
                          const SizedBox(height: 24),
                          const _SecureStrip(),
                          const SizedBox(height: 22),
                          _SupportActionCard(
                            onCall: _openSupportCall,
                            onWhatsapp: _openSupportWhatsapp,
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

// ignore: unused_element
class _LoginSyncStatus extends StatelessWidget {
  final bool visible;
  final String phone;
  final String statusKey;
  final String statusCode;
  final int? farmCount;
  final String farmerName;
  final String farmerId;
  final DateTime? lastSyncAt;

  const _LoginSyncStatus({
    required this.visible,
    required this.phone,
    required this.statusKey,
    required this.statusCode,
    required this.farmCount,
    required this.farmerName,
    required this.farmerId,
    required this.lastSyncAt,
  });

  static const _steps = [
    'login_step_checking_farmer_number',
    'login_step_farmer_profile_found',
    'login_step_starting_farmer_session',
    'login_step_syncing_farm_records',
    'login_step_opening_farmer_dashboard',
  ];

  int _activeStep() {
    switch (statusKey) {
      case 'farmer_profile_found':
      case 'linking_farmer_profile':
        return 1;
      case 'starting_farmer_session':
      case 'syncing_farmer_session':
        return 2;
      case 'syncing_farm_records':
      case 'repairing_empty_farm_cache':
      case 'farm_records_synced':
      case 'no_farm_records_found':
        return 3;
      case 'opening_farmer_dashboard':
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final message = UiStrings.t(
      statusKey,
    ).replaceAll('{count}', '${farmCount ?? 0}');
    final activeStep = _activeStep();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFD7E8D2)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.greenDark.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    phone.length == 10
                        ? '${UiStrings.t('mobile_number')}: +91 $phone'
                        : UiStrings.t('mobile_number'),
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (farmerName.trim().isNotEmpty) ...[
              _FarmerPreviewCard(name: farmerName, farmerId: farmerId),
              const SizedBox(height: 10),
            ],
            Text(
              message,
              style: const TextStyle(
                color: AppTheme.textMuted,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (farmCount != null || lastSyncAt != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (farmCount != null)
                    _LoginMetaChip(
                      icon: Icons.grass_rounded,
                      label: UiStrings.f('farm_count_value', {
                        'count': farmCount,
                      }),
                    ),
                  if (lastSyncAt != null)
                    _LoginMetaChip(
                      icon: Icons.schedule_rounded,
                      label: UiStrings.f('last_sync_value', {
                        'value':
                            '${LocaleText.date(lastSyncAt!, pattern: 'dd/MM')} ${LocaleText.time(lastSyncAt!)}',
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            for (var i = 0; i < _steps.length; i++)
              _LoginProgressStep(
                label: UiStrings.t(_steps[i]),
                active: i == activeStep,
                done: i < activeStep,
              ),
            if (statusCode.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                UiStrings.f('login_status_code_value', {'code': statusCode}),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LoginHealthCheckCard extends StatelessWidget {
  final bool visible;
  final bool farmerVerified;
  final bool sessionLinked;
  final bool farmSynced;
  final bool offlineCacheReady;
  final int? farmCount;
  final DateTime? lastSyncAt;
  final String statusCode;

  const _LoginHealthCheckCard({
    required this.visible,
    required this.farmerVerified,
    required this.sessionLinked,
    required this.farmSynced,
    required this.offlineCacheReady,
    required this.farmCount,
    required this.lastSyncAt,
    required this.statusCode,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final lastSyncLabel = lastSyncAt == null
        ? UiStrings.t('last_sync_not_available')
        : UiStrings.f('last_sync_value', {
            'value':
                '${LocaleText.date(lastSyncAt!, pattern: 'dd/MM')} ${LocaleText.time(lastSyncAt!)}',
          });
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFDDE9D5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.greenDark.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.greenPale,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.health_and_safety_rounded,
                    color: AppTheme.greenDark,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UiStrings.t('login_health_check'),
                        style: const TextStyle(
                          color: AppTheme.greenDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        UiStrings.t('login_health_check_desc'),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LoginHealthRow(
              icon: Icons.verified_rounded,
              label: UiStrings.t('health_farmer_verified'),
              ready: farmerVerified,
            ),
            _LoginHealthRow(
              icon: Icons.link_rounded,
              label: UiStrings.t('health_session_linked'),
              ready: sessionLinked,
            ),
            _LoginHealthRow(
              icon: Icons.cloud_done_rounded,
              label: UiStrings.t('health_farm_sync'),
              ready: farmSynced,
              detail: farmCount == null
                  ? null
                  : UiStrings.f('farm_count_value', {'count': farmCount}),
            ),
            _LoginHealthRow(
              icon: Icons.offline_bolt_rounded,
              label: UiStrings.t('health_offline_cache'),
              ready: offlineCacheReady,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LoginMetaChip(
                  icon: Icons.schedule_rounded,
                  label: lastSyncLabel,
                ),
                if (statusCode.isNotEmpty)
                  _LoginMetaChip(
                    icon: Icons.info_outline_rounded,
                    label: UiStrings.f('login_status_code_value', {
                      'code': statusCode,
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHealthRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool ready;
  final String? detail;

  const _LoginHealthRow({
    required this.icon,
    required this.label,
    required this.ready,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final color = ready ? AppTheme.green : AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail == null ? label : '$label • $detail',
              style: TextStyle(
                color: ready ? AppTheme.textDark : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            UiStrings.t(ready ? 'health_ready' : 'health_waiting'),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _InlineLanguageSelector extends StatelessWidget {
  final String code;
  final ValueChanged<String> onChanged;

  const _InlineLanguageSelector({required this.code, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE9D5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            UiStrings.t('change_language'),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          LanguageSelectorButton(code: code, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LastFarmerLoginCard extends StatelessWidget {
  final String name;
  final String phone;
  final int? farmCount;
  final DateTime? lastSyncAt;
  final bool disabled;
  final VoidCallback onUse;
  final VoidCallback onLogin;

  const _LastFarmerLoginCard({
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
    final title = name.trim().isEmpty ? UiStrings.t('last_farmer') : name;
    final syncText = lastSyncAt == null
        ? UiStrings.t('last_sync_not_available')
        : UiStrings.f('last_sync_value', {
            'value':
                '${LocaleText.date(lastSyncAt!, pattern: 'dd/MM')} ${LocaleText.time(lastSyncAt!)}',
          });
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E8D2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.history_rounded, color: AppTheme.greenDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: disabled ? null : onUse,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '+91 $phone • ${UiStrings.f('farm_count_value', {'count': farmCount ?? 0})}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    syncText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: disabled ? null : onLogin,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 38),
            ),
            child: Text(UiStrings.t('login')),
          ),
        ],
      ),
    );
  }
}

class _FarmerPreviewCard extends StatelessWidget {
  final String name;
  final String farmerId;

  const _FarmerPreviewCard({required this.name, required this.farmerId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppTheme.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              farmerId.trim().isEmpty ? name : '$name • $farmerId',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LoginMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.greenDark, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginProgressStep extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _LoginProgressStep({
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final color = done || active ? AppTheme.green : const Color(0xFFB6C0B1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : active
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.greenDark : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportActionCard extends StatelessWidget {
  final VoidCallback onCall;
  final VoidCallback onWhatsapp;

  const _SupportActionCard({required this.onCall, required this.onWhatsapp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE9D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.support_agent_rounded,
                color: AppTheme.green,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  UiStrings.t('need_help'),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: Text(UiStrings.t('call_support')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onWhatsapp,
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: Text(UiStrings.t('whatsapp')),
                ),
              ),
            ],
          ),
        ],
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
        color: AppTheme.greenPale.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDEBD7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: AppTheme.green,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                UiStrings.t('login_note'),
                style: const TextStyle(
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

class _SignupErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onSignup;

  const _SignupErrorCard({required this.message, required this.onSignup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4E6CC)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: AppTheme.greenDark,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onSignup,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Text(UiStrings.t('sign_up')),
          ),
        ],
      ),
    );
  }
}

class _SignupPrompt extends StatelessWidget {
  final VoidCallback onTap;

  const _SignupPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE9D5)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(15),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: AppTheme.greenDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.t('new_farmer_create_profile'),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  UiStrings.t('create_profile_this_mobile'),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 40),
            ),
            child: Text(UiStrings.t('sign_up')),
          ),
        ],
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                color: AppTheme.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                UiStrings.t('secure_private'),
                style: const TextStyle(
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
