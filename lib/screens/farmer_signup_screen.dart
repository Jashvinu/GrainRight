import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/brand_assets.dart';
import '../config/theme.dart';
import '../config/ui_strings.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/app_back_button.dart';
import '../widgets/farm_hills_background.dart';
import '../widgets/language_selector_button.dart';

class FarmerSignupScreen extends StatefulWidget {
  const FarmerSignupScreen({super.key});

  @override
  State<FarmerSignupScreen> createState() => _FarmerSignupScreenState();
}

class _FarmerSignupScreenState extends State<FarmerSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();

  late final String _phone;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final rawPhone = args is Map ? '${args['phone'] ?? ''}' : '';
    _phone = rawPhone.replaceAll(RegExp(r'\D'), '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await Get.find<MainAuthController>().registerFarmerProfile(
      phone: _phone,
      farmerName: _nameController.text,
      defaultLocation: _locationController.text.trim().isEmpty
          ? 'Kalsubai Farms'
          : _locationController.text,
    );
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Get.back();
    } else {
      Get.offAllNamed('/farmer/login');
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
              padding: EdgeInsets.fromLTRB(22, 16, 22, 180 + bottomInset),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: _formKey,
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
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            width: 128,
                            height: 128,
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFDDEBD7)),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppTheme.green.withValues(alpha: 0.14),
                                  blurRadius: 26,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                BrandAssets.farmerLoginAvatar,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                cacheWidth: 320,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  color: AppTheme.green,
                                  size: 62,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          UiStrings.t('create_farmer_profile'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          UiStrings.t('farmer_signup_subtitle'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMedium),
                            border:
                                Border.all(color: const Color(0xFFE5E7EB)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.055),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ReadOnlyPhone(phone: _phone),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _nameController,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: UiStrings.t('farmer_name'),
                                  hintText: UiStrings.t('enter_full_name'),
                                  prefixIcon: const Icon(Icons.person_outline),
                                ),
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return UiStrings.t(
                                      'enter_farmer_name_error',
                                    );
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _locationController,
                                textInputAction: TextInputAction.done,
                                textCapitalization: TextCapitalization.words,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: UiStrings.t('village_or_location'),
                                  hintText: UiStrings.t('location_example'),
                                  prefixIcon: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                ),
                              ),
                              Obx(
                                () => auth.errorMessage.isEmpty
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding:
                                            const EdgeInsets.only(top: 14),
                                        child: Text(
                                          UiStrings.authError(
                                            auth.errorMessage.value,
                                          ),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Obx(
                          () => _SignupSyncStatus(
                            visible:
                                auth.isLoading.value ||
                                auth.farmerLoginSyncStatusKey.value.isNotEmpty,
                            phone: auth.farmerLoginSyncPhone.value.isEmpty
                                ? _phone
                                : auth.farmerLoginSyncPhone.value,
                            statusKey: auth.farmerLoginSyncStatusKey.value,
                            farmCount: auth.farmerLoginSyncedFarmCount.value,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Obx(
                          () => SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed:
                                  auth.isLoading.value ? null : _submit,
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
                                    ? UiStrings.t('creating_profile')
                                    : UiStrings.t('continue_to_farm_setup'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.greenDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusMedium,
                                  ),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
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

class _SignupSyncStatus extends StatelessWidget {
  final bool visible;
  final String phone;
  final String statusKey;
  final int? farmCount;

  const _SignupSyncStatus({
    required this.visible,
    required this.phone,
    required this.statusKey,
    required this.farmCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final key = statusKey.trim().isEmpty ? 'creating_farmer_profile' : statusKey;
    final message = UiStrings.t(key).replaceAll('{count}', '${farmCount ?? 0}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFD7E8D2)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone.length == 10
                      ? '${UiStrings.t('mobile_number')}: +91 $phone'
                      : UiStrings.t('mobile_number'),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyPhone extends StatelessWidget {
  final String phone;

  const _ReadOnlyPhone({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.greenPale.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: const Color(0xFFDDEBD7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_outlined, color: AppTheme.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.t('registered_mobile_number'),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '+91 $phone',
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, color: AppTheme.green, size: 20),
        ],
      ),
    );
  }
}
