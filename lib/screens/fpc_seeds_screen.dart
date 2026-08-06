import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../services/fpc_operating_service.dart';
import '../widgets/fpc_bottom_nav.dart';
import '../widgets/fpc_module_workspace.dart';

class FpcSeedsScreen extends StatefulWidget {
  const FpcSeedsScreen({super.key});

  @override
  State<FpcSeedsScreen> createState() => _FpcSeedsScreenState();
}

class _FpcSeedsScreenState extends State<FpcSeedsScreen> {
  final _service = FpcOperatingService();
  List<Map<String, dynamic>> _rows = const [];
  int _initialTabIndex = 0;
  String? _initialOperation;
  Map<String, dynamic> _initialValues = const {};
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final arguments = Get.arguments;
    if (arguments is Map) {
      _initialTabIndex = _tabIndex('${arguments['tab'] ?? ''}');
      _initialOperation = arguments['open_operation'] as String?;
      final prefill = arguments['prefill'];
      if (prefill is Map) {
        _initialValues = Map<String, dynamic>.from(prefill);
      }
    }
    _load();
  }

  int _tabIndex(String tab) => switch (tab) {
    'requests' => 1,
    'stock' || 'available_stock' => 2,
    'programs' => 3,
    'distribution' => 4,
    'analyses' || 'analysis' => 5,
    _ => 0,
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await _service.loadModuleRows('crop_programs');
      if (!mounted) return;
      setState(() {
        _rows = rows
            .where(
              (row) => const {
                'seed_request',
                'program',
                'seed_batch',
                'enrollment',
                'seed_issue',
                'seed_payment',
                'evaluation',
              }.contains('${row['_entity'] ?? ''}'),
            )
            .toList(growable: false);
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.seeds,
      title: 'Seeds',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: UiStrings.t('refresh'),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? _SeedsError(message: _error, onRetry: _load)
          : DefaultTabController(
              initialIndex: _initialTabIndex,
              length: 6,
              child: Column(
                children: [
                  Material(
                    color: Colors.white,
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(text: UiStrings.fromEnglish('Overview')),
                        Tab(text: UiStrings.fromEnglish('Requests')),
                        Tab(text: UiStrings.fromEnglish('Available Stock')),
                        Tab(text: UiStrings.fromEnglish('Programs')),
                        Tab(text: UiStrings.fromEnglish('Distribution')),
                        Tab(text: UiStrings.fromEnglish('Analyses')),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _SeedsOverview(rows: _rows),
                        _workspace(
                          rows: _entityRows({'seed_request'}),
                          title: 'Farmer seed requests',
                          description:
                              'Review demand, reserve one certified batch for 24 hours, and track payment.',
                          allowedOperations: const {},
                        ),
                        _workspace(
                          rows: _entityRows({'seed_batch'}),
                          title: 'Available certified stock',
                          description:
                              'Physical stock, batch certification, sellable quantity and all-inclusive ₹/kg price.',
                          allowedOperations: const {'register_seed_batch'},
                        ),
                        _workspace(
                          rows: _entityRows({'program'}),
                          title: 'Seed-to-sale programs',
                          description:
                              'Create and activate crop programs that govern seed and harvest policy.',
                          allowedOperations: const {'create_crop_program'},
                        ),
                        _workspace(
                          rows: _entityRows({
                            'enrollment',
                            'seed_issue',
                            'seed_payment',
                          }),
                          title: 'Paid distribution',
                          description:
                              'Track paid orders, Field Officer issue, delivery and Farmer acknowledgement.',
                          allowedOperations: const {'issue_program_seed'},
                        ),
                        _workspace(
                          rows: _entityRows({'evaluation'}),
                          title: 'Seed program analyses',
                          description:
                              'Review harvest compliance and grading analyses separately from stock and demand.',
                          allowedOperations: const {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Map<String, dynamic>> _entityRows(Set<String> entities) => _rows
      .where((row) => entities.contains('${row['_entity'] ?? ''}'))
      .toList(growable: false);

  Widget _workspace({
    required List<Map<String, dynamic>> rows,
    required String title,
    required String description,
    required Set<String> allowedOperations,
  }) {
    return FpcModuleWorkspace(
      module: 'crop_programs',
      rows: rows,
      service: _service,
      onBack: () => Get.offNamed('/fpo'),
      onChanged: _load,
      title: title,
      description: description,
      showBack: false,
      allowedOperations: allowedOperations,
      initialOperation: allowedOperations.contains(_initialOperation)
          ? _initialOperation
          : null,
      initialValues: _initialValues,
    );
  }
}

class _SeedsOverview extends StatelessWidget {
  final List<Map<String, dynamic>> rows;

  const _SeedsOverview({required this.rows});

  int _count(String entity, [bool Function(Map<String, dynamic>)? where]) {
    return rows
        .where(
          (row) => row['_entity'] == entity && (where == null || where(row)),
        )
        .length;
  }

  double get _physicalStock => rows
      .where((row) => row['_entity'] == 'seed_batch')
      .fold<double>(
        0,
        (total, row) =>
            total +
            (row['available_quantity_kg'] is num
                ? (row['available_quantity_kg'] as num).toDouble()
                : double.tryParse('${row['available_quantity_kg']}') ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'New requests',
        _count('seed_request', (row) => row['status'] == 'submitted'),
        Icons.inbox_outlined,
      ),
      (
        'Awaiting payment',
        _count(
          'seed_request',
          (row) => const {
            'awaiting_payment',
            'order_created',
            'failed',
          }.contains(row['payment_status']),
        ),
        Icons.schedule_rounded,
      ),
      (
        'Paid orders',
        _count('seed_request', (row) => row['payment_status'] == 'captured'),
        Icons.payments_outlined,
      ),
      ('Certified batches', _count('seed_batch'), Icons.verified_outlined),
      (
        'Active programs',
        _count('program', (row) => row['status'] == 'active'),
        Icons.hub_outlined,
      ),
      (
        'In distribution',
        _count(
          'seed_issue',
          (row) => !{'acknowledged', 'cancelled'}.contains(row['status']),
        ),
        Icons.local_shipping_outlined,
      ),
      (
        'Pending analyses',
        _count('evaluation', (row) => row['status'] == 'pending_fpc_review'),
        Icons.science_outlined,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 112),
      children: [
        Text(
          UiStrings.fromEnglish('Seed operations overview'),
          style: const TextStyle(
            color: AppTheme.greenDark,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          UiStrings.fromEnglish(
            'Demand, sellable stock, programs, paid distribution and analyses remain separate but connected.',
          ),
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: _SeedOverviewMetric(
                      label: metric.$1,
                      value: '${metric.$2}',
                      icon: metric.$3,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _SeedOverviewMetric(
          label: 'Physical certified stock',
          value: '${_physicalStock.toStringAsFixed(3)} kg',
          icon: Icons.inventory_2_outlined,
        ),
      ],
    );
  }
}

class _SeedOverviewMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SeedOverviewMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.greenPale,
              child: Icon(icon, color: AppTheme.greenDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    UiStrings.fromEnglish(label),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
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

class _SeedsError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _SeedsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: AppTheme.greenDark,
            ),
            const SizedBox(height: 10),
            Text(UiStrings.authError(message), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(UiStrings.t('try_again')),
            ),
          ],
        ),
      ),
    );
  }
}
