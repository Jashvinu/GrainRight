import 'package:get/get.dart';

import '../models/stakeholder_plan.dart';
import '../models/verified_farmer_record.dart';
import '../services/stakeholder_service.dart';

class StakeholderController extends GetxController {
  StakeholderController({StakeholderService? service})
    : _service = service ?? StakeholderService();

  final StakeholderService _service;

  final plan = Rxn<StakeholderPlan>();
  final application = Rxn<StakeholderApplication>();
  final events = <StakeholderApplicationEvent>[].obs;
  final selectedAmount = 1000.0.obs;
  final farmerNote = ''.obs;
  final consentInterestOnly = false.obs;
  final consentNoGuaranteedReturn = false.obs;
  final consentDataUse = false.obs;
  final isLoading = false.obs;
  final isSubmitting = false.obs;
  final errorMessage = ''.obs;

  int get estimatedShares =>
      plan.value?.estimateShares(selectedAmount.value) ?? 0;

  bool get hasApplication => application.value != null;

  bool get isApplicationLocked {
    final status = application.value?.status;
    return status != null &&
        status.trim().isNotEmpty &&
        status != StakeholderApplicationStatus.submitted;
  }

  bool get canSubmit {
    final activePlan = plan.value;
    return activePlan != null &&
        activePlan.isValidAmount(selectedAmount.value) &&
        consentInterestOnly.value &&
        consentNoGuaranteedReturn.value &&
        consentDataUse.value &&
        !isLoading.value &&
        !isSubmitting.value;
  }

  Future<void> loadForFarmer(VerifiedFarmerRecord? farmer) async {
    if (farmer == null) {
      plan.value = StakeholderPlan.fallback();
      application.value = null;
      events.clear();
      errorMessage.value = '';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final bundle = await _service.loadForFarmer(farmer);
      _applyBundle(bundle);
    } catch (error) {
      errorMessage.value = _cleanError(error);
    } finally {
      isLoading.value = false;
    }
  }

  void setSelectedAmount(double amount) {
    final activePlan = plan.value ?? StakeholderPlan.fallback();
    final clamped = amount.clamp(activePlan.minAmount, activePlan.maxAmount);
    selectedAmount.value = (clamped as num).toDouble();
  }

  void setFarmerNote(String value) {
    farmerNote.value = value.trim();
  }

  void setConsentInterestOnly(bool value) {
    consentInterestOnly.value = value;
  }

  void setConsentNoGuaranteedReturn(bool value) {
    consentNoGuaranteedReturn.value = value;
  }

  void setConsentDataUse(bool value) {
    consentDataUse.value = value;
  }

  Future<bool> submitInterest(VerifiedFarmerRecord? farmer) async {
    final activePlan = plan.value;
    if (farmer == null || activePlan == null) {
      errorMessage.value = 'Login as a farmer stakeholder first.';
      return false;
    }
    if (!canSubmit) {
      errorMessage.value =
          'Select a valid amount and accept all stakeholder consent points.';
      return false;
    }
    isSubmitting.value = true;
    errorMessage.value = '';
    try {
      final bundle = await _service.submitInterest(
        farmer: farmer,
        plan: activePlan,
        selectedAmount: selectedAmount.value,
        farmerNote: farmerNote.value,
      );
      _applyBundle(bundle);
      return true;
    } catch (error) {
      errorMessage.value = _cleanError(error);
      return false;
    } finally {
      isSubmitting.value = false;
    }
  }

  void _applyBundle(StakeholderPlanBundle bundle) {
    plan.value = bundle.plan;
    application.value = bundle.application;
    events.assignAll(bundle.events);
    final amount = bundle.application?.selectedAmount;
    if (amount != null && amount > 0) {
      selectedAmount.value = amount;
    } else {
      selectedAmount.value = bundle.plan.minAmount;
    }
    final submitted = bundle.application != null;
    consentInterestOnly.value =
        bundle.application?.consentInterestOnly ?? submitted;
    consentNoGuaranteedReturn.value =
        bundle.application?.consentNoGuaranteedReturn ?? submitted;
    consentDataUse.value = bundle.application?.consentDataUse ?? submitted;
    farmerNote.value = bundle.application?.farmerNote ?? '';
  }

  String _cleanError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? 'Stakeholder plan sync failed.' : text;
  }
}
