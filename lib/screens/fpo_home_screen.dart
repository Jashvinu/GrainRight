import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_procurement_dashboard.dart';
import '../models/marketplace_listing.dart';
import '../services/apmc_market_service.dart';
import '../services/fpc_dashboard_service.dart';
import '../widgets/fpc_bottom_nav.dart';
import '../widgets/fpc_procurement_dashboard.dart';

class FpoHomeScreen extends StatefulWidget {
  final FpcDashboardService? dashboardService;
  final ApmcMarketService? apmcService;

  const FpoHomeScreen({super.key, this.dashboardService, this.apmcService});

  @override
  State<FpoHomeScreen> createState() => _FpoHomeScreenState();
}

class _FpoHomeScreenState extends State<FpoHomeScreen> {
  late final FpcDashboardService _dashboardService;
  late final ApmcMarketService _apmcService;
  FpcProcurementDashboardSnapshot? _snapshot;
  List<FpcFarmWorkCard> _farms = const [];
  List<FpcFarmMapPoint> _mapPoints = const [];
  List<ApmcMarketRate> _apmcRates = const [];
  String _dashboardError = '';
  String _queueError = '';
  String _mapError = '';
  String _apmcError = '';
  bool _loading = true;
  bool _queueLoading = false;
  bool _mapLoading = false;
  bool _queueHasMore = false;
  int _nextQueueOffset = 0;
  bool _apmcLoading = false;
  final _dashboardRequests = FpcDashboardRequestTracker();
  final _queueRequests = FpcDashboardRequestTracker();
  final _mapRequests = FpcDashboardRequestTracker();
  final _apmcRequests = FpcDashboardRequestTracker();

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? const FpcDashboardService();
    _apmcService = widget.apmcService ?? ApmcMarketService();
    unawaited(_loadInitial());
  }

  Future<void> _loadInitial() async {
    final request = _dashboardRequests.begin();
    setState(() {
      _loading = true;
      _dashboardError = '';
    });
    try {
      final allClusters = await _dashboardService.loadOverview();
      if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      final prefs = await SharedPreferences.getInstance();
      final savedCluster = prefs.getString(_preferenceKey(allClusters.fpcId));
      final validSavedCluster =
          savedCluster != null &&
          allClusters.clusters.any((cluster) => cluster.id == savedCluster);
      if (savedCluster != null && !validSavedCluster) {
        await prefs.remove(_preferenceKey(allClusters.fpcId));
        if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      }
      final selected = validSavedCluster
          ? await _dashboardService.loadOverview(clusterId: savedCluster)
          : allClusters;
      if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      setState(() {
        _snapshot = selected;
        _loading = false;
      });
      await _loadQueue(snapshot: selected);
      unawaited(_loadMapPoints(snapshot: selected));
      unawaited(_loadApmc(selected));
    } catch (error) {
      if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      setState(() {
        _dashboardError = _friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadDashboard({String? clusterId}) async {
    final request = _dashboardRequests.begin();
    setState(() {
      _loading = true;
      _dashboardError = '';
    });
    try {
      final snapshot = await _dashboardService.loadOverview(
        clusterId: clusterId,
      );
      if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      await _persistClusterSelection(snapshot, clusterId);
      if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      setState(() {
        _snapshot = snapshot;
        _farms = const [];
        _mapPoints = const [];
        _queueHasMore = false;
        _nextQueueOffset = 0;
        _loading = false;
      });
      await _loadQueue(snapshot: snapshot);
      unawaited(_loadMapPoints(snapshot: snapshot));
      unawaited(_loadApmc(snapshot, refresh: false));
    } catch (error) {
      if (!mounted || !_dashboardRequests.isCurrent(request)) return;
      final text = '$error'.toLowerCase();
      if (clusterId != null &&
          (text.contains('not available') || text.contains('invalid'))) {
        final fpcId = _snapshot?.fpcId;
        if (fpcId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_preferenceKey(fpcId));
        }
        if (!mounted || !_dashboardRequests.isCurrent(request)) return;
        unawaited(_loadDashboard());
        return;
      }
      setState(() {
        _dashboardError = _friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadDashboard(clusterId: _snapshot?.selectedClusterId);
  }

  Future<void> _loadQueue({
    required FpcProcurementDashboardSnapshot snapshot,
    bool append = false,
  }) async {
    if (append && (!_queueHasMore || _queueLoading)) return;
    final request = _queueRequests.begin();
    final offset = append ? _nextQueueOffset : 0;
    if (mounted) {
      setState(() {
        _queueLoading = true;
        if (!append) _queueError = '';
      });
    }
    try {
      final page = await _dashboardService.loadFarmQueue(
        clusterId: snapshot.selectedClusterId,
        offset: offset,
      );
      if (!mounted || !_queueRequests.isCurrent(request)) return;
      setState(() {
        _farms = append ? [..._farms, ...page.farms] : page.farms;
        _queueHasMore = page.hasMore;
        _nextQueueOffset = page.nextOffset;
        _queueLoading = false;
      });
    } catch (error) {
      if (!mounted || !_queueRequests.isCurrent(request)) return;
      setState(() {
        _queueError = _friendlyError(error);
        _queueLoading = false;
      });
    }
  }

  Future<void> _loadMoreFarms() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await _loadQueue(snapshot: snapshot, append: true);
  }

  Future<void> _loadMapPoints({
    required FpcProcurementDashboardSnapshot snapshot,
  }) async {
    final request = _mapRequests.begin();
    if (mounted) {
      setState(() {
        _mapLoading = true;
        _mapError = '';
      });
    }
    try {
      final points = await _dashboardService.loadFarmMapPoints(
        clusterId: snapshot.selectedClusterId,
      );
      if (!mounted || !_mapRequests.isCurrent(request)) return;
      setState(() {
        _mapPoints = points;
        _mapLoading = false;
      });
    } catch (error) {
      if (!mounted || !_mapRequests.isCurrent(request)) return;
      setState(() {
        _mapError = _friendlyError(error);
        _mapLoading = false;
      });
    }
  }

  Future<FpcFarmWorkCard> _loadFarmDetail(FpcFarmWorkCard farm) {
    return _dashboardService.loadFarmDetail(
      farmerLinkId: farm.linkId,
      clusterId: _snapshot?.selectedClusterId,
    );
  }

  Future<void> _loadApmc(
    FpcProcurementDashboardSnapshot snapshot, {
    bool refresh = false,
  }) async {
    final request = _apmcRequests.begin();
    final cluster = snapshot.selectedCluster;
    if (cluster == null) {
      if (!mounted || !_apmcRequests.isCurrent(request)) return;
      setState(() {
        _apmcRates = const [];
        _apmcError = '';
        _apmcLoading = false;
      });
      return;
    }
    if (cluster.district.trim().isEmpty &&
        cluster.preferredApmcMarket.trim().isEmpty) {
      if (!mounted || !_apmcRequests.isCurrent(request)) return;
      setState(() {
        _apmcRates = const [];
        _apmcError = UiStrings.fromEnglish(
          'Add a district or preferred APMC market in cluster settings.',
        );
        _apmcLoading = false;
      });
      return;
    }
    setState(() {
      _apmcLoading = true;
      _apmcError = '';
    });
    try {
      final result = await _apmcService.search(
        state: cluster.state,
        district: cluster.district,
        market: cluster.preferredApmcMarket,
        refresh: refresh,
      );
      if (!mounted || !_apmcRequests.isCurrent(request)) return;
      setState(() {
        _apmcRates = result.rates;
        _apmcLoading = false;
      });
    } catch (error) {
      if (!mounted || !_apmcRequests.isCurrent(request)) return;
      setState(() {
        _apmcRates = const [];
        _apmcError = _friendlyError(error);
        _apmcLoading = false;
      });
    }
  }

  Future<void> _persistClusterSelection(
    FpcProcurementDashboardSnapshot snapshot,
    String? clusterId,
  ) async {
    if (snapshot.fpcId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _preferenceKey(snapshot.fpcId);
    if (clusterId == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, clusterId);
    }
  }

  String _preferenceKey(String fpcId) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    return 'fpc_dashboard_cluster_${userId}_$fpcId';
  }

  Future<void> _openClusterManager() async {
    FpcProcurementDashboardSnapshot allClusters;
    try {
      allClusters = await _dashboardService.load();
    } catch (error) {
      if (!mounted) return;
      _showError(_friendlyError(error));
      return;
    }
    if (!mounted) return;
    final changed = MediaQuery.sizeOf(context).width < 720
        ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.white,
            builder: (_) => FractionallySizedBox(
              heightFactor: 0.94,
              child: _ClusterManager(
                service: _dashboardService,
                initialSnapshot: allClusters,
              ),
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 880,
                height: 720,
                child: _ClusterManager(
                  service: _dashboardService,
                  initialSnapshot: allClusters,
                ),
              ),
            ),
          );
    if (changed == true && mounted) {
      await _loadDashboard(clusterId: _snapshot?.selectedClusterId);
    }
  }

  void _openPlanning(FpcFarmWorkCard farm) {
    Get.toNamed(
      '/fpo/operations',
      arguments: {
        'module': 'harvest_planning',
        'open_operation': 'create_harvest_plan',
        'prefill': {
          'farm_id': farm.farmId,
          'crop': farm.crop,
          'village': farm.village,
          'expected_harvest_date': farm.expectedHarvestDate
              ?.toIso8601String()
              .split('T')
              .first,
          'expected_quantity_kg': farm.expectedQuantityKg,
          'expected_grade': farm.latestGrade == 'Not graded'
              ? farm.expectedGrade
              : farm.latestGrade,
          'readiness': farm.isReady ? 'ready' : 'planned',
          'priority': farm.needsReview ? 'high' : 'normal',
        },
      },
    );
  }

  void _openSeedRequests() {
    Get.toNamed(
      '/fpo/operations',
      arguments: const {'module': 'crop_programs'},
    );
  }

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.home,
      title: UiStrings.t('fpo_dashboard'),
      showQrAction: false,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 920 ? 24 : 14,
              14,
              constraints.maxWidth >= 920 ? 24 : 14,
              110,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SeedRequestDashboardCard(
                        summary:
                            _snapshot?.seedRequests ??
                            const FpcSeedRequestSummary.empty(),
                        loading: _loading,
                        onOpen: _openSeedRequests,
                      ),
                      const SizedBox(height: 14),
                      FpcProcurementDashboard(
                        snapshot: _snapshot,
                        farms: _farms,
                        mapPoints: _mapPoints,
                        loading: _loading,
                        queueLoading: _queueLoading,
                        queueHasMore: _queueHasMore,
                        queueError: _queueError,
                        mapLoading: _mapLoading,
                        mapError: _mapError,
                        error: _dashboardError,
                        apmcRates: _apmcRates,
                        apmcLoading: _apmcLoading,
                        apmcError: _apmcError,
                        onClusterChanged: (clusterId) =>
                            _loadDashboard(clusterId: clusterId),
                        onRefresh: _refresh,
                        onLoadMoreFarms: _loadMoreFarms,
                        onLoadFarmDetail: _loadFarmDetail,
                        onLoadMapFarmDetail: (linkId) =>
                            _dashboardService.loadFarmDetail(
                              farmerLinkId: linkId,
                              clusterId: _snapshot?.selectedClusterId,
                            ),
                        onManageClusters: _openClusterManager,
                        onRetryApmc: () {
                          final snapshot = _snapshot;
                          if (snapshot != null) {
                            unawaited(_loadApmc(snapshot, refresh: true));
                          }
                        },
                        onPlanProcurement: _openPlanning,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SeedRequestDashboardCard extends StatelessWidget {
  final FpcSeedRequestSummary summary;
  final bool loading;
  final VoidCallback onOpen;

  const _SeedRequestDashboardCard({
    required this.summary,
    required this.loading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('fpc_seed_pending_review', summary.submitted, Icons.inbox_rounded),
      ('fpc_seed_ready_to_issue', summary.readyToIssue, Icons.task_alt_rounded),
      (
        'fpc_seed_in_delivery',
        summary.inDelivery,
        Icons.local_shipping_rounded,
      ),
      ('completed', summary.completed, Icons.check_circle_rounded),
    ];
    return Card(
      key: const Key('fpc-seed-request-dashboard-card'),
      elevation: 0,
      color: const Color(0xFFF2F8EF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFD7E6D0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppTheme.greenDark,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.grass_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UiStrings.t('fpc_seed_requests_title'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        UiStrings.t('fpc_seed_requests_tracking_desc'),
                        style: const TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: loading ? null : onOpen,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(UiStrings.t('fpc_open_tracking')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final metric in metrics)
                  Container(
                    constraints: const BoxConstraints(minWidth: 118),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(metric.$3, size: 17, color: AppTheme.greenDark),
                        const SizedBox(width: 7),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${metric.$2}',
                              style: const TextStyle(
                                color: AppTheme.greenDark,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              UiStrings.t(metric.$1),
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClusterManager extends StatefulWidget {
  final FpcDashboardService service;
  final FpcProcurementDashboardSnapshot initialSnapshot;

  const _ClusterManager({required this.service, required this.initialSnapshot});

  @override
  State<_ClusterManager> createState() => _ClusterManagerState();
}

class _ClusterManagerState extends State<_ClusterManager> {
  late FpcProcurementDashboardSnapshot _snapshot;
  bool _working = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.initialSnapshot;
  }

  Future<void> _reload() async {
    final snapshot = await widget.service.load();
    if (mounted) setState(() => _snapshot = snapshot);
  }

  Future<void> _openClusterForm([FpcOperatingCluster? cluster]) async {
    final input = await showDialog<_ClusterInput>(
      context: context,
      builder: (_) => _ClusterForm(cluster: cluster),
    );
    if (input == null) return;
    await _run(() async {
      if (cluster == null) {
        await widget.service.createCluster(
          name: input.name,
          district: input.district,
          state: input.state,
          preferredApmcMarket: input.market,
        );
      } else {
        await widget.service.updateCluster(
          clusterId: cluster.id,
          name: input.name,
          district: input.district,
          state: input.state,
          preferredApmcMarket: input.market,
        );
      }
      await _reload();
    });
  }

  Future<void> _deactivate(FpcOperatingCluster cluster) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(UiStrings.fromEnglish('Deactivate cluster?')),
        content: Text(
          UiStrings.fromEnglish(
            'Assigned farms will stay linked but this cluster will no longer be selectable.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UiStrings.fromEnglish('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(UiStrings.fromEnglish('Deactivate')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await widget.service.deactivateCluster(cluster.id);
      await _reload();
    });
  }

  Future<void> _assign(FpcFarmWorkCard farm, String? clusterId) async {
    await _run(() async {
      await widget.service.assignFarmToCluster(
        farmerLinkId: farm.linkId,
        clusterId: clusterId,
      );
      await _reload();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      _changed = true;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.hub_outlined, color: AppTheme.greenDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UiStrings.fromEnglish('Manage operating clusters'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      UiStrings.fromEnglish(
                        'Create regions and assign each linked farm once.',
                      ),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: UiStrings.fromEnglish('Close'),
                onPressed: () => Navigator.pop(context, _changed),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        if (_working) const LinearProgressIndicator(),
        const Divider(height: 1),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  tabs: [
                    Tab(text: UiStrings.fromEnglish('Clusters')),
                    Tab(text: UiStrings.fromEnglish('Farm assignments')),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [_clusterList(), _farmAssignments()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _clusterList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('create-cluster-button'),
            onPressed: _working ? null : _openClusterForm,
            icon: const Icon(Icons.add_rounded),
            label: Text(UiStrings.fromEnglish('Create cluster')),
          ),
        ),
        const SizedBox(height: 14),
        if (_snapshot.clusters.isEmpty)
          _ManagerEmpty(
            title: UiStrings.fromEnglish('No operating clusters yet'),
            message: UiStrings.fromEnglish(
              'Create the first region with its district and preferred APMC market.',
            ),
          )
        else
          for (final cluster in _snapshot.clusters)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.greenPale,
                  foregroundColor: AppTheme.green,
                  child: const Icon(Icons.hub_outlined),
                ),
                title: Text(
                  cluster.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  [
                    if (cluster.district.isNotEmpty) cluster.district,
                    if (cluster.preferredApmcMarket.isNotEmpty)
                      cluster.preferredApmcMarket,
                    '${cluster.farmCount} ${UiStrings.fromEnglish('farms')}',
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') _openClusterForm(cluster);
                    if (action == 'deactivate') _deactivate(cluster);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(UiStrings.fromEnglish('Rename and edit')),
                    ),
                    PopupMenuItem(
                      value: 'deactivate',
                      child: Text(UiStrings.fromEnglish('Deactivate')),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _farmAssignments() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_snapshot.farms.isEmpty)
          _ManagerEmpty(
            title: UiStrings.fromEnglish('No linked farms available'),
            message: UiStrings.fromEnglish(
              'Verified farmer links will appear here for cluster assignment.',
            ),
          )
        else
          for (final farm in _snapshot.farms)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final details = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farm.farmName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          [
                            farm.farmerName,
                            farm.village,
                            farm.crop,
                          ].where((value) => value.isNotEmpty).join(' · '),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                    final assignedClusterIsInactive =
                        farm.clusterId != null &&
                        !_snapshot.clusters.any(
                          (cluster) => cluster.id == farm.clusterId,
                        );
                    final selector = DropdownButtonFormField<String>(
                      key: ValueKey(
                        'assignment-${farm.linkId}-${farm.clusterId}',
                      ),
                      initialValue: farm.clusterId ?? '',
                      decoration: InputDecoration(
                        labelText: UiStrings.fromEnglish('Cluster assignment'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(UiStrings.fromEnglish('Unassigned')),
                        ),
                        if (assignedClusterIsInactive)
                          DropdownMenuItem(
                            value: farm.clusterId,
                            child: Text(
                              UiStrings.fromEnglish('Inactive cluster'),
                            ),
                          ),
                        for (final cluster in _snapshot.clusters)
                          DropdownMenuItem(
                            value: cluster.id,
                            child: Text(
                              cluster.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _working
                          ? null
                          : (value) => _assign(
                              farm,
                              value == null || value.isEmpty ? null : value,
                            ),
                    );
                    if (constraints.maxWidth < 560) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          details,
                          const SizedBox(height: 10),
                          selector,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: details),
                        const SizedBox(width: 16),
                        SizedBox(width: 280, child: selector),
                      ],
                    );
                  },
                ),
              ),
            ),
      ],
    );
  }
}

class _ClusterForm extends StatefulWidget {
  final FpcOperatingCluster? cluster;

  const _ClusterForm({this.cluster});

  @override
  State<_ClusterForm> createState() => _ClusterFormState();
}

class _ClusterFormState extends State<_ClusterForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _district;
  late final TextEditingController _state;
  late final TextEditingController _market;

  @override
  void initState() {
    super.initState();
    final cluster = widget.cluster;
    _name = TextEditingController(text: cluster?.name ?? '');
    _district = TextEditingController(text: cluster?.district ?? '');
    _state = TextEditingController(text: cluster?.state ?? 'Maharashtra');
    _market = TextEditingController(text: cluster?.preferredApmcMarket ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _district.dispose();
    _state.dispose();
    _market.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        UiStrings.fromEnglish(
          widget.cluster == null ? 'Create cluster' : 'Edit cluster',
        ),
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  key: const Key('cluster-name-field'),
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Cluster name'),
                  ),
                  validator: (value) => value == null || value.trim().length < 2
                      ? UiStrings.fromEnglish('Enter at least two characters')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _district,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('District'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _state,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('State'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _market,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Preferred APMC market'),
                  ),
                ),
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
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _ClusterInput(
                name: _name.text,
                district: _district.text,
                state: _state.text,
                market: _market.text,
              ),
            );
          },
          child: Text(UiStrings.fromEnglish('Save')),
        ),
      ],
    );
  }
}

class _ClusterInput {
  final String name;
  final String district;
  final String state;
  final String market;

  const _ClusterInput({
    required this.name,
    required this.district,
    required this.state,
    required this.market,
  });
}

class _ManagerEmpty extends StatelessWidget {
  final String title;
  final String message;

  const _ManagerEmpty({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 42, color: AppTheme.textMuted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

String _friendlyError(Object error) {
  final text = '$error'
      .replaceFirst('FpcDashboardException: ', '')
      .replaceFirst('ApmcMarketException: ', '')
      .trim();
  return text.isEmpty
      ? UiStrings.fromEnglish('Something went wrong. Please retry.')
      : UiStrings.authError(text);
}
