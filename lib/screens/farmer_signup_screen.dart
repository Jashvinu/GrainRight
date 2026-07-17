import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:kalsubai_farms/core/config/brand_assets.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../services/farmer_identity_document_service.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import '../widgets/farm_hills_background.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';

class FarmerSignupScreen extends StatefulWidget {
  const FarmerSignupScreen({super.key});

  @override
  State<FarmerSignupScreen> createState() => _FarmerSignupScreenState();
}

class _FarmerSignupScreenState extends State<FarmerSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _agriRecordController = TextEditingController();
  final _documentService = FarmerIdentityDocumentService();
  final _imagePicker = ImagePicker();

  late final String _phone;
  Uint8List? _documentBytes;
  String _documentName = '';
  String _documentPath = '';
  double? _documentConfidence;
  bool _documentBusy = false;
  bool _documentOcrFailed = false;
  String _documentMessage = '';
  String _nextRoute = '/farmer';

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final rawPhone = args is Map ? '${args['phone'] ?? ''}' : '';
    final rawCountryDialCode = args is Map
        ? '${args['countryDialCode'] ?? ''}'.trim()
        : '';
    _phone = rawPhone.replaceAll(RegExp(r'\D'), '');
    final rawNextRoute = args is Map ? '${args['nextRoute'] ?? ''}'.trim() : '';
    if (rawNextRoute.isNotEmpty) {
      _nextRoute = rawNextRoute;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _aadhaarController.dispose();
    _agriRecordController.dispose();
    super.dispose();
  }

  String get _aadhaarDigits =>
      _aadhaarController.text.replaceAll(RegExp(r'\D'), '');

  String get _aadhaarLast4 => _aadhaarDigits.length >= 4
      ? _aadhaarDigits.substring(_aadhaarDigits.length - 4)
      : '';

  String get _aadhaarMasked =>
      _aadhaarLast4.isEmpty ? '' : 'XXXX XXXX $_aadhaarLast4';

  Future<void> _pickDocument(ImageSource source) async {
    if (_documentBusy) return;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 86,
        maxWidth: 1800,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _documentBytes = bytes;
        _documentName = image.name.isEmpty ? 'agri-record.jpg' : image.name;
        _documentPath = '';
        _documentConfidence = null;
        _documentOcrFailed = false;
        _documentMessage = '';
      });
      await _readDocument();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _documentMessage = UiStrings.t('image_capture_error');
      });
    }
  }

  Future<void> _readDocument() async {
    final bytes = _documentBytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _documentMessage = UiStrings.t('farmer_identity_document_required');
      });
      return;
    }
    setState(() {
      _documentBusy = true;
      _documentMessage = UiStrings.t('reading_agri_record_document');
    });
    try {
      final auth = Get.find<MainAuthController>();
      await auth.ensureFarmerSignupSession(phone: _phone);
      final result = await _documentService.readDocument(
        bytes: bytes,
        fileName: _documentName.isEmpty ? 'agri-record.jpg' : _documentName,
      );
      if (!mounted) return;
      final aadhaarDigits = result.aadhaarDigits;
      final farmerName = result.farmerName.trim();
      setState(() {
        _documentPath = result.documentPath;
        _documentConfidence = result.confidence;
        _documentOcrFailed = result.ocrFailed;
        if (farmerName.isNotEmpty && _nameController.text.trim().isEmpty) {
          _nameController.text = farmerName;
        }
        if (aadhaarDigits.length == 12) {
          _aadhaarController.text = aadhaarDigits;
        }
        if (result.agriRecordId.isNotEmpty) {
          _agriRecordController.text = result.agriRecordId;
        }
        _documentMessage = result.ocrFailed
            ? UiStrings.t('agri_record_document_manual')
            : UiStrings.t('agri_record_document_ready');
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is FarmerIdentityDocumentException
          ? error.message
          : UiStrings.authError(error.toString());
      setState(() {
        _documentPath = '';
        _documentConfidence = null;
        _documentOcrFailed = true;
        _documentMessage = message;
      });
    } finally {
      if (mounted) {
        setState(() => _documentBusy = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_documentBusy) return;
    if (_documentPath.isEmpty) {
      if (_documentBytes == null) {
        setState(() {
          _documentMessage = UiStrings.t('farmer_identity_document_required');
        });
        return;
      }
      await _readDocument();
      if (!mounted || _documentPath.isEmpty) return;
    }
    if (!_formKey.currentState!.validate()) return;
    final auth = Get.find<MainAuthController>();
    if (!auth.isFarmerPhoneVerifiedForSignup(
      _phone,
      countryDialCode: _countryDialCode,
    )) {
      setState(() => _otpError = 'Verify this mobile number first');
      return;
    }
    FocusScope.of(context).unfocus();
    await auth.registerFarmerProfile(
      phone: _phone,
      farmerName: _nameController.text,
      defaultLocation: _locationController.text.trim().isEmpty
          ? 'Kalsubai Farms'
          : _locationController.text,
      agriRecordId: _agriRecordController.text,
      aadhaarMasked: _aadhaarMasked,
      aadhaarLast4: _aadhaarLast4,
      identityDocumentPath: _documentPath,
      identityOcrConfidence: _documentConfidence,
      nextRoute: _nextRoute,
    );
  }

  Future<void> _sendCode() async {
    final auth = Get.find<MainAuthController>();
    if (auth.isLoading.value) return;
    setState(() => _otpError = null);
    FocusScope.of(context).unfocus();
    await auth.sendFarmerPhoneCode(
      _phone,
      verifyOnly: true,
      countryDialCode: _countryDialCode,
    );
  }

  Future<void> _verifyCode() async {
    final auth = Get.find<MainAuthController>();
    if (auth.isLoading.value) return;
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');
    if (code.length < 4) {
      setState(() => _otpError = 'Enter the SMS verification code');
      return;
    }
    FocusScope.of(context).unfocus();
    await auth.verifyFarmerPhoneCode(
      code,
      verifyOnly: true,
      countryDialCode: _countryDialCode,
    );
  }

  Future<void> _primaryAction() async {
    final auth = Get.find<MainAuthController>();
    if (auth.isFarmerPhoneVerifiedForSignup(
      _phone,
      countryDialCode: _countryDialCode,
    )) {
      await _submit();
      return;
    }
    if (auth.isFarmerPhoneCodeSentFor(
      _phone,
      countryDialCode: _countryDialCode,
    )) {
      await _verifyCode();
      return;
    }
    await _sendCode();
  }

  String _buttonLabel(MainAuthController auth) {
    if (auth.isLoading.value) return UiStrings.t('creating_profile');
    if (auth.isFarmerPhoneVerifiedForSignup(
      _phone,
      countryDialCode: _countryDialCode,
    )) {
      return UiStrings.t('continue_to_farm_setup');
    }
    if (auth.isFarmerPhoneCodeSentFor(
      _phone,
      countryDialCode: _countryDialCode,
    )) {
      return 'Verify SMS code';
    }
    return 'Send SMS code';
  }

  void _goBack() {
    if (Navigator.canPop(context)) {
      Get.back();
    } else {
      Get.offAllNamed(
        _nextRoute == '/stakeholder' ? '/stakeholder/login' : '/farmer/login',
      );
    }
  }

  Widget _buildIdentityDocumentSection() {
    final hasImage = _documentBytes != null;
    final status = _documentMessage.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          UiStrings.t('farmer_identity_document'),
          style: const TextStyle(
            color: AppTheme.textDark,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          UiStrings.t('farmer_identity_document_hint'),
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 86,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.greenPale.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: const Color(0xFFDDEBD7)),
              ),
              child: hasImage
                  ? Image.memory(_documentBytes!, fit: BoxFit.cover)
                  : const Icon(
                      Icons.badge_outlined,
                      color: AppTheme.green,
                      size: 30,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _documentBusy
                        ? null
                        : () => _pickDocument(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(UiStrings.t('capture_agri_record_document')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _documentBusy
                        ? null
                        : () => _pickDocument(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(UiStrings.t('choose_agri_record_document')),
                  ),
                  if (hasImage && _documentPath.isEmpty)
                    TextButton.icon(
                      onPressed: _documentBusy ? null : _readDocument,
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: Text(UiStrings.t('read_agri_record_document')),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (_documentBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  _documentPath.isEmpty || _documentOcrFailed
                      ? Icons.info_outline
                      : Icons.check_circle_outline,
                  color: _documentPath.isEmpty
                      ? Colors.red.shade700
                      : AppTheme.green,
                  size: 20,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: _documentPath.isEmpty
                        ? Colors.red.shade700
                        : AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
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
                              border: Border.all(
                                color: const Color(0xFFDDEBD7),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.green.withValues(alpha: 0.14),
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
                                errorBuilder: (_, _, _) => const Icon(
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
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ReadOnlyPhone(
                                phone: _phone,
                                countryDialCode: _countryDialCode,
                              ),
                              const SizedBox(height: 16),
                              Obx(() {
                                final isVerified = auth
                                    .isFarmerPhoneVerifiedForSignup(
                                      _phone,
                                      countryDialCode: _countryDialCode,
                                    );
                                final codeSent = auth.isFarmerPhoneCodeSentFor(
                                  _phone,
                                  countryDialCode: _countryDialCode,
                                );
                                return _SignupOtpStep(
                                  verified: isVerified,
                                  codeSent: codeSent,
                                  controller: _otpController,
                                  errorText: _otpError,
                                  onChanged: (_) {
                                    if (_otpError != null) {
                                      setState(() => _otpError = null);
                                    }
                                  },
                                  onSubmitted: (_) => _primaryAction(),
                                  onResend: auth.isLoading.value
                                      ? null
                                      : _sendCode,
                                );
                              }),
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
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: UiStrings.t('village_or_location'),
                                  hintText: UiStrings.t('location_example'),
                                  prefixIcon: const Icon(
                                    Icons.location_on_outlined,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildIdentityDocumentSection(),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _agriRecordController,
                                textInputAction: TextInputAction.next,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: UiStrings.t(
                                    'farmer_agri_record_id',
                                  ),
                                  hintText: UiStrings.t('enter_agri_record_id'),
                                  prefixIcon: const Icon(
                                    Icons.assignment_ind_outlined,
                                  ),
                                ),
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return UiStrings.t(
                                      'enter_agri_record_id_error',
                                    );
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _aadhaarController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(12),
                                ],
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: UiStrings.t('aadhaar_number'),
                                  hintText: UiStrings.t('aadhaar_number_hint'),
                                  prefixIcon: const Icon(Icons.pin_outlined),
                                ),
                                validator: (value) {
                                  final digits = (value ?? '').replaceAll(
                                    RegExp(r'\D'),
                                    '',
                                  );
                                  if (digits.length != 12) {
                                    return UiStrings.t('aadhaar_number_error');
                                  }
                                  return null;
                                },
                              ),
                              Obx(
                                () => auth.errorMessage.isEmpty
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 14),
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
                              onPressed: auth.isLoading.value || _documentBusy
                                  ? null
                                  : _submit,
                              icon: auth.isLoading.value || _documentBusy
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
                                _documentBusy
                                    ? UiStrings.t(
                                        'reading_agri_record_document',
                                      )
                                    : auth.isLoading.value
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

class _SignupOtpStep extends StatelessWidget {
  final bool verified;
  final bool codeSent;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onResend;

  const _SignupOtpStep({
    required this.verified,
    required this.codeSent,
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    if (verified) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.greenPale.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: const Color(0xFFC9E4C5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_rounded, color: AppTheme.green),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mobile number verified',
                style: TextStyle(
                  color: AppTheme.greenDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          codeSent
              ? 'Enter the SMS code sent to this mobile number'
              : 'Verify this mobile number before creating the profile',
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        if (codeSent) ...[
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 6,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              counterText: '',
              errorText: errorText,
              labelText: 'SMS code',
              hintText: 'Enter SMS code',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onResend,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Resend code'),
            ),
          ),
        ],
      ],
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
    final key = statusKey.trim().isEmpty
        ? 'creating_farmer_profile'
        : statusKey;
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
  final String countryDialCode;

  const _ReadOnlyPhone({required this.phone, required this.countryDialCode});

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
                  '$countryDialCode $phone',
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
