import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/localization/ui_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/fpc_procurement_dashboard.dart';
import '../models/marketplace_listing.dart';
import '../services/map_tile_provider.dart';

class FpcProcurementDashboard extends StatefulWidget {
  final FpcProcurementDashboardSnapshot? snapshot;
  final List<FpcFarmWorkCard> farms;
  final List<FpcFarmMapPoint> mapPoints;
  final bool loading;
  final bool queueLoading;
  final bool queueHasMore;
  final String queueError;
  final bool mapLoading;
  final String mapError;
  final String error;
  final List<ApmcMarketRate> apmcRates;
  final bool apmcLoading;
  final String apmcError;
  final bool enableMapTiles;
  final ValueChanged<String?> onClusterChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMoreFarms;
  final Future<FpcFarmWorkCard> Function(FpcFarmWorkCard farm) onLoadFarmDetail;
  final Future<FpcFarmWorkCard> Function(String linkId) onLoadMapFarmDetail;
  final VoidCallback onManageClusters;
  final VoidCallback onRetryApmc;
  final ValueChanged<FpcFarmWorkCard> onPlanProcurement;

  const FpcProcurementDashboard({
    super.key,
    required this.snapshot,
    required this.farms,
    required this.mapPoints,
    required this.loading,
    required this.queueLoading,
    required this.queueHasMore,
    required this.queueError,
    required this.mapLoading,
    required this.mapError,
    required this.error,
    required this.apmcRates,
    required this.apmcLoading,
    required this.apmcError,
    this.enableMapTiles = true,
    required this.onClusterChanged,
    required this.onRefresh,
    required this.onLoadMoreFarms,
    required this.onLoadFarmDetail,
    required this.onLoadMapFarmDetail,
    required this.onManageClusters,
    required this.onRetryApmc,
    required this.onPlanProcurement,
  });

  @override
  State<FpcProcurementDashboard> createState() =>
      _FpcProcurementDashboardState();
}

class _FpcProcurementDashboardState extends State<FpcProcurementDashboard> {
  final _searchController = TextEditingController();
  final _mapController = MapController();
  String _statusFilter = 'all';
  String _cropFilter = 'all';
  String _gradeFilter = 'all';
  String? _focusedLinkId;
  FpcFarmMapPoint? _selectedMapPoint;
  bool _mobileRatesExpanded = false;
  final Map<String, FpcFarmWorkCard> _farmDetails = {};
  final Set<String> _loadingFarmDetails = {};
  final Set<String> _farmDetailFailures = {};

