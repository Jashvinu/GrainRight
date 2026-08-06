import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_crop_program.dart';
import '../services/fpc_crop_program_service.dart';
import '../services/seed_checkout_service.dart';

class FarmerCropProgramCard extends StatefulWidget {
  final String farmId;
  final bool showEmptyState;

  const FarmerCropProgramCard({
    super.key,
    required this.farmId,
    this.showEmptyState = false,
  });

  @override
  State<FarmerCropProgramCard> createState() => _FarmerCropProgramCardState();
}

class _FarmerCropProgramCardState extends State<FarmerCropProgramCard> {
  final _service = FpcCropProgramService();
  final _checkoutService = SeedCheckoutService();
  late final Razorpay _razorpay;
  SeedRazorpayOrder? _activeOrder;
  FpcCropProgramSnapshot? _snapshot;
  String _error = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    _load();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FarmerCropProgramCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.farmId != widget.farmId) _load();
  }

  Future<void> _load() async {
    if (widget.farmId.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _snapshot = const FpcCropProgramSnapshot.empty();
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final snapshot = await _service.loadForFarm(widget.farmId);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptTerms(FpcCropProgramSnapshot snapshot) async {
    await _run(
      () => _service.acceptTerms(
        enrollmentId: snapshot.enrollmentId,
        policyVersion: snapshot.policyVersion,
      ),
    );
  }

  Future<void> _acknowledgeSeed(FpcCropProgramSnapshot snapshot) async {
    await _run(() => _service.acknowledgeSeed(snapshot.seedIssueId));
  }

  Future<void> _requestSeed(
    FpcCropProgramSnapshot snapshot,
    Map<String, dynamic> batch,
  ) async {
    final quantity = TextEditingController();
    final note = TextEditingController();
    final seedBatchId = '${batch['id'] ?? ''}'.trim();
    final sellableQuantity =
        _number(batch['sellable_quantity_kg']) ?? double.infinity;
    final formKey = GlobalKey<FormState>();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UiStrings.t('seed_request_from_fpc')),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.verified_rounded,
                    color: AppTheme.greenDark,
                  ),
                  title: Text(
                    '${batch['seed_name'] ?? batch['crop'] ?? 'Seed'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${batch['fpc_name'] ?? ''} · ${batch['batch_code'] ?? ''}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: UiStrings.t('seed_request_quantity_kg'),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse((value ?? '').trim()) ?? 0;
                    if (parsed <= 0) {
                      return UiStrings.t('seed_request_quantity_required');
                    }
                    if (parsed > sellableQuantity) {
                      return UiStrings.t('seed_quantity_exceeds_stock');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: UiStrings.t('seed_request_note_optional'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UiStrings.fromEnglish('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, true);
            },
            child: Text(UiStrings.t('seed_request_send')),
          ),
        ],
      ),
    );
    final requestedQuantity = double.tryParse(quantity.text.trim());
    final requestNote = note.text;
    quantity.dispose();
    note.dispose();
    if (submit != true || requestedQuantity == null || seedBatchId.isEmpty) {
      return;
    }
    await _run(
      () => _service.requestSeed(
        farmId: widget.farmId,
        seedBatchId: seedBatchId,
        quantityKg: requestedQuantity,
        note: requestNote,
      ),
    );
  }

  Future<void> _startPayment(FpcCropProgramSnapshot snapshot) async {
    if (!snapshot.canPaySeedRequest || _saving) return;
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final order = await _checkoutService.createOrder(snapshot.seedRequestId);
      if (!order.isValid) {
        throw const SeedCheckoutException(
          'Only Razorpay Test Mode seed orders are accepted.',
        );
      }
      _activeOrder = order;
      _razorpay.open({
        'key': order.keyId,
        'amount': order.amountSubunits,
        'currency': order.currency,
        'name': 'Kalsubai Farms',
        'description': 'Certified seed purchase · Test Mode',
        'order_id': order.orderId,
        'allow_rotation': true,
        'theme': {'color': '#0B5D2A'},
      });
    } catch (error) {
      _activeOrder = null;
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final order = _activeOrder;
    _activeOrder = null;
    if (order == null) return;
    try {
      final captured = await _checkoutService.verifyPayment(
        razorpayOrderId: response.orderId ?? order.orderId,
        razorpayPaymentId: response.paymentId ?? '',
        razorpaySignature: response.signature ?? '',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              captured
                  ? 'Test payment captured. The FPC can now issue your seed.'
                  : 'Payment verified. Waiting for Razorpay capture.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    _activeOrder = null;
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = response.message ?? 'Payment was cancelled or failed.';
    });
  }

  void _handleExternalWallet(ExternalWalletResponse _) {}

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.hasContext) {
      if (_error.isNotEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error, style: const TextStyle(color: Colors.red)),
          ),
        );
      }
      if (!widget.showEmptyState) return const SizedBox.shrink();
      return Card(
        elevation: 0,
        color: const Color(0xFFF8FBF5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppTheme.green.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(
                Icons.link_off_rounded,
                color: AppTheme.greenDark,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                UiStrings.t('farmer_seeds_no_active_program'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                UiStrings.t('farmer_seeds_no_active_program_help'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, height: 1.35),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(UiStrings.t('try_again')),
              ),
            ],
          ),
        ),
      );
    }
    if (!snapshot.exists) return _seedRequestCard(snapshot);
    final statusColor = snapshot.isSaleBlocked
        ? const Color(0xFFF57C00)
        : AppTheme.greenDark;
    return Card(
      elevation: 0,
      color: const Color(0xFFF4FAF3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.green.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_rounded, color: AppTheme.greenDark),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    UiStrings.fromEnglish(snapshot.programName),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusChip(
                  label: _statusLabel(snapshot.status),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              UiStrings.f('crop_program_tracked_by', {
                'name': snapshot.sponsorName,
              }),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 13),
            _line(Icons.verified_user_outlined, _policyLine(snapshot)),
            if (snapshot.referenceRatePerKg != null)
              _line(
                Icons.currency_rupee_rounded,
                UiStrings.f('crop_program_reference_rate', {
                  'rate': snapshot.referenceRatePerKg!.toStringAsFixed(2),
                }),
              ),
            if (snapshot.seedBatchCode.isNotEmpty)
              _line(
                Icons.grass_rounded,
                snapshot.seedQuantityKg == null
                    ? UiStrings.f('crop_program_seed_batch', {
                        'code': snapshot.seedBatchCode,
                        'status': _statusLabel(snapshot.seedIssueStatus),
                      })
                    : UiStrings.f('crop_program_seed_batch_quantity', {
                        'code': snapshot.seedBatchCode,
                        'quantity': snapshot.seedQuantityKg,
                        'status': _statusLabel(snapshot.seedIssueStatus),
                      }),
              ),
            if (snapshot.hasSeedRequest)
              _line(
                Icons.outbox_outlined,
                UiStrings.f('crop_program_seed_request_summary', {
                  'quantity': snapshot.requestedQuantityKg ?? '-',
                  'status': _statusLabel(snapshot.seedRequestStatus),
                }),
              ),
            if (snapshot.seedRequestAmountPaise != null)
              _line(
                Icons.payments_outlined,
                '${_moneyFromPaise(snapshot.seedRequestAmountPaise!)} · '
                '${UiStrings.fromEnglish(_paymentStatusLabel(snapshot.seedRequestPaymentStatus))}',
              ),
            if (snapshot.requiredCheckCount > 0)
              _line(
                Icons.fact_check_outlined,
                UiStrings.f('crop_program_checks_verified', {
                  'verified': snapshot.verifiedCheckCount,
                  'required': snapshot.requiredCheckCount,
                }),
              ),
            if (snapshot.latestEvaluationStatus.isNotEmpty)
              _line(
                Icons.science_outlined,
                UiStrings.f('crop_program_harvest_check', {
                  'attempt': (snapshot.latestAttempt ?? 0) + 1,
                  'status': _statusLabel(snapshot.latestEvaluationStatus),
                }),
              ),
            if (snapshot.latestReasons.isNotEmpty) ...[
              const SizedBox(height: 7),
              for (final reason in snapshot.latestReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• ${UiStrings.fromEnglish(reason)}',
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
            if (snapshot.status == 'released' &&
                snapshot.releaseReason.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                UiStrings.fromEnglish(snapshot.releaseReason),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _saleMessage(snapshot),
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w900),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error, style: const TextStyle(color: Colors.red)),
            ],
            if (snapshot.canPaySeedRequest) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _startPayment(snapshot),
                  icon: const Icon(Icons.lock_rounded),
                  label: Text(
                    UiStrings.f('seed_pay_securely', {
                      'amount': _moneyFromPaise(
                        snapshot.seedRequestAmountPaise ?? 0,
                      ),
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                UiStrings.fromEnglish(
                  'Razorpay Test Mode · reservation valid for 24 hours after FPC approval.',
                ),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (snapshot.needsTerms || snapshot.needsSeedAcknowledgement) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => snapshot.needsTerms
                            ? _acceptTerms(snapshot)
                            : _acknowledgeSeed(snapshot),
                  icon: Icon(
                    snapshot.needsTerms
                        ? Icons.rule_rounded
                        : Icons.inventory_rounded,
                  ),
                  label: Text(
                    snapshot.needsTerms
                        ? UiStrings.t('crop_program_accept_policy')
                        : UiStrings.t('crop_program_confirm_seed'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seedRequestCard(FpcCropProgramSnapshot snapshot) {
    final declined = snapshot.seedRequestStatus == 'declined';
    final statusColor = declined ? Colors.red.shade700 : AppTheme.greenDark;
    return Card(
      elevation: 0,
      color: const Color(0xFFF4FAF3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.green.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.grass_rounded, color: AppTheme.greenDark),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    snapshot.hasSeedRequest
                        ? UiStrings.fromEnglish(snapshot.requestedProgramName)
                        : UiStrings.t('seed_request_from_your_fpc'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (snapshot.hasSeedRequest)
                  _StatusChip(
                    label: _statusLabel(snapshot.seedRequestStatus),
                    color: statusColor,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              snapshot.hasSeedRequest
                  ? _seedRequestMessage(snapshot)
                  : UiStrings.t('seed_request_intro'),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (!snapshot.hasSeedRequest || declined) ...[
              const SizedBox(height: 12),
              for (final batch in snapshot.availableBatches) ...[
                _availableBatch(snapshot, batch),
                const SizedBox(height: 8),
              ],
              if (snapshot.availableBatches.isEmpty &&
                  snapshot.availablePrograms.isNotEmpty) ...[
                for (final program in snapshot.availablePrograms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.hourglass_top_rounded,
                      color: AppTheme.greenDark,
                    ),
                    title: Text(
                      UiStrings.label(
                        '${program['name'] ?? program['crop'] ?? 'Seed program'}',
                      ),
                    ),
                    subtitle: Text(
                      UiStrings.fromEnglish(
                        snapshot.requestablePrograms.contains(program)
                            ? 'The FPC must add a certified batch price before purchase.'
                            : 'Choose a farm matching this program crop.',
                      ),
                    ),
                  ),
              ],
              if (snapshot.requestableBatches.isEmpty)
                Text(
                  UiStrings.t(
                    snapshot.hasFarmMatchingProgram
                        ? 'seed_program_verification_required_help'
                        : 'seed_program_choose_matching_farm_help',
                  ),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
            ],
            if (snapshot.hasSeedRequest) ...[
              const SizedBox(height: 12),
              _line(
                Icons.scale_outlined,
                UiStrings.f('seed_request_requested_quantity', {
                  'quantity': snapshot.requestedQuantityKg ?? '-',
                }),
              ),
              if (snapshot.seedRequestNote.isNotEmpty)
                _line(Icons.notes_rounded, snapshot.seedRequestNote),
              if (snapshot.seedRequestResponse.isNotEmpty)
                _line(
                  declined
                      ? Icons.info_outline_rounded
                      : Icons.task_alt_rounded,
                  snapshot.seedRequestResponse,
                ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _availableBatch(
    FpcCropProgramSnapshot snapshot,
    Map<String, dynamic> batch,
  ) {
    final name = '${batch['seed_name'] ?? batch['crop'] ?? ''}'.trim();
    final fpcName = '${batch['fpc_name'] ?? ''}'.trim();
    final crop = '${batch['crop'] ?? ''}'.trim();
    final variety = '${batch['variety'] ?? ''}'.trim();
    final batchCode = '${batch['batch_code'] ?? ''}'.trim();
    final certification = '${batch['certification_number'] ?? ''}'.trim();
    final availableSeedKg = batch['sellable_quantity_kg'];
    final unitPricePaise = _integer(batch['unit_price_paise']);
    final requestAllowed = batch['request_allowed'] != false;
    final availabilityText = requestAllowed
        ? UiStrings.t('seed_program_available_for_farm')
        : UiStrings.f('seed_program_choose_matching_farm', {
            'crop': UiStrings.option(crop),
          });
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.label(name),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (fpcName.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              UiStrings.f('seed_program_from_fpc', {'name': fpcName}),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (crop.isNotEmpty)
                _ProgramTag(
                  icon: Icons.grass_rounded,
                  label: UiStrings.option(crop),
                ),
              if (variety.isNotEmpty)
                _ProgramTag(
                  icon: Icons.eco_outlined,
                  label: UiStrings.option(variety),
                ),
              if (availableSeedKg != null)
                _ProgramTag(
                  icon: Icons.inventory_2_outlined,
                  label: UiStrings.f('seed_program_stock_available', {
                    'quantity': availableSeedKg,
                  }),
                ),
              if (unitPricePaise > 0)
                _ProgramTag(
                  icon: Icons.currency_rupee_rounded,
                  label: '${_moneyFromPaise(unitPricePaise)}/kg',
                ),
              if (batchCode.isNotEmpty)
                _ProgramTag(icon: Icons.qr_code_2_rounded, label: batchCode),
              if (certification.isNotEmpty)
                _ProgramTag(
                  icon: Icons.verified_outlined,
                  label: certification,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                requestAllowed
                    ? Icons.check_circle_outline_rounded
                    : Icons.swap_horiz_rounded,
                size: 17,
                color: requestAllowed
                    ? AppTheme.greenDark
                    : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  availabilityText,
                  style: TextStyle(
                    color: requestAllowed
                        ? AppTheme.greenDark
                        : Colors.orange.shade900,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (requestAllowed && snapshot.canRequestSeed) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _requestSeed(snapshot, batch),
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(UiStrings.t('seed_request_action')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _moneyFromPaise(int paise) =>
      '₹${(paise / 100).toStringAsFixed(2)}';

  static int _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String _paymentStatusLabel(String value) => switch (value) {
    'awaiting_payment' => 'Awaiting payment',
    'order_created' => 'Checkout ready',
    'captured' => 'Paid',
    'failed' => 'Payment failed',
    'expired' => 'Reservation expired',
    'refund_pending' => 'Refund pending',
    'refunded' => 'Refunded',
    _ => 'Not paid',
  };

  String _seedRequestMessage(FpcCropProgramSnapshot snapshot) =>
      switch (snapshot.seedRequestStatus) {
        'submitted' => UiStrings.f('seed_request_submitted_message', {
          'name': snapshot.sponsorName,
        }),
        'approved' => UiStrings.t('seed_request_approved_message'),
        'seed_issued' => UiStrings.t('seed_request_issued_message'),
        'delivered' => UiStrings.t('seed_request_delivered_message'),
        'acknowledged' => UiStrings.t('seed_request_acknowledged_message'),
        'declined' => UiStrings.t('seed_request_declined_message'),
        _ => UiStrings.t('seed_request_updating_message'),
      };

  String _policyLine(FpcCropProgramSnapshot snapshot) {
    final moisture = snapshot.maxMoisturePercent;
    if (moisture == null) {
      return UiStrings.f('crop_program_policy_grade', {
        'grade': snapshot.minimumGrade,
      });
    }
    return UiStrings.f('crop_program_policy_grade_moisture', {
      'grade': snapshot.minimumGrade,
      'moisture': moisture,
    });
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.greenDark),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  static String _saleMessage(FpcCropProgramSnapshot snapshot) {
    if (snapshot.status == 'released') {
      return UiStrings.t('crop_program_sale_released');
    }
    if (snapshot.isExclusive) {
      return UiStrings.t('crop_program_sale_exclusive');
    }
    if (snapshot.status == 'procured' || snapshot.status == 'completed') {
      return UiStrings.t('crop_program_sale_procured');
    }
    return UiStrings.t('crop_program_sale_locked');
  }

  static String _statusLabel(String value) =>
      UiStrings.option(value.replaceAll('_', ' '));
}

class _ProgramTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProgramTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.greenDark),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}
