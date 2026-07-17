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

  bool get _hasManualIdentityDetails =>
      _nameController.text.trim().isNotEmpty &&
      _aadhaarDigits.length == 12;

  String get _identitySource {
    if (_documentPath.trim().isEmpty) return 'manual_entry';
    return _documentOcrFailed
        ? 'manual_after_ocr_failure'
        : 'agri_record_document';
  }

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
    if (!_formKey.currentState!.validate()) return;
    if (_documentPath.isEmpty && !_hasManualIdentityDetails) {
      setState(() {
        _documentMessage = UiStrings.t('farmer_identity_document_required');
      });
      return;
    }
    if (_documentPath.isEmpty && mounted) {
      setState(() {
        _documentMessage = UiStrings.t('manual_identity_details_ready');
      });
    }
    FocusScope.of(context).unfocus();
    await Get.find<MainAuthController>().registerFarmerProfile(
      phone: _phone,
      farmerName: _nameController.text,
      defaultLocation: _locationController.text.trim().isEmpty
          ? 'Kalsubai Farms'
          : _locationController.text,
      agriRecordId: _agriRecordController.text,
      aadhaarNumber: _aadhaarDigits,
      aadhaarMasked: _aadhaarMasked,
      aadhaarLast4: _aadhaarLast4,
      identityDocumentPath: _documentPath,
      identitySource: _identitySource,
      identityOcrConfidence: _documentConfidence,
      nextRoute: _nextRoute,
    );
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
    final manualReady = _documentPath.isEmpty && _hasManualIdentityDetails;
    final hasAcceptedProof = _documentPath.isNotEmpty || manualReady;
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
              Icon(
                _documentBusy
                    ? Icons.document_scanner_outlined
                    : !hasAcceptedProof || _documentOcrFailed
                    ? Icons.info_outline
                    : Icons.check_circle_outline,
                color: !hasAcceptedProof && !_documentBusy
                    ? Colors.red.shade700
                    : AppTheme.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: !hasAcceptedProof
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
                                    'farmer_agri_record_id_optional',
                                  ),
                                  hintText: UiStrings.t('enter_agri_record_id'),
                                  prefixIcon: const Icon(
                                    Icons.assignment_ind_outlined,
                                  ),
                                ),
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
                          () => SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: auth.isLoading.value || _documentBusy
                                  ? null
                                  : _submit,
                              icon: _documentBusy || auth.isLoading.value
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                              label: _documentBusy || auth.isLoading.value
                                  ? const SizedBox.shrink()
                                  : Text(UiStrings.t('continue_to_farm_setup')),
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
