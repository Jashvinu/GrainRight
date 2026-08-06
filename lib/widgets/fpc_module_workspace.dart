import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/localization/locale_text.dart';
import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_operating_models.dart';
import '../services/fpc_operating_service.dart';
import '../services/fpc_report_service.dart';
import '../services/seed_checkout_service.dart';

class FpcModuleWorkspace extends StatefulWidget {
  final String module;
  final List<Map<String, dynamic>> rows;
  final FpcOperatingService service;
  final VoidCallback onBack;
  final Future<void> Function() onChanged;
  final String? initialOperation;
  final Map<String, dynamic> initialValues;
  final String? title;
  final String? description;
  final bool showBack;
  final Set<String>? allowedOperations;

  const FpcModuleWorkspace({
    super.key,
    required this.module,
    required this.rows,
    required this.service,
    required this.onBack,
    required this.onChanged,
    this.initialOperation,
    this.initialValues = const {},
    this.title,
    this.description,
    this.showBack = true,
    this.allowedOperations,
  });

  @override
  State<FpcModuleWorkspace> createState() => _FpcModuleWorkspaceState();
}

class _FpcModuleWorkspaceState extends State<FpcModuleWorkspace> {
  final _seedCheckoutService = SeedCheckoutService();
  bool _working = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final requested = widget.initialOperation;
      if (!mounted || requested == null) return;
      for (final operation in _moduleOperations(widget.module)) {
        if (operation.operation == requested) {
          _runOperationForm(operation, initialValues: widget.initialValues);
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 112),
      children: [
        Row(
          children: [
            if (widget.showBack)
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.fromEnglish(
                      widget.title ?? _moduleTitle(widget.module),
                    ),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    UiStrings.fromEnglish(
                      widget.description ?? _moduleDescription(widget.module),
                    ),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_working) const LinearProgressIndicator(),
        Wrap(spacing: 8, runSpacing: 8, children: _actionButtons()),
        const SizedBox(height: 16),
        if (widget.module == 'collection_center')
          _CollectionCenterWorkspace(
            rows: widget.rows,
            onAction: _handleRowAction,
          )
        else if (widget.rows.isEmpty)
          _EmptyState(module: widget.module)
        else
          for (final row in widget.rows)
            _RecordCard(
              module: widget.module,
              row: row,
              onAction: (action) => _handleRowAction(action, row),
            ),
      ],
    );
  }

