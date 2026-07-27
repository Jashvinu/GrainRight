import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../services/fpc_operating_service.dart';
import '../services/fpc_report_service.dart';

class FpcModuleWorkspace extends StatefulWidget {
  final String module;
  final List<Map<String, dynamic>> rows;
  final FpcOperatingService service;
  final VoidCallback onBack;
  final Future<void> Function() onChanged;

  const FpcModuleWorkspace({
    super.key,
    required this.module,
    required this.rows,
    required this.service,
    required this.onBack,
    required this.onChanged,
  });

  @override
  State<FpcModuleWorkspace> createState() => _FpcModuleWorkspaceState();
}

class _FpcModuleWorkspaceState extends State<FpcModuleWorkspace> {
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 112),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.fromEnglish(_moduleTitle(widget.module)),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    UiStrings.fromEnglish(_moduleDescription(widget.module)),
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
        if (widget.rows.isEmpty)
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

  Future<void> _runOperationForm(_OperationSpec operation) async {
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
    if (operation.operation == 'approve_quality') {
      payload['results'] = {'lab_note': payload.remove('lab_note')};
    }
    await _execute(operation.operation, payload);
  }

  Future<void> _handleRowAction(String action, Map<String, dynamic> row) async {
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
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _OperationDialog(operation: operation, lookups: const {}),
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
        UiStrings.fromEnglish(
          '${result.fileName} contains ${result.rowCount} records.',
        ),
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

enum _InputType { text, number }

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
  const _OperationDialog({required this.operation, required this.lookups});

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
        field.key: TextEditingController(text: field.initialValue),
    };
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
      final usable = field.lookupTable == 'fpc_memberships'
          ? lookup
                .where(
                  (row) =>
                      row['role'] == 'field_officer' &&
                      row['status'] == 'active',
                )
                .toList()
          : lookup;
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
          _rowTitle(module, row),
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
          'Expected harvest date (YYYY-MM-DD)',
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
          'Schedule time (ISO)',
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
        _InputSpec('address', 'Address'),
        _InputSpec('capacity_kg', 'Capacity kg', type: _InputType.number),
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
          'Manufacturing date (YYYY-MM-DD)',
          initialValue: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        ),
        _InputSpec('expires_on', 'Expiry date (YYYY-MM-DD)'),
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
        _InputSpec('expires_on', 'Expiry date (YYYY-MM-DD)', required: false),
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
    'farmer_network' =>
      '${row['village'] ?? ''} • ${row['crop'] ?? ''} • KYC ${row['kyc_status'] ?? ''}',
    'farm_monitoring' =>
      entity == 'farm'
          ? '${row['crop'] ?? ''} • ${row['variety'] ?? ''} • ${row['area_acres'] ?? 0} acres • ${row['current_status_stage'] ?? ''}'
          : entity == 'snapshot'
          ? '${row['snapshot_date'] ?? ''} • NDVI ${row['snapshot'] is Map ? (row['snapshot'] as Map)['ndvi'] ?? '-' : '-'} • Disease risk ${row['disease_risk'] ?? '-'} • Rain ${row['rain_mm'] ?? 0} mm'
          : '${row['village'] ?? ''} • ${row['crop'] ?? ''} • KYC ${row['kyc_status'] ?? ''}',
    'harvest_planning' =>
      '${row['expected_harvest_date'] ?? ''} • ${row['expected_quantity_kg'] ?? 0} kg • ${row['priority'] ?? ''}',
    'procurement' =>
      entity == 'lot'
          ? '${row['crop'] ?? ''} • ${row['net_weight_kg'] ?? 0} kg • Grade ${row['grade'] ?? '-'}'
          : entity == 'vehicle'
          ? '${row['driver_name'] ?? ''} • ${row['driver_phone'] ?? ''}'
          : '${row['notes'] ?? ''}',
    'collection_center' =>
      entity == 'center'
          ? '${row['village'] ?? ''} • Capacity ${row['capacity_kg'] ?? 0} kg'
          : '${row['crop_type'] ?? ''} • ${row['net_weight_kg'] ?? row['quantity_kg'] ?? 0} kg',
    'quality' => 'Grade ${row['grade'] ?? '-'} • ${row['approved_at'] ?? ''}',
    'warehouse' =>
      entity == 'location'
          ? '${row['location_type'] ?? ''} • Capacity ${row['capacity_kg'] ?? 0} kg'
          : '${row['address'] ?? ''} • Capacity ${row['capacity_kg'] ?? 0} kg',
    'production' =>
      '${row['process_type'] ?? ''} • Input ${row['input_kg'] ?? 0} kg • Output ${row['output_kg'] ?? 0} kg • Recovery ${row['recovery_percent'] ?? 0}%',
    'packaging' =>
      '${row['product_name'] ?? ''} • ${row['package_count'] ?? 0} × ${row['package_size_grams'] ?? 0} g • EXP ${row['expires_on'] ?? '-'}',
    'inventory' =>
      '${row['movement_type'] ?? ''} • ${row['quantity_kg'] ?? 0} kg • ${row['occurred_at'] ?? ''}',
    'sales' =>
      entity == 'buyer'
          ? '${row['buyer_type'] ?? ''} • ${row['gstin'] ?? ''}'
          : entity == 'payment'
          ? '₹${row['amount'] ?? 0} • ${row['payment_mode'] ?? ''} • ${row['recorded_at'] ?? ''}'
          : entity == 'credit_note'
          ? '₹${row['amount'] ?? 0} • ${row['reason'] ?? ''} • ${row['issued_at'] ?? ''}'
          : '₹${row['total'] ?? 0} • ${row['ordered_at'] ?? ''}',
    'logistics' =>
      '${row['driver_name'] ?? ''} • ${row['dispatched_at'] ?? ''}',
    'farmer_payments' =>
      '${row['net_weight_kg'] ?? 0} kg × ₹${row['rate_per_kg'] ?? 0} • Bonus ₹${row['bonus'] ?? 0} • Deductions ₹${row['deductions'] ?? 0}',
    'reports' =>
      '${row['format'] ?? ''} • ${row['row_count'] ?? 0} rows • ${row['generated_at'] ?? ''}',
    'ai_insights' =>
      '${row['summary'] ?? ''} • ${row['engine'] ?? ''} ${row['model_version'] ?? ''}',
    _ => '',
  };
  return status.isEmpty ? details : '${_humanize(status)} • $details';
}

String _moduleTitle(String module) =>
    {
      'farmer_network': 'Farmer Network',
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
      'farm_monitoring':
          'Read-only linked farm, crop, weather and health context.',
      'harvest_planning':
          'Expected harvest, readiness, priority and officer assignment.',
      'procurement': 'Schedules, vehicles and traceable procurement lots.',
      'collection_center':
          'Existing QR receiver records and configured centers.',
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
