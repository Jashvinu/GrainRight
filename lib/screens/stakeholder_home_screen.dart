import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import '../controllers/main_auth_controller.dart';
import '../controllers/stakeholder_controller.dart';
import '../models/stakeholder_plan.dart';
import '../models/verified_farmer_record.dart';
import 'package:kalsubai_farms/core/widgets/app_back_button.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: () => Get.offAllNamed('/login')),
        title: Text(UiStrings.t('stakeholder_home_title')),
        actions: [
          IconButton(
            tooltip: UiStrings.t('refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Obx(() {
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
                      title: UiStrings.t('stakeholder_agri_record_id'),
                      value: farmer.agriRecordId,
                      icon: Icons.assignment_outlined,
                    ),
                    _InfoTile(
                      title: UiStrings.t('stakeholder_aadhaar_last4'),
                      value: farmer.aadhaarLast4,
                      icon: Icons.credit_card_outlined,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.fact_check_outlined,
                title: UiStrings.t('stakeholder_plan_page_title'),
                subtitle: UiStrings.t('stakeholder_plan_page_sub'),
                route: '/stakeholder/plan',
              ),
              _ActionTile(
                icon: Icons.currency_rupee_rounded,
                title: UiStrings.t('stakeholder_select_amount'),
                subtitle: UiStrings.t('stakeholder_select_amount_sub'),
                route: '/stakeholder/select-amount',
              ),
              _ActionTile(
                icon: Icons.timeline_rounded,
                title: UiStrings.t('stakeholder_status_title'),
                subtitle: UiStrings.t('stakeholder_status_sub'),
                route: '/stakeholder/status',
              ),
              _ActionTile(
                icon: Icons.folder_copy_outlined,
                title: UiStrings.t('stakeholder_documents_title'),
                subtitle: UiStrings.t('stakeholder_documents_sub'),
                route: '/stakeholder/documents',
              ),
              _ActionTile(
                icon: Icons.help_outline_rounded,
                title: UiStrings.t('stakeholder_help_title'),
                subtitle: UiStrings.t('stakeholder_help_intro'),
                route: '/stakeholder/help',
              ),
            ],
          ),
        );
      }),
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

class StakeholderSelectAmountScreen extends StatefulWidget {
  const StakeholderSelectAmountScreen({super.key});

  @override
  State<StakeholderSelectAmountScreen> createState() =>
      _StakeholderSelectAmountScreenState();
}