  @override
  void didUpdateWidget(covariant FpcProcurementDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visibleIds = {
      ...widget.farms.map((farm) => farm.linkId),
      ...widget.mapPoints.map((point) => point.linkId),
    };
    _farmDetails.removeWhere((linkId, _) => !visibleIds.contains(linkId));
    _loadingFarmDetails.removeWhere((linkId) => !visibleIds.contains(linkId));
    _farmDetailFailures.removeWhere((linkId) => !visibleIds.contains(linkId));
    if (_focusedLinkId == null && widget.mapPoints.isNotEmpty) {
      final firstPoint = widget.mapPoints.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusedLinkId == null) {
          _selectMapPoint(firstPoint, fitMap: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.mapPoints.isNotEmpty) {
        _selectMapPoint(widget.mapPoints.first, fitMap: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 960;
        final tablet = constraints.maxWidth >= 720;
        final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.10;
        final snapshot = widget.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(snapshot, compact: !tablet),
            const SizedBox(height: 14),
            if (widget.error.isNotEmpty)
              _DashboardError(message: widget.error, onRetry: widget.onRefresh),
            if (widget.error.isNotEmpty) const SizedBox(height: 14),
            if (widget.loading && snapshot == null)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _metricGrid(
                snapshot?.summary,
                columns: desktop ? 6 : (tablet ? 3 : 2),
                dense: desktop && !largeText,
              ),
              const SizedBox(height: 14),
              if (snapshot != null && snapshot.clusters.isNotEmpty) ...[
                _clusterStrip(
                  snapshot,
                  desktop: desktop,
                  dense: desktop && !largeText,
                ),
                const SizedBox(height: 14),
              ],
              _mapPanel(snapshot, height: desktop ? 430 : (tablet ? 360 : 320)),
              const SizedBox(height: 14),
              if (desktop || tablet)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: desktop ? 6 : 5,
                      child: _farmQueue(snapshot, columns: 1),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: desktop ? 4 : 5,
                      child: _ratesPanel(snapshot),
                    ),
                  ],
                )
              else ...[
                _farmQueue(snapshot, columns: 1),
                const SizedBox(height: 12),
                _mobileSidePanel(
                  title: _t('APMC rates'),
                  icon: Icons.currency_rupee_rounded,
                  expanded: _mobileRatesExpanded,
                  onChanged: (value) =>
                      setState(() => _mobileRatesExpanded = value),
                  child: _ratesPanel(snapshot, nested: true),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _header(
    FpcProcurementDashboardSnapshot? snapshot, {
    required bool compact,
  }) {
    final generated = snapshot?.generatedAt.toLocal();
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('Procurement command center'),
          style: TextStyle(
            color: AppTheme.greenDark,
            fontSize: compact ? 22 : 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          generated == null
              ? _t('Live farm readiness and procurement planning')
              : '${_t('Last updated')} ${DateFormat('d MMM, h:mm a').format(generated)}',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      ],
    );
    final clusterControl = Semantics(
      label: _t('Selected operating cluster'),
      child: KeyedSubtree(
        key: const Key('fpc-cluster-selector'),
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            'fpc-cluster-value-${snapshot?.selectedClusterId ?? 'all'}',
          ),
          initialValue: snapshot?.selectedClusterId ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _t('Operating cluster'),
            prefixIcon: const Icon(Icons.hub_outlined),
          ),
          items: [
            DropdownMenuItem(value: '', child: Text(_t('All clusters'))),
            for (final cluster in snapshot?.clusters ?? const [])
              DropdownMenuItem(
                value: cluster.id,
                child: Text(
                  '${cluster.name} · ${cluster.farmCount}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: widget.loading
              ? null
              : (value) => widget.onClusterChanged(
                  value == null || value.isEmpty ? null : value,
                ),
        ),
      ),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('manage-clusters-button'),
          onPressed: widget.onManageClusters,
          icon: const Icon(Icons.tune_rounded),
          label: Text(_t('Manage clusters')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        IconButton.outlined(
          tooltip: _t('Refresh dashboard'),
          onPressed: widget.loading ? null : widget.onRefresh,
          icon: widget.loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
    return _Panel(
      accentColor: AppTheme.gold,
      padding: const EdgeInsets.all(16),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 14),
                clusterControl,
                const SizedBox(height: 10),
                actions,
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                SizedBox(width: 280, child: clusterControl),
                const SizedBox(width: 10),
                actions,
              ],
            ),
    );
  }

  Widget _metricGrid(
    FpcProcurementSummary? summary, {
    required int columns,
    required bool dense,
  }) {
    final gradeMix = summary?.gradeMix ?? const <FpcGradeCount>[];
    final totalGrades = gradeMix.fold<int>(0, (sum, item) => sum + item.count);
    final gradeSummary = gradeMix
        .where((item) => item.count > 0)
        .take(2)
        .map(
          (item) =>
              '${item.grade == 'Not graded' ? 'NG' : item.grade.replaceFirst('Grade ', '')} ${totalGrades == 0 ? 0 : (item.count * 100 / totalGrades).round()}%',
        )
        .join(' · ');
    final cards = [
      _MetricData(
        _t('Network farms'),
        '${summary?.networkFarms ?? 0}',
        '${summary?.readyFarms ?? 0} ${_t('ready')}',
        Icons.groups_2_outlined,
        const Color(0xFF087F5B),
      ),
      _MetricData(
        _t('Expected procurement'),
        _quantity(summary?.expectedProcurementKg ?? 0),
        _t('active harvest plans'),
        Icons.scale_outlined,
        const Color(0xFFC56A00),
      ),
      _MetricData(
        _t('Open lots'),
        '${summary?.openLots ?? 0}',
        _t('in procurement'),
        Icons.inventory_2_outlined,
        const Color(0xFF1971C2),
      ),
      _MetricData(
        _t('Needs review'),
        '${summary?.needsReview ?? 0}',
        _t('quality decisions'),
        Icons.fact_check_outlined,
        const Color(0xFFD9480F),
      ),
      _MetricData(
        _t('Farm health'),
        summary?.healthAverage == null ? '—' : '${summary!.healthAverage}%',
        '${summary?.healthCoverage ?? 0}/${summary?.networkFarms ?? 0} ${_t('with data')}',
        Icons.eco_outlined,
        const Color(0xFF5C940D),
      ),
      _MetricData(
        _t('Grade mix'),
        gradeSummary.isEmpty ? '—' : gradeSummary,
        gradeMix.isEmpty ? _t('No verified grades') : _t('latest verified'),
        Icons.verified_outlined,
        const Color(0xFF6741D9),
        valueFontSize: 16,
      ),
    ];
    return GridView.builder(
      key: const Key('fpc-kpi-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: dense ? 128 : 142,
      ),
      itemBuilder: (_, index) => _MetricCard(data: cards[index]),
    );
  }

  Widget _clusterStrip(
    FpcProcurementDashboardSnapshot snapshot, {
    required bool desktop,
    required bool dense,
  }) {
    return SizedBox(
      height: dense ? 120 : 134,
      child: ListView.separated(
        key: const Key('fpc-cluster-strip'),
        scrollDirection: Axis.horizontal,
        itemCount: snapshot.clusters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final cluster = snapshot.clusters[index];
          final selected = cluster.id == snapshot.selectedClusterId;
          return InkWell(
            onTap: () => widget.onClusterChanged(cluster.id),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: desktop ? 260 : 232,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? AppTheme.greenPale : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? AppTheme.green : const Color(0xFFDDE7DA),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cluster.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.greenDark,
                          ),
                        ),
                      ),
                      _StatusPill(
                        label: '${cluster.readyCount} ${_t('ready')}',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppTheme.green,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    [
                      if (cluster.district.isNotEmpty) cluster.district,
                      if (cluster.preferredApmcMarket.isNotEmpty)
                        cluster.preferredApmcMarket,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      _ClusterValue(
                        label: _t('Farms'),
                        value: '${cluster.farmCount}',
                      ),
                      const SizedBox(width: 24),
                      _ClusterValue(
                        label: _t('Expected'),
                        value: _quantity(cluster.expectedQuantityKg),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _farmQueue(
    FpcProcurementDashboardSnapshot? snapshot, {
    required int columns,
  }) {
    final farms = widget.farms;
    final resolvedFarms = [
      for (final farm in farms) _farmDetails[farm.linkId] ?? farm,
    ];
    final cropOptions =
        resolvedFarms
            .map((farm) => farm.crop.trim())
            .where((crop) => crop.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final gradeOptions =
        resolvedFarms
            .map((farm) => farm.latestGrade)
            .where((grade) => grade.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final filtered = _filteredFarms(resolvedFarms);
    return _Panel(
      key: const Key('fpc-farm-queue'),
      accentColor: const Color(0xFF20A879),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.agriculture_outlined, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('Farm procurement queue'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${filtered.length} ${_t('loaded')} · ${snapshot?.summary.networkFarms ?? farms.length} ${_t('farms')}',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  key: const Key('fpc-farm-search'),
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _t('Search farmer, farm, crop or village'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: _t('Clear search'),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterMenu(
                        key: const Key('fpc-status-filter'),
                        label: _t('Status'),
                        value: _statusFilter,
                        options: {
                          'all': _t('All statuses'),
                          'ready': _t('Ready'),
                          'needs_review': _t('Needs review'),
                          'planned': _t('Planned'),
                        },
                        onChanged: (value) =>
                            setState(() => _statusFilter = value),
                      ),
                      const SizedBox(width: 8),
                      _FilterMenu(
                        key: const Key('fpc-crop-filter'),
                        label: _t('Crop'),
                        value: _cropFilter,
                        options: {
                          'all': _t('All crops'),
                          for (final crop in cropOptions) crop: crop,
                        },
                        onChanged: (value) =>
                            setState(() => _cropFilter = value),
                      ),
                      const SizedBox(width: 8),
                      _FilterMenu(
                        key: const Key('fpc-grade-filter'),
                        label: _t('Grade'),
                        value: _gradeFilter,
                        options: {
                          'all': _t('All grades'),
                          for (final grade in gradeOptions) grade: grade,
                        },
                        onChanged: (value) =>
                            setState(() => _gradeFilter = value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (farms.isEmpty && widget.queueLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.queueError.isNotEmpty)
            _SimpleEmptyState(
              icon: Icons.cloud_off_outlined,
              title: _t('Farm queue unavailable'),
              message: widget.queueError,
              actionLabel: _t('Retry'),
              onAction: widget.onRefresh,
            )
          else if (farms.isEmpty)
            _emptyQueue(snapshot)
          else if (filtered.isEmpty)
            _SimpleEmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: _t('No farms match these filters'),
              message: _t('Clear or change filters to see this cluster queue.'),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 240 &&
                      widget.queueHasMore &&
                      !widget.queueLoading) {
                    widget.onLoadMoreFarms();
                  }
                  return false;
                },
                child: ListView.separated(
                  key: const Key('fpc-farm-selector-list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount:
                      filtered.length +
                      (widget.queueHasMore || widget.queueLoading ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    if (index == filtered.length) {
                      return _QueueLoadMoreCard(
                        loading: widget.queueLoading,
                        onLoadMore: widget.queueHasMore
                            ? widget.onLoadMoreFarms
                            : null,
                      );
                    }
                    final farm = filtered[index];
                    return _FarmSelectorTile(
                      farm: farm,
                      focused: farm.linkId == _focusedLinkId,
                      onTap: () {
                        final matches = widget.mapPoints.where(
                          (item) => item.linkId == farm.linkId,
                        );
                        if (matches.isNotEmpty) {
                          _selectMapPoint(matches.first);
                        } else {
                          _selectFarm(farm);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<FpcFarmWorkCard> _filteredFarms(List<FpcFarmWorkCard> farms) {
    final query = _searchController.text.trim().toLowerCase();
    return farms
        .where((farm) {
          final matchesQuery =
              query.isEmpty ||
              [
                farm.farmerName,
                farm.farmName,
                farm.crop,
                farm.village,
              ].any((value) => value.toLowerCase().contains(query));
          final matchesStatus = switch (_statusFilter) {
            'ready' => farm.isReady,
            'needs_review' => farm.needsReview,
            'planned' => !farm.isReady && farm.harvestPlanId != null,
            _ => true,
          };
          final matchesCrop = _cropFilter == 'all' || farm.crop == _cropFilter;
          final matchesGrade =
              _gradeFilter == 'all' || farm.latestGrade == _gradeFilter;
          return matchesQuery && matchesStatus && matchesCrop && matchesGrade;
        })
        .toList(growable: false);
  }

  Widget _emptyQueue(FpcProcurementDashboardSnapshot? snapshot) {
    final hasClusters = snapshot?.clusters.isNotEmpty ?? false;
    return _SimpleEmptyState(
      icon: hasClusters ? Icons.agriculture_outlined : Icons.hub_outlined,
      title: hasClusters
          ? _t('No linked farms in this selection')
          : _t('Set up your procurement regions'),
      message: hasClusters
          ? _t('Assign linked farms to this cluster or return to All clusters.')
          : _t(
              'Create a cluster, then assign linked farms when farmer data is available.',
            ),
      actionLabel: _t('Manage clusters'),
      onAction: widget.onManageClusters,
    );
  }

  Future<FpcFarmWorkCard?> _ensureFarmDetail(FpcFarmWorkCard farm) async {
    final existing = _farmDetails[farm.linkId];
    if (existing != null) return existing;
    if (_loadingFarmDetails.contains(farm.linkId)) return null;
    setState(() {
      _loadingFarmDetails.add(farm.linkId);
      _farmDetailFailures.remove(farm.linkId);
    });
    try {
      final detail = await widget.onLoadFarmDetail(farm);
      if (!mounted) return detail;
      setState(() {
        _farmDetails[farm.linkId] = detail;
        _loadingFarmDetails.remove(farm.linkId);
      });
      return detail;
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingFarmDetails.remove(farm.linkId);
          _farmDetailFailures.add(farm.linkId);
        });
      }
      return null;
    }
  }

  Future<void> _selectFarm(FpcFarmWorkCard farm) async {
    setState(() {
      _focusedLinkId = farm.linkId;
    });
    final detail = await _ensureFarmDetail(farm);
    if (detail?.hasMapLocation == true) _focusOnMap(detail!);
  }

  Future<void> _selectMapPoint(
    FpcFarmMapPoint point, {
    bool fitMap = false,
  }) async {
    setState(() {
      _focusedLinkId = point.linkId;
      _selectedMapPoint = point;
    });
    if (fitMap) _fitMapToPoints();
    if (_farmDetails.containsKey(point.linkId) ||
        _loadingFarmDetails.contains(point.linkId)) {
      return;
    }
    setState(() => _loadingFarmDetails.add(point.linkId));
    try {
      final detail = await widget.onLoadMapFarmDetail(point.linkId);
      if (!mounted) return;
      setState(() {
        _farmDetails[point.linkId] = detail;
        _loadingFarmDetails.remove(point.linkId);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingFarmDetails.remove(point.linkId);
          _farmDetailFailures.add(point.linkId);
        });
      }
    }
  }

  void _fitMapToPoints() {
    final points = widget.mapPoints;
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(
          LatLng(points.first.latitude, points.first.longitude),
          13,
        );
        return;
      }
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: [
            for (final point in points) LatLng(point.latitude, point.longitude),
          ],
          padding: const EdgeInsets.all(42),
          maxZoom: 13,
        ),
      );
    });
  }

  Widget _mapPanel(
    FpcProcurementDashboardSnapshot? snapshot, {
    required double height,
    bool nested = false,
  }) {
    final points = widget.mapPoints;
    final selected = _selectedMapPoint;
    final selectedDetail = selected == null
        ? null
        : _farmDetails[selected.linkId];
    final center = points.isNotEmpty
        ? LatLng(points.first.latitude, points.first.longitude)
        : const LatLng(19.7515, 75.7139);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!nested) _panelTitle(Icons.map_outlined, _t('Farm map')),
        if (!nested) const Divider(height: 1),
        SizedBox(
          height: height,
          child: widget.mapLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.mapError.isNotEmpty
              ? _SimpleEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: _t('Farm map unavailable'),
                  message: widget.mapError,
                  actionLabel: _t('Retry'),
                  onAction: widget.onRefresh,
                )
              : points.isEmpty
              ? _SimpleEmptyState(
                  icon: Icons.location_off_outlined,
                  title: _t('No mapped farms in this selection'),
                  message: _t('Add farm locations to show their pins here.'),
                )
              : ClipRRect(
                  borderRadius: nested
                      ? BorderRadius.circular(14)
                      : const BorderRadius.vertical(
                          bottom: Radius.circular(17),
                        ),
                  child: FlutterMap(
                    key: const Key('fpc-farm-map'),
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 14,
                      minZoom: mapTileMinZoom,
                      maxZoom: mapTileMaxZoom,
                    ),
                    children: [
                      OfflineMapBackground(message: _t('Farm locations')),
                      if (widget.enableMapTiles)
                        ...fieldImageryTileLayers(keepBuffer: 0, panBuffer: 0),
                      MarkerLayer(
                        markers: [
                          for (final point in points)
                            Marker(
                              point: LatLng(point.latitude, point.longitude),
                              width: 42,
                              height: 42,
                              child: Tooltip(
                                message:
                                    '${point.farmerName} · ${point.farmName}',
                                child: Material(
                                  color: point.needsReview
                                      ? const Color(0xFFE67700)
                                      : point.isReady
                                      ? AppTheme.green
                                      : const Color(0xFF1971C2),
                                  shape: const CircleBorder(),
                                  elevation: point.linkId == _focusedLinkId
                                      ? 7
                                      : 3,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => _selectMapPoint(point),
                                    child: const Icon(
                                      Icons.agriculture_rounded,
                                      color: Colors.white,
                                      size: 21,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${selected.farmerName} · ${selected.farmName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (selectedDetail != null)
                  TextButton(
                    onPressed: () => widget.onPlanProcurement(selectedDetail),
                    child: Text(_t('Plan procurement')),
                  )
                else if (_loadingFarmDetails.contains(selected.linkId))
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
      ],
    );
    return nested ? content : _Panel(padding: EdgeInsets.zero, child: content);
  }

  Widget _ratesPanel(
    FpcProcurementDashboardSnapshot? snapshot, {
    bool nested = false,
  }) {
    final cluster = snapshot?.selectedCluster;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!nested)
          _panelTitle(Icons.currency_rupee_rounded, _t('APMC rates')),
        if (!nested) const Divider(height: 1),
        if (cluster == null)
          _SimpleEmptyState(
            icon: Icons.location_city_outlined,
            title: _t('Choose one cluster'),
            message: _t(
              'Select a cluster to load rates for its district and preferred market.',
            ),
          )
        else if (widget.apmcLoading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.apmcError.isNotEmpty)
          _SimpleEmptyState(
            icon: Icons.cloud_off_outlined,
            title: _t('Rates unavailable'),
            message: widget.apmcError,
            actionLabel: _t('Retry'),
            onAction: widget.onRetryApmc,
          )
        else if (widget.apmcRates.isEmpty)
          _SimpleEmptyState(
            icon: Icons.query_stats_outlined,
            title: _t('No local rates found'),
            message:
                '${cluster.preferredApmcMarket.isEmpty ? cluster.district : cluster.preferredApmcMarket} · ${_t('No live rate was returned.')}',
          )
        else
          for (final rate in widget.apmcRates.take(6))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rate.commodity,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            rate.market,
                            if (rate.variety.isNotEmpty) rate.variety,
                            if (rate.arrivalDate != null)
                              DateFormat(
                                'd MMM',
                              ).format(rate.arrivalDate!.toLocal()),
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${_plainNumber(rate.modalPrice)}/${_t('qtl')}',
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
    return nested
        ? content
        : _Panel(
            accentColor: AppTheme.gold,
            padding: EdgeInsets.zero,
            child: content,
          );
  }

  Widget _panelTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.greenDark),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _mobileSidePanel({
    required String title,
    required IconData icon,
    required bool expanded,
    required ValueChanged<bool> onChanged,
    required Widget child,
  }) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onChanged,
          leading: Icon(icon, color: AppTheme.greenDark),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [child],
        ),
      ),
    );
  }

  void _focusOnMap(FpcFarmWorkCard farm) {
    setState(() => _focusedLinkId = farm.linkId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(
          LatLng(farm.centroidLatitude!, farm.centroidLongitude!),
          14,
        );
      } catch (_) {
        // The map can still be mounting after a mobile expansion.
      }
    });
  }
}

class _FarmSelectorTile extends StatelessWidget {
  final FpcFarmWorkCard farm;
  final bool focused;
  final VoidCallback onTap;

  const _FarmSelectorTile({
    required this.farm,
    required this.focused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = _progressFor(farm);
    return Material(
      color: focused ? AppTheme.greenPale : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                farm.needsReview
                    ? Icons.warning_amber_rounded
                    : farm.isReady
                    ? Icons.check_circle_rounded
                    : Icons.agriculture_outlined,
                color: farm.needsReview
                    ? const Color(0xFFE67700)
                    : farm.isReady
                    ? AppTheme.greenDark
                    : AppTheme.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${farm.farmerName} · ${farm.farmName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      [
                        farm.crop,
                        farm.village,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: progress.$1,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE6ECE1),
                              color: progress.$2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          progress.$3,
                          style: TextStyle(
                            color: progress.$2,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        if (farm.areaAcres != null)
                          _TimelineFact(
                            icon: Icons.landscape_outlined,
                            label:
                                '${farm.areaAcres!.toStringAsFixed(1)} acres',
                          ),
                        if (farm.expectedHarvestDate != null)
                          _TimelineFact(
                            icon: Icons.event_outlined,
                            label: DateFormat(
                              'd MMM',
                            ).format(farm.expectedHarvestDate!.toLocal()),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  (double, Color, String) _progressFor(FpcFarmWorkCard farm) {
    if (farm.needsReview) {
      return (0.25, const Color(0xFFE67700), _t('Needs review'));
    }
    if (farm.isReady) {
      return (0.82, AppTheme.greenDark, _t('Ready to collect'));
    }
    if (farm.harvestPlanId != null) {
      return (0.58, AppTheme.greenDark, _t('Harvest planned'));
    }
    if (farm.currentStatusStage.trim().isNotEmpty) {
      return (0.36, const Color(0xFF517A9B), _t('Farm monitoring'));
    }
    return (0.15, AppTheme.textMuted, _t('Farm linked'));
  }
}

class _TimelineFact extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TimelineFact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppTheme.textMuted),
      const SizedBox(width: 3),
      Text(
        label,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
      ),
    ],
  );
}

// Retained for the detailed farm sheet used by existing command-center flows.
// ignore: unused_element
class _FarmCard extends StatelessWidget {
  final FpcFarmWorkCard farm;
  final FpcFarmWorkCard? detail;
  final bool loadingDetails;
  final bool detailFailed;
  final bool focused;
  final Future<void> Function() onFocus;
  final Future<void> Function() onPlan;

  const _FarmCard({
    required this.farm,
    required this.detail,
    required this.loadingDetails,
    required this.detailFailed,
    required this.focused,
    required this.onFocus,
    required this.onPlan,
  });

  @override
  Widget build(BuildContext context) {
    final details = detail;
    return Semantics(
      label:
          '${farm.farmerName}, ${farm.crop}, ${farm.village}, ${farm.readiness}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: focused ? AppTheme.gold : const Color(0xFFDDE7DA),
            width: focused ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farm.farmerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          farm.crop.isEmpty
                              ? _t('Crop not recorded')
                              : farm.crop,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          [
                            farm.village,
                            farm.farmName,
                          ].where((value) => value.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(
                    label: farm.isReady
                        ? _t('Ready')
                        : _t(_humanize(farm.readiness)),
                    icon: farm.isReady
                        ? Icons.check_circle_outline_rounded
                        : Icons.schedule_rounded,
                    color: farm.isReady
                        ? AppTheme.green
                        : const Color(0xFF6B7280),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _HarvestDate(farm: farm),
              const SizedBox(height: 10),
              if (details == null)
                _FarmDetailSkeleton(
                  failed: detailFailed,
                  loading: loadingDetails,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _FarmFact(
                        _t('Grade'),
                        details.latestGrade,
                        const Color(0xFFFFF3BF),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _FarmFact(
                        _t('Health'),
                        details.healthScore == null
                            ? _t('No data')
                            : '${details.healthScore}%',
                        const Color(0xFFE9FAC8),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _FarmFact(
                        _t('Quantity'),
                        details.expectedQuantityKg == null
                            ? '—'
                            : _quantity(details.expectedQuantityKg!),
                        const Color(0xFFDFF5FF),
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              if (details != null) _DataFreshness(farm: details),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: _t('Show field map'),
                    onPressed: () => onFocus(),
                    icon: const Icon(Icons.map_outlined, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: details == null ? null : () => onPlan(),
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text(_t('Plan procurement')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HarvestDate extends StatelessWidget {
  final FpcFarmWorkCard farm;

  const _HarvestDate({required this.farm});

  @override
  Widget build(BuildContext context) {
    final date = farm.expectedHarvestDate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 17, color: Color(0xFF9A6200)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _t('Predicted harvest'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            date == null
                ? _t('Not planned')
                : DateFormat('d MMM y').format(date.toLocal()),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _FarmDetailSkeleton extends StatelessWidget {
  final bool failed;
  final bool loading;

  const _FarmDetailSkeleton({required this.failed, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return const Text(
        'Details unavailable. Open the map to retry.',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
      );
    }
    return Row(
      children: List.generate(
        3,
        (index) => Expanded(
          child: Container(
            height: 48,
            margin: EdgeInsets.only(right: index == 2 ? 0 : 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: loading
                ? const Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _QueueLoadMoreCard extends StatelessWidget {
  final bool loading;
  final Future<void> Function()? onLoadMore;

  const _QueueLoadMoreCard({required this.loading, required this.onLoadMore});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading || onLoadMore == null ? null : () => onLoadMore!(),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Load next 5 farms'),
    );
  }
}

class _DataFreshness extends StatelessWidget {
  final FpcFarmWorkCard farm;

  const _DataFreshness({required this.farm});

  @override
  Widget build(BuildContext context) {
    if (farm.dataUpdatedAt == null) {
      return Text(
        _t('No monitoring update'),
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Row(
      children: [
        Icon(
          farm.isDataStale ? Icons.history_rounded : Icons.sync_rounded,
          size: 14,
          color: farm.isDataStale ? const Color(0xFFC56A00) : AppTheme.green,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${farm.isDataStale ? _t('Stale data') : _t('Live data')} · ${DateFormat('d MMM, h:mm a').format(farm.dataUpdatedAt!.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: farm.isDataStale
                  ? const Color(0xFF9C4D00)
                  : AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FarmFact extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _FarmFact(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final String supporting;
  final IconData icon;
  final Color color;
  final double valueFontSize;

  const _MetricData(
    this.label,
    this.value,
    this.supporting,
    this.icon,
    this.color, {
    this.valueFontSize = 20,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: data.color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(data.icon, size: 18, color: data.color),
              ),
              const Spacer(),
            ],
          ),
          const Spacer(),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textDark,
              fontSize: data.valueFontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          Text(
            data.supporting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _FilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final option in options.entries)
          PopupMenuItem(value: option.key, child: Text(option.value)),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: value == 'all' ? Colors.white : AppTheme.greenPale,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: value == 'all' ? const Color(0xFFD9E0D6) : AppTheme.green,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ${options[value] ?? value}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClusterValue extends StatelessWidget {
  final String label;
  final String value;

  const _ClusterValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _SimpleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SimpleEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34, color: AppTheme.textMuted),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _DashboardError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF4E6),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD9480F)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: Text(_t('Retry'))),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accentColor;

  const _Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              accentColor?.withValues(alpha: 0.72) ?? const Color(0xFFDDE7DA),
          width: accentColor == null ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

String _t(String english) => UiStrings.fromEnglish(english);

String _humanize(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _quantity(double kilograms) {
  if (kilograms >= 1000) {
    final tonnes = kilograms / 1000;
    return '${_plainNumber(tonnes)} t';
  }
  return '${_plainNumber(kilograms)} kg';
}

String _plainNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}