  List<Widget> _actionButtons() {
    final buttons = <Widget>[];
    for (final operation in _moduleOperations(widget.module)) {
      if (widget.allowedOperations != null &&
          !widget.allowedOperations!.contains(operation.operation)) {
        continue;
      }
      buttons.add(
        FilledButton.tonalIcon(
          onPressed: _working ? null : () => _runOperationForm(operation),
          icon: Icon(operation.icon),
          label: Text(UiStrings.fromEnglish(operation.label)),
        ),
      );
    }
    if (widget.module == 'farmer_network') {
      buttons.add(
        _routeButton(
          'Scan farmer',
          Icons.qr_code_scanner_rounded,
          '/fpo/scan-farmer',
        ),
      );
    }
    if (widget.module == 'collection_center') {
      buttons.add(
        _routeButton('Open receiver', Icons.qr_code_2_rounded, '/fpo/receiver'),
      );
    }
    if (widget.module == 'quality') {
      buttons.add(
        _routeButton(
          'Review grading',
          Icons.fact_check_outlined,
          '/fpo/grading-review',
        ),
      );
    }
    if (widget.module == 'sales') {
      buttons.add(
        _routeButton(
          'Marketplace',
          Icons.storefront_outlined,
          '/fpo/marketplace',
        ),
      );
    }
    if (widget.module == 'reports') {
      for (final report in const [
        'farmers',
        'procurement',
        'quality',
        'warehouse',
        'inventory',
        'production',
        'packaging',
        'sales',
        'logistics',
        'finance',
      ]) {
        buttons.add(
          PopupMenuButton<String>(
            enabled: !_working,
            onSelected: (format) => _generateReport(report, format),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'pdf',
                child: Text(UiStrings.fromEnglish('Export PDF')),
              ),
              PopupMenuItem(
                value: 'xlsx',
                child: Text(UiStrings.fromEnglish('Export Excel')),
              ),
            ],
            child: Chip(
              avatar: const Icon(Icons.download_rounded, size: 18),
              label: Text(UiStrings.fromEnglish(_humanize(report))),
            ),
          ),
        );
      }
    }
    if (widget.module == 'ai_insights') {
      buttons.add(
        FilledButton.icon(
          onPressed: _working ? null : _refreshInsights,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(UiStrings.fromEnglish('Refresh deterministic insights')),
        ),
      );
    }
    return buttons;
  }

  Widget _routeButton(String label, IconData icon, String route) =>
      OutlinedButton.icon(
        onPressed: _working ? null : () => Get.toNamed(route),
        icon: Icon(icon),
        label: Text(UiStrings.fromEnglish(label)),
      );

  Future<void> _runOperationForm(
    _OperationSpec operation, {
    Map<String, dynamic> initialValues = const {},
  }) async {
    final lookups = <String, List<Map<String, dynamic>>>{};
    for (final field in operation.fields.where(
      (field) => field.lookupTable != null,
    )) {
      lookups[field.key] = await widget.service.loadLookup(field.lookupTable!);
    }
    if (!mounted) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _OperationDialog(
        operation: operation,
        lookups: lookups,
        initialValues: initialValues,
      ),
    );
    if (payload == null) return;
    if (operation.operation == 'approve_quality') {
      payload['results'] = {'lab_note': payload.remove('lab_note')};
    }
    if (operation.operation == 'create_crop_program') {
      payload['crop'] =
          _canonicalOperatingGrain('${payload['crop'] ?? ''}') ??
          '${payload['crop'] ?? ''}'.trim();
      final checkpoints = '${payload.remove('checkpoints') ?? ''}'
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      payload['policy_rules'] = {
        'minimum_grade': payload.remove('minimum_grade'),
        'max_moisture_percent': num.tryParse(
          '${payload.remove('max_moisture_percent') ?? ''}',
        ),
      };
      payload['required_checkpoints'] = [
        for (final checkpoint in checkpoints)
          {'code': _slug(checkpoint), 'name': checkpoint, 'required': true},
      ];
      payload['price_formula'] = {
        'reference_rate_per_kg': num.tryParse(
          '${payload.remove('reference_rate_per_kg') ?? ''}',
        ),
        'grade_adjustments': const {'A': 0, 'B': 0, 'C': 0},
      };
    }
    if (operation.operation == 'register_seed_batch') {
      final priceRupees = double.tryParse(
        '${payload.remove('unit_price_per_kg') ?? ''}',
      );
      payload['unit_price_paise'] = priceRupees == null
          ? 0
          : (priceRupees * 100).round();
    }
    await _execute(operation.operation, payload);
  }

  Future<void> _handleRowAction(String action, Map<String, dynamic> row) async {
    if (action == 'approve_seed_request') {
      await _runRowForm(
        _OperationSpec(
          'Approve Farmer seed request',
          'approve_seed_request',
          Icons.task_alt_rounded,
          [
            _InputSpec(
              'assigned_officer_id',
              'Field Officer',
              lookupTable: 'fpc_memberships',
              valueKey: 'user_id',
              displayKeys: ['display_name', 'email'],
            ),
            _InputSpec('response_note', 'Response note', required: false),
          ],
        ),
        {'seed_request_id': row['id']},
      );
      return;
    }
    if (action == 'decline_seed_request') {
      await _runRowForm(
        _OperationSpec(
          'Decline Farmer seed request',
          'decline_seed_request',
          Icons.cancel_outlined,
          [_InputSpec('response_note', 'Reason')],
        ),
        {'seed_request_id': row['id']},
      );
      return;
    }
    if (action == 'price_seed_batch') {
      await _runRowForm(
        _OperationSpec(
          'Set certified seed price',
          'price_seed_batch',
          Icons.currency_rupee_rounded,
          [
            _InputSpec(
              'unit_price_per_kg',
              'All-inclusive price per kg (₹)',
              type: _InputType.number,
            ),
          ],
        ),
        {'seed_batch_id': row['id']},
        transform: (payload) {
          final priceRupees = double.tryParse(
            '${payload.remove('unit_price_per_kg') ?? ''}',
          );
          payload['unit_price_paise'] = priceRupees == null
              ? 0
              : (priceRupees * 100).round();
        },
      );
      return;
    }
    if (action == 'refund_seed_request') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Refund full seed payment?')),
          content: Text(
            UiStrings.fromEnglish(
              'This is allowed only before delivery. Any issued stock will be returned to the certified batch.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UiStrings.fromEnglish('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(UiStrings.fromEnglish('Refund payment')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _working = true);
      try {
        await _seedCheckoutService.refundSeedRequest('${row['id'] ?? ''}');
        if (mounted) await widget.onChanged();
      } catch (error) {
        if (mounted) {
          Get.snackbar(UiStrings.fromEnglish('Refund failed'), '$error');
        }
      } finally {
        if (mounted) setState(() => _working = false);
      }
      return;
    }
    if (action == 'issue_requested_seed') {
      final issueOperation = _moduleOperations(
        'crop_programs',
      ).firstWhere((operation) => operation.operation == 'issue_program_seed');
      await _runOperationForm(
        issueOperation,
        initialValues: {
          'enrollment_id': row['enrollment_id'],
          'quantity_kg': row['requested_quantity_kg'],
        },
      );
      return;
    }
    if (action == 'activate_crop_program') {
      await _execute('activate_crop_program', {'program_id': row['id']});
      return;
    }
    if (action == 'pass_crop_program' || action == 'fail_crop_program') {
      await _runRowForm(
        _OperationSpec(
          action == 'pass_crop_program'
              ? 'Approve harvest compliance'
              : 'Hold harvest for remediation',
          'review_program_compliance',
          action == 'pass_crop_program'
              ? Icons.verified_rounded
              : Icons.pause_circle_outline_rounded,
          [_InputSpec('decision_note', 'Decision note')],
        ),
        {
          'evaluation_id': row['id'],
          'decision': action == 'pass_crop_program' ? 'passed' : 'failed',
        },
      );
      return;
    }
    if (action == 'release_crop_program') {
      await _runRowForm(
        _OperationSpec(
          'Release farmer from FPC exclusivity',
          'release_program_enrollment',
          Icons.lock_open_rounded,
          [_InputSpec('reason', 'Release reason')],
        ),
        {'enrollment_id': row['id']},
      );
      return;
    }
    if (action == 'activate_farmer' || action == 'deactivate_farmer') {
      await _execute('set_farmer_status', {
        'farmer_link_id': row['id'],
        'status': action == 'activate_farmer' ? 'active' : 'inactive',
      });
      return;
    }
    if (action == 'start_production') {
      await _execute('start_production', {'production_run_id': row['id']});
      return;
    }
    if (action.startsWith('procurement_')) {
      await _execute('transition_procurement_schedule', {
        'procurement_schedule_id': row['id'],
        'status': action.substring('procurement_'.length),
      });
      return;
    }
    if (action == 'complete_production') {
      await _runRowForm(
        _OperationSpec(
          'Complete production',
          'complete_production',
          Icons.task_alt_rounded,
          [
            _InputSpec('output_kg', 'Output kg', type: _InputType.number),
            _InputSpec(
              'waste_kg',
              'Waste kg',
              type: _InputType.number,
              initialValue: '0',
            ),
            _InputSpec('product_name', 'Output product'),
          ],
        ),
        {'production_run_id': row['id']},
      );
      return;
    }
    if (action == 'invoice_order') {
      await _execute('invoice_sales_order', {'sales_order_id': row['id']});
      return;
    }
    if (action == 'cancel_sales_order') {
      await _runRowForm(
        _OperationSpec(
          'Cancel quotation',
          'cancel_sales_order',
          Icons.cancel_outlined,
          [_InputSpec('reason', 'Cancellation reason')],
        ),
        {'sales_order_id': row['id']},
      );
      return;
    }
    if (action == 'cancel_invoiced_order') {
      await _runRowForm(
        _OperationSpec(
          'Cancel invoice with credit note',
          'cancel_invoiced_order',
          Icons.receipt_long_outlined,
          [_InputSpec('reason', 'Credit note reason')],
        ),
        {'sales_order_id': row['id']},
      );
      return;
    }
    if (action == 'record_sales_payment') {
      await _runRowForm(
        _OperationSpec(
          'Record buyer payment',
          'record_sales_payment',
          Icons.account_balance_rounded,
          [
            _InputSpec('amount', 'Received amount', type: _InputType.number),
            _InputSpec(
              'payment_mode',
              'Payment mode',
              choices: const ['upi', 'bank_transfer', 'cash', 'cheque'],
            ),
            _InputSpec('reference', 'Payment reference'),
            _InputSpec('proof_path', 'Payment proof path', required: false),
          ],
        ),
        {'sales_order_id': row['id']},
      );
      return;
    }
    if (action == 'reverse_sales_payment') {
      await _runRowForm(
        _OperationSpec(
          'Reverse buyer payment',
          'reverse_sales_payment',
          Icons.undo_rounded,
          [_InputSpec('reason', 'Reversal reason')],
        ),
        {'sales_payment_id': row['id']},
      );
      return;
    }
    if (action == 'deliver_dispatch') {
      await _runRowForm(
        _OperationSpec(
          'Confirm delivery',
          'deliver_dispatch',
          Icons.task_alt_rounded,
          [
            _InputSpec('delivery_note', 'Delivery note'),
            _InputSpec('signature_name', 'Received by'),
            _InputSpec('proof_image_path', 'Proof image path', required: false),
          ],
        ),
        {'dispatch_id': row['id']},
        transform: (payload) {
          payload['proof_of_delivery'] = {
            'note': payload.remove('delivery_note'),
            'signature_name': payload.remove('signature_name'),
            'image_path': payload.remove('proof_image_path'),
            'captured_at': DateTime.now().toUtc().toIso8601String(),
          };
        },
      );
      return;
    }
    if (action == 'cancel_dispatch') {
      await _runRowForm(
        _OperationSpec(
          'Cancel dispatch',
          'cancel_dispatch',
          Icons.cancel_outlined,
          [_InputSpec('reason', 'Cancellation reason')],
        ),
        {'dispatch_id': row['id']},
      );
      return;
    }
    if (action.startsWith('payment_')) {
      final next = action.substring('payment_'.length);
      if (next == 'paid') {
        await _runRowForm(
          _OperationSpec(
            'Mark payment paid',
            'transition_farmer_payment',
            Icons.payments_rounded,
            [
              _InputSpec(
                'payment_mode',
                'Payment mode',
                choices: const ['upi', 'bank_transfer'],
              ),
              _InputSpec('payment_reference', 'Transfer reference'),
              _InputSpec(
                'payment_proof_path',
                'Payment proof path',
                required: false,
              ),
            ],
          ),
          {'payment_id': row['id'], 'status': 'paid'},
        );
      } else {
        await _execute('transition_farmer_payment', {
          'payment_id': row['id'],
          'status': next,
        });
      }
      return;
    }
    if (action == 'correct_payment') {
      await _runRowForm(
        _OperationSpec(
          'Correct payment',
          'correct_farmer_payment',
          Icons.edit_note_rounded,
          [
            _InputSpec(
              'net_weight_kg',
              'Net weight kg',
              type: _InputType.number,
              initialValue: '${row['net_weight_kg'] ?? ''}',
            ),
            _InputSpec(
              'rate_per_kg',
              'Rate per kg',
              type: _InputType.number,
              initialValue: '${row['rate_per_kg'] ?? ''}',
            ),
            _InputSpec(
              'bonus',
              'Bonus',
              type: _InputType.number,
              initialValue: '${row['bonus'] ?? 0}',
            ),
            _InputSpec(
              'deductions',
              'Deductions',
              type: _InputType.number,
              initialValue: '${row['deductions'] ?? 0}',
            ),
          ],
        ),
        {'payment_id': row['id']},
      );
    }
  }

  Future<void> _runRowForm(
    _OperationSpec operation,
    Map<String, dynamic> fixed, {
    void Function(Map<String, dynamic>)? transform,
  }) async {
    final lookups = <String, List<Map<String, dynamic>>>{};
    for (final field in operation.fields.where(
      (field) => field.lookupTable != null,
    )) {
      lookups[field.key] = await widget.service.loadLookup(field.lookupTable!);
    }
    if (!mounted) return;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _OperationDialog(operation: operation, lookups: lookups),
    );
    if (payload == null) return;
    payload.addAll(fixed);
    transform?.call(payload);
    await _execute(operation.operation, payload);
  }

  Future<void> _execute(String operation, Map<String, dynamic> payload) async {
    setState(() => _working = true);
    try {
      await widget.service.executeOperation(operation, payload);
      if (!mounted) return;
      Get.snackbar(
        UiStrings.fromEnglish('Saved'),
        UiStrings.fromEnglish('The FPC record was saved successfully.'),
      );
      await widget.onChanged();
    } catch (error) {
      if (mounted) {
        Get.snackbar(UiStrings.fromEnglish('Could not save'), '$error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _generateReport(String type, String format) async {
    setState(() => _working = true);
    try {
      final result = await FpcReportService(
        operatingService: widget.service,
      ).generateAndShare(reportType: type, format: format);
      if (!mounted) return;
      Get.snackbar(
        UiStrings.fromEnglish('Report ready'),
        UiStrings.f('fpc_report_generated', {
          'file': result.fileName,
          'count': result.rowCount,
        }),
      );
      await widget.onChanged();
    } catch (error) {
      if (mounted) {
        Get.snackbar(UiStrings.fromEnglish('Report failed'), '$error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refreshInsights() => _execute('generate_ai_insights', const {});
}

enum _InputType { text, number, date, dateTime }

class _InputSpec {
  final String key;
  final String label;
  final _InputType type;
  final bool required;
  final String initialValue;
  final List<String> choices;
  final String? lookupTable;
  final String valueKey;
  final List<String> displayKeys;

  const _InputSpec(
    this.key,
    this.label, {
    this.type = _InputType.text,
    this.required = true,
    this.initialValue = '',
    this.choices = const [],
    this.lookupTable,
    this.valueKey = 'id',
    this.displayKeys = const ['name', 'title', 'id'],
  });
}

class _OperationSpec {
  final String label;
  final String operation;
  final IconData icon;
  final List<_InputSpec> fields;
  const _OperationSpec(this.label, this.operation, this.icon, this.fields);
}

class _OperationDialog extends StatefulWidget {
  final _OperationSpec operation;
  final Map<String, List<Map<String, dynamic>>> lookups;
  final Map<String, dynamic> initialValues;
  const _OperationDialog({
    required this.operation,
    required this.lookups,
    this.initialValues = const {},
  });

  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  final Map<String, String> _selected = {};

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.operation.fields)
        field.key: TextEditingController(
          text:
              widget.initialValues[field.key]?.toString() ?? field.initialValue,
        ),
    };
    for (final field in widget.operation.fields) {
      if (field.choices.isNotEmpty || field.lookupTable != null) {
        final value = widget.initialValues[field.key]?.toString() ?? '';
        if (value.isNotEmpty) _selected[field.key] = value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(UiStrings.fromEnglish(widget.operation.label)),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in widget.operation.fields) ...[
                  _field(field),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(UiStrings.fromEnglish('Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(UiStrings.fromEnglish('Save')),
        ),
      ],
    );
  }

  Widget _field(_InputSpec field) {
    final lookup = widget.lookups[field.key];
    if (lookup != null) {
      final usable = switch (field.lookupTable) {
        'fpc_memberships' =>
          lookup
              .where(
                (row) =>
                    row['role'] == 'field_officer' && row['status'] == 'active',
              )
              .toList(),
        'fpc_crop_programs' =>
          lookup.where((row) => row['status'] == 'active').toList(),
        'fpc_seed_batches' =>
          lookup.where((row) => row['status'] == 'active').toList(),
        'fpc_program_enrollments' =>
          lookup.where((row) => row['status'] == 'accepted').toList(),
        'fpc_farmer_links' =>
          lookup.where((row) => row['status'] == 'active').toList(),
        _ => lookup,
      };
      return DropdownButtonFormField<String>(
        initialValue: _selected[field.key],
        decoration: InputDecoration(
          labelText: UiStrings.fromEnglish(field.label),
        ),
        items: usable
            .map(
              (row) => DropdownMenuItem(
                value: '${row[field.valueKey] ?? ''}',
                child: Text(
                  _lookupLabel(row, field.displayKeys),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) =>
            setState(() => _selected[field.key] = value ?? ''),
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? UiStrings.fromEnglish('Required')
            : null,
      );
    }
    if (field.choices.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: (_selected[field.key] ?? '').isNotEmpty
            ? _selected[field.key]
            : null,
        decoration: InputDecoration(
          labelText: UiStrings.fromEnglish(field.label),
        ),
        items: field.choices
            .map(
              (choice) => DropdownMenuItem(
                value: choice,
                child: Text(UiStrings.fromEnglish(_humanize(choice))),
              ),
            )
            .toList(),
        onChanged: (value) =>
            setState(() => _selected[field.key] = value ?? ''),
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? UiStrings.fromEnglish('Required')
            : null,
      );
    }
    if (field.type == _InputType.date || field.type == _InputType.dateTime) {
      final controller = _controllers[field.key]!;
      final parsed = DateTime.tryParse(controller.text);
      return TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: UiStrings.fromEnglish(field.label),
          suffixIcon: const Icon(Icons.calendar_month_rounded),
        ),
        onTap: () async {
          final now = DateTime.now();
          final selectedDate = await showDatePicker(
            context: context,
            initialDate: parsed ?? now,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (selectedDate == null || !mounted) return;
          if (field.type == _InputType.date) {
            controller.text = DateFormat('yyyy-MM-dd').format(selectedDate);
          } else {
            final selectedTime = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(parsed ?? now),
            );
            if (selectedTime == null || !mounted) return;
            controller.text = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              selectedTime.hour,
              selectedTime.minute,
            ).toUtc().toIso8601String();
          }
          setState(() {});
        },
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? UiStrings.fromEnglish('Required')
            : null,
      );
    }
    return TextFormField(
      controller: _controllers[field.key],
      keyboardType: field.type == _InputType.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: UiStrings.fromEnglish(field.label),
      ),
      validator: (value) {
        if (field.required && (value == null || value.trim().isEmpty)) {
          return UiStrings.fromEnglish('Required');
        }
        if (field.type == _InputType.number &&
            value!.isNotEmpty &&
            num.tryParse(value) == null) {
          return UiStrings.fromEnglish('Enter a valid number');
        }
        if (field.type == _InputType.number &&
            field.key == 'capacity_kg' &&
            value != null &&
            value.isNotEmpty &&
            (num.tryParse(value) ?? 0) < 0) {
          return UiStrings.fromEnglish('Enter zero or a positive capacity');
        }
        return null;
      },
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final result = <String, dynamic>{};
    for (final field in widget.operation.fields) {
      result[field.key] = field.choices.isNotEmpty || field.lookupTable != null
          ? (_selected[field.key] ?? '')
          : _controllers[field.key]!.text.trim();
    }
    Navigator.pop(context, result);
  }

  static String _lookupLabel(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != 'null') return value;
    }
    return '${row['id'] ?? ''}';
  }
}

