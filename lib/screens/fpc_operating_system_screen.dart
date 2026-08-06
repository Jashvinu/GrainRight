import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_operating_models.dart';
import '../services/fpc_operating_service.dart';
import '../widgets/fpc_bottom_nav.dart';
import '../widgets/fpc_module_workspace.dart';

class FpcOperatingSystemScreen extends StatefulWidget {
  const FpcOperatingSystemScreen({super.key});

  @override
  State<FpcOperatingSystemScreen> createState() =>
      _FpcOperatingSystemScreenState();
}

class _FpcOperatingSystemScreenState extends State<FpcOperatingSystemScreen> {
  final _service = FpcOperatingService();
  FpcMembershipContext? _membership;
  Map<String, int> _counts = const {};
  Map<String, dynamic> _metrics = const {};
  String? _selectedModule;
  String? _requestedOperation;
  bool _returnToSetup = false;
  Map<String, dynamic> _prefill = const {};
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final requested = Get.arguments;
    if (requested is Map) {
      _returnToSetup = requested['return_to_setup'] == true;
      if (requested['module'] is String) {
        _selectedModule = requested['module'] as String;
        _requestedOperation = requested['open_operation'] as String?;
        final prefill = requested['prefill'];
        if (prefill is Map) {
          _prefill = Map<String, dynamic>.from(prefill);
        }
      }
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final membership = await _service.loadMembership();
      final counts = await _service.loadOperationalCounts();
      final metrics = await _service.loadDashboardMetrics();
      final rows = _selectedModule == null
          ? const <Map<String, dynamic>>[]
          : await _service.loadModuleRows(_selectedModule!);
      if (!mounted) return;
      setState(() {
        _membership = membership;
        _counts = counts;
        _metrics = metrics;
        _rows = rows;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openModule(String module) async {
    setState(() => _selectedModule = module);
    await _load();
  }

  void _goBack() {
    if (_selectedModule != null && !_returnToSetup) {
      setState(() {
        _selectedModule = null;
        _requestedOperation = null;
        _prefill = const {};
      });
      return;
    }
    if (Get.previousRoute.isNotEmpty && Get.previousRoute != Get.currentRoute) {
      Get.back();
    } else {
      Get.offNamed('/fpo');
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = _selectedModule;
    return FpcWorkspaceScaffold(
      current: FpcNavTab.operations,
      title: module == null
          ? 'FPC Operating System'
          : fpcModuleDefinition(module).title,
      actions: [
        IconButton(
          tooltip: UiStrings.fromEnglish('Back'),
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        IconButton(
          tooltip: UiStrings.fromEnglish('Refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? _ErrorState(message: _error, onRetry: _load)
          : module == null
          ? _moduleDashboard()
          : FpcModuleWorkspace(
              module: module,
              rows: _rows,
              service: _service,
              onBack: _returnToSetup
                  ? Get.back
                  : () => setState(() => _selectedModule = null),
              onChanged: _load,
              initialOperation: _requestedOperation,
              initialValues: _prefill,
            ),
    );
  }

  Widget _moduleDashboard() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 112),
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(
                    _membership?.fpcName ?? 'FPC workspace',
                  ),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  UiStrings.t('fpc_os_workspace_summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: UiStrings.fromEnglish('Analytics'),
            onPressed: () => Get.toNamed('/fpo/analytics'),
            icon: const Icon(Icons.analytics_rounded),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _KpiStrip(metrics: _metrics),
      const SizedBox(height: 14),
      Text(
        UiStrings.fromEnglish('Operations'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 2),
      Text(
        UiStrings.fromEnglish('Network → harvest → procurement → sale'),
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 950
              ? 4
              : constraints.maxWidth >= 620
              ? 3
              : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: fpcModuleDefinitions.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: columns == 2 ? 108 : 104,
            ),
            itemBuilder: (context, index) {
              final item = fpcModuleDefinitions[index];
              return _ModuleCard(
                definition: item,
                count: _counts[item.key] ?? 0,
                onTap: () => _openModule(item.key),
              );
            },
          );
        },
      ),
    ],
  );
}

class FpcModuleDefinition {
  final String key;
  final String title;
  final String itemLabel;
  final String description;
  final IconData icon;
  const FpcModuleDefinition(
    this.key,
    this.title,
    this.itemLabel,
    this.description,
    this.icon,
  );
}

const fpcModuleDefinitions = <FpcModuleDefinition>[
  FpcModuleDefinition(
    'farmer_network',
    'Farmer Network',
    'Farmer record',
    'Linked farmers, KYC, farms, history and payments.',
    Icons.groups_rounded,
  ),
  FpcModuleDefinition(
    'crop_programs',
    'Seed-to-Sale Programs',
    'Farmer enrollment',
    'Issue seed, track mandatory field checks, approve harvest and protect selling.',
    Icons.hub_rounded,
  ),
  FpcModuleDefinition(
    'farm_monitoring',
    'Farm Monitoring',
    'Monitoring note',
    'Satellite health, NDVI, weather, disease and crop timeline.',
    Icons.satellite_alt_rounded,
  ),
  FpcModuleDefinition(
    'harvest_planning',
    'Harvest Planning',
    'Harvest plan',
    'Ready farms, expected quantity, clusters and schedules.',
    Icons.event_available_rounded,
  ),
  FpcModuleDefinition(
    'procurement',
    'Procurement',
    'Procurement plan',
    'Schedules, vehicles, approvals and lot workflow.',
    Icons.local_shipping_outlined,
  ),
  FpcModuleDefinition(
    'collection_center',
    'Collection Center',
    'Receipt',
    'Weighing, moisture, inspection, lots and receipts.',
    Icons.scale_rounded,
  ),
  FpcModuleDefinition(
    'quality',
    'Quality & Grading',
    'Quality certificate',
    'AI grading, immutable certificates and approvals.',
    Icons.fact_check_rounded,
  ),
  FpcModuleDefinition(
    'warehouse',
    'Warehouse',
    'Warehouse',
    'Racks, bins, FIFO/FEFO, transfers and capacity.',
    Icons.warehouse_rounded,
  ),
  FpcModuleDefinition(
    'production',
    'Production',
    'Production run',
    'Millet and rice process runs, recovery and waste.',
    Icons.precision_manufacturing_rounded,
  ),
  FpcModuleDefinition(
    'packaging',
    'Packaging',
    'Packaging batch',
    'Pack sizes, QR, barcode, batch and expiry.',
    Icons.inventory_2_rounded,
  ),
  FpcModuleDefinition(
    'inventory',
    'Inventory',
    'Stock movement',
    'Append-only raw and finished goods ledger with alerts.',
    Icons.list_alt_rounded,
  ),
  FpcModuleDefinition(
    'sales',
    'Buyers & Sales',
    'Sales order',
    'Quotations, GST invoices, orders and payments.',
    Icons.point_of_sale_rounded,
  ),
  FpcModuleDefinition(
    'logistics',
    'Logistics',
    'Dispatch',
    'Vehicle assignment, dispatch, delivery and POD.',
    Icons.route_rounded,
  ),
  FpcModuleDefinition(
    'farmer_payments',
    'Farmer Payments',
    'Payment',
    'Verified UPI/bank ledger with bonus and deductions.',
    Icons.account_balance_wallet_rounded,
  ),
  FpcModuleDefinition(
    'reports',
    'Reports',
    'Report',
    'Organization-scoped PDF and Excel operational reports.',
    Icons.analytics_rounded,
  ),
  FpcModuleDefinition(
    'ai_insights',
    'AI Insights',
    'Insight',
    'Versioned forecasts, risks and deterministic recommendations.',
    Icons.auto_awesome_rounded,
  ),
];

FpcModuleDefinition fpcModuleDefinition(String key) =>
    fpcModuleDefinitions.firstWhere((item) => item.key == key);

class _KpiStrip extends StatelessWidget {
  final Map<String, dynamic> metrics;
  const _KpiStrip({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'Ready farms',
        '${metrics['ready_farms'] ?? 0}',
        Icons.agriculture_rounded,
      ),
      (
        'Expected kg',
        _number(metrics['expected_procurement_kg']),
        Icons.event_available_rounded,
      ),
      (
        'Today kg',
        _number(metrics['today_procurement_kg']),
        Icons.scale_rounded,
      ),
      ('Open lots', '${metrics['open_lots'] ?? 0}', Icons.inventory_2_outlined),
      ('Stock kg', _number(metrics['stock_kg']), Icons.warehouse_outlined),
    ];
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = values[index];
          return Container(
            width: 132,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE3E9DD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.$3, size: 18, color: AppTheme.greenDark),
                const Spacer(),
                Text(
                  item.$2,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  UiStrings.fromEnglish(item.$1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _number(Object? value) =>
      (num.tryParse('$value') ?? 0).toStringAsFixed(1);
}

class _ModuleCard extends StatelessWidget {
  final FpcModuleDefinition definition;
  final int count;
  final VoidCallback onTap;
  const _ModuleCard({
    required this.definition,
    required this.count,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(definition.icon, color: AppTheme.greenDark),
                const Spacer(),
                Text(
                  '$count',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            Text(
              UiStrings.fromEnglish(definition.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              UiStrings.fromEnglish(definition.itemLabel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: 10),
          Text(UiStrings.authError(message), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(UiStrings.fromEnglish('Retry')),
          ),
        ],
      ),
    ),
  );
}
