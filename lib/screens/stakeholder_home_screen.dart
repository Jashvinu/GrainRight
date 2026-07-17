import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/main_auth_controller.dart';
import '../controllers/stakeholder_controller.dart';
import '../models/stakeholder_land_record.dart';
import '../models/stakeholder_plan.dart';
import '../models/verified_farmer_record.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';
import 'package:kalsubai_farms/core/widgets/app_logout_flow.dart';
import '../widgets/farm_hills_background.dart';

class StakeholderHomeScreen extends StatefulWidget {
  const StakeholderHomeScreen({super.key});

  @override
  State<StakeholderHomeScreen> createState() => _StakeholderHomeScreenState();
}

class _StakeholderHomeScreenState extends State<StakeholderHomeScreen> {
  late final MainAuthController _auth;
  late final StakeholderController _stakeholder;
  late final Worker _farmerWorker;
  String _loadedFarmerKey = '';

  @override
  void initState() {
    super.initState();
    _auth = Get.find<MainAuthController>();
    _stakeholder = Get.find<StakeholderController>();
    _farmerWorker = ever<VerifiedFarmerRecord?>(
      _auth.verifiedFarmer,
      _loadForFarmer,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadForFarmer(_auth.verifiedFarmer.value);
    });
  }

  @override
  void dispose() {
    _farmerWorker.dispose();
    super.dispose();
  }

  void _loadForFarmer(VerifiedFarmerRecord? farmer) {
    final key = _farmerKey(farmer);
    if (key.isNotEmpty &&
        key == _loadedFarmerKey &&
        _stakeholder.plan.value != null) {
      return;
    }
    _loadedFarmerKey = key;
    _stakeholder.loadForFarmer(farmer);
  }

  Future<void> _refresh() async {
    _loadedFarmerKey = '';
    await _stakeholder.loadForFarmer(_auth.verifiedFarmer.value);
  }

  bool _hasNomineeSignatureProofs() {
    final primary = _stakeholder.nomineeSignature.value.contains(
      '/nominee_signature/',
    );
    final second =
        _stakeholder.nomineeCount.value == 1 ||
        _stakeholder.nominee2Signature.value.contains('/nominee2_signature/');
    return primary && second;
  }

  @override
  Widget build(BuildContext context) {
    return _StakeholderScaffold(
      title: UiStrings.t('stakeholder_home_title'),
      currentRoute: '/stakeholder',
      actions: [
        IconButton(
          tooltip: UiStrings.t('refresh'),
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Obx(() {
        final farmer = _auth.verifiedFarmer.value;
        if (farmer == null) {
          return _NoStakeholderProfile();
        }
        final plan = _stakeholder.plan.value ?? StakeholderPlan.fallback();
        final application = _stakeholder.application.value;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (_stakeholder.isLoading.value) const LinearProgressIndicator(),
              if (_stakeholder.isLoading.value) const SizedBox(height: 14),
              _StakeholderErrorBanner(
                message: _stakeholder.errorMessage.value,
                onRetry: _refresh,
              ),
              _PlanHeroCard(plan: plan, application: application),
              const SizedBox(height: 12),
              _InterestOnlyNotice(),
              const SizedBox(height: 12),
              _ApplicationSnapshot(
                plan: plan,
                application: application,
                selectedAmount: _stakeholder.selectedAmount.value,
                estimatedShares: _stakeholder.estimatedShares,
              ),
              if (application != null) ...[
                const SizedBox(height: 12),
                _ShareholderSummaryCard(
                  plan: plan,
                  application: application,
                  selectedAmount: _stakeholder.selectedAmount.value,
                  estimatedShares: _stakeholder.estimatedShares,
                ),
                if (_stakeholder.canStartPayment) ...[
                  const SizedBox(height: 12),
                  _StakeholderPaymentCard(
                    plan: plan,
                    stakeholder: _stakeholder,
                  ),
                ],
              ],
              if (application == null) ...[
                const SizedBox(height: 12),
                _PromptCard(
                  icon: Icons.currency_rupee_rounded,
                  title: UiStrings.t('stakeholder_no_application_title'),
                  body: UiStrings.t('stakeholder_no_application_body'),
                  actionLabel: UiStrings.t('stakeholder_submit_interest'),
                  onAction: () => Get.toNamed('/stakeholder/select-amount'),
                ),
              ],
              const SizedBox(height: 12),
              _FarmerRecordSection(farmer: farmer, application: application),
              const SizedBox(height: 12),
              _StakeholderChecklist(
                items: [
                  _ChecklistStatusItem(
                    label: 'PAN',
                    ready: _stakeholder.hasValidPanProof,
                    icon: Icons.badge_outlined,
                  ),
                  _ChecklistStatusItem(
                    label: 'Signatures',
                    ready: _hasNomineeSignatureProofs(),
                    icon: Icons.draw_outlined,
                  ),
                  _ChecklistStatusItem(
                    label: '7/12',
                    ready: _stakeholder.hasValidLandRecordProof,
                    icon: Icons.description_outlined,
                  ),
                  _ChecklistStatusItem(
                    label: 'Bank',
                    ready: _stakeholder.hasValidBankProof,
                    icon: Icons.account_balance_outlined,
                  ),
                  _ChecklistStatusItem(
                    label: 'Declaration',
                    ready:
                        _stakeholder.consentInterestOnly.value &&
                        _stakeholder.consentNoGuaranteedReturn.value &&
                        _stakeholder.consentDataUse.value,
                    icon: Icons.fact_check_outlined,
                  ),
                  _ChecklistStatusItem(
                    label: 'Review',
                    ready: application != null,
                    icon: Icons.admin_panel_settings_outlined,
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _StakeholderBackground extends StatelessWidget {
  final Widget child;

  const _StakeholderBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFCF5), AppTheme.surface],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 150,
            child: IgnorePointer(
              child: Opacity(opacity: 0.42, child: FarmHillsBackground()),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class StakeholderPlanDetailScreen extends StatelessWidget {
  const StakeholderPlanDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _ensureStakeholderLoaded();
    final stakeholder = Get.find<StakeholderController>();
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_plan_page_title'),
      currentRoute: '/stakeholder/plan',
      child: Obx(() {
        final plan = stakeholder.plan.value ?? StakeholderPlan.fallback();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (stakeholder.isLoading.value) const LinearProgressIndicator(),
            if (stakeholder.isLoading.value) const SizedBox(height: 14),
            _StakeholderErrorBanner(
              message: stakeholder.errorMessage.value,
              onRetry: () => stakeholder.loadForFarmer(
                Get.find<MainAuthController>().verifiedFarmer.value,
              ),
            ),
            _Section(
              title: plan.title,
              subtitle: plan.summary,
              child: _MetricGrid(
                metrics: [
                  _MetricData(
                    UiStrings.t('stakeholder_share_unit'),
                    _money(plan.shareUnitValue),
                  ),
                  _MetricData(
                    UiStrings.t('stakeholder_min_amount'),
                    _money(plan.minAmount),
                  ),
                  _MetricData(
                    UiStrings.t('stakeholder_max_amount'),
                    _money(plan.maxAmount),
                  ),
                  _MetricData(
                    UiStrings.t('stakeholder_application_status'),
                    _statusLabel(stakeholder.application.value?.status),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _BulletSection(
              title: UiStrings.t('stakeholder_plan_purpose'),
              items: plan.purpose,
            ),
            _BulletSection(
              title: UiStrings.t('stakeholder_use_of_funds'),
              items: plan.useOfFunds,
            ),
            _BulletSection(
              title: UiStrings.t('stakeholder_program_stages'),
              items: plan.stages,
            ),
            _BulletSection(
              title: UiStrings.t('stakeholder_risk_terms'),
              items: plan.riskNotes,
            ),
            _BulletSection(
              title: UiStrings.t('stakeholder_terms_title'),
              items: plan.terms,
            ),
          ],
        );
      }),
    );
  }
}

class StakeholderPanKycScreen extends StatefulWidget {
  const StakeholderPanKycScreen({super.key});

  @override
  State<StakeholderPanKycScreen> createState() =>
      _StakeholderPanKycScreenState();
}

class _StakeholderPanKycScreenState extends State<StakeholderPanKycScreen> {
  late final StakeholderController _stakeholder;
  late final TextEditingController _panController;
  late final TextEditingController _panHolderNameController;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _ensureStakeholderLoaded();
    _stakeholder = Get.find<StakeholderController>();
    _panController = TextEditingController(text: _stakeholder.panNumber.value);
    _panHolderNameController = TextEditingController(
      text: _stakeholder.panHolderName.value,
    );
  }

  @override
  void dispose() {
    _panController.dispose();
    _panHolderNameController.dispose();
    super.dispose();
  }

  Future<void> _pickPanDocument() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await _stakeholder.uploadPanDocument(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  bool _hasValidManualPanDetails() {
    return _stakeholder.hasPanManualDetails;
  }

  void _syncPanFields() {
    _stakeholder.setPanNumber(_panController.text);
    _stakeholder.setPanHolderName(_panHolderNameController.text);
  }

  void _save() {
    _syncPanFields();
    if (!_stakeholder.hasValidPanProof) {
      _showStakeholderMessage(
        context,
        'Enter valid PAN details or upload a clear PAN card image.',
      );
      return;
    }
    _showStakeholderMessage(context, 'PAN KYC saved.');
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return _StakeholderPage(
      title: 'PAN KYC',
      currentRoute: '/stakeholder/pan-kyc',
      child: Obx(() {
        final manualValid = _hasValidManualPanDetails();
        return Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  16,
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  24,
                ),
                children: [
                  _StakeholderErrorBanner(
                    message: _stakeholder.errorMessage.value,
                    onRetry: () => _stakeholder.loadForFarmer(
                      Get.find<MainAuthController>().verifiedFarmer.value,
                    ),
                  ),
                  const _SecureNotice(
                    icon: Icons.info_outline_rounded,
                    title: 'PAN KYC for identity verification',
                    body:
                        'Enter PAN details or upload the PAN card for Kalsubai Farms review.',
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'PAN Card Details',
                    child: Column(
                      children: [
                        _StakeholderFormTextField(
                          controller: _panController,
                          label: 'PAN number',
                          icon: Icons.credit_card_rounded,
                          maxLength: 14,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: _stakeholder.setPanNumber,
                          helperText: 'Example: ABCDE1234F',
                        ),
                        _StakeholderFormTextField(
                          controller: _panHolderNameController,
                          label: 'Name as per PAN optional',
                          icon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                          onChanged: _stakeholder.setPanHolderName,
                        ),
                        if (manualValid)
                          const _ProofStatusTile(
                            message:
                                'PAN details accepted. Upload is optional.',
                          ),
                        _DocumentUploadButton(
                          label: 'Upload PAN Card',
                          optional: manualValid,
                          uploaded: _stakeholder.panDocumentPath.value
                              .trim()
                              .isNotEmpty,
                          uploading: _stakeholder.isUploadingPan.value,
                          onPressed: _pickPanDocument,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _StakeholderBottomBar(
              primaryLabel: 'Save PAN Details',
              primaryIcon: Icons.save_outlined,
              onPrimary: _save,
            ),
          ],
        );
      }),
    );
  }
}

class StakeholderLandRecordScreen extends StatefulWidget {
  const StakeholderLandRecordScreen({super.key});

  @override
  State<StakeholderLandRecordScreen> createState() =>
      _StakeholderLandRecordScreenState();
}

class _StakeholderLandRecordScreenState
    extends State<StakeholderLandRecordScreen> {
  late final StakeholderController _stakeholder;
  late final _LandRecordFieldControllers _landRecordFields;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _ensureStakeholderLoaded();
    _stakeholder = Get.find<StakeholderController>();
    _landRecordFields = _LandRecordFieldControllers.fromSummary(
      _stakeholder.landRecordDetails.value,
    );
  }

  @override
  void dispose() {
    _landRecordFields.dispose();
    super.dispose();
  }

  Future<void> _pickLandRecordDocument(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await _stakeholder.uploadLandRecordDocument(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  void _syncLandRecord() {
    _stakeholder.setLandRecordDetails(_landRecordFields.details.summary);
  }

  void _save() {
    _syncLandRecord();
    if (!_stakeholder.hasValidLandRecordProof) {
      _showStakeholderMessage(
        context,
        'Complete the required 7/12 fields or upload the 7/12 land record image.',
      );
      return;
    }
    _showStakeholderMessage(context, '7/12 land record saved.');
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return _StakeholderPage(
      title: '7/12 Land Record',
      currentRoute: '/stakeholder/land-record',
      child: Obx(() {
        final manualValid = _stakeholder.hasLandRecordManualDetails;
        final uploaded = _stakeholder.hasLandRecordDocument;
        return SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    _StakeholderErrorBanner(
                      message: _stakeholder.errorMessage.value,
                      onRetry: () => _stakeholder.loadForFarmer(
                        Get.find<MainAuthController>().verifiedFarmer.value,
                      ),
                    ),
                    const _StakeholderStepTitle(
                      text: 'Enter 7/12 land details',
                      icon: Icons.description_outlined,
                    ),
                    const SizedBox(height: 12),
                    _LandRecordProgressBar(
                      fieldsReady: manualValid,
                      imageUploaded: uploaded,
                    ),
                    const SizedBox(height: 12),
                    const _LandRecordContextCard(),
                    const SizedBox(height: 16),
                    _LandRecordFieldsCard(
                      fields: _landRecordFields,
                      onChanged: _syncLandRecord,
                    ),
                    const SizedBox(height: 16),
                    _LandRecordProofPanel(
                      uploaded: uploaded,
                      uploading: _stakeholder.isUploadingLandRecord.value,
                      optional: manualValid,
                      onCamera: () =>
                          _pickLandRecordDocument(ImageSource.camera),
                      onGallery: () =>
                          _pickLandRecordDocument(ImageSource.gallery),
                    ),
                    const SizedBox(height: 12),
                    if (manualValid)
                      const _ProofStatusTile(
                        message: 'Required 7/12 fields are complete.',
                      ),
                    if (uploaded)
                      const _ProofStatusTile(
                        message: '7/12 land record image uploaded.',
                      ),
                  ],
                ),
              ),
              _StakeholderBottomBar(
                primaryLabel: 'Save 7/12 details',
                primaryIcon: Icons.save_outlined,
                onPrimary: _save,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class StakeholderBankDetailsScreen extends StatefulWidget {
  const StakeholderBankDetailsScreen({super.key});

  @override
  State<StakeholderBankDetailsScreen> createState() =>
      _StakeholderBankDetailsScreenState();
}

class _StakeholderBankDetailsScreenState
    extends State<StakeholderBankDetailsScreen> {
  late final StakeholderController _stakeholder;
  late final TextEditingController _accountHolderController;
  late final TextEditingController _accountNumberController;
  late final TextEditingController _confirmAccountNumberController;
  late final TextEditingController _ifscController;
  late final TextEditingController _upiController;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _ensureStakeholderLoaded();
    _stakeholder = Get.find<StakeholderController>();
    _accountHolderController = TextEditingController(
      text: _stakeholder.accountHolderName.value,
    );
    _accountNumberController = TextEditingController(
      text: _stakeholder.bankAccountNumber.value,
    );
    _confirmAccountNumberController = TextEditingController(
      text: _stakeholder.bankAccountNumber.value,
    );
    _ifscController = TextEditingController(text: _stakeholder.ifscCode.value);
    _upiController = TextEditingController(text: _stakeholder.upiId.value);
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _accountNumberController.dispose();
    _confirmAccountNumberController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _pickPassbookDocument() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await _stakeholder.uploadPassbookDocument(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  void _syncBankFields() {
    _stakeholder.setAccountHolderName(_accountHolderController.text);
    _stakeholder.setBankAccountNumber(_accountNumberController.text);
    _stakeholder.setIfscCode(_ifscController.text);
    _stakeholder.setUpiId(_upiController.text);
  }

  bool _hasValidManualBankDetails() {
    final account = _normalizedAccount(_accountNumberController.text);
    final confirm = _normalizedAccount(_confirmAccountNumberController.text);
    return _stakeholder.bankName.value.trim().length >= 2 &&
        _accountHolderController.text.trim().length >= 2 &&
        RegExp(r'^[0-9]{6,20}$').hasMatch(account) &&
        account == confirm &&
        RegExp(
          r'^[A-Z]{4}0[A-Z0-9]{6}$',
        ).hasMatch(_ifscController.text.trim().toUpperCase());
  }

  void _save() {
    _syncBankFields();
    final manualValid = _hasValidManualBankDetails();
    if (!manualValid && !_stakeholder.hasPassbookDocument) {
      _showStakeholderMessage(
        context,
        'Enter valid bank details or upload passbook/cancelled cheque image.',
      );
      return;
    }
    _showStakeholderMessage(context, 'Bank details saved.');
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return _StakeholderPage(
      title: 'Bank Details',
      currentRoute: '/stakeholder/bank-details',
      child: Obx(() {
        final manualValid = _hasValidManualBankDetails();
        return Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  16,
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  24,
                ),
                children: [
                  _StakeholderErrorBanner(
                    message: _stakeholder.errorMessage.value,
                    onRetry: () => _stakeholder.loadForFarmer(
                      Get.find<MainAuthController>().verifiedFarmer.value,
                    ),
                  ),
                  const _SecureNotice(
                    icon: Icons.lock_outline_rounded,
                    title: 'Your bank details are secure',
                    body:
                        'Used only for verification, review and future payouts.',
                  ),
                  const SizedBox(height: 12),
                  _Section(
                    title: 'Bank Account Details',
                    child: Column(
                      children: [
                        _BankDropdown(
                          value: _stakeholder.bankName.value,
                          onChanged: _stakeholder.setBankName,
                        ),
                        _StakeholderFormTextField(
                          controller: _accountHolderController,
                          label: 'Account holder name',
                          icon: Icons.person_outline_rounded,
                          textCapitalization: TextCapitalization.words,
                          onChanged: _stakeholder.setAccountHolderName,
                        ),
                        _StakeholderFormTextField(
                          controller: _accountNumberController,
                          label: 'Account number',
                          icon: Icons.numbers_rounded,
                          keyboardType: TextInputType.number,
                          onChanged: _stakeholder.setBankAccountNumber,
                        ),
                        _StakeholderFormTextField(
                          controller: _confirmAccountNumberController,
                          label: 'Confirm account number',
                          icon: Icons.verified_outlined,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                        ),
                        _StakeholderFormTextField(
                          controller: _ifscController,
                          label: 'IFSC code',
                          icon: Icons.confirmation_number_outlined,
                          maxLength: 11,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: _stakeholder.setIfscCode,
                        ),
                        _StakeholderFormTextField(
                          controller: _upiController,
                          label: 'UPI ID optional',
                          icon: Icons.alternate_email_rounded,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: _stakeholder.setUpiId,
                        ),
                        if (manualValid)
                          const _ProofStatusTile(
                            message:
                                'Bank details accepted. Upload is optional.',
                          ),
                        _DocumentUploadButton(
                          label: 'Upload Passbook',
                          optional: manualValid,
                          uploaded: _stakeholder.passbookDocumentPath.value
                              .trim()
                              .isNotEmpty,
                          uploading: _stakeholder.isUploadingPassbook.value,
                          onPressed: _pickPassbookDocument,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _StakeholderBottomBar(
              primaryLabel: 'Save Bank Details',
              primaryIcon: Icons.save_outlined,
              onPrimary: _save,
            ),
          ],
        );
      }),
    );
  }
}

class StakeholderSelectAmountScreen extends StatefulWidget {
  const StakeholderSelectAmountScreen({super.key});

  @override
  State<StakeholderSelectAmountScreen> createState() =>
      _StakeholderSelectAmountScreenState();
}

class _StakeholderSelectAmountScreenState
    extends State<StakeholderSelectAmountScreen> {
  late final StakeholderController _stakeholder;
  late final TextEditingController _farmerFullNameController;
  late final TextEditingController _farmerFatherNameController;
  late final TextEditingController _farmerMobileController;
  late final TextEditingController _farmerAadhaarLast4Controller;
  late final TextEditingController _farmerAgriRecordController;
  late final TextEditingController _farmerAddressController;
  late final TextEditingController _farmerVillageController;
  late final TextEditingController _farmerTalukaController;
  late final TextEditingController _farmerDistrictController;
  late final TextEditingController _farmerPincodeController;
  late final TextEditingController _farmerTotalLandAcresController;
  late final TextEditingController _nomineeNameController;
  late final TextEditingController _nomineeAddressController;
  late final TextEditingController _nomineeMobileController;
  late final TextEditingController _nominee2NameController;
  late final TextEditingController _nominee2AddressController;
  late final TextEditingController _nominee2MobileController;
  late final TextEditingController _noteController;
  late final TextEditingController _panController;
  late final TextEditingController _panHolderNameController;
  late final _LandRecordFieldControllers _landRecordFields;
  late final TextEditingController _accountHolderController;
  late final TextEditingController _accountNumberController;
  late final TextEditingController _confirmAccountNumberController;
  late final TextEditingController _ifscController;
  late final TextEditingController _upiController;
  late final Worker _noteWorker;
  final _picker = ImagePicker();
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _ensureStakeholderLoaded();
    _stakeholder = Get.find<StakeholderController>();
    final farmer = Get.find<MainAuthController>().verifiedFarmer.value;
    _farmerFullNameController = TextEditingController(
      text: _initialText(_stakeholder.farmerFullName.value, farmer?.farmerName),
    );
    _farmerFatherNameController = TextEditingController(
      text: _stakeholder.farmerFatherName.value,
    );
    _farmerMobileController = TextEditingController(
      text: _initialText(
        _stakeholder.farmerMobileNumber.value,
        _phoneText(farmer?.phone),
      ),
    );
    final fetchedAadhaarNumber = _initialText(
      _stakeholder.farmerAadhaarNumber.value,
      farmer?.aadhaarNumber,
    );
    final fetchedAadhaar = _initialText(
      fetchedAadhaarNumber,
      _initialText(_stakeholder.farmerAadhaarLast4.value, farmer?.aadhaarLast4),
    );
    _farmerAadhaarLast4Controller = TextEditingController(text: fetchedAadhaar);
    if (fetchedAadhaar.isNotEmpty) {
      _stakeholder.setFarmerAadhaarNumber(fetchedAadhaar);
    }
    final fetchedAgriRecord = _initialText(
      _stakeholder.farmerAgriRecordId.value,
      farmer?.agriRecordId,
    );
    _farmerAgriRecordController = TextEditingController(
      text: fetchedAgriRecord,
    );
    if (fetchedAgriRecord.isNotEmpty) {
      _stakeholder.setFarmerAgriRecordId(fetchedAgriRecord);
    }
    _farmerAddressController = TextEditingController(
      text: _initialText(
        _stakeholder.farmerAddress.value,
        farmer?.defaultLocation,
      ),
    );
    _farmerVillageController = TextEditingController(
      text: _stakeholder.farmerVillage.value,
    );
    _farmerTalukaController = TextEditingController(
      text: _stakeholder.farmerTaluka.value,
    );
    _farmerDistrictController = TextEditingController(
      text: _stakeholder.farmerDistrict.value,
    );
    _farmerPincodeController = TextEditingController(
      text: _stakeholder.farmerPincode.value,
    );
    _farmerTotalLandAcresController = TextEditingController(
      text: _stakeholder.farmerTotalLandAcres.value,
    );
    _nomineeNameController = TextEditingController(
      text: _stakeholder.nomineeName.value,
    );
    _nomineeAddressController = TextEditingController(
      text: _stakeholder.nomineeAddress.value,
    );
    _nomineeMobileController = TextEditingController(
      text: _stakeholder.nomineeMobileNumber.value,
    );
    _nominee2NameController = TextEditingController(
      text: _stakeholder.nominee2Name.value,
    );
    _nominee2AddressController = TextEditingController(
      text: _stakeholder.nominee2Address.value,
    );
    _nominee2MobileController = TextEditingController(
      text: _stakeholder.nominee2MobileNumber.value,
    );
    _noteController = TextEditingController(
      text: _stakeholder.farmerNote.value,
    );
    _panController = TextEditingController(text: _stakeholder.panNumber.value);
    _panHolderNameController = TextEditingController(
      text: _stakeholder.panHolderName.value,
    );
    _landRecordFields = _LandRecordFieldControllers.fromSummary(
      _stakeholder.landRecordDetails.value,
    );
    _accountHolderController = TextEditingController(
      text: _stakeholder.accountHolderName.value,
    );
    _accountNumberController = TextEditingController(
      text: _stakeholder.bankAccountNumber.value,
    );
    _confirmAccountNumberController = TextEditingController(
      text: _stakeholder.bankAccountNumber.value,
    );
    _ifscController = TextEditingController(text: _stakeholder.ifscCode.value);
    _upiController = TextEditingController(text: _stakeholder.upiId.value);
    _noteWorker = ever<String>(_stakeholder.farmerNote, (value) {
      if (_noteController.text != value) {
        _noteController.text = value;
      }
    });
  }

  @override
  void dispose() {
    _noteWorker.dispose();
    _farmerFullNameController.dispose();
    _farmerFatherNameController.dispose();
    _farmerMobileController.dispose();
    _farmerAadhaarLast4Controller.dispose();
    _farmerAgriRecordController.dispose();
    _farmerAddressController.dispose();
    _farmerVillageController.dispose();
    _farmerTalukaController.dispose();
    _farmerDistrictController.dispose();
    _farmerPincodeController.dispose();
    _farmerTotalLandAcresController.dispose();
    _nomineeNameController.dispose();
    _nomineeAddressController.dispose();
    _nomineeMobileController.dispose();
    _nominee2NameController.dispose();
    _nominee2AddressController.dispose();
    _nominee2MobileController.dispose();
    _noteController.dispose();
    _panController.dispose();
    _panHolderNameController.dispose();
    _landRecordFields.dispose();
    _accountHolderController.dispose();
    _accountNumberController.dispose();
    _confirmAccountNumberController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  static String _initialText(String current, String? fallback) {
    final existing = current.trim();
    if (existing.isNotEmpty) return existing;
    return (fallback ?? '').trim();
  }

  static String _phoneText(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
  }

  String _nomineeSummary() {
    final primary =
        '${_stakeholder.nomineeName.value} • ${_stakeholder.nomineeMobileNumber.value} • ${_uploadedLabel(_stakeholder.nomineeSignature.value)}';
    if (_stakeholder.nomineeCount.value == 1) return primary;
    final second =
        '${_stakeholder.nominee2Name.value} • ${_stakeholder.nominee2MobileNumber.value} • ${_uploadedLabel(_stakeholder.nominee2Signature.value)}';
    return '$primary\n$second';
  }

  Future<void> _submit() async {
    _syncApplicationFields();
    final ok = await _stakeholder.submitInterest(
      Get.find<MainAuthController>().verifiedFarmer.value,
    );
    if (ok) {
      Get.snackbar(
        'Submitted successfully',
        'Stakeholder request saved for admin review.',
        snackPosition: SnackPosition.BOTTOM,
      );
      Get.offNamed('/stakeholder/status');
    }
  }

  Future<void> _pickPanDocument() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await _stakeholder.uploadPanDocument(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  Future<void> _pickPassbookDocument() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await _stakeholder.uploadPassbookDocument(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  Future<void> _pickLandRecordDocument(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    await _stakeholder.uploadLandRecordDocument(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: await file.readAsBytes(),
      fileName: file.name,
    );
  }

  Future<void> _saveFarmerSignature(Uint8List bytes) async {
    await _stakeholder.uploadFarmerSignature(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: bytes,
      fileName: 'farmer-signature.png',
    );
  }

  Future<void> _saveNomineeSignature(Uint8List bytes) async {
    await _stakeholder.uploadNomineeSignature(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: bytes,
      fileName: 'nominee-signature.png',
    );
  }

  Future<void> _saveNominee2Signature(Uint8List bytes) async {
    await _stakeholder.uploadNominee2Signature(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      bytes: bytes,
      fileName: 'nominee-2-signature.png',
    );
  }

  Widget _buyTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
    bool enabled = true,
    TextInputType? keyboardType,
    int? maxLength,
    int maxLines = 1,
    String? helperText,
    TextCapitalization textCapitalization = TextCapitalization.characters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        maxLength: maxLength,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        textInputAction: maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          counterText: '',
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _documentButton({
    required String label,
    required bool uploaded,
    required bool uploading,
    required VoidCallback? onPressed,
    bool optional = false,
  }) {
    final buttonLabel = uploaded
        ? '$label uploaded'
        : optional
        ? '$label optional'
        : label;
    return OutlinedButton.icon(
      onPressed: uploading ? null : onPressed,
      icon: uploading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(uploaded ? Icons.check_circle_outline : Icons.upload_file),
      label: Text(buttonLabel),
    );
  }

  bool _accountNumbersMatch() {
    return _normalizedAccount(_accountNumberController.text) ==
        _normalizedAccount(_confirmAccountNumberController.text);
  }

  bool _hasValidManualPanStep() {
    return _stakeholder.hasPanManualDetails;
  }

  bool _hasValidManualBankStep() {
    return _stakeholder.bankName.value.trim().length >= 2 &&
        _accountHolderController.text.trim().length >= 2 &&
        RegExp(
          r'^[0-9]{6,20}$',
        ).hasMatch(_normalizedAccount(_accountNumberController.text)) &&
        _accountNumbersMatch() &&
        RegExp(
          r'^[A-Z]{4}0[A-Z0-9]{6}$',
        ).hasMatch(_ifscController.text.trim().toUpperCase());
  }

  bool _hasValidBankStep() {
    return _stakeholder.hasPassbookDocument || _hasValidManualBankStep();
  }

  bool _hasValidLandRecordStep() {
    return _stakeholder.hasValidLandRecordProof;
  }

  bool _hasValidFarmerDetailsStep() {
    return _stakeholder.hasFarmerApplicationDetails;
  }

  void _syncApplicationFields() {
    _stakeholder.setFarmerFullName(_farmerFullNameController.text);
    _stakeholder.setFarmerFatherName(_farmerFatherNameController.text);
    _stakeholder.setFarmerMobileNumber(_farmerMobileController.text);
    _stakeholder.setFarmerAadhaarNumber(_farmerAadhaarLast4Controller.text);
    _stakeholder.setFarmerAgriRecordId(_farmerAgriRecordController.text);
    _stakeholder.setFarmerAddress(_farmerAddressController.text);
    _stakeholder.setFarmerVillage(_farmerVillageController.text);
    _stakeholder.setFarmerTaluka(_farmerTalukaController.text);
    _stakeholder.setFarmerDistrict(_farmerDistrictController.text);
    _stakeholder.setFarmerPincode(_farmerPincodeController.text);
    _stakeholder.setFarmerTotalLandAcres(_farmerTotalLandAcresController.text);
    _stakeholder.setNomineeName(_nomineeNameController.text);
    _stakeholder.setNomineeAddress(_nomineeAddressController.text);
    _stakeholder.setNomineeMobileNumber(_nomineeMobileController.text);
    _stakeholder.setNominee2Name(_nominee2NameController.text);
    _stakeholder.setNominee2Address(_nominee2AddressController.text);
    _stakeholder.setNominee2MobileNumber(_nominee2MobileController.text);
    _stakeholder.setFarmerNote(_noteController.text);
    _stakeholder.setPanNumber(_panController.text);
    _stakeholder.setPanHolderName(_panHolderNameController.text);
    _stakeholder.setLandRecordDetails(_landRecordFields.details.summary);
    _stakeholder.setAccountHolderName(_accountHolderController.text);
    _stakeholder.setBankAccountNumber(_accountNumberController.text);
    _stakeholder.setIfscCode(_ifscController.text);
    _stakeholder.setUpiId(_upiController.text);
  }

  String _panProofSummary() {
    final hasManual = _hasValidManualPanStep();
    final hasDocument = _stakeholder.hasPanDocument;
    if (hasManual && hasDocument) {
      return '${_maskedPan(_stakeholder.panNumber.value)} • uploaded document';
    }
    if (hasManual) {
      final holderName = _stakeholder.panHolderName.value.trim();
      if (holderName.isEmpty) return _maskedPan(_stakeholder.panNumber.value);
      return '${_maskedPan(_stakeholder.panNumber.value)} • $holderName';
    }
    if (hasDocument) return 'Uploaded PAN document';
    return '-';
  }

  String _bankProofSummary() {
    final hasManual = _hasValidManualBankStep();
    final hasDocument = _stakeholder.hasPassbookDocument;
    if (hasManual && hasDocument) {
      return '${_stakeholder.bankName.value} ${_maskedAccount(_stakeholder.bankAccountNumber.value)} • uploaded passbook';
    }
    if (hasManual) {
      return '${_stakeholder.bankName.value} ${_maskedAccount(_stakeholder.bankAccountNumber.value)} • ${_stakeholder.ifscCode.value}';
    }
    if (hasDocument) return 'Uploaded passbook/cancelled cheque';
    return '-';
  }

  String _landRecordSummary() {
    final hasManual = _stakeholder.hasLandRecordManualDetails;
    final hasDocument = _stakeholder.hasLandRecordDocument;
    final details = StakeholderLandRecordDetails.fromSummary(
      _stakeholder.landRecordDetails.value,
    ).compactLabel;
    if (hasManual && hasDocument) {
      return '$details - uploaded image';
    }
    if (hasManual) return details;
    if (hasDocument) return 'Uploaded 7/12 land record';
    return '-';
  }

  bool _canContinueStep(StakeholderPlan plan, double amount) {
    _syncApplicationFields();
    switch (_step) {
      case 0:
        return _hasValidFarmerDetailsStep();
      case 1:
        return plan.isValidAmount(amount);
      case 2:
        return (_hasValidManualPanStep() || _stakeholder.hasPanDocument) &&
            !_stakeholder.isUploadingPan.value;
      case 3:
        return _hasValidLandRecordStep() &&
            !_stakeholder.isUploadingLandRecord.value;
      case 4:
        return _hasValidBankStep() && !_stakeholder.isUploadingPassbook.value;
      case 5:
        return _stakeholder.hasContractAcceptance &&
            _stakeholder.canSubmitBuyApplication &&
            _hasValidBankStep();
    }
    return false;
  }

  String _stepError() {
    switch (_step) {
      case 0:
        return 'Complete farmer details and drawn nominee signatures first.';
      case 1:
        return 'Select a valid amount in Rs 100 steps.';
      case 2:
        return 'Enter a valid PAN number or upload PAN card image.';
      case 3:
        return 'Complete the required 7/12 fields or upload the 7/12 land record image.';
      case 4:
        return 'Enter bank details or upload passbook/cancelled cheque image.';
      case 5:
        return 'Read each policy, complete every policy check, then draw farmer signature.';
    }
    return 'Complete this step first.';
  }

  void _continue(StakeholderPlan plan, double amount) {
    if (!_canContinueStep(plan, amount)) {
      _showStakeholderMessage(context, _stepError());
      return;
    }
    if (_step < 5) {
      setState(() => _step += 1);
      return;
    }
    _submit();
  }

  Widget _setupProgress() {
    const labels = ['Farmer', 'Amount', 'PAN', '7/12', 'Bank', 'Contract'];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration(AppTheme.greenPale),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index == _step;
          final done = index < _step;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : 6,
              ),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: active || done ? AppTheme.greenDark : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD6E3D1)),
              ),
              child: Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active || done ? Colors.white : AppTheme.greenDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _farmerDetailsStep() {
    final ready = _stakeholder.hasFarmerApplicationDetails;
    return _Section(
      title: 'Step 1: Farmer Details',
      subtitle:
          'Fill farmer identity, land holding and nominee details before selecting amount.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LandRecordSectionLabel(
            title: 'Farmer identity',
            subtitle: 'Use the same details that will appear in the contract.',
          ),
          _buyTextField(
            controller: _farmerFullNameController,
            label: 'Full name',
            icon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            onChanged: _stakeholder.setFarmerFullName,
          ),
          _buyTextField(
            controller: _farmerFatherNameController,
            label: 'Father name',
            icon: Icons.family_restroom_rounded,
            textCapitalization: TextCapitalization.words,
            onChanged: _stakeholder.setFarmerFatherName,
          ),
          _buyTextField(
            controller: _farmerMobileController,
            label: 'Mobile number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onChanged: _stakeholder.setFarmerMobileNumber,
          ),
          _LandRecordFieldRow(
            children: [
              _buyTextField(
                controller: _farmerAadhaarLast4Controller,
                label: 'Aadhaar number',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                maxLength: 12,
                helperText:
                    'Fetched from database. Edit only if correction is needed.',
                onChanged: _stakeholder.setFarmerAadhaarNumber,
              ),
              _buyTextField(
                controller: _farmerAgriRecordController,
                label: 'Farmer ID',
                icon: Icons.assignment_ind_outlined,
                helperText: 'Fetched from login. Edit if correction is needed.',
                onChanged: _stakeholder.setFarmerAgriRecordId,
              ),
            ],
          ),
          _buyTextField(
            controller: _farmerAddressController,
            label: 'Full address',
            icon: Icons.home_outlined,
            maxLines: 3,
            helperText: 'House, road, post and landmark if available.',
            textCapitalization: TextCapitalization.sentences,
            onChanged: _stakeholder.setFarmerAddress,
          ),
          _LandRecordFieldRow(
            children: [
              _buyTextField(
                controller: _farmerVillageController,
                label: 'Village',
                icon: Icons.location_city_outlined,
                textCapitalization: TextCapitalization.words,
                onChanged: _stakeholder.setFarmerVillage,
              ),
              _buyTextField(
                controller: _farmerTalukaController,
                label: 'Taluka',
                icon: Icons.map_outlined,
                textCapitalization: TextCapitalization.words,
                onChanged: _stakeholder.setFarmerTaluka,
              ),
            ],
          ),
          _LandRecordFieldRow(
            children: [
              _buyTextField(
                controller: _farmerDistrictController,
                label: 'District',
                icon: Icons.public_rounded,
                textCapitalization: TextCapitalization.words,
                onChanged: _stakeholder.setFarmerDistrict,
              ),
              _buyTextField(
                controller: _farmerPincodeController,
                label: 'Pincode',
                icon: Icons.local_post_office_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
                onChanged: _stakeholder.setFarmerPincode,
              ),
            ],
          ),
          _buyTextField(
            controller: _farmerTotalLandAcresController,
            label: 'Total farm land in acres',
            icon: Icons.square_foot_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            helperText: 'Example: 2.5',
            onChanged: _stakeholder.setFarmerTotalLandAcres,
          ),
          const _LandRecordSectionLabel(
            title: 'Nominee details',
            subtitle:
                'Select one or two nominees and draw a signature or thumb mark for each nominee.',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('1 nominee'),
                  selected: _stakeholder.nomineeCount.value == 1,
                  onSelected: (_) => _stakeholder.setNomineeCount(1),
                ),
                ChoiceChip(
                  label: const Text('2 nominees'),
                  selected: _stakeholder.nomineeCount.value == 2,
                  onSelected: (_) => _stakeholder.setNomineeCount(2),
                ),
              ],
            ),
          ),
          _buyTextField(
            controller: _nomineeNameController,
            label: 'Nominee 1 full name',
            icon: Icons.person_add_alt_1_outlined,
            textCapitalization: TextCapitalization.words,
            onChanged: _stakeholder.setNomineeName,
          ),
          _buyTextField(
            controller: _nomineeMobileController,
            label: 'Nominee 1 mobile number',
            icon: Icons.phone_android_outlined,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onChanged: _stakeholder.setNomineeMobileNumber,
          ),
          _buyTextField(
            controller: _nomineeAddressController,
            label: 'Nominee 1 full address',
            icon: Icons.home_work_outlined,
            maxLines: 3,
            helperText: 'House, road, village and landmark if available.',
            textCapitalization: TextCapitalization.sentences,
            onChanged: _stakeholder.setNomineeAddress,
          ),
          _SignaturePadPanel(
            title: 'Nominee 1 signature / thumb mark',
            subtitle: 'Draw nominee 1 signature or thumb mark in the box.',
            uploaded: _stakeholder.nomineeSignature.value.trim().isNotEmpty,
            uploading: _stakeholder.isUploadingNomineeSignature.value,
            uploadedText: 'Nominee 1 signature saved',
            emptyText: 'Nominee 1 signature required',
            onSave: _saveNomineeSignature,
          ),
          if (_stakeholder.nomineeCount.value == 2) ...[
            _buyTextField(
              controller: _nominee2NameController,
              label: 'Nominee 2 full name',
              icon: Icons.person_add_alt_1_outlined,
              textCapitalization: TextCapitalization.words,
              onChanged: _stakeholder.setNominee2Name,
            ),
            _buyTextField(
              controller: _nominee2MobileController,
              label: 'Nominee 2 mobile number',
              icon: Icons.phone_android_outlined,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              onChanged: _stakeholder.setNominee2MobileNumber,
            ),
            _buyTextField(
              controller: _nominee2AddressController,
              label: 'Nominee 2 full address',
              icon: Icons.home_work_outlined,
              maxLines: 3,
              helperText: 'House, road, village and landmark if available.',
              textCapitalization: TextCapitalization.sentences,
              onChanged: _stakeholder.setNominee2Address,
            ),
            _SignaturePadPanel(
              title: 'Nominee 2 signature / thumb mark',
              subtitle: 'Draw nominee 2 signature or thumb mark in the box.',
              uploaded: _stakeholder.nominee2Signature.value.trim().isNotEmpty,
              uploading: _stakeholder.isUploadingNominee2Signature.value,
              uploadedText: 'Nominee 2 signature saved',
              emptyText: 'Nominee 2 signature required',
              onSave: _saveNominee2Signature,
            ),
          ],
          if (ready)
            const _ProofStatusTile(
              message: 'Farmer and nominee details are complete.',
            ),
        ],
      ),
    );
  }

  Widget _amountStep(StakeholderPlan plan, double amount) {
    return _Section(
      title: 'Step 2: Select Amount',
      subtitle: 'Choose the share application amount before KYC.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricGrid(
            metrics: [
              _MetricData(
                UiStrings.t('stakeholder_selected_amount'),
                _money(amount),
              ),
              _MetricData(
                UiStrings.t('stakeholder_estimated_shares'),
                LocaleText.number(_stakeholder.estimatedShares),
              ),
              _MetricData(
                UiStrings.t('stakeholder_share_unit'),
                _money(plan.shareUnitValue),
              ),
              _MetricData('Step size', _money(StakeholderPlan.amountStep)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(
                tooltip: UiStrings.f('decrease_amount_by', {'amount': 100}),
                onPressed: () => _stakeholder.setSelectedAmount(
                  amount - StakeholderPlan.amountStep,
                ),
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _money(amount),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      UiStrings.f('amount_changes_in_steps', {'amount': 100}),
                      textAlign: TextAlign.center,
                      style: _smallMutedStyle,
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: UiStrings.f('increase_amount_by', {'amount': 100}),
                onPressed: () => _stakeholder.setSelectedAmount(
                  amount + StakeholderPlan.amountStep,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Slider(
            value: amount,
            min: plan.minAmount,
            max: plan.maxAmount,
            divisions: _sliderDivisions(plan),
            label: _money(amount),
            onChanged: _stakeholder.setSelectedAmount,
          ),
          Row(
            children: [
              Expanded(
                child: Text(_money(plan.minAmount), style: _smallMutedStyle),
              ),
              Text(_money(plan.maxAmount), style: _smallMutedStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panStep() {
    final hasManual = _hasValidManualPanStep();
    return _Section(
      title: 'Step 3: PAN KYC',
      subtitle: 'Enter PAN details or upload PAN card proof.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buyTextField(
            controller: _panController,
            label: 'PAN number',
            icon: Icons.credit_card_rounded,
            maxLength: 14,
            onChanged: _stakeholder.setPanNumber,
            helperText: 'Example: ABCDE1234F',
          ),
          _buyTextField(
            controller: _panHolderNameController,
            label: 'Name as per PAN optional',
            icon: Icons.person_outline_rounded,
            onChanged: _stakeholder.setPanHolderName,
          ),
          if (hasManual)
            const _ProofStatusTile(
              message: 'PAN details accepted. Upload is optional.',
            ),
          _documentButton(
            label: 'Upload PAN document',
            optional: hasManual,
            uploaded: _stakeholder.panDocumentPath.value.trim().isNotEmpty,
            uploading: _stakeholder.isUploadingPan.value,
            onPressed: _pickPanDocument,
          ),
        ],
      ),
    );
  }

  Widget _landRecordStep() {
    final hasManual = _stakeholder.hasLandRecordManualDetails;
    final hasDocument = _stakeholder.hasLandRecordDocument;
    return _Section(
      title: 'Step 4: 7/12 Land Record',
      subtitle:
          'Fill the land record fields or upload a clear 7/12 land record image.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LandRecordFieldsCard(
            fields: _landRecordFields,
            onChanged: _syncApplicationFields,
            dense: true,
          ),
          const SizedBox(height: 12),
          if (hasManual)
            const _ProofStatusTile(
              message: 'Required 7/12 fields are complete.',
            ),
          _LandRecordProofPanel(
            optional: hasManual,
            uploaded: hasDocument,
            uploading: _stakeholder.isUploadingLandRecord.value,
            onCamera: () => _pickLandRecordDocument(ImageSource.camera),
            onGallery: () => _pickLandRecordDocument(ImageSource.gallery),
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _bankStep() {
    final accountNumbersMatch = _accountNumbersMatch();
    final hasManual = _hasValidManualBankStep();
    return _Section(
      title: 'Step 5: Bank Details',
      subtitle:
          'Enter bank account details or upload passbook/cancelled cheque proof.',
      child: Column(
        children: [
          _BankDropdown(
            value: _stakeholder.bankName.value,
            onChanged: _stakeholder.setBankName,
          ),
          _buyTextField(
            controller: _accountHolderController,
            label: 'Account holder name',
            icon: Icons.person_outline_rounded,
            onChanged: _stakeholder.setAccountHolderName,
          ),
          _buyTextField(
            controller: _accountNumberController,
            label: 'Account number',
            icon: Icons.numbers_rounded,
            keyboardType: TextInputType.number,
            onChanged: _stakeholder.setBankAccountNumber,
          ),
          _buyTextField(
            controller: _confirmAccountNumberController,
            label: 'Confirm account number',
            icon: Icons.verified_outlined,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
          _buyTextField(
            controller: _ifscController,
            label: 'IFSC code',
            icon: Icons.confirmation_number_outlined,
            maxLength: 11,
            onChanged: _stakeholder.setIfscCode,
          ),
          _buyTextField(
            controller: _upiController,
            label: 'UPI ID optional',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            onChanged: _stakeholder.setUpiId,
          ),
          if (hasManual)
            const _ProofStatusTile(
              message: 'Bank details accepted. Upload is optional.',
            ),
          _documentButton(
            label: 'Upload passbook',
            optional: hasManual,
            uploaded: _stakeholder.passbookDocumentPath.value.trim().isNotEmpty,
            uploading: _stakeholder.isUploadingPassbook.value,
            onPressed: _pickPassbookDocument,
          ),
          if (!accountNumbersMatch)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                UiStrings.t('account_numbers_must_match'),
                style: TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contractStep(StakeholderPlan plan, double amount) {
    final contractReady = _stakeholder.contractReadAccepted.value;
    return Column(
      children: [
        _ShareholderSummaryCard(
          plan: plan,
          application: _stakeholder.application.value,
          selectedAmount: amount,
          estimatedShares: _stakeholder.estimatedShares,
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Step 6: Policy Check & Contract',
          subtitle:
              'Review every policy point, check consent, draw farmer signature and submit for admin review.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoTile(
                title: 'Farmer',
                value:
                    '${_stakeholder.farmerFullName.value} • ${_stakeholder.farmerMobileNumber.value}',
                icon: Icons.person_outline_rounded,
              ),
              _InfoTile(
                title: 'Nominee',
                value: _nomineeSummary(),
                icon: Icons.person_add_alt_1_outlined,
              ),
              _InfoTile(
                title: 'PAN KYC',
                value: _panProofSummary(),
                icon: Icons.badge_outlined,
              ),
              _InfoTile(
                title: '7/12 land record',
                value: _landRecordSummary(),
                icon: Icons.description_outlined,
              ),
              _InfoTile(
                title: 'Bank details',
                value: _bankProofSummary(),
                icon: Icons.account_balance_outlined,
              ),
              _PolicyChecklistPanel(
                contractReadAccepted: contractReady,
                consentInterestOnly: _stakeholder.consentInterestOnly.value,
                consentNoGuaranteedReturn:
                    _stakeholder.consentNoGuaranteedReturn.value,
                consentDataUse: _stakeholder.consentDataUse.value,
                onContractReadAccepted: _stakeholder.setContractReadAccepted,
                onConsentInterestOnly: contractReady
                    ? _stakeholder.setConsentInterestOnly
                    : null,
                onConsentNoGuaranteedReturn: contractReady
                    ? _stakeholder.setConsentNoGuaranteedReturn
                    : null,
                onConsentDataUse: contractReady
                    ? _stakeholder.setConsentDataUse
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                onChanged: _stakeholder.setFarmerNote,
                decoration: InputDecoration(
                  hintText: UiStrings.t('stakeholder_note_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _SignaturePadPanel(
                title: 'Farmer signature / thumb mark',
                subtitle:
                    'Draw farmer signature or thumb mark after reading the contract.',
                uploaded: _stakeholder.farmerSignature.value.trim().isNotEmpty,
                uploading: _stakeholder.isUploadingFarmerSignature.value,
                uploadedText: 'Farmer signature saved',
                emptyText: 'Farmer signature required',
                onSave: _saveFarmerSignature,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_select_amount'),
      currentRoute: '/stakeholder/select-amount',
      child: Obx(() {
        final plan = _stakeholder.plan.value ?? StakeholderPlan.fallback();
        final application = _stakeholder.application.value;
        final amount = _stakeholder.selectedAmount.value
            .clamp(plan.minAmount, plan.maxAmount)
            .toDouble();
        if (application != null) {
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (_stakeholder.isLoading.value) const LinearProgressIndicator(),
              if (_stakeholder.isLoading.value) const SizedBox(height: 14),
              _StakeholderErrorBanner(
                message: _stakeholder.errorMessage.value,
                onRetry: () => _stakeholder.loadForFarmer(
                  Get.find<MainAuthController>().verifiedFarmer.value,
                ),
              ),
              _ShareholderSummaryCard(
                plan: plan,
                application: application,
                selectedAmount: amount,
                estimatedShares: _stakeholder.estimatedShares,
              ),
              const SizedBox(height: 12),
              if (_stakeholder.canStartPayment)
                _StakeholderPaymentCard(plan: plan, stakeholder: _stakeholder)
              else
                _PromptCard(
                  icon: _stakeholder.hasPaidShares
                      ? Icons.verified_rounded
                      : Icons.lock_outline_rounded,
                  title: _stakeholder.hasPaidShares
                      ? 'Shares bought'
                      : UiStrings.t('stakeholder_application_locked_title'),
                  body: _stakeholder.hasPaidShares
                      ? 'Your bought shares are saved in stakeholder login and farmer profile.'
                      : UiStrings.t('stakeholder_application_locked_body'),
                  actionLabel: UiStrings.t('stakeholder_status_title'),
                  onAction: () => Get.offNamed('/stakeholder/status'),
                ),
            ],
          );
        }
        final stepContent = switch (_step) {
          0 => _farmerDetailsStep(),
          1 => _amountStep(plan, amount),
          2 => _panStep(),
          3 => _landRecordStep(),
          4 => _bankStep(),
          _ => _contractStep(plan, amount),
        };
        return Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  16,
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                  24,
                ),
                children: [
                  if (_stakeholder.isLoading.value)
                    const LinearProgressIndicator(),
                  if (_stakeholder.isLoading.value) const SizedBox(height: 14),
                  _StakeholderErrorBanner(
                    message: _stakeholder.errorMessage.value,
                    onRetry: () => _stakeholder.loadForFarmer(
                      Get.find<MainAuthController>().verifiedFarmer.value,
                    ),
                  ),
                  _setupProgress(),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: AppMotion.page,
                    switchInCurve: AppMotion.emphasized,
                    switchOutCurve: AppMotion.standard,
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: stepContent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_step < 5)
                    _Section(
                      title: 'Application flow',
                      subtitle:
                          'Complete the steps in order. Payment starts only after admin approval.',
                      child: const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
            _StakeholderBottomBar(
              primaryLabel: _step == 5 ? 'Submit interest' : 'Continue',
              primaryIcon: _stakeholder.isSubmitting.value
                  ? Icons.hourglass_top_rounded
                  : _step == 5
                  ? Icons.send_rounded
                  : Icons.arrow_forward_rounded,
              onPrimary: _stakeholder.isSubmitting.value
                  ? null
                  : () => _continue(plan, amount),
              secondaryLabel: _step == 0 ? null : 'Back',
              secondaryIcon: _step == 0 ? null : Icons.arrow_back_rounded,
              onSecondary: _step == 0 ? null : () => setState(() => _step -= 1),
            ),
          ],
        );
      }),
    );
  }
}

class StakeholderStatusScreen extends StatelessWidget {
  const StakeholderStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _ensureStakeholderLoaded();
    final stakeholder = Get.find<StakeholderController>();
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_status_title'),
      currentRoute: '/stakeholder/status',
      child: Obx(() {
        final plan = stakeholder.plan.value ?? StakeholderPlan.fallback();
        final application = stakeholder.application.value;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (stakeholder.isLoading.value) const LinearProgressIndicator(),
            if (stakeholder.isLoading.value) const SizedBox(height: 14),
            _StakeholderErrorBanner(
              message: stakeholder.errorMessage.value,
              onRetry: () => stakeholder.loadForFarmer(
                Get.find<MainAuthController>().verifiedFarmer.value,
              ),
            ),
            if (application != null) ...[
              _StakeholderSubmissionSuccessCard(application: application),
              const SizedBox(height: 12),
            ],
            _ApplicationSnapshot(
              plan: plan,
              application: application,
              selectedAmount: stakeholder.selectedAmount.value,
              estimatedShares: stakeholder.estimatedShares,
            ),
            if (application != null) ...[
              const SizedBox(height: 12),
              _ShareholderSummaryCard(
                plan: plan,
                application: application,
                selectedAmount: stakeholder.selectedAmount.value,
                estimatedShares: stakeholder.estimatedShares,
              ),
              const SizedBox(height: 12),
              _StakeholderApplicationDetailsCard(application: application),
              if (stakeholder.canStartPayment) ...[
                const SizedBox(height: 12),
                _StakeholderPaymentCard(plan: plan, stakeholder: stakeholder),
              ],
            ],
            if (application == null) ...[
              const SizedBox(height: 12),
              _PromptCard(
                icon: Icons.currency_rupee_rounded,
                title: UiStrings.t('stakeholder_no_application_title'),
                body: UiStrings.t('stakeholder_no_application_body'),
                actionLabel: UiStrings.t('stakeholder_submit_interest'),
                onAction: () => Get.toNamed('/stakeholder/select-amount'),
              ),
            ],
            const SizedBox(height: 12),
            _Section(
              title: UiStrings.t('stakeholder_review_timeline'),
              child: Column(
                children: [
                  _TimelineTile(
                    active: true,
                    title: UiStrings.t('stakeholder_timeline_draft'),
                    body: UiStrings.t('stakeholder_timeline_draft_body'),
                  ),
                  _TimelineTile(
                    active: application != null,
                    title: UiStrings.t('stakeholder_timeline_submitted'),
                    body: application == null
                        ? UiStrings.t('stakeholder_timeline_submit_pending')
                        : UiStrings.t('stakeholder_timeline_submitted_body'),
                  ),
                  _TimelineTile(
                    active: application != null,
                    title: UiStrings.t('stakeholder_timeline_review'),
                    body: UiStrings.t('stakeholder_timeline_review_body'),
                  ),
                  _TimelineTile(
                    active:
                        application?.status ==
                        StakeholderApplicationStatus.approved,
                    title: UiStrings.t('stakeholder_timeline_approval'),
                    body: UiStrings.t('stakeholder_timeline_approval_body'),
                    last: true,
                  ),
                ],
              ),
            ),
            if (stakeholder.events.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Section(
                title: UiStrings.t('stakeholder_application_status'),
                child: Column(
                  children: stakeholder.events
                      .map(
                        (event) => _InfoTile(
                          title: event.title,
                          value: _eventText(event),
                          icon: Icons.history_rounded,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _Section(
              title: UiStrings.t('stakeholder_status_next_title'),
              subtitle: UiStrings.t('stakeholder_status_next_body'),
              child: const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            if (application == null)
              FilledButton.icon(
                onPressed: () => Get.toNamed('/stakeholder/select-amount'),
                icon: const Icon(Icons.currency_rupee_rounded),
                label: Text(UiStrings.t('stakeholder_submit_interest')),
              ),
          ],
        );
      }),
    );
  }
}

class StakeholderProfileScreen extends StatelessWidget {
  const StakeholderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _ensureStakeholderLoaded();
    final auth = Get.find<MainAuthController>();
    final stakeholder = Get.find<StakeholderController>();
    return _StakeholderPage(
      title: UiStrings.t('profile'),
      currentRoute: '/stakeholder/profile',
      child: Obx(() {
        final farmer = auth.verifiedFarmer.value;
        final application = stakeholder.application.value;
        if (farmer == null) {
          return _NoStakeholderProfile();
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _Section(
              title: UiStrings.t('stakeholder_verified_title'),
              child: Column(
                children: [
                  _InfoTile(
                    title: UiStrings.t('stakeholder_farmer_name'),
                    value: farmer.farmerName,
                    icon: Icons.verified_user_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_farmer_identity'),
                    value: farmer.farmerId,
                    icon: Icons.badge_outlined,
                  ),
                  _InfoTile(
                    title: 'Mobile number',
                    value: farmer.phone,
                    icon: Icons.phone_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_agri_record_id'),
                    value: _firstNonEmpty(
                      application?.agriRecordId,
                      farmer.agriRecordId,
                    ),
                    icon: Icons.assignment_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_aadhaar_number'),
                    value: _aadhaarRecordLabel(
                      application: application,
                      farmer: farmer,
                    ),
                    icon: Icons.credit_card_outlined,
                  ),
                  _InfoTile(
                    title: 'Address',
                    value: farmer.defaultLocation,
                    icon: Icons.location_on_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ApplicationSnapshot(
              plan: stakeholder.plan.value ?? StakeholderPlan.fallback(),
              application: stakeholder.application.value,
              selectedAmount: stakeholder.selectedAmount.value,
              estimatedShares: stakeholder.estimatedShares,
            ),
            if (stakeholder.application.value != null) ...[
              const SizedBox(height: 12),
              _ShareholderSummaryCard(
                plan: stakeholder.plan.value ?? StakeholderPlan.fallback(),
                application: stakeholder.application.value,
                selectedAmount: stakeholder.selectedAmount.value,
                estimatedShares: stakeholder.estimatedShares,
              ),
            ],
          ],
        );
      }),
    );
  }
}

class StakeholderDocumentsScreen extends StatelessWidget {
  const StakeholderDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _ensureStakeholderLoaded();
    final auth = Get.find<MainAuthController>();
    final stakeholder = Get.find<StakeholderController>();
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_documents_title'),
      currentRoute: '/stakeholder/documents',
      child: Obx(() {
        final farmer = auth.verifiedFarmer.value;
        final application = stakeholder.application.value;
        if (farmer == null) {
          return _NoStakeholderProfile();
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _Section(
              title: UiStrings.t('stakeholder_verified_title'),
              child: Column(
                children: [
                  _InfoTile(
                    title: UiStrings.t('stakeholder_farmer_identity'),
                    value: farmer.farmerId,
                    icon: Icons.badge_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_farmer_name'),
                    value: farmer.farmerName,
                    icon: Icons.verified_user_outlined,
                  ),
                  _InfoTile(
                    title: 'Mobile number',
                    value: farmer.phone,
                    icon: Icons.phone_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_agri_record_id'),
                    value: _firstNonEmpty(
                      application?.agriRecordId,
                      farmer.agriRecordId,
                    ),
                    icon: Icons.assignment_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_aadhaar_number'),
                    value: _aadhaarRecordLabel(
                      application: application,
                      farmer: farmer,
                    ),
                    icon: Icons.credit_card_outlined,
                  ),
                  _InfoTile(
                    title: 'Address',
                    value: farmer.defaultLocation,
                    icon: Icons.location_on_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: UiStrings.t('stakeholder_consent_snapshot'),
              child: Column(
                children: [
                  _InfoTile(
                    title: UiStrings.t('stakeholder_consent_interest_only'),
                    value: _yesNo(application?.consentInterestOnly ?? false),
                    icon: Icons.check_circle_outline,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_consent_no_return'),
                    value: _yesNo(
                      application?.consentNoGuaranteedReturn ?? false,
                    ),
                    icon: Icons.check_circle_outline,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_consent_data_use'),
                    value: _yesNo(application?.consentDataUse ?? false),
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ),
            ),
            if (application != null) ...[
              const SizedBox(height: 12),
              _Section(
                title: 'KYC and payment records',
                child: Column(
                  children: [
                    _InfoTile(
                      title: 'PAN number',
                      value: _maskedPan(application.panNumber),
                      icon: Icons.credit_card_outlined,
                    ),
                    _InfoTile(
                      title: 'Name as per PAN',
                      value: application.panHolderName,
                      icon: Icons.person_outline_rounded,
                    ),
                    _InfoTile(
                      title: 'PAN document',
                      value: _uploadedLabel(application.panDocumentPath),
                      icon: Icons.upload_file_outlined,
                    ),
                    _InfoTile(
                      title: '7/12 land record',
                      value: _landRecordApplicationLabel(application),
                      icon: Icons.description_outlined,
                    ),
                    _InfoTile(
                      title: 'Farmer signature',
                      value: _uploadedLabel(application.farmerSignature),
                      icon: Icons.draw_outlined,
                    ),
                    _InfoTile(
                      title: 'Nominee 1 signature',
                      value: _uploadedLabel(application.nomineeSignature),
                      icon: Icons.draw_outlined,
                    ),
                    if (application.nomineeCount == 2)
                      _InfoTile(
                        title: 'Nominee 2 signature',
                        value: _uploadedLabel(application.nominee2Signature),
                        icon: Icons.draw_outlined,
                      ),
                    _InfoTile(
                      title: 'Account holder',
                      value: application.accountHolderName,
                      icon: Icons.person_outline_rounded,
                    ),
                    _InfoTile(
                      title: 'Bank account',
                      value:
                          '${application.bankName} ${_maskedAccount(application.bankAccountNumber)}',
                      icon: Icons.account_balance_outlined,
                    ),
                    _InfoTile(
                      title: 'IFSC code',
                      value: application.ifscCode,
                      icon: Icons.confirmation_number_outlined,
                    ),
                    _InfoTile(
                      title: 'Passbook',
                      value: _uploadedLabel(application.passbookDocumentPath),
                      icon: Icons.upload_file_outlined,
                    ),
                    _InfoTile(
                      title: 'Payment method',
                      value: _paymentMethodLabel(application.paymentMethod),
                      icon: Icons.payment_rounded,
                    ),
                    _InfoTile(
                      title: 'Payment status',
                      value: _paymentStatusLabel(application.paymentStatus),
                      icon: Icons.fact_check_outlined,
                    ),
                    if (application.bankTransferReference.trim().isNotEmpty)
                      _InfoTile(
                        title: 'Transfer reference',
                        value: application.bankTransferReference,
                        icon: Icons.receipt_long_outlined,
                      ),
                    if (application.bankTransferProofPath.trim().isNotEmpty)
                      _InfoTile(
                        title: 'Transfer proof',
                        value: _uploadedLabel(
                          application.bankTransferProofPath,
                        ),
                        icon: Icons.upload_file_outlined,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (application == null) ...[
              _PromptCard(
                icon: Icons.folder_copy_outlined,
                title: UiStrings.t('stakeholder_documents_empty_title'),
                body: UiStrings.t('stakeholder_documents_empty_body'),
                actionLabel: UiStrings.t('stakeholder_submit_interest'),
                onAction: () => Get.toNamed('/stakeholder/select-amount'),
              ),
              const SizedBox(height: 12),
            ],
            _Section(
              title: UiStrings.t('stakeholder_future_documents'),
              subtitle: UiStrings.t('stakeholder_future_documents_body'),
              child: const SizedBox.shrink(),
            ),
          ],
        );
      }),
    );
  }
}

class StakeholderHelpScreen extends StatelessWidget {
  const StakeholderHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_help_title'),
      currentRoute: '/stakeholder/help',
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          _Section(
            title: UiStrings.t('stakeholder_help_title'),
            subtitle: UiStrings.t('stakeholder_help_intro'),
            child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          _FaqTile(
            title: UiStrings.t('stakeholder_faq_what_title'),
            body: UiStrings.t('stakeholder_faq_what_body'),
          ),
          _FaqTile(
            title: UiStrings.t('stakeholder_faq_shares_title'),
            body: UiStrings.t('stakeholder_faq_shares_body'),
          ),
          _FaqTile(
            title: UiStrings.t('stakeholder_faq_approval_title'),
            body: UiStrings.t('stakeholder_faq_approval_body'),
          ),
          _FaqTile(
            title: UiStrings.t('stakeholder_faq_returns_title'),
            body: UiStrings.t('stakeholder_faq_returns_body'),
          ),
        ],
      ),
    );
  }
}

class _StakeholderPage extends StatelessWidget {
  final String title;
  final String currentRoute;
  final Widget child;

  const _StakeholderPage({
    required this.title,
    required this.child,
    this.currentRoute = '',
  });

  @override
  Widget build(BuildContext context) {
    return _StakeholderScaffold(
      title: title,
      currentRoute: currentRoute,
      showBack: true,
      child: child,
    );
  }
}

class _StakeholderScaffold extends StatelessWidget {
  final String title;
  final String currentRoute;
  final Widget child;
  final List<Widget> actions;
  final bool showBack;

  const _StakeholderScaffold({
    required this.title,
    required this.currentRoute,
    required this.child,
    this.actions = const [],
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      drawer: wide ? null : _StakeholderDrawer(currentRoute: currentRoute),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: !wide,
        leadingWidth: wide ? null : appBackButtonLeadingWidth,
        leading: wide
            ? null
            : Builder(
                builder: (context) => showBack
                    ? appBackButtonLeading(
                        context,
                        onPressed: () => Get.offNamed('/stakeholder'),
                      )!
                    : appMenuButtonLeading(context),
              ),
        title: Text(UiStrings.fromEnglish(title)),
        actions: [
          ...actions,
          if (showBack && !wide) ...[
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: AppMenuButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      body: _StakeholderBackground(
        child: _StakeholderResponsiveBody(
          currentRoute: currentRoute,
          child: child,
        ),
      ),
    );
  }
}

class _StakeholderResponsiveBody extends StatelessWidget {
  final String currentRoute;
  final Widget child;

  const _StakeholderResponsiveBody({
    required this.currentRoute,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return _StakeholderAnimatedSurface(child: child);
        }
        final expandedNavigation = constraints.maxWidth >= 1060;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StakeholderNavigationPanel(
              currentRoute: currentRoute,
              expanded: expandedNavigation,
            ),
            Expanded(child: _StakeholderAnimatedSurface(child: child)),
          ],
        );
      },
    );
  }
}

class _StakeholderAnimatedSurface extends StatelessWidget {
  final Widget child;

  const _StakeholderAnimatedSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 1180
            ? 1180.0
            : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            height: constraints.maxHeight,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.page,
              curve: AppMotion.emphasized,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 10),
                    child: child,
                  ),
                );
              },
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _StakeholderNavigationPanel extends StatelessWidget {
  final String currentRoute;
  final bool expanded;

  const _StakeholderNavigationPanel({
    required this.currentRoute,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: expanded ? 272 : 104,
      margin: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF4FAEF)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFDCE8D2)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.10),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _StakeholderNavigationContent(
        currentRoute: currentRoute,
        closeDrawerOnTap: false,
        expanded: expanded,
      ),
    );
  }
}

class _StakeholderDrawer extends StatelessWidget {
  final String currentRoute;

  const _StakeholderDrawer({required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: _StakeholderNavigationContent(
        currentRoute: currentRoute,
        closeDrawerOnTap: true,
        expanded: true,
      ),
    );
  }
}

class _StakeholderNavigationContent extends StatelessWidget {
  final String currentRoute;
  final bool closeDrawerOnTap;
  final bool expanded;

  const _StakeholderNavigationContent({
    required this.currentRoute,
    required this.closeDrawerOnTap,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    final farmer = auth.verifiedFarmer.value;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(expanded ? 14 : 10),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(expanded ? 14 : 10),
              decoration: _cardDecoration(AppTheme.greenPale),
              child: expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFDCE8D2)),
                          ),
                          child: const Icon(
                            Icons.handshake_outlined,
                            color: AppTheme.greenDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          UiStrings.t('stakeholder_home_title'),
                          style: const TextStyle(
                            color: AppTheme.greenDark,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          farmer?.farmerName.trim().isNotEmpty == true
                              ? farmer!.farmerName
                              : UiStrings.t('stakeholder_no_profile_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((farmer?.phone ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            '+91 ${farmer!.phone}',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Tooltip(
                      message: farmer?.farmerName.trim().isNotEmpty == true
                          ? farmer!.farmerName
                          : UiStrings.t('stakeholder_home_title'),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFDCE8D2)),
                        ),
                        child: const Icon(
                          Icons.handshake_outlined,
                          color: AppTheme.greenDark,
                          size: 28,
                        ),
                      ),
                    ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                expanded ? 10 : 8,
                0,
                expanded ? 10 : 8,
                10,
              ),
              children: [
                _StakeholderDrawerTile(
                  item: _StakeholderSectionItem(
                    icon: Icons.person_outline_rounded,
                    title: UiStrings.t('profile'),
                    subtitle: 'Farmer record',
                    route: '/stakeholder/profile',
                  ),
                  currentRoute: currentRoute,
                  closeDrawerOnTap: closeDrawerOnTap,
                  expanded: expanded,
                ),
                for (final item in _stakeholderSectionItems())
                  _StakeholderDrawerTile(
                    item: item,
                    currentRoute: currentRoute,
                    closeDrawerOnTap: closeDrawerOnTap,
                    expanded: expanded,
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              expanded ? 12 : 10,
              6,
              expanded ? 12 : 10,
              16,
            ),
            child: Tooltip(
              message: UiStrings.t('logout'),
              child: OutlinedButton.icon(
                onPressed: () async {
                  if (closeDrawerOnTap) Get.back();
                  await AppLogoutFlow.run(
                    context,
                    onLogout: Get.find<MainAuthController>().logout,
                  );
                },
                icon: const Icon(Icons.logout_rounded),
                label: expanded
                    ? Text(UiStrings.t('logout'))
                    : const SizedBox.shrink(),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(expanded ? 50 : 56),
                  padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StakeholderDrawerTile extends StatelessWidget {
  final _StakeholderSectionItem item;
  final String currentRoute;
  final bool closeDrawerOnTap;
  final bool expanded;

  const _StakeholderDrawerTile({
    required this.item,
    required this.currentRoute,
    required this.closeDrawerOnTap,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final selected = item.route == currentRoute;
    final tile = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: selected
            ? null
            : () {
                if (closeDrawerOnTap) Get.back();
                Get.offNamed(item.route);
              },
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          constraints: BoxConstraints(minHeight: expanded ? 58 : 56),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 8,
            vertical: expanded ? 8 : 6,
          ),
          decoration: BoxDecoration(
            color: selected ? AppTheme.greenDark : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: expanded
              ? Row(
                  children: [
                    Icon(
                      item.icon,
                      color: selected ? Colors.white : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : AppTheme.textDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.78)
                                  : AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Icon(
                    item.icon,
                    color: selected ? Colors.white : AppTheme.textMuted,
                    size: 24,
                  ),
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: expanded ? tile : Tooltip(message: item.title, child: tile),
    );
  }
}

class _NoStakeholderProfile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              UiStrings.t('stakeholder_no_profile_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              UiStrings.t('stakeholder_no_profile_desc'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Get.offNamed('/stakeholder/login'),
              child: Text(UiStrings.t('stakeholder_login_cta')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanHeroCard extends StatelessWidget {
  final StakeholderPlan plan;
  final StakeholderApplication? application;

  const _PlanHeroCard({required this.plan, required this.application});

  @override
  Widget build(BuildContext context) {
    final hasApplication = application != null;
    final paymentReady =
        application?.status == StakeholderApplicationStatus.approved &&
        application?.paymentStatus !=
            StakeholderPaymentStatus.gatewayVerified &&
        application?.paymentStatus !=
            StakeholderPaymentStatus.bankTransferSubmitted;
    final locked =
        hasApplication &&
        application!.status != StakeholderApplicationStatus.submitted;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(AppTheme.greenPale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
              ),
              _StatusChip(status: application?.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan.summary,
            style: const TextStyle(
              color: AppTheme.textMuted,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Get.toNamed(
                    paymentReady
                        ? '/stakeholder/select-amount'
                        : locked
                        ? '/stakeholder/status'
                        : '/stakeholder/select-amount',
                  ),
                  icon: Icon(
                    paymentReady
                        ? Icons.payment_rounded
                        : locked
                        ? Icons.timeline_rounded
                        : Icons.currency_rupee_rounded,
                  ),
                  label: Text(
                    paymentReady
                        ? 'Start payment'
                        : locked
                        ? UiStrings.t('stakeholder_status_title')
                        : hasApplication
                        ? UiStrings.t('stakeholder_select_amount')
                        : UiStrings.t('stakeholder_submit_interest'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: UiStrings.t('stakeholder_status_title'),
                onPressed: () => Get.toNamed('/stakeholder/status'),
                icon: const Icon(Icons.timeline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _PromptCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTheme.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _InterestOnlyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Section(
      title: UiStrings.t('stakeholder_interest_only_title'),
      subtitle: UiStrings.t('stakeholder_interest_only_body'),
      child: const SizedBox.shrink(),
    );
  }
}

class _StakeholderSubmissionSuccessCard extends StatelessWidget {
  final StakeholderApplication application;

  const _StakeholderSubmissionSuccessCard({required this.application});

  @override
  Widget build(BuildContext context) {
    final status = application.status;
    final title = switch (status) {
      StakeholderApplicationStatus.approved => 'Application approved',
      StakeholderApplicationStatus.rejected => 'Application rejected',
      StakeholderApplicationStatus.underReview => 'Application under review',
      _ => 'Submitted successfully',
    };
    final body = switch (status) {
      StakeholderApplicationStatus.approved =>
        'Admin approved this stakeholder request. Payment can start from this page.',
      StakeholderApplicationStatus.rejected =>
        'Admin rejected this stakeholder request. Check the admin note or contact Kalsubai Farms.',
      StakeholderApplicationStatus.underReview =>
        'Kalsubai Farms admin is reviewing the submitted farmer stakeholder request.',
      _ =>
        'Your farmer stakeholder request is saved and waiting for admin review.',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(AppTheme.greenPale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            status == StakeholderApplicationStatus.rejected
                ? Icons.cancel_outlined
                : Icons.verified_rounded,
            color: status == StakeholderApplicationStatus.rejected
                ? const Color(0xFFB91C1C)
                : AppTheme.greenDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.textDark,
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

class _ApplicationSnapshot extends StatelessWidget {
  final StakeholderPlan plan;
  final StakeholderApplication? application;
  final double selectedAmount;
  final int estimatedShares;

  const _ApplicationSnapshot({
    required this.plan,
    required this.application,
    required this.selectedAmount,
    required this.estimatedShares,
  });

  @override
  Widget build(BuildContext context) {
    final submittedAt = application?.submittedAt;
    final paymentMethod = application?.paymentMethod ?? '';
    final paymentStatus = application?.paymentStatus ?? '';
    return _Section(
      title: UiStrings.t('stakeholder_application_snapshot'),
      child: _MetricGrid(
        metrics: [
          _MetricData(
            UiStrings.t('stakeholder_application_status'),
            _statusLabel(application?.status),
          ),
          _MetricData(
            UiStrings.t('stakeholder_selected_amount'),
            _money(application?.selectedAmount ?? selectedAmount),
          ),
          _MetricData(
            UiStrings.t('stakeholder_estimated_shares'),
            LocaleText.number(application?.estimatedShares ?? estimatedShares),
          ),
          _MetricData(
            UiStrings.t('stakeholder_share_unit'),
            _money(plan.shareUnitValue),
          ),
          if (paymentMethod.trim().isNotEmpty)
            _MetricData('Payment method', _paymentMethodLabel(paymentMethod)),
          if (paymentStatus.trim().isNotEmpty)
            _MetricData('Payment status', _paymentStatusLabel(paymentStatus)),
          if (submittedAt != null)
            _MetricData(
              UiStrings.t('stakeholder_submitted_at'),
              '${LocaleText.date(submittedAt)} ${LocaleText.time(submittedAt)}',
            ),
        ],
      ),
    );
  }
}

class _StakeholderApplicationDetailsCard extends StatelessWidget {
  final StakeholderApplication application;

  const _StakeholderApplicationDetailsCard({required this.application});

  @override
  Widget build(BuildContext context) {
    final aadhaarEnding = application.farmerAadhaarLast4.trim().isNotEmpty
        ? application.farmerAadhaarLast4
        : application.aadhaarLast4;
    final nomineeSummary = application.nomineeCount == 2
        ? '${application.nomineeName} (${application.nomineeMobileNumber})\n${application.nominee2Name} (${application.nominee2MobileNumber})'
        : '${application.nomineeName} (${application.nomineeMobileNumber})';
    final farmerAddress = [
      application.farmerAddress,
      application.farmerVillage,
      application.farmerTaluka,
      application.farmerDistrict,
      application.farmerPincode,
    ].where((part) => part.trim().isNotEmpty).join(', ');
    return _Section(
      title: 'Submitted stakeholder details',
      subtitle: 'Farmer, nominee, KYC, land and bank details saved for review.',
      child: Column(
        children: [
          _InfoTile(
            title: 'Farmer full name',
            value: application.farmerFullName,
            icon: Icons.person_outline_rounded,
          ),
          _InfoTile(
            title: 'Father name',
            value: application.farmerFatherName,
            icon: Icons.badge_outlined,
          ),
          _InfoTile(
            title: 'Mobile and Aadhaar',
            value:
                '${application.farmerMobileNumber} • Aadhaar ending ${aadhaarEnding.trim().isEmpty ? '-' : aadhaarEnding}',
            icon: Icons.phone_android_outlined,
          ),
          _InfoTile(
            title: 'Address',
            value: farmerAddress,
            icon: Icons.home_work_outlined,
          ),
          _InfoTile(
            title: 'Land record',
            value:
                '${application.agriRecordId} • ${application.farmerTotalLandAcres} acres\n${_landRecordDisplay(application)}',
            icon: Icons.description_outlined,
          ),
          _InfoTile(
            title: 'Nominee',
            value: nomineeSummary,
            icon: Icons.person_add_alt_1_outlined,
          ),
          _InfoTile(
            title: 'PAN',
            value: application.panNumber.trim().isEmpty
                ? _uploadedLabel(application.panDocumentPath)
                : application.panNumber,
            icon: Icons.credit_card_rounded,
          ),
          _InfoTile(
            title: 'Bank',
            value:
                '${application.accountHolderName}\n${application.bankName} • ${application.bankAccountNumber}\nIFSC ${application.ifscCode}',
            icon: Icons.account_balance_outlined,
          ),
          _InfoTile(
            title: 'Contract signatures',
            value:
                'Farmer: ${_uploadedLabel(application.farmerSignature)}\nNominee: ${_uploadedLabel(application.nomineeSignature)}',
            icon: Icons.draw_outlined,
          ),
          if (application.adminNote.trim().isNotEmpty)
            _InfoTile(
              title: 'Admin note',
              value: application.adminNote,
              icon: Icons.admin_panel_settings_outlined,
            ),
        ],
      ),
    );
  }

  String _landRecordDisplay(StakeholderApplication application) {
    if (application.landRecordDetails.trim().isNotEmpty) {
      return application.landRecordDetails;
    }
    return _uploadedLabel(application.landRecordDocumentPath);
  }
}

class _ShareholderSummaryCard extends StatelessWidget {
  final StakeholderPlan plan;
  final StakeholderApplication? application;
  final double selectedAmount;
  final int estimatedShares;

  const _ShareholderSummaryCard({
    required this.plan,
    required this.application,
    required this.selectedAmount,
    required this.estimatedShares,
  });

  @override
  Widget build(BuildContext context) {
    final farmer = Get.isRegistered<MainAuthController>()
        ? Get.find<MainAuthController>().verifiedFarmer.value
        : null;
    final paid =
        application?.paymentStatus == StakeholderPaymentStatus.gatewayVerified;
    final approved =
        application?.status == StakeholderApplicationStatus.approved;
    final amount = application?.selectedAmount ?? selectedAmount;
    final shares = application?.estimatedShares ?? estimatedShares;
    return _Section(
      title: paid
          ? 'Shareholder Summary'
          : approved
          ? 'Approved Share Application'
          : 'Short Shareholder Format',
      subtitle: paid
          ? 'Bought shares are now linked to this stakeholder and farmer profile.'
          : approved
          ? 'Admin approved this application. Start payment to buy shares.'
          : 'Review this format before submitting interest for admin approval.',
      child: _MetricGrid(
        metrics: [
          _MetricData(
            'Farmer ID',
            application?.farmerId ?? farmer?.farmerId ?? '-',
          ),
          _MetricData(
            'Farmer name',
            application?.farmerName ?? farmer?.farmerName ?? '-',
          ),
          _MetricData('Share unit', _money(plan.shareUnitValue)),
          _MetricData('Application amount', _money(amount)),
          _MetricData('Shares', LocaleText.number(shares)),
          _MetricData(
            'Shareholder status',
            paid
                ? 'Shares bought'
                : approved
                ? 'Approved for payment'
                : _statusLabel(application?.status),
          ),
        ],
      ),
    );
  }
}

class _StakeholderPaymentCard extends StatefulWidget {
  final StakeholderPlan plan;
  final StakeholderController stakeholder;

  const _StakeholderPaymentCard({
    required this.plan,
    required this.stakeholder,
  });

  @override
  State<_StakeholderPaymentCard> createState() =>
      _StakeholderPaymentCardState();
}

class _StakeholderPaymentCardState extends State<_StakeholderPaymentCard> {
  late final Razorpay _razorpay;
  Completer<bool>? _paymentCompleter;
  StakeholderRazorpayOrder? _activeOrder;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _startPayment() async {
    final farmer = Get.find<MainAuthController>().verifiedFarmer.value;
    final order = await widget.stakeholder.createRazorpayOrder(farmer);
    if (order == null) return;
    final completer = Completer<bool>();
    _activeOrder = order;
    _paymentCompleter = completer;
    try {
      _razorpay.open({
        'key': order.keyId,
        'amount': order.amountSubunits,
        'currency': order.currency,
        'name': 'Kalsubai Farms',
        'description': 'Approved stakeholder share payment',
        'order_id': order.orderId,
        'allow_rotation': true,
        'prefill': {
          'name': farmer?.farmerName.trim() ?? '',
          'contact': farmer?.phone ?? '',
        },
        'notes': {
          'farmer_id': farmer?.farmerId ?? '',
          'selected_amount': widget.stakeholder.selectedAmount.value
              .toStringAsFixed(0),
        },
        'theme': {'color': '#0B5D2A'},
      });
    } catch (_) {
      _activeOrder = null;
      _paymentCompleter = null;
      widget.stakeholder.errorMessage.value =
          'Could not open payment. Try again.';
      if (!completer.isCompleted) completer.complete(false);
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final order = _activeOrder;
    final completer = _paymentCompleter;
    if (order == null || completer == null || completer.isCompleted) return;
    final ok = await widget.stakeholder.verifyRazorpayPayment(
      farmer: Get.find<MainAuthController>().verifiedFarmer.value,
      razorpayOrderId: response.orderId ?? order.orderId,
      razorpayPaymentId: response.paymentId ?? '',
      razorpaySignature: response.signature ?? '',
    );
    if (!completer.isCompleted) completer.complete(ok);
    _activeOrder = null;
    _paymentCompleter = null;
    if (ok && mounted) {
      _showStakeholderMessage(context, 'Payment verified. Shares bought.');
      Get.offNamed('/stakeholder/status');
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    final completer = _paymentCompleter;
    widget.stakeholder.errorMessage.value =
        response.message ?? 'Payment was cancelled or failed.';
    if (completer != null && !completer.isCompleted) {
      completer.complete(false);
    }
    _activeOrder = null;
    _paymentCompleter = null;
  }

  void _handleExternalWallet(ExternalWalletResponse _) {}

  @override
  Widget build(BuildContext context) {
    final application = widget.stakeholder.application.value;
    return _Section(
      title: 'Start Payment',
      subtitle:
          'Your application is approved. Complete payment to buy the approved shares.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricGrid(
            metrics: [
              _MetricData(
                'Approved amount',
                _money(application?.selectedAmount ?? 0),
              ),
              _MetricData(
                'Shares to buy',
                LocaleText.number(application?.estimatedShares ?? 0),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: widget.stakeholder.isSubmitting.value
                  ? null
                  : _startPayment,
              icon: widget.stakeholder.isSubmitting.value
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payment_rounded),
              label: Text(UiStrings.t('pay_now_buy_shares')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.fromEnglish(title),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              UiStrings.fromEnglish(subtitle!),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          if (child is! SizedBox) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }
}

class _BulletSection extends StatelessWidget {
  final String title;
  final List<String> items;

  const _BulletSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Section(
        title: title,
        child: Column(
          children: items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: AppTheme.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          UiStrings.fromEnglish(item),
                          style: const TextStyle(
                            color: AppTheme.textDark,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _MetricData {
  final String title;
  final String value;

  const _MetricData(this.title, this.value);
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> metrics;

  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return GridView.builder(
          itemCount: metrics.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: compact ? 1 : 2,
            childAspectRatio: compact ? 4.2 : 2.7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final metric = metrics[index];
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _smallMutedStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.value.trim().isEmpty ? '-' : metric.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InfoTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(UiStrings.fromEnglish(title), style: _smallMutedStyle),
                const SizedBox(height: 3),
                Text(
                  displayValue,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
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

class _FarmerRecordSection extends StatelessWidget {
  final VerifiedFarmerRecord farmer;
  final StakeholderApplication? application;

  const _FarmerRecordSection({required this.farmer, required this.application});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Farmer record before allocation',
      subtitle: 'Short record linked to this application.',
      child: _MetricGrid(
        metrics: [
          _MetricData(
            'Farmer',
            _firstNonEmpty(application?.farmerFullName, farmer.farmerName),
          ),
          _MetricData(
            'Aadhaar number',
            _aadhaarRecordLabel(application: application, farmer: farmer),
          ),
          _MetricData(
            'Farmer ID',
            _firstNonEmpty(application?.agriRecordId, farmer.agriRecordId),
          ),
        ],
      ),
    );
  }
}

class _ChecklistStatusItem {
  final String label;
  final bool ready;
  final IconData icon;

  const _ChecklistStatusItem({
    required this.label,
    required this.ready,
    required this.icon,
  });
}

class _StakeholderChecklist extends StatelessWidget {
  final List<_ChecklistStatusItem> items;

  const _StakeholderChecklist({required this.items});

  @override
  Widget build(BuildContext context) {
    final readyCount = items.where((item) => item.ready).length;
    return _Section(
      title: 'Farmer stakeholder checklist',
      subtitle: '$readyCount/${items.length} ready before allocation review.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final item in items) _ChecklistPill(item: item)],
      ),
    );
  }
}

class _ChecklistPill extends StatelessWidget {
  final _ChecklistStatusItem item;

  const _ChecklistPill({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.ready ? AppTheme.greenDark : AppTheme.textMuted;
    final background = item.ready ? AppTheme.greenPale : AppTheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: item.ready ? const Color(0xFFD6E8D0) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.ready ? Icons.check_circle_rounded : item.icon,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 6),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StakeholderSectionItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _StakeholderSectionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

List<_StakeholderSectionItem> _stakeholderSectionItems({
  bool includeHome = true,
}) {
  return [
    if (includeHome)
      _StakeholderSectionItem(
        icon: Icons.dashboard_outlined,
        title: UiStrings.t('stakeholder_home_title'),
        subtitle: 'Overview',
        route: '/stakeholder',
      ),
    _StakeholderSectionItem(
      icon: Icons.currency_rupee_rounded,
      title: UiStrings.t('stakeholder_select_amount'),
      subtitle: 'Application',
      route: '/stakeholder/select-amount',
    ),
    _StakeholderSectionItem(
      icon: Icons.badge_outlined,
      title: 'PAN KYC',
      subtitle: 'Identity',
      route: '/stakeholder/pan-kyc',
    ),
    _StakeholderSectionItem(
      icon: Icons.description_outlined,
      title: '7/12 Land Record',
      subtitle: 'Farm record',
      route: '/stakeholder/land-record',
    ),
    _StakeholderSectionItem(
      icon: Icons.account_balance_outlined,
      title: 'Bank Details',
      subtitle: 'Payout record',
      route: '/stakeholder/bank-details',
    ),
    _StakeholderSectionItem(
      icon: Icons.timeline_rounded,
      title: UiStrings.t('stakeholder_status_title'),
      subtitle: 'Review',
      route: '/stakeholder/status',
    ),
    _StakeholderSectionItem(
      icon: Icons.folder_copy_outlined,
      title: UiStrings.t('stakeholder_documents_title'),
      subtitle: 'Saved proofs',
      route: '/stakeholder/documents',
    ),
    _StakeholderSectionItem(
      icon: Icons.help_outline_rounded,
      title: UiStrings.t('stakeholder_help_title'),
      subtitle: 'Questions',
      route: '/stakeholder/help',
    ),
  ];
}

class _StakeholderStepTitle extends StatelessWidget {
  final String text;
  final IconData icon;

  const _StakeholderStepTitle({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            UiStrings.fromEnglish(text),
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _LandRecordProgressBar extends StatelessWidget {
  final bool fieldsReady;
  final bool imageUploaded;

  const _LandRecordProgressBar({
    required this.fieldsReady,
    required this.imageUploaded,
  });

  @override
  Widget build(BuildContext context) {
    final saveReady = fieldsReady || imageUploaded;
    final steps = [
      _LandRecordProgressStep(
        label: 'Fields',
        icon: Icons.edit_note_rounded,
        done: fieldsReady,
        active: !fieldsReady,
      ),
      _LandRecordProgressStep(
        label: 'Image',
        icon: Icons.image_outlined,
        done: imageUploaded,
        active: fieldsReady && !imageUploaded,
      ),
      _LandRecordProgressStep(
        label: 'Save',
        icon: Icons.save_outlined,
        done: saveReady,
        active: saveReady,
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: _cardDecoration(AppTheme.greenPale),
      child: Row(
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final color = step.done || step.active
              ? AppTheme.green
              : AppTheme.textMuted;
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 4,
                        color: index == 0
                            ? Colors.transparent
                            : (steps[index - 1].done
                                  ? AppTheme.green
                                  : const Color(0xFFE2E7DC)),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: step.done ? AppTheme.green : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: step.done || step.active
                              ? AppTheme.green
                              : const Color(0xFFD9E0D6),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        step.done ? Icons.check_rounded : step.icon,
                        size: 18,
                        color: step.done ? Colors.white : color,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 4,
                        color: index == steps.length - 1
                            ? Colors.transparent
                            : (step.done
                                  ? AppTheme.green
                                  : const Color(0xFFE2E7DC)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  UiStrings.fromEnglish(step.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _LandRecordProgressStep {
  final String label;
  final IconData icon;
  final bool done;
  final bool active;

  const _LandRecordProgressStep({
    required this.label,
    required this.icon,
    required this.done,
    required this.active,
  });
}

class _LandRecordContextCard extends StatelessWidget {
  const _LandRecordContextCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5ECE2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined, color: AppTheme.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.t('farmer_land_ownership_record'),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  UiStrings.t('farmer_land_record_entry_help'),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
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

class _LandRecordFieldControllers {
  final TextEditingController surveyGatNumber;
  final TextEditingController subDivisionNumber;
  final TextEditingController village;
  final TextEditingController taluka;
  final TextEditingController district;
  final TextEditingController ownerName;
  final TextEditingController landArea;
  final TextEditingController cultivableArea;
  final TextEditingController khataNumber;
  final TextEditingController cropOrUse;
  final TextEditingController irrigationSource;
  final TextEditingController mutationEntryNumber;
  final TextEditingController landRevenue;
  final TextEditingController otherRights;

  _LandRecordFieldControllers._(StakeholderLandRecordDetails details)
    : surveyGatNumber = TextEditingController(text: details.surveyGatNumber),
      subDivisionNumber = TextEditingController(
        text: details.subDivisionNumber,
      ),
      village = TextEditingController(text: details.village),
      taluka = TextEditingController(text: details.taluka),
      district = TextEditingController(text: details.district),
      ownerName = TextEditingController(text: details.ownerName),
      landArea = TextEditingController(text: details.landArea),
      cultivableArea = TextEditingController(text: details.cultivableArea),
      khataNumber = TextEditingController(text: details.khataNumber),
      cropOrUse = TextEditingController(text: details.cropOrUse),
      irrigationSource = TextEditingController(text: details.irrigationSource),
      mutationEntryNumber = TextEditingController(
        text: details.mutationEntryNumber,
      ),
      landRevenue = TextEditingController(text: details.landRevenue),
      otherRights = TextEditingController(text: details.otherRights);

  factory _LandRecordFieldControllers.fromSummary(String summary) {
    return _LandRecordFieldControllers._(
      StakeholderLandRecordDetails.fromSummary(summary),
    );
  }

  StakeholderLandRecordDetails get details => StakeholderLandRecordDetails(
    surveyGatNumber: surveyGatNumber.text,
    subDivisionNumber: subDivisionNumber.text,
    village: village.text,
    taluka: taluka.text,
    district: district.text,
    ownerName: ownerName.text,
    landArea: landArea.text,
    cultivableArea: cultivableArea.text,
    khataNumber: khataNumber.text,
    cropOrUse: cropOrUse.text,
    irrigationSource: irrigationSource.text,
    mutationEntryNumber: mutationEntryNumber.text,
    landRevenue: landRevenue.text,
    otherRights: otherRights.text,
  );

  void dispose() {
    surveyGatNumber.dispose();
    subDivisionNumber.dispose();
    village.dispose();
    taluka.dispose();
    district.dispose();
    ownerName.dispose();
    landArea.dispose();
    cultivableArea.dispose();
    khataNumber.dispose();
    cropOrUse.dispose();
    irrigationSource.dispose();
    mutationEntryNumber.dispose();
    landRevenue.dispose();
    otherRights.dispose();
  }
}

class _LandRecordFieldsCard extends StatelessWidget {
  final _LandRecordFieldControllers fields;
  final VoidCallback onChanged;
  final bool dense;

  const _LandRecordFieldsCard({
    required this.fields,
    required this.onChanged,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!dense) ...[
          const _StakeholderStepTitle(
            text: 'Manual 7/12 extract',
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 12),
        ],
        const _LandRecordSectionLabel(
          title: 'Required land identity',
          subtitle: 'These details are enough when no 7/12 image is uploaded.',
        ),
        _LandRecordFieldRow(
          children: [
            _LandRecordTextField(
              controller: fields.surveyGatNumber,
              label: 'Survey/Gat number',
              icon: Icons.tag_rounded,
              helperText: 'Example: Gat 45/2',
              onChanged: onChanged,
            ),
            _LandRecordTextField(
              controller: fields.subDivisionNumber,
              label: 'Sub-division optional',
              icon: Icons.call_split_rounded,
              helperText: 'Example: Hissa 1A',
              onChanged: onChanged,
            ),
          ],
        ),
        _LandRecordFieldRow(
          children: [
            _LandRecordTextField(
              controller: fields.village,
              label: 'Village',
              icon: Icons.location_city_outlined,
              textCapitalization: TextCapitalization.words,
              onChanged: onChanged,
            ),
            _LandRecordTextField(
              controller: fields.taluka,
              label: 'Taluka',
              icon: Icons.map_outlined,
              textCapitalization: TextCapitalization.words,
              onChanged: onChanged,
            ),
          ],
        ),
        _LandRecordFieldRow(
          children: [
            _LandRecordTextField(
              controller: fields.district,
              label: 'District',
              icon: Icons.public_rounded,
              textCapitalization: TextCapitalization.words,
              onChanged: onChanged,
            ),
            _LandRecordTextField(
              controller: fields.landArea,
              label: 'Land area',
              icon: Icons.square_foot_rounded,
              helperText: 'Example: 2 acres',
              onChanged: onChanged,
            ),
          ],
        ),
        _LandRecordTextField(
          controller: fields.ownerName,
          label: 'Owner name on 7/12',
          icon: Icons.person_pin_circle_outlined,
          textCapitalization: TextCapitalization.words,
          onChanged: onChanged,
        ),
        const _LandRecordSectionLabel(
          title: 'Detailed 7/12 fields',
          subtitle: 'Fill what is visible on the extract for faster review.',
        ),
        _LandRecordFieldRow(
          children: [
            _LandRecordTextField(
              controller: fields.cultivableArea,
              label: 'Cultivable area optional',
              icon: Icons.landscape_outlined,
              helperText: 'Example: 1.75 acres',
              onChanged: onChanged,
            ),
            _LandRecordTextField(
              controller: fields.khataNumber,
              label: 'Khata number optional',
              icon: Icons.confirmation_number_outlined,
              onChanged: onChanged,
            ),
          ],
        ),
        _LandRecordFieldRow(
          children: [
            _LandRecordTextField(
              controller: fields.cropOrUse,
              label: 'Crop/land use optional',
              icon: Icons.grass_rounded,
              textCapitalization: TextCapitalization.words,
              onChanged: onChanged,
            ),
            _LandRecordTextField(
              controller: fields.irrigationSource,
              label: 'Irrigation source optional',
              icon: Icons.water_drop_outlined,
              textCapitalization: TextCapitalization.words,
              helperText: 'Example: Well, borewell, rainfed',
              onChanged: onChanged,
            ),
          ],
        ),
        _LandRecordFieldRow(
          children: [
            _LandRecordTextField(
              controller: fields.mutationEntryNumber,
              label: 'Mutation/Ferfar entry optional',
              icon: Icons.history_edu_outlined,
              onChanged: onChanged,
            ),
            _LandRecordTextField(
              controller: fields.landRevenue,
              label: 'Land revenue optional',
              icon: Icons.receipt_long_outlined,
              helperText: 'Example: Rs 12.50',
              onChanged: onChanged,
            ),
          ],
        ),
        _LandRecordTextField(
          controller: fields.otherRights,
          label: 'Other rights/loan charge optional',
          icon: Icons.gavel_outlined,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          onChanged: onChanged,
        ),
      ],
    );
    if (dense) return child;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5ECE2)),
      ),
      child: child,
    );
  }
}

class _LandRecordSectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _LandRecordSectionLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.green,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(title),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  UiStrings.fromEnglish(subtitle),
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
        ],
      ),
    );
  }
}

class _LandRecordTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback onChanged;
  final TextCapitalization textCapitalization;
  final String? helperText;
  final int maxLines;

  const _LandRecordTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.textCapitalization = TextCapitalization.characters,
    this.helperText,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        textCapitalization: textCapitalization,
        textInputAction: maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: UiStrings.fromEnglish(label),
          helperText: helperText == null
              ? null
              : UiStrings.fromEnglish(helperText!),
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }
}

class _LandRecordFieldRow extends StatelessWidget {
  final List<Widget> children;

  const _LandRecordFieldRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: children);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

class _LandRecordProofPanel extends StatelessWidget {
  final bool uploaded;
  final bool uploading;
  final bool optional;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final bool compact;

  const _LandRecordProofPanel({
    required this.uploaded,
    required this.uploading,
    required this.optional,
    required this.onCamera,
    required this.onGallery,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final preview = Container(
      height: compact ? 132 : 188,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1EFE6),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5ECE2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            uploaded ? Icons.verified_rounded : Icons.document_scanner_outlined,
            size: compact ? 48 : 72,
            color: uploaded ? AppTheme.green : const Color(0xFFB7BCAE),
          ),
          const SizedBox(height: 10),
          Text(
            uploaded
                ? UiStrings.t('land_record_image_uploaded')
                : optional
                ? UiStrings.t('image_optional')
                : UiStrings.t('add_land_image_if_incomplete'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          const _StakeholderStepTitle(
            text: '7/12 image proof',
            icon: Icons.image_outlined,
          ),
          const SizedBox(height: 12),
        ],
        preview,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: uploading ? null : onCamera,
                icon: uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_rounded),
                label: Text(UiStrings.t(uploaded ? 'retake_photo' : 'camera')),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(compact ? 48 : 56),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: uploading ? null : onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  UiStrings.t(uploaded ? 'replace_image' : 'gallery'),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(compact ? 48 : 56),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    if (compact) return content;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFE5ECE2)),
      ),
      child: content,
    );
  }
}

class _SignaturePadPanel extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool uploaded;
  final bool uploading;
  final String uploadedText;
  final String emptyText;
  final Future<void> Function(Uint8List bytes) onSave;

  const _SignaturePadPanel({
    required this.title,
    required this.subtitle,
    required this.uploaded,
    required this.uploading,
    required this.uploadedText,
    required this.emptyText,
    required this.onSave,
  });

  @override
  State<_SignaturePadPanel> createState() => _SignaturePadPanelState();
}

class _SignaturePadPanelState extends State<_SignaturePadPanel> {
  final List<List<Offset>> _strokes = <List<Offset>>[];
  Size _canvasSize = Size.zero;

  bool get _hasInk => _strokes.any((stroke) => stroke.isNotEmpty);

  void _startStroke(DragStartDetails details) {
    if (widget.uploading) return;
    setState(() {
      _strokes.add(<Offset>[_bounded(details.localPosition)]);
    });
  }

  void _appendStroke(DragUpdateDetails details) {
    if (widget.uploading || _strokes.isEmpty) return;
    setState(() {
      _strokes.last.add(_bounded(details.localPosition));
    });
  }

  Offset _bounded(Offset point) {
    if (_canvasSize == Size.zero) return point;
    return Offset(
      point.dx.clamp(0, _canvasSize.width).toDouble(),
      point.dy.clamp(0, _canvasSize.height).toDouble(),
    );
  }

  Future<void> _save() async {
    if (!_hasInk || widget.uploading) return;
    final size = _canvasSize == Size.zero ? const Size(320, 156) : _canvasSize;
    final bytes = await _renderSignaturePng(
      _strokes.map((stroke) => List<Offset>.from(stroke)).toList(),
      size,
    );
    await widget.onSave(bytes);
  }

  void _clear() {
    if (widget.uploading || !_hasInk) return;
    setState(_strokes.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(AppTheme.greenPale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                widget.uploaded ? Icons.verified_rounded : Icons.draw_outlined,
                color: widget.uploaded ? AppTheme.green : AppTheme.greenDark,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.fromEnglish(widget.title),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.uploaded
                          ? UiStrings.fromEnglish(widget.uploadedText)
                          : '${UiStrings.fromEnglish(widget.emptyText)}. ${UiStrings.fromEnglish(widget.subtitle)}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 320.0;
              final height = width < 360 ? 146.0 : 164.0;
              _canvasSize = Size(width, height);
              return GestureDetector(
                onPanStart: _startStroke,
                onPanUpdate: _appendStroke,
                child: CustomPaint(
                  size: _canvasSize,
                  painter: _SignaturePainter(strokes: _strokes),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.uploading || !_hasInk ? null : _clear,
                  icon: const Icon(Icons.backspace_outlined),
                  label: Text(UiStrings.t('clear')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.uploading || !_hasInk ? null : _save,
                  icon: widget.uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(UiStrings.t(widget.uploaded ? 'update' : 'save')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  const _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      BorderRadius.circular(8).toRRect(rect),
      Paint()..color = Colors.white,
    );
    final borderPaint = Paint()
      ..color = const Color(0xFFD6E3D1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(BorderRadius.circular(8).toRRect(rect), borderPaint);
    final guidePaint = Paint()
      ..color = const Color(0xFFE4ECE0)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(18, size.height - 34),
      Offset(size.width - 18, size.height - 34),
      guidePaint,
    );
    _drawStrokes(canvas, strokes);
  }

  static void _drawStrokes(Canvas canvas, List<List<Offset>> strokes) {
    final inkPaint = Paint()
      ..color = AppTheme.greenDark
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = AppTheme.greenDark
      ..style = PaintingStyle.fill;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 2.2, dotPaint);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, inkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

Future<Uint8List> _renderSignaturePng(
  List<List<Offset>> strokes,
  Size size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  _SignaturePainter._drawStrokes(canvas, strokes);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return Uint8List(0);
  return data.buffer.asUint8List();
}

class _StakeholderBottomBar extends StatelessWidget {
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  const _StakeholderBottomBar({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final hasSecondary = secondaryLabel != null && secondaryIcon != null;
    return RepaintBoundary(
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDDE9D5)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.greenDark.withValues(alpha: 0.11),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              if (hasSecondary) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSecondary,
                    icon: Icon(secondaryIcon),
                    label: Text(secondaryLabel!),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPrimary,
                  icon: Icon(primaryIcon),
                  label: Text(primaryLabel),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: AppTheme.greenDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecureNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _SecureNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(AppTheme.greenPale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.greenDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
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

class _StakeholderFormTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final String? helperText;

  const _StakeholderFormTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        textCapitalization: textCapitalization,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: UiStrings.fromEnglish(label),
          helperText: helperText == null
              ? null
              : UiStrings.fromEnglish(helperText!),
          counterText: '',
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _BankDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _BankDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final banks = _bankOptions(value);
    final selected = banks.contains(value.trim()) ? value.trim() : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: UiStrings.t('bank_name'),
          prefixIcon: const Icon(Icons.account_balance_outlined),
          border: const OutlineInputBorder(),
        ),
        hint: Text(UiStrings.t('select_bank')),
        items: banks
            .map(
              (bank) => DropdownMenuItem<String>(
                value: bank,
                child: Text(bank, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        onChanged: (bank) {
          if (bank != null) onChanged(bank);
        },
      ),
    );
  }
}

class _DocumentUploadButton extends StatelessWidget {
  final String label;
  final bool optional;
  final bool uploaded;
  final bool uploading;
  final VoidCallback? onPressed;

  const _DocumentUploadButton({
    required this.label,
    this.optional = false,
    required this.uploaded,
    required this.uploading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final localizedLabel = UiStrings.fromEnglish(label);
    final buttonLabel = uploaded
        ? UiStrings.f('document_uploaded', {'document': localizedLabel})
        : optional
        ? UiStrings.f('document_optional', {'document': localizedLabel})
        : localizedLabel;
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: uploading ? null : onPressed,
        icon: uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(uploaded ? Icons.check_circle_outline : Icons.upload_file),
        label: Text(buttonLabel),
      ),
    );
  }
}

class _ProofStatusTile extends StatelessWidget {
  final String message;

  const _ProofStatusTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6E3D1)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: AppTheme.greenDark,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              UiStrings.fromEnglish(message),
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyChecklistPanel extends StatelessWidget {
  final bool contractReadAccepted;
  final bool consentInterestOnly;
  final bool consentNoGuaranteedReturn;
  final bool consentDataUse;
  final ValueChanged<bool> onContractReadAccepted;
  final ValueChanged<bool>? onConsentInterestOnly;
  final ValueChanged<bool>? onConsentNoGuaranteedReturn;
  final ValueChanged<bool>? onConsentDataUse;

  const _PolicyChecklistPanel({
    required this.contractReadAccepted,
    required this.consentInterestOnly,
    required this.consentNoGuaranteedReturn,
    required this.consentDataUse,
    required this.onContractReadAccepted,
    required this.onConsentInterestOnly,
    required this.onConsentNoGuaranteedReturn,
    required this.onConsentDataUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E8DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            UiStrings.t('policy_checklist'),
            style: TextStyle(
              color: AppTheme.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _PolicyCheckItem(
            value: contractReadAccepted,
            onChanged: onContractReadAccepted,
            title: 'Application is interest only',
            body:
                'This form records interest for farmer stakeholder shares. It is not a confirmed allocation.',
          ),
          _PolicyCheckItem(
            value: consentInterestOnly,
            onChanged: onConsentInterestOnly,
            title: 'Admin review is required',
            body:
                'Kalsubai Farms will review farmer identity, land record, PAN, bank and nominee details before approval.',
          ),
          _PolicyCheckItem(
            value: consentNoGuaranteedReturn,
            onChanged: onConsentNoGuaranteedReturn,
            title: 'No guaranteed return',
            body:
                'Payment starts only after admin approval. No return, buyback, dividend or profit is guaranteed.',
          ),
          _PolicyCheckItem(
            value: consentDataUse,
            onChanged: onConsentDataUse,
            title: 'Data use and signature consent',
            body:
                'Submitted farmer, KYC, bank and nominee details are used only for stakeholder review, compliance and records.',
            last: true,
          ),
          if (!contractReadAccepted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                UiStrings.t('unlock_remaining_policy_checks'),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PolicyCheckItem extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String body;
  final bool last;

  const _PolicyCheckItem({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 6),
        child: CheckboxListTile(
          value: value,
          onChanged: onChanged == null
              ? null
              : (checked) => onChanged!(checked ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            UiStrings.fromEnglish(title),
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          subtitle: Text(
            UiStrings.fromEnglish(body),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final bool active;
  final String title;
  final String body;
  final bool last;

  const _TimelineTile({
    required this.active,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.green : const Color(0xFFB7C2B1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              active
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: color,
            ),
            if (!last)
              Container(width: 2, height: 42, color: const Color(0xFFDDE7D9)),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: active ? AppTheme.greenDark : AppTheme.textMuted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String title;
  final String body;

  const _FaqTile({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Section(
        title: title,
        subtitle: body,
        child: const SizedBox.shrink(),
      ),
    );
  }
}

class _StakeholderErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _StakeholderErrorBanner({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFB91C1C)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                UiStrings.authError(message),
                style: const TextStyle(
                  color: Color(0xFF991B1B),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: () {
                  onRetry!();
                },
                child: Text(UiStrings.t('refresh')),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String? status;

  const _StatusChip({this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD4E4CE)),
      ),
      child: Text(
        _statusLabel(status),
        style: const TextStyle(
          color: AppTheme.greenDark,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

void _ensureStakeholderLoaded() {
  final auth = Get.find<MainAuthController>();
  final stakeholder = Get.find<StakeholderController>();
  final farmer = auth.verifiedFarmer.value;
  if (farmer != null &&
      stakeholder.plan.value == null &&
      !stakeholder.isLoading.value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (stakeholder.plan.value == null && !stakeholder.isLoading.value) {
        stakeholder.loadForFarmer(farmer);
      }
    });
  }
}

String _farmerKey(VerifiedFarmerRecord? farmer) {
  if (farmer == null) return '';
  return '${farmer.phone.trim()}|${farmer.farmerId.trim()}';
}

String _money(num value) {
  return UiStrings.f('rs_value', {'value': LocaleText.number(value.round())});
}

String _statusLabel(String? status) {
  switch (StakeholderApplicationStatus.normalize(status ?? '')) {
    case StakeholderApplicationStatus.underReview:
      return UiStrings.t('stakeholder_status_under_review');
    case StakeholderApplicationStatus.approved:
      return UiStrings.t('stakeholder_status_approved');
    case StakeholderApplicationStatus.rejected:
      return UiStrings.t('stakeholder_status_rejected');
    case StakeholderApplicationStatus.submitted:
      return status == null || status.trim().isEmpty
          ? UiStrings.t('stakeholder_status_draft')
          : UiStrings.t('stakeholder_status_submitted');
  }
  return UiStrings.t('stakeholder_status_draft');
}

String _paymentMethodLabel(String? method) {
  switch ((method ?? '').trim()) {
    case StakeholderPaymentMethod.razorpay:
      return 'Razorpay';
    case StakeholderPaymentMethod.bankTransfer:
      return 'Bank transfer';
  }
  return 'Not selected';
}

String _paymentStatusLabel(String? status) {
  switch ((status ?? '').trim()) {
    case StakeholderPaymentStatus.gatewayOrderCreated:
      return 'Payment started';
    case StakeholderPaymentStatus.gatewayVerified:
      return 'Payment verified';
    case StakeholderPaymentStatus.bankTransferSubmitted:
      return 'Bank transfer submitted';
    case StakeholderPaymentStatus.failed:
      return 'Payment failed';
  }
  return 'Pending';
}

String _uploadedLabel(String path) {
  final clean = path.trim();
  if (clean.isEmpty) return 'Not uploaded';
  return clean.startsWith('local/') ? 'Saved in form' : 'Uploaded';
}

String _firstNonEmpty(String? value, String fallback) {
  final clean = (value ?? '').trim();
  return clean.isEmpty ? fallback : clean;
}

String _aadhaarRecordLabel({
  required StakeholderApplication? application,
  required VerifiedFarmerRecord farmer,
}) {
  final value = _firstNonEmpty(
    application?.farmerAadhaarNumber,
    _firstNonEmpty(
      application?.aadhaarNumber,
      _firstNonEmpty(
        farmer.aadhaarNumber,
        _firstNonEmpty(application?.farmerAadhaarLast4, farmer.aadhaarLast4),
      ),
    ),
  );
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12) {
    return '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}';
  }
  return value.trim().isEmpty ? '-' : value.trim();
}

String _landRecordApplicationLabel(StakeholderApplication application) {
  final details = application.landRecordDetails.trim();
  final uploaded = application.landRecordDocumentPath.trim().isNotEmpty;
  if (details.isNotEmpty && uploaded) {
    return '$details • ${UiStrings.t('image_uploaded')}';
  }
  if (details.isNotEmpty) return details;
  return uploaded ? UiStrings.t('image_uploaded') : UiStrings.t('not_provided');
}

String _maskedPan(String value) {
  final pan = value.trim().toUpperCase();
  if (pan.length <= 4) return pan.isEmpty ? '-' : pan;
  return UiStrings.f('ending_value', {'value': pan.substring(pan.length - 4)});
}

String _maskedAccount(String value) {
  final account = value.replaceAll(RegExp(r'\D'), '');
  if (account.length <= 4) return account.isEmpty ? '-' : account;
  return 'ending ${account.substring(account.length - 4)}';
}

String _normalizedAccount(String value) {
  return value.replaceAll(RegExp(r'\D'), '');
}

List<String> _bankOptions(String currentValue) {
  final current = currentValue.trim();
  if (current.isEmpty || _commonIndianBanks.contains(current)) {
    return _commonIndianBanks;
  }
  return <String>[current, ..._commonIndianBanks];
}

void _showStakeholderMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(UiStrings.fromEnglish(message))));
}

String _yesNo(bool value) {
  return value ? UiStrings.t('health_ready') : UiStrings.t('health_waiting');
}

String _eventText(StakeholderApplicationEvent event) {
  final createdAt = event.createdAt;
  final note = event.note.trim();
  if (createdAt == null) return note;
  final when = '${LocaleText.date(createdAt)} ${LocaleText.time(createdAt)}';
  return note.isEmpty ? when : '$note\n$when';
}

int _sliderDivisions(StakeholderPlan plan) {
  const step = StakeholderPlan.amountStep;
  final raw = ((plan.maxAmount - plan.minAmount) / step).round();
  return raw.clamp(1, 1000).toInt();
}

BoxDecoration _cardDecoration(Color color) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFE3EADD)),
    boxShadow: [
      BoxShadow(
        color: AppTheme.greenDark.withValues(alpha: 0.06),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

const _smallMutedStyle = TextStyle(
  color: AppTheme.textMuted,
  fontSize: 12,
  fontWeight: FontWeight.w800,
);

const _commonIndianBanks = <String>[
  'State Bank of India',
  'HDFC Bank',
  'ICICI Bank',
  'Axis Bank',
  'Kotak Mahindra Bank',
  'Bank of Baroda',
  'Punjab National Bank',
  'Canara Bank',
  'Union Bank of India',
  'Bank of India',
  'Indian Bank',
  'Central Bank of India',
  'Indian Overseas Bank',
  'UCO Bank',
  'Bank of Maharashtra',
  'Punjab & Sind Bank',
  'IDBI Bank',
  'IDFC FIRST Bank',
  'Federal Bank',
  'IndusInd Bank',
  'Yes Bank',
  'Bandhan Bank',
  'RBL Bank',
  'South Indian Bank',
  'Karur Vysya Bank',
  'Tamilnad Mercantile Bank',
  'City Union Bank',
  'Karnataka Bank',
  'Jammu & Kashmir Bank',
  'DCB Bank',
  'Dhanlaxmi Bank',
  'CSB Bank',
  'AU Small Finance Bank',
  'Equitas Small Finance Bank',
  'Ujjivan Small Finance Bank',
  'Suryoday Small Finance Bank',
  'ESAF Small Finance Bank',
  'Utkarsh Small Finance Bank',
  'Fincare Small Finance Bank',
  'Jana Small Finance Bank',
  'Capital Small Finance Bank',
  'Airtel Payments Bank',
  'India Post Payments Bank',
  'NSDL Payments Bank',
  'Maharashtra Gramin Bank',
  'Vidharbha Konkan Gramin Bank',
  'Maharashtra State Co-operative Bank',
  'District Central Co-operative Bank',
  'Other scheduled bank',
];