class _StakeholderSelectAmountScreenState
    extends State<StakeholderSelectAmountScreen> {
  late final StakeholderController _stakeholder;
  late final TextEditingController _noteController;
  late final Worker _noteWorker;

  @override
  void initState() {
    super.initState();
    _ensureStakeholderLoaded();
    _stakeholder = Get.find<StakeholderController>();
    _noteController = TextEditingController(text: _stakeholder.farmerNote.value);
    _noteWorker = ever<String>(_stakeholder.farmerNote, (value) {
      if (_noteController.text != value) {
        _noteController.text = value;
      }
    });
  }

  @override
  void dispose() {
    _noteWorker.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await _stakeholder.submitInterest(
      Get.find<MainAuthController>().verifiedFarmer.value,
    );
    if (ok) {
      Get.offNamed('/stakeholder/status');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_select_amount'),
      child: Obx(() {
        final plan = _stakeholder.plan.value ?? StakeholderPlan.fallback();
        final locked = _stakeholder.isApplicationLocked;
        final amount = _stakeholder.selectedAmount.value
            .clamp(plan.minAmount, plan.maxAmount)
            .toDouble();
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
            if (locked) ...[
              _PromptCard(
                icon: Icons.lock_outline_rounded,
                title: UiStrings.t('stakeholder_application_locked_title'),
                body: UiStrings.t('stakeholder_application_locked_body'),
                actionLabel: UiStrings.t('stakeholder_status_title'),
                onAction: () => Get.offNamed('/stakeholder/status'),
              ),
              const SizedBox(height: 12),
            ],
            _Section(
              title: UiStrings.t('stakeholder_amount_estimator'),
              subtitle: UiStrings.f('stakeholder_amount_estimator_body', {
                'unit': _money(plan.shareUnitValue),
              }),
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: amount,
                    min: plan.minAmount,
                    max: plan.maxAmount,
                    divisions: _sliderDivisions(plan),
                    label: _money(amount),
                    onChanged: locked ? null : _stakeholder.setSelectedAmount,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _money(plan.minAmount),
                          style: _smallMutedStyle,
                        ),
                      ),
                      Text(_money(plan.maxAmount), style: _smallMutedStyle),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickAmounts(plan)
                        .map(
                          (value) => ChoiceChip(
                            label: Text(_money(value)),
                            selected: amount == value,
                            onSelected: locked
                                ? null
                                : (_) => _stakeholder.setSelectedAmount(value),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: UiStrings.t('stakeholder_note_label'),
              child: TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                enabled: !locked,
                onChanged: _stakeholder.setFarmerNote,
                decoration: InputDecoration(
                  hintText: UiStrings.t('stakeholder_note_hint'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              title: UiStrings.t('stakeholder_consent_title'),
              child: Column(
                children: [
                  _ConsentTile(
                    value: _stakeholder.consentInterestOnly.value,
                    onChanged: locked
                        ? null
                        : _stakeholder.setConsentInterestOnly,
                    label: UiStrings.t('stakeholder_consent_interest_only'),
                  ),
                  _ConsentTile(
                    value: _stakeholder.consentNoGuaranteedReturn.value,
                    onChanged: locked
                        ? null
                        : _stakeholder.setConsentNoGuaranteedReturn,
                    label: UiStrings.t('stakeholder_consent_no_return'),
                  ),
                  _ConsentTile(
                    value: _stakeholder.consentDataUse.value,
                    onChanged:
                        locked ? null : _stakeholder.setConsentDataUse,
                    label: UiStrings.t('stakeholder_consent_data_use'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: locked || !_stakeholder.canSubmit ? null : _submit,
                icon: _stakeholder.isSubmitting.value
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  locked
                      ? UiStrings.t('stakeholder_status_under_review')
                      : UiStrings.t('stakeholder_submit_interest'),
                ),
              ),
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
            _ApplicationSnapshot(
              plan: plan,
              application: application,
              selectedAmount: stakeholder.selectedAmount.value,
              estimatedShares: stakeholder.estimatedShares,
            ),
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
                    active: application?.status ==
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

class StakeholderDocumentsScreen extends StatelessWidget {
  const StakeholderDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _ensureStakeholderLoaded();
    final auth = Get.find<MainAuthController>();
    final stakeholder = Get.find<StakeholderController>();
    return _StakeholderPage(
      title: UiStrings.t('stakeholder_documents_title'),
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
                    title: UiStrings.t('stakeholder_agri_record_id'),
                    value: farmer.agriRecordId,
                    icon: Icons.assignment_outlined,
                  ),
                  _InfoTile(
                    title: UiStrings.t('stakeholder_aadhaar_last4'),
                    value: farmer.aadhaarLast4,
                    icon: Icons.credit_card_outlined,
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
                    value: _yesNo(application?.consentNoGuaranteedReturn ?? false),
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
  final Widget child;

  const _StakeholderPage({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AppBackButton(onPressed: () => Get.offNamed('/stakeholder')),
        title: Text(title),
      ),
      body: child,
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
    final locked = hasApplication &&
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
                    locked ? '/stakeholder/status' : '/stakeholder/select-amount',
                  ),
                  icon: Icon(
                    locked
                        ? Icons.timeline_rounded
                        : Icons.currency_rupee_rounded,
                  ),
                  label: Text(
                    locked
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
            title,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
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
                          item,
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
                Text(title, style: _smallMutedStyle),
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

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE1E8DE)),
        ),
        child: ListTile(
          leading: Icon(icon, color: AppTheme.greenDark),
          title: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Get.toNamed(route),
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  const _ConsentTile({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged == null
            ? null
            : (value) => onChanged!(value ?? false),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w700,
            height: 1.3,
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
  final step = plan.shareUnitValue <= 0 ? 1000 : plan.shareUnitValue;
  final raw = ((plan.maxAmount - plan.minAmount) / step).round();
  return raw.clamp(1, 100).toInt();
}

List<double> _quickAmounts(StakeholderPlan plan) {
  final unit = plan.shareUnitValue <= 0 ? 1000.0 : plan.shareUnitValue;
  final midpoint = ((plan.minAmount + plan.maxAmount) / 2 / unit).round() * unit;
  return <double>{plan.minAmount, midpoint, plan.maxAmount}
      .where((value) => plan.isValidAmount(value))
      .toList(growable: false);
}

BoxDecoration _cardDecoration(Color color) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: const Color(0xFFE1E8DE)),
  );
}

const _smallMutedStyle = TextStyle(
  color: AppTheme.textMuted,
  fontSize: 12,
  fontWeight: FontWeight.w800,
);