class _RecordCard extends StatelessWidget {
  final String module;
  final Map<String, dynamic> row;
  final ValueChanged<String> onAction;
  const _RecordCard({
    required this.module,
    required this.row,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final actions = _rowActions(module, row);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.greenLight.withValues(alpha: 0.25),
          child: Icon(_moduleIcon(module), color: AppTheme.greenDark),
        ),
        title: Text(
          UiStrings.fromEnglish(_rowTitle(module, row)),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          _rowSubtitle(module, row),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: actions.isEmpty
            ? null
            : PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (_) => actions
                    .map(
                      (action) => PopupMenuItem(
                        value: action.$1,
                        child: Text(UiStrings.fromEnglish(action.$2)),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class _CollectionCenterWorkspace extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final void Function(String action, Map<String, dynamic> row) onAction;

  const _CollectionCenterWorkspace({
    required this.rows,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final centers =
        rows.where((row) => row['_entity'] == 'center').toList(growable: true)
          ..sort(_compareCollectionCenters);
    final receipts =
        rows.where((row) => row['_entity'] == 'receipt').toList(growable: true)
          ..sort(_compareCollectionReceipts);
    final activeCenters = centers
        .where((row) => row['active'] != false)
        .toList(growable: false);
    final totalCapacity = centers.fold<double>(
      0,
      (sum, row) => sum + (num.tryParse('${row['capacity_kg'] ?? 0}') ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollectionReadinessCard(
          activeCenters: activeCenters.length,
          totalCenters: centers.length,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _CollectionMetricCard(
              label: 'Active centers',
              value: '${activeCenters.length}',
              icon: Icons.storefront_outlined,
            ),
            _CollectionMetricCard(
              label: 'Handling capacity',
              value: _fpcKg(totalCapacity),
              icon: Icons.scale_outlined,
            ),
            _CollectionMetricCard(
              label: 'Recent receipts',
              value: '${receipts.length}',
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CollectionSectionTitle(
          step: 1,
          title: 'Collection centers',
          subtitle: activeCenters.isEmpty
              ? 'Set up one active center before receiving farmer produce.'
              : 'Use active centers for farmer receiving and weighing.',
        ),
        const SizedBox(height: 8),
        if (centers.isEmpty)
          _CollectionEmptyCard(
            icon: Icons.add_business_rounded,
            title: 'No collection center yet',
            message:
                'Add the village center, address and daily handling capacity first.',
          )
        else
          for (var index = 0; index < centers.length; index++)
            _CollectionCenterCard(row: centers[index], sequence: index + 1),
        const SizedBox(height: 18),
        _CollectionSectionTitle(
          step: 2,
          title: 'Recent receipts',
          subtitle: 'Latest produce received through QR or receiver workflow.',
        ),
        const SizedBox(height: 8),
        if (receipts.isEmpty)
          _CollectionEmptyCard(
            icon: Icons.receipt_long_outlined,
            title: 'No receipts yet',
            message:
                'Use the receiver after a center is ready to record incoming produce.',
          )
        else
          for (final receipt in receipts)
            _RecordCard(
              module: 'collection_center',
              row: receipt,
              onAction: (action) => onAction(action, receipt),
            ),
      ],
    );
  }
}

int _compareCollectionCenters(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final leftActive = left['active'] != false;
  final rightActive = right['active'] != false;
  if (leftActive != rightActive) return leftActive ? -1 : 1;
  final byName = _fpcRaw(
    left['name'],
  ).toLowerCase().compareTo(_fpcRaw(right['name']).toLowerCase());
  if (byName != 0) return byName;
  final byVillage = _fpcRaw(
    left['village'],
  ).toLowerCase().compareTo(_fpcRaw(right['village']).toLowerCase());
  if (byVillage != 0) return byVillage;
  return _fpcRaw(left['id']).compareTo(_fpcRaw(right['id']));
}

int _compareCollectionReceipts(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final byReceived = _compareDateDesc(
    left['received_at'],
    right['received_at'],
  );
  if (byReceived != 0) return byReceived;
  return _compareDateDesc(left['created_at'], right['created_at']);
}

int _compareDateDesc(Object? left, Object? right) {
  final leftDate = DateTime.tryParse(_fpcRaw(left));
  final rightDate = DateTime.tryParse(_fpcRaw(right));
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return rightDate.compareTo(leftDate);
}

class _CollectionReadinessCard extends StatelessWidget {
  final int activeCenters;
  final int totalCenters;

  const _CollectionReadinessCard({
    required this.activeCenters,
    required this.totalCenters,
  });

  @override
  Widget build(BuildContext context) {
    final ready = activeCenters > 0;
    final activeCenterText = _collectionCount(activeCenters, 'active center');
    final totalCenterText = _collectionCount(totalCenters, 'total center');
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready
                      ? Icons.check_circle_outline_rounded
                      : Icons.priority_high_rounded,
                  color: ready ? AppTheme.greenDark : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    UiStrings.fromEnglish(
                      ready ? 'Ready for receiving' : 'Center setup needed',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              UiStrings.fromEnglish(
                ready
                    ? '$activeCenterText out of $totalCenterText.'
                    : 'Add one active collection center before recording farmer produce.',
              ),
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _CollectionMetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.greenDark),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.fromEnglish(value),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      UiStrings.fromEnglish(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _collectionCount(int count, String label) {
  return '$count $label${count == 1 ? '' : 's'}';
}

class _CollectionSectionTitle extends StatelessWidget {
  final int? step;
  final String title;
  final String subtitle;

  const _CollectionSectionTitle({
    this.step,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          UiStrings.fromEnglish(step == null ? title : 'Step $step: $title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          UiStrings.fromEnglish(subtitle),
          style: const TextStyle(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

class _CollectionCenterCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final int sequence;

  const _CollectionCenterCard({required this.row, required this.sequence});

  @override
  Widget build(BuildContext context) {
    final active = row['active'] != false;
    final address = '${row['address'] ?? ''}'.trim();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: active
                  ? AppTheme.greenLight.withValues(alpha: 0.25)
                  : Colors.grey.shade200,
              foregroundColor: active ? AppTheme.greenDark : Colors.grey,
              child: Text(
                '$sequence',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          UiStrings.fromEnglish('${row['name'] ?? 'Center'}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Chip(
                        label: Text(
                          UiStrings.fromEnglish(active ? 'Active' : 'Inactive'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      _CollectionInfoChip(
                        icon: Icons.location_on_outlined,
                        text: '${row['village'] ?? 'Village'}',
                      ),
                      _CollectionInfoChip(
                        icon: Icons.scale_outlined,
                        text: _fpcKg(row['capacity_kg']),
                      ),
                    ],
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      UiStrings.fromEnglish(address),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CollectionInfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          UiStrings.fromEnglish(text),
          style: const TextStyle(color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

class _CollectionEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _CollectionEmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.greenDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.fromEnglish(title),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    UiStrings.fromEnglish(message),
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String module;
  const _EmptyState({required this.module});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(_moduleIcon(module), size: 42, color: AppTheme.greenDark),
          const SizedBox(height: 10),
          Text(
            UiStrings.fromEnglish('No records yet.'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            UiStrings.fromEnglish(
              'Use the available action to create the first live record.',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

List<_OperationSpec> _moduleOperations(String module) => switch (module) {
  'crop_programs' => [
    _OperationSpec(
      'Create crop program',
      'create_crop_program',
      Icons.add_rounded,
      [
        _InputSpec('name', 'Program name'),
        _InputSpec('code', 'Program code', required: false),
        _InputSpec(
          'crop',
          'Operating grain',
          choices: FpcSetupReadiness.allowedGrains,
        ),
        _InputSpec('variety', 'Variety', required: false),
        _InputSpec('season', 'Season'),
        _InputSpec('minimum_grade', 'Minimum grade', choices: ['A', 'B', 'C']),
        _InputSpec(
          'max_moisture_percent',
          'Maximum moisture percent',
          type: _InputType.number,
          initialValue: '14',
        ),
        _InputSpec(
          'reference_rate_per_kg',
          'Protected reference rate per kg',
          type: _InputType.number,
        ),
        _InputSpec(
          'checkpoints',
          'Required checkpoints (comma separated)',
          initialValue: 'Sowing, Vegetative, Flowering, Pre-harvest',
        ),
      ],
    ),
    _OperationSpec(
      'Register seed batch',
      'register_seed_batch',
      Icons.grass_rounded,
      [
        _InputSpec(
          'program_id',
          'Active crop program',
          lookupTable: 'fpc_crop_programs',
          displayKeys: ['name', 'code'],
        ),
        _InputSpec('batch_code', 'Seed batch code'),
        _InputSpec('seed_name', 'Seed name'),
        _InputSpec('supplier_name', 'Supplier name'),
        _InputSpec(
          'certification_number',
          'Certification number',
          required: false,
        ),
        _InputSpec(
          'received_quantity_kg',
          'Received quantity kg',
          type: _InputType.number,
        ),
        _InputSpec(
          'unit_price_per_kg',
          'All-inclusive price per kg (₹)',
          type: _InputType.number,
        ),
        _InputSpec(
          'manufactured_on',
          'Manufactured on',
          type: _InputType.date,
          required: false,
        ),
        _InputSpec(
          'expires_on',
          'Expires on',
          type: _InputType.date,
          required: false,
        ),
      ],
    ),
    _OperationSpec(
      'Enroll linked farmer',
      'enroll_farmer_program',
      Icons.person_add_alt_1_rounded,
      [
        _InputSpec(
          'program_id',
          'Active crop program',
          lookupTable: 'fpc_crop_programs',
          displayKeys: ['name', 'code'],
        ),
        _InputSpec(
          'farmer_link_id',
          'Linked farmer',
          lookupTable: 'fpc_farmer_links',
          displayKeys: ['farmer_name', 'farmer_id'],
        ),
        _InputSpec(
          'assigned_officer_id',
          'Field Officer',
          lookupTable: 'fpc_memberships',
          valueKey: 'user_id',
          displayKeys: ['display_name', 'email'],
        ),
      ],
    ),
    _OperationSpec(
      'Issue program seed',
      'issue_program_seed',
      Icons.inventory_2_outlined,
      [
        _InputSpec(
          'enrollment_id',
          'Accepted farmer enrollment',
          lookupTable: 'fpc_program_enrollments',
          displayKeys: ['farmer_id', 'crop'],
        ),
        _InputSpec(
          'seed_batch_id',
          'Seed batch',
          lookupTable: 'fpc_seed_batches',
          displayKeys: ['batch_code', 'seed_name'],
        ),
        _InputSpec('quantity_kg', 'Issue quantity kg', type: _InputType.number),
        _InputSpec(
          'scheduled_for',
          'Delivery schedule',
          type: _InputType.dateTime,
          initialValue: DateTime.now()
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        ),
      ],
    ),
  ],
  'harvest_planning' => [
    _OperationSpec(
      'Add harvest plan',
      'create_harvest_plan',
      Icons.add_rounded,
      [
        _InputSpec('farm_id', 'Farm ID'),
        _InputSpec('crop', 'Crop'),
        _InputSpec('village', 'Village'),
        _InputSpec(
          'expected_harvest_date',
          'Expected harvest date',
          type: _InputType.date,
        ),
        _InputSpec(
          'expected_quantity_kg',
          'Expected quantity kg',
          type: _InputType.number,
        ),
        _InputSpec('expected_grade', 'Expected grade', required: false),
        _InputSpec(
          'readiness',
          'Readiness',
          choices: ['planned', 'monitoring', 'ready'],
        ),
        _InputSpec(
          'priority',
          'Priority',
          choices: ['low', 'normal', 'high', 'urgent'],
        ),
        _InputSpec(
          'assigned_to',
          'Field Officer',
          required: false,
          lookupTable: 'fpc_memberships',
          valueKey: 'user_id',
          displayKeys: ['display_name', 'email'],
        ),
        _InputSpec('notes', 'Notes', required: false),
      ],
    ),
  ],
  'procurement' => [
    _OperationSpec(
      'Schedule procurement',
      'create_procurement_schedule',
      Icons.event_rounded,
      [
        _InputSpec(
          'harvest_plan_id',
          'Harvest plan',
          lookupTable: 'harvest_plans',
          displayKeys: ['crop', 'farm_id'],
        ),
        _InputSpec(
          'collection_center_id',
          'Collection center',
          lookupTable: 'collection_centers',
        ),
        _InputSpec(
          'assigned_officer_id',
          'Field Officer',
          lookupTable: 'fpc_memberships',
          valueKey: 'user_id',
          displayKeys: ['display_name', 'email'],
        ),
        _InputSpec(
          'scheduled_at',
          'Schedule time',
          type: _InputType.dateTime,
          initialValue: DateTime.now()
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        ),
        _InputSpec('notes', 'Notes', required: false),
      ],
    ),
    _OperationSpec(
      'Assign vehicle',
      'create_vehicle_assignment',
      Icons.local_shipping_outlined,
      [
        _InputSpec(
          'procurement_schedule_id',
          'Procurement schedule',
          lookupTable: 'procurement_schedules',
          displayKeys: ['scheduled_at', 'id'],
        ),
        _InputSpec('vehicle_number', 'Vehicle number'),
        _InputSpec('driver_name', 'Driver name'),
        _InputSpec('driver_phone', 'Driver phone'),
        _InputSpec('route_notes', 'Route notes', required: false),
      ],
    ),
  ],
  'collection_center' => [
    _OperationSpec(
      'Add collection center',
      'create_collection_center',
      Icons.add_business_rounded,
      [
        _InputSpec('name', 'Center name'),
        _InputSpec('village', 'Village'),
        _InputSpec('address', 'Address / landmark'),
        _InputSpec(
          'capacity_kg',
          'Daily handling capacity kg',
          type: _InputType.number,
        ),
      ],
    ),
  ],
  'quality' => [
    _OperationSpec(
      'Approve quality certificate',
      'approve_quality',
      Icons.verified_rounded,
      [
        _InputSpec(
          'lot_id',
          'Procurement lot',
          lookupTable: 'procurement_lots',
          displayKeys: ['batch_id', 'crop'],
        ),
        _InputSpec(
          'analysis_job_id',
          'Grading analysis',
          required: false,
          lookupTable: 'analysis_jobs',
          displayKeys: ['batch_id', 'id'],
        ),
        _InputSpec('grade', 'Approved grade'),
        _InputSpec('lab_note', 'Lab note', required: false),
      ],
    ),
  ],
  'warehouse' => [
    _OperationSpec(
      'Add warehouse',
      'create_warehouse',
      Icons.add_business_rounded,
      [
        _InputSpec('name', 'Warehouse name'),
        _InputSpec('address', 'Address'),
        _InputSpec('capacity_kg', 'Capacity kg', type: _InputType.number),
      ],
    ),
    _OperationSpec(
      'Add rack or bin',
      'create_warehouse_location',
      Icons.grid_view_rounded,
      [
        _InputSpec('warehouse_id', 'Warehouse', lookupTable: 'warehouses'),
        _InputSpec('code', 'Rack or bin code'),
        _InputSpec(
          'location_type',
          'Location type',
          choices: ['rack', 'bin', 'floor'],
        ),
        _InputSpec('capacity_kg', 'Capacity kg', type: _InputType.number),
      ],
    ),
  ],
  'production' => [
    _OperationSpec(
      'Create production run',
      'create_production_run',
      Icons.add_rounded,
      [
        _InputSpec('process_type', 'Process type', choices: ['millet', 'rice']),
        _InputSpec(
          'input_lot_id',
          'Input procurement lot',
          lookupTable: 'procurement_lots',
          displayKeys: ['batch_id', 'crop'],
        ),
        _InputSpec('input_kg', 'Input kg', type: _InputType.number),
        _InputSpec('machine', 'Machine'),
        _InputSpec('operator_name', 'Operator'),
      ],
    ),
  ],
  'packaging' => [
    _OperationSpec(
      'Create packaging batch',
      'create_packaging_batch',
      Icons.add_box_rounded,
      [
        _InputSpec(
          'production_run_id',
          'Completed production run',
          lookupTable: 'production_runs',
          displayKeys: ['run_number', 'process_type'],
        ),
        _InputSpec('product_name', 'Product name'),
        _InputSpec(
          'package_size_grams',
          'Package size',
          choices: ['500', '1000', '5000', '10000', '25000', '50000'],
        ),
        _InputSpec('package_count', 'Package count', type: _InputType.number),
        _InputSpec(
          'manufactured_on',
          'Manufacturing date',
          type: _InputType.date,
          initialValue: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        ),
        _InputSpec('expires_on', 'Expiry date', type: _InputType.date),
      ],
    ),
  ],
  'inventory' => [
    _OperationSpec(
      'Post stock movement',
      'post_stock_movement',
      Icons.playlist_add_rounded,
      [
        _InputSpec(
          'movement_type',
          'Movement type',
          choices: ['receipt', 'adjustment_in', 'adjustment_out', 'damage'],
        ),
        _InputSpec(
          'item_type',
          'Item type',
          choices: ['raw_material', 'work_in_progress', 'finished_goods'],
        ),
        _InputSpec('item_name', 'Item name'),
        _InputSpec('quantity_kg', 'Quantity kg', type: _InputType.number),
        _InputSpec(
          'warehouse_id',
          'Warehouse',
          required: false,
          lookupTable: 'warehouses',
        ),
        _InputSpec(
          'location_id',
          'Rack or bin',
          required: false,
          lookupTable: 'warehouse_locations',
          displayKeys: ['code', 'id'],
        ),
        _InputSpec(
          'lot_id',
          'Procurement lot',
          required: false,
          lookupTable: 'procurement_lots',
          displayKeys: ['batch_id', 'crop'],
        ),
        _InputSpec(
          'packaging_batch_id',
          'Packaging batch',
          required: false,
          lookupTable: 'packaging_batches',
          displayKeys: ['batch_number', 'product_name'],
        ),
        _InputSpec('reason', 'Reason'),
        _InputSpec(
          'expires_on',
          'Expiry date',
          type: _InputType.date,
          required: false,
        ),
      ],
    ),
    _OperationSpec(
      'Transfer stock',
      'transfer_stock',
      Icons.swap_horiz_rounded,
      [
        _InputSpec(
          'source_warehouse_id',
          'Source warehouse',
          lookupTable: 'warehouses',
        ),
        _InputSpec(
          'source_location_id',
          'Source location',
          lookupTable: 'warehouse_locations',
          displayKeys: ['code', 'id'],
        ),
        _InputSpec(
          'destination_warehouse_id',
          'Destination warehouse',
          lookupTable: 'warehouses',
        ),
        _InputSpec(
          'destination_location_id',
          'Destination location',
          lookupTable: 'warehouse_locations',
          displayKeys: ['code', 'id'],
        ),
        _InputSpec(
          'lot_id',
          'Procurement lot',
          required: false,
          lookupTable: 'procurement_lots',
          displayKeys: ['batch_id', 'crop'],
        ),
        _InputSpec(
          'packaging_batch_id',
          'Packaging batch',
          required: false,
          lookupTable: 'packaging_batches',
          displayKeys: ['batch_number', 'product_name'],
        ),
        _InputSpec(
          'item_type',
          'Item type',
          choices: ['raw_material', 'finished_goods'],
        ),
        _InputSpec('item_name', 'Item name'),
        _InputSpec('quantity_kg', 'Quantity kg', type: _InputType.number),
        _InputSpec('reason', 'Transfer reason'),
      ],
    ),
  ],
  'sales' => [
    _OperationSpec(
      'Add buyer',
      'create_buyer',
      Icons.person_add_alt_1_rounded,
      [
        _InputSpec(
          'buyer_type',
          'Buyer type',
          choices: [
            'retail',
            'distributor',
            'government',
            'export',
            'institutional',
          ],
        ),
        _InputSpec('name', 'Buyer name'),
        _InputSpec('phone', 'Phone', required: false),
        _InputSpec('email', 'Email', required: false),
        _InputSpec('gstin', 'GSTIN', required: false),
      ],
    ),
    _OperationSpec(
      'Create quotation',
      'create_sales_order',
      Icons.request_quote_rounded,
      [
        _InputSpec('buyer_id', 'Buyer', lookupTable: 'buyers'),
        _InputSpec(
          'packaging_batch_id',
          'Packaging batch',
          required: false,
          lookupTable: 'packaging_batches',
          displayKeys: ['batch_number', 'product_name'],
        ),
        _InputSpec('item_name', 'Product name'),
        _InputSpec(
          'allocation_method',
          'Stock allocation',
          choices: ['fefo', 'fifo'],
        ),
        _InputSpec('description', 'Product description'),
        _InputSpec('quantity_kg', 'Quantity kg', type: _InputType.number),
        _InputSpec('rate', 'Rate per kg', type: _InputType.number),
        _InputSpec(
          'tax_rate',
          'GST percent',
          type: _InputType.number,
          initialValue: '5',
        ),
        _InputSpec('interstate', 'Interstate sale', choices: ['false', 'true']),
      ],
    ),
  ],
  'logistics' => [
    _OperationSpec(
      'Dispatch invoiced order',
      'dispatch_sales_order',
      Icons.local_shipping_rounded,
      [
        _InputSpec(
          'sales_order_id',
          'Invoiced sales order',
          lookupTable: 'sales_orders',
          displayKeys: ['invoice_number', 'order_number'],
        ),
        _InputSpec('vehicle_number', 'Vehicle number'),
        _InputSpec('driver_name', 'Driver name'),
        _InputSpec('route_notes', 'Route notes', required: false),
      ],
    ),
  ],
  'farmer_payments' ||
  'reports' ||
  'ai_insights' ||
  'farmer_network' ||
  'farm_monitoring' => const [],
  _ => const [],
};

List<(String, String)> _rowActions(String module, Map<String, dynamic> row) {
  final status = '${row['status'] ?? ''}';
  if (module == 'farmer_network') {
    return status == 'active'
        ? [('deactivate_farmer', 'Deactivate link')]
        : [('activate_farmer', 'Activate link')];
  }
  if (module == 'crop_programs') {
    final entity = '${row['_entity'] ?? ''}';
    final enrollment = row['enrollment'] is Map
        ? Map<String, dynamic>.from(row['enrollment'] as Map)
        : const <String, dynamic>{};
    final enrollmentStatus = '${enrollment['status'] ?? ''}';
    return [
      if (entity == 'seed_request' && status == 'submitted')
        ('approve_seed_request', 'Approve and assign officer'),
      if (entity == 'seed_request' && status == 'submitted')
        ('decline_seed_request', 'Decline request'),
      if (entity == 'seed_request' &&
          status == 'approved' &&
          enrollmentStatus == 'accepted' &&
          row['payment_status'] == 'captured')
        ('issue_requested_seed', 'Issue requested seed'),
      if (entity == 'seed_request' &&
          row['payment_status'] == 'captured' &&
          !{'delivered', 'acknowledged', 'cancelled'}.contains(status))
        ('refund_seed_request', 'Refund full payment'),
      if (entity == 'seed_batch') ('price_seed_batch', 'Set or update price'),
      if (entity == 'program' && status == 'draft')
        ('activate_crop_program', 'Activate program'),
      if (entity == 'evaluation' && status == 'pending_fpc_review')
        ('pass_crop_program', 'Approve harvest'),
      if (entity == 'evaluation' && status == 'pending_fpc_review')
        ('fail_crop_program', 'Hold for remediation'),
      if (entity == 'enrollment' &&
          !{'released', 'completed', 'cancelled', 'procured'}.contains(status))
        ('release_crop_program', 'Final decline and release'),
    ];
  }
  if (module == 'production') {
    return [
      if (status == 'planned') ('start_production', 'Start production'),
      if (status == 'planned' || status == 'in_progress')
        ('complete_production', 'Complete production'),
    ];
  }
  if (module == 'procurement' && row['_entity'] == 'schedule') {
    return [
      if (status == 'scheduled')
        ('procurement_in_collection', 'Start collection'),
      if (status == 'warehoused')
        ('procurement_completed', 'Complete procurement'),
      if (!{'completed', 'cancelled'}.contains(status))
        ('procurement_cancelled', 'Cancel schedule'),
    ];
  }
  if (module == 'sales' && row['_entity'] == 'order') {
    return [
      if (status == 'quotation' || status == 'confirmed')
        ('invoice_order', 'Issue GST invoice'),
      if (status == 'quotation' || status == 'confirmed')
        ('cancel_sales_order', 'Cancel quotation'),
      if (status == 'invoiced')
        ('cancel_invoiced_order', 'Cancel with credit note'),
      if (status == 'delivered' || status == 'paid')
        ('record_sales_payment', 'Record buyer payment'),
    ];
  }
  if (module == 'sales' &&
      row['_entity'] == 'payment' &&
      row['entry_type'] == 'receipt') {
    return [('reverse_sales_payment', 'Reverse buyer payment')];
  }
  if (module == 'logistics') {
    return [
      if (status == 'dispatched' || status == 'in_transit')
        ('deliver_dispatch', 'Confirm delivery'),
      if (status != 'delivered' && status != 'cancelled')
        ('cancel_dispatch', 'Cancel dispatch'),
    ];
  }
  if (module == 'farmer_payments') {
    return [
      if (status == 'draft') ('payment_verified', 'Verify payment'),
      if (status == 'verified') ('payment_approved', 'Approve payment'),
      if (status == 'approved') ('payment_paid', 'Mark paid'),
      if (status == 'verified' || status == 'approved' || status == 'paid')
        ('correct_payment', 'Correct with reversal'),
    ];
  }
  return const [];
}

String _rowTitle(String module, Map<String, dynamic> row) => switch (module) {
  'farmer_network' => '${row['farmer_name'] ?? row['farmer_id'] ?? 'Farmer'}',
  'crop_programs' =>
    row['_entity'] == 'seed_request'
        ? UiStrings.f('fpc_seed_request_row_title', {
            'farmer': row['farmer_id'] ?? UiStrings.t('farmer'),
          })
        : row['_entity'] == 'program'
        ? '${row['name'] ?? 'Crop program'}'
        : row['_entity'] == 'seed_batch'
        ? '${row['batch_code'] ?? 'Seed batch'}'
        : row['_entity'] == 'evaluation'
        ? UiStrings.f('fpc_harvest_check_count', {
            'count': ((row['attempt_no'] as num?)?.toInt() ?? 0) + 1,
          })
        : '${row['farmer_id'] ?? 'Farmer'} • ${row['crop'] ?? ''}',
  'farm_monitoring' =>
    row['_entity'] == 'farm'
        ? '${row['name'] ?? 'Farm'}'
        : row['_entity'] == 'snapshot'
        ? '${row['farm_name'] ?? 'Farm snapshot'}'
        : '${row['farmer_name'] ?? row['farmer_id'] ?? 'Farmer'}',
  'harvest_planning' => '${row['crop'] ?? 'Crop'} - ${row['farm_id'] ?? ''}',
  'procurement' =>
    row['_entity'] == 'lot'
        ? '${row['batch_id'] ?? 'Lot'}'
        : row['_entity'] == 'vehicle'
        ? '${row['vehicle_number'] ?? 'Vehicle'}'
        : '${row['scheduled_at'] ?? 'Schedule'}',
  'collection_center' =>
    row['_entity'] == 'center'
        ? '${row['name'] ?? 'Center'}'
        : '${row['receipt_number'] ?? row['batch_id'] ?? 'Receipt'}',
  'quality' => '${row['certificate_number'] ?? 'Quality certificate'}',
  'warehouse' =>
    row['_entity'] == 'location'
        ? '${row['code'] ?? 'Location'}'
        : '${row['name'] ?? 'Warehouse'}',
  'production' => '${row['run_number'] ?? 'Production run'}',
  'packaging' => '${row['batch_number'] ?? 'Packaging batch'}',
  'inventory' => '${row['item_name'] ?? 'Stock movement'}',
  'sales' =>
    row['_entity'] == 'buyer'
        ? '${row['name'] ?? 'Buyer'}'
        : row['_entity'] == 'payment'
        ? '${row['reference'] ?? 'Buyer payment'}'
        : row['_entity'] == 'credit_note'
        ? '${row['credit_note_number'] ?? 'Credit note'}'
        : '${row['invoice_number']?.toString().isNotEmpty == true ? row['invoice_number'] : row['order_number']}',
  'logistics' =>
    '${row['vehicle_number']?.toString().isNotEmpty == true ? row['vehicle_number'] : 'Dispatch'}',
  'farmer_payments' =>
    '${row['farmer_id'] ?? 'Farmer'} - ₹${row['final_amount'] ?? 0}',
  'reports' => '${row['file_name'] ?? 'Report'}',
  'ai_insights' => '${row['title'] ?? 'Insight'}',
  _ => '${row['id'] ?? ''}',
};

String _rowSubtitle(String module, Map<String, dynamic> row) {
  final status = '${row['status'] ?? row['delivery_status'] ?? ''}';
  final entity = '${row['_entity'] ?? ''}';
  final details = switch (module) {
    'farmer_network' => _fpcParts([
      _fpcRaw(row['village']),
      _fpcOption(row['crop']),
      _fpcMetric('KYC', _fpcOption(row['kyc_status'])),
    ]),
    'crop_programs' =>
      entity == 'seed_request'
          ? _fpcParts([
              _fpcOption(
                row['program'] is Map ? (row['program'] as Map)['crop'] : null,
              ),
              _fpcMetric('Requested', _fpcKg(row['requested_quantity_kg'])),
              _fpcMetric(
                'Enrollment',
                _fpcOption(
                  row['enrollment'] is Map
                      ? (row['enrollment'] as Map)['status']
                      : null,
                ),
              ),
            ])
          : entity == 'program'
          ? _fpcParts([
              _fpcOption(row['crop']),
              _fpcOption(row['season']),
              _fpcMetric(
                'Policy version',
                _fpcNumber(row['policy_version'] ?? 1),
              ),
            ])
          : entity == 'seed_batch'
          ? _fpcParts([
              _fpcOption(row['seed_name']),
              _fpcMetric('Available', _fpcKg(row['available_quantity_kg'])),
              _fpcMetric('Expiry', _fpcDate(row['expires_on'])),
            ])
          : entity == 'evaluation'
          ? _fpcParts([
              _fpcMetric('Floor', _fpcRatePerKg(row['protected_floor_rate'])),
              _fpcMetric('Decision due', _fpcDate(row['decision_due_at'])),
            ])
          : _fpcParts([
              _fpcOption(row['crop']),
              _fpcMetric('Farm', _fpcRaw(row['farm_id'])),
            ]),
    'farm_monitoring' =>
      entity == 'farm'
          ? _fpcParts([
              _fpcOption(row['crop']),
              _fpcOption(row['variety']),
              UiStrings.f('acres_value', {
                'value': _fpcNumber(row['area_acres']),
              }),
              _fpcOption(row['current_status_stage']),
            ])
          : entity == 'snapshot'
          ? _fpcParts([
              _fpcDate(row['snapshot_date']),
              _fpcMetric(
                'NDVI',
                _fpcNumber(
                  row['snapshot'] is Map
                      ? (row['snapshot'] as Map)['ndvi']
                      : null,
                  '-',
                ),
              ),
              _fpcMetric('Disease risk', _fpcOption(row['disease_risk'])),
              _fpcMetric(
                'Rain',
                '${_fpcNumber(row['rain_mm'])} ${UiStrings.t('mm_unit')}',
              ),
            ])
          : _fpcParts([
              _fpcRaw(row['village']),
              _fpcOption(row['crop']),
              _fpcMetric('KYC', _fpcOption(row['kyc_status'])),
            ]),
    'harvest_planning' => _fpcParts([
      _fpcDate(row['expected_harvest_date']),
      _fpcKg(row['expected_quantity_kg']),
      _fpcOption(row['priority']),
    ]),
    'procurement' =>
      entity == 'lot'
          ? _fpcParts([
              _fpcOption(row['crop']),
              _fpcKg(row['net_weight_kg']),
              _fpcMetric('Grade', _fpcOption(row['grade'])),
            ])
          : entity == 'vehicle'
          ? _fpcParts([
              _fpcRaw(row['driver_name']),
              _fpcRaw(row['driver_phone']),
            ])
          : _fpcRaw(row['notes']),
    'collection_center' =>
      entity == 'center'
          ? _fpcParts([
              _fpcRaw(row['village']),
              _fpcMetric('Capacity', _fpcKg(row['capacity_kg'])),
            ])
          : _fpcParts([
              _fpcOption(row['crop_type']),
              _fpcKg(row['net_weight_kg'] ?? row['quantity_kg']),
            ]),
    'quality' => _fpcParts([
      _fpcMetric('Grade', _fpcOption(row['grade'])),
      _fpcDate(row['approved_at']),
    ]),
    'warehouse' =>
      entity == 'location'
          ? _fpcParts([
              _fpcOption(row['location_type']),
              _fpcMetric('Capacity', _fpcKg(row['capacity_kg'])),
            ])
          : _fpcParts([
              _fpcRaw(row['address']),
              _fpcMetric('Capacity', _fpcKg(row['capacity_kg'])),
            ]),
    'production' => _fpcParts([
      _fpcOption(row['process_type']),
      _fpcMetric('Input', _fpcKg(row['input_kg'])),
      _fpcMetric('Output', _fpcKg(row['output_kg'])),
      _fpcMetric('Recovery', '${_fpcNumber(row['recovery_percent'])}%'),
    ]),
    'packaging' => _fpcParts([
      _fpcOption(row['product_name']),
      '${_fpcNumber(row['package_count'])} × '
          '${_fpcNumber(row['package_size_grams'])} ${UiStrings.t('g_unit')}',
      _fpcMetric('Expiry', _fpcDate(row['expires_on'])),
    ]),
    'inventory' => _fpcParts([
      _fpcOption(row['movement_type']),
      _fpcKg(row['quantity_kg']),
      _fpcDate(row['occurred_at']),
    ]),
    'sales' =>
      entity == 'buyer'
          ? _fpcParts([_fpcOption(row['buyer_type']), _fpcRaw(row['gstin'])])
          : entity == 'payment'
          ? _fpcParts([
              _fpcMoney(row['amount']),
              _fpcOption(row['payment_mode']),
              _fpcDate(row['recorded_at']),
            ])
          : entity == 'credit_note'
          ? _fpcParts([
              _fpcMoney(row['amount']),
              _fpcRaw(row['reason']),
              _fpcDate(row['issued_at']),
            ])
          : _fpcParts([_fpcMoney(row['total']), _fpcDate(row['ordered_at'])]),
    'logistics' => _fpcParts([
      _fpcRaw(row['driver_name']),
      _fpcDate(row['dispatched_at']),
    ]),
    'farmer_payments' => _fpcParts([
      '${_fpcKg(row['net_weight_kg'])} × ${_fpcRatePerKg(row['rate_per_kg'])}',
      _fpcMetric('Bonus', _fpcMoney(row['bonus'])),
      _fpcMetric('Deductions', _fpcMoney(row['deductions'])),
    ]),
    'reports' => _fpcParts([
      _fpcOption(row['format']),
      _fpcMetric('Rows', _fpcNumber(row['row_count'])),
      _fpcDate(row['generated_at']),
    ]),
    'ai_insights' => _fpcParts([
      _fpcRaw(row['summary']),
      _fpcParts([_fpcRaw(row['engine']), _fpcRaw(row['model_version'])], ' '),
    ]),
    _ => '',
  };
  final localizedStatus = _fpcOption(status);
  return status.isEmpty ? details : _fpcParts([localizedStatus, details]);
}

String _fpcParts(Iterable<String> values, [String separator = ' • ']) {
  return values.where((value) => value.trim().isNotEmpty).join(separator);
}

String _fpcRaw(Object? value) {
  final text = value == null ? '' : '$value'.trim();
  return text.toLowerCase() == 'null' ? '' : LocaleText.digits(text);
}

String _fpcOption(Object? value) {
  final text = _fpcRaw(value);
  return text.isEmpty ? '' : UiStrings.option(_humanize(text));
}

String _fpcNumber(Object? value, [String fallback = '0']) {
  final number = value is num ? value : num.tryParse(_fpcRaw(value));
  return number == null ? fallback : LocaleText.number(number);
}

String _fpcKg(Object? value) {
  return UiStrings.f('kg_value', {'value': _fpcNumber(value)});
}

String _fpcMoney(Object? value) => '₹${_fpcNumber(value)}';

String _fpcRatePerKg(Object? value) {
  return '${_fpcMoney(value)} / ${UiStrings.t('kg_unit')}';
}

String _fpcMetric(String label, String value) {
  return '${UiStrings.fromEnglish(label)} $value'.trim();
}

String _fpcDate(Object? value) {
  final text = _fpcRaw(value);
  if (text.isEmpty || text == '-') return '-';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final local = parsed.toLocal();
  final hasTime = local.hour != 0 || local.minute != 0 || local.second != 0;
  return hasTime
      ? '${LocaleText.date(local)} ${LocaleText.time(local)}'
      : LocaleText.date(local);
}

String _moduleTitle(String module) =>
    {
      'farmer_network': 'Farmer Network',
      'crop_programs': 'Seed-to-Sale Programs',
      'farm_monitoring': 'Farm Monitoring',
      'harvest_planning': 'Harvest Planning',
      'procurement': 'Procurement',
      'collection_center': 'Collection Center',
      'quality': 'Quality & Grading',
      'warehouse': 'Warehouse',
      'production': 'Production',
      'packaging': 'Packaging',
      'inventory': 'Inventory',
      'sales': 'Buyers & Sales',
      'logistics': 'Logistics',
      'farmer_payments': 'Farmer Payments',
      'reports': 'Reports',
      'ai_insights': 'AI Insights',
    }[module] ??
    module;

String _moduleDescription(String module) =>
    {
      'farmer_network':
          'Real linked farmers; deactivation affects only this FPC relationship.',
      'crop_programs':
          'Issue a traceable seed batch, verify every required field checkpoint, approve policy-compliant harvest and control the exclusive sale window.',
      'farm_monitoring':
          'Read-only linked farm, crop, weather and health context.',
      'harvest_planning':
          'Expected harvest, readiness, priority and officer assignment.',
      'procurement': 'Schedules, vehicles and traceable procurement lots.',
      'collection_center':
          'Set up receiving centers first, then review QR receiver records.',
      'quality':
          'Approved certificates are immutable and linked to procurement lots.',
      'warehouse': 'Warehouses, racks and bins backed by the stock ledger.',
      'production':
          'Transactional raw-stock consumption, output, recovery and waste.',
      'packaging': 'Finished-goods batches with QR, barcode, MFG and expiry.',
      'inventory': 'Append-only movements, transfers, damage and adjustments.',
      'sales': 'Buyers, quotations, GST-ready invoices and payment tracking.',
      'logistics':
          'Dispatch stock posting, delivery proof and compensating cancellation.',
      'farmer_payments':
          'Verified ledger workflow with immutable paid entries and corrections.',
      'reports':
          'Generate and share real PDF or Excel exports from tenant data.',
      'ai_insights':
          'Versioned deterministic fallback insights from live operating data.',
    }[module] ??
    '';

IconData _moduleIcon(String module) =>
    {
      'farmer_network': Icons.groups_rounded,
      'crop_programs': Icons.hub_rounded,
      'farm_monitoring': Icons.satellite_alt_rounded,
      'harvest_planning': Icons.event_available_rounded,
      'procurement': Icons.local_shipping_outlined,
      'collection_center': Icons.scale_rounded,
      'quality': Icons.fact_check_rounded,
      'warehouse': Icons.warehouse_rounded,
      'production': Icons.precision_manufacturing_rounded,
      'packaging': Icons.inventory_2_rounded,
      'inventory': Icons.list_alt_rounded,
      'sales': Icons.point_of_sale_rounded,
      'logistics': Icons.route_rounded,
      'farmer_payments': Icons.account_balance_wallet_rounded,
      'reports': Icons.analytics_rounded,
      'ai_insights': Icons.auto_awesome_rounded,
    }[module] ??
    Icons.folder_outlined;

String _humanize(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _slug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String? _canonicalOperatingGrain(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'rice' || normalized.contains('paddy')) return 'Rice';
  if (normalized == 'ragi' || normalized.contains('finger millet')) {
    return 'Ragi';
  }
  if (normalized == 'bajra' || normalized.contains('pearl millet')) {
    return 'Bajra';
  }
  return null;
}
