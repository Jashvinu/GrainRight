import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import '../models/fpc_account_identity.dart';
import '../models/fpc_dashboard_summary.dart';
import '../models/fpc_farmer_profile.dart';
import '../services/fpc_dashboard_service.dart';
import '../services/fpc_operating_service.dart';
import '../services/fpc_procurement_service.dart';
import '../services/grain_grading_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpoHomeScreen extends StatefulWidget {
  const FpoHomeScreen({super.key});

  @override
  State<FpoHomeScreen> createState() => _FpoHomeScreenState();
}

class _FpoHomeScreenState extends State<FpoHomeScreen> {
  final _service = FpcDashboardService();
  final _operatingService = FpcOperatingService();
  FpcDashboardSummary? _summary;
  Map<String, dynamic> _operatingMetrics = const {};
  List<Map<String, dynamic>> _notifications = const [];
  List<FpcFarmerProfile> _farmers = const [];
  bool _farmerDirectoryFailed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dashboardFuture = _service.load();
    final operatingFuture = _optional(_operatingService.loadDashboardMetrics());
    final notificationFuture = _optional(
      _operatingService.loadNotifications(unreadOnly: true),
    );
    final farmerFuture = _optional(_operatingService.loadFarmerDirectory());
    final dashboard = await dashboardFuture;
    final operatingMetrics = await operatingFuture;
    final notifications = await notificationFuture;
    final farmers = await farmerFuture;
    if (!mounted) return;
    setState(() {
      _summary = dashboard;
      _operatingMetrics = operatingMetrics ?? const <String, dynamic>{};
      _notifications = notifications ?? const <Map<String, dynamic>>[];
      _farmers = farmers ?? const <FpcFarmerProfile>[];
      _farmerDirectoryFailed = farmers == null;
      _loading = false;
    });
  }

  Future<T?> _optional<T>(Future<T> request) async {
    try {
      return await request;
    } catch (_) {
      // Keep the rest of the dashboard usable when one tenant module is not
      // provisioned or temporarily unavailable.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FpcWorkspaceScaffold(
      current: FpcNavTab.home,
      title: UiStrings.t('fpo_dashboard'),
      actions: [
        IconButton(
          tooltip: UiStrings.fromEnglish('Refresh dashboard'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              constraints.maxWidth >= 920 ? 28 : 16,
              16,
              constraints.maxWidth >= 920 ? 28 : 16,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: _DashboardView(
                    account: FpcAccountIdentity.current(),
                    summary: _summary,
                    operatingMetrics: _operatingMetrics,
                    notifications: _notifications,
                    farmers: _farmers,
                    farmerDirectoryFailed: _farmerDirectoryFailed,
                    loading: _loading,
                    onRefresh: _load,
                    onReadNotification: (id) async {
                      await _operatingService.markNotificationRead(id);
                      await _load();
                    },
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

class _DashboardView extends StatelessWidget {
  final FpcAccountIdentity account;
  final FpcDashboardSummary? summary;
  final Map<String, dynamic> operatingMetrics;
  final List<Map<String, dynamic>> notifications;
  final List<FpcFarmerProfile> farmers;
  final bool farmerDirectoryFailed;
  final bool loading;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String id) onReadNotification;

  const _DashboardView({
    required this.account,
    required this.summary,
    required this.operatingMetrics,
    required this.notifications,
    required this.farmers,
    required this.farmerDirectoryFailed,
    required this.loading,
    required this.onRefresh,
    required this.onReadNotification,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(account: account, loading: loading, onRefresh: onRefresh),
        const SizedBox(height: 14),
        _metrics(),
        const SizedBox(height: 14),
        _actionsPanel(),
        if (notifications.isNotEmpty) ...[
          const SizedBox(height: 14),
          _notificationPanel(),
        ],
        if (!loading && (summary?.hasErrors ?? false)) ...[
          const SizedBox(height: 14),
          _Warning(onRetry: onRefresh),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final main = _activeFarmersPanel();
            final side = _reviewsPanel();
            if (constraints.maxWidth < 940) {
              return Column(children: [main, const SizedBox(height: 14), side]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: main),
                const SizedBox(width: 14),
                Expanded(flex: 3, child: side),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _receivedPanel(),
      ],
    );
  }

  Widget _metrics() {
    final metrics = [
      (
        'Tracked farmers',
        _value(summary?.farmers),
        'Visible in FPC records',
        Icons.groups_2_outlined,
        const Color(0xFF087F5B),
        summary?.farmers.failed ?? false,
      ),
      (
        'Ready to harvest',
        '${operatingMetrics['ready_farms'] ?? 0}',
        'Farms ready for action',
        Icons.agriculture_outlined,
        const Color(0xFF1D67A8),
        false,
      ),
      (
        'Needs review',
        _value(summary?.reviews),
        'Quality decisions waiting',
        Icons.fact_check_outlined,
        const Color(0xFFC56A00),
        summary?.reviews.failed ?? false,
      ),
      (
        'Payments pending',
        '${operatingMetrics['pending_payments'] ?? 0}',
        'Farmer payments to finish',
        Icons.payments_outlined,
        const Color(0xFF7C3FA0),
        false,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 4
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: metric.$1,
                  value: metric.$2,
                  note: metric.$3,
                  icon: metric.$4,
                  color: metric.$5,
                  failed: metric.$6,
                  loading: loading,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _notificationPanel() => _Panel(
    title: 'Operational alerts',
    subtitle: 'Unread assignments, stock, expiry and delivery notifications.',
    child: Column(
      children: [
        for (final notification in notifications.take(8))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.notifications_active_outlined,
              color: AppTheme.greenDark,
            ),
            title: Text(
              '${notification['title'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('${notification['body'] ?? ''}'),
            trailing: TextButton(
              onPressed: () => onReadNotification('${notification['id']}'),
              child: Text(UiStrings.fromEnglish('Mark read')),
            ),
          ),
      ],
    ),
  );

  Widget _activeFarmersPanel() {
    final activeFarmers = farmers
        .where((farmer) => farmer.isActive)
        .toList(growable: false);
    final regions = _farmerRegions(activeFarmers);
    final verified = activeFarmers.where((farmer) => farmer.isVerified).length;
    return _Panel(
      title: 'Active farmer network',
      subtitle:
          'Linked farmer details, crop coverage and village-wise operating regions.',
      trailing: TextButton.icon(
        onPressed: () => Get.toNamed('/fpo/farmers'),
        icon: const Icon(Icons.groups_2_outlined, size: 18),
        label: Text(UiStrings.fromEnglish('View all farmers')),
      ),
      child: loading
          ? const _Loading()
          : farmerDirectoryFailed
          ? const _Empty(
              icon: Icons.cloud_off_outlined,
              title: 'Farmer directory unavailable',
              message: 'Refresh the dashboard to retry.',
            )
          : farmers.isEmpty
          ? const _Empty(
              icon: Icons.group_add_outlined,
              title: 'No linked farmers yet',
              message:
                  'Use the floating Scan QR button and choose Farmer profile QR to link the first farmer.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FarmerNetworkOverview(
                  active: activeFarmers.length,
                  total: farmers.length,
                  regions: regions.length,
                  verified: verified,
                ),
                const SizedBox(height: 16),
                _RegionCoverage(regions: regions),
                const SizedBox(height: 18),
                Text(
                  UiStrings.fromEnglish('Active farmer details'),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (activeFarmers.isEmpty)
                  const _Empty(
                    icon: Icons.person_off_outlined,
                    title: 'No active farmers',
                    message:
                        'Linked farmers will appear here after their FPC status becomes active.',
                  )
                else
                  _ActiveFarmerGrid(
                    farmers: activeFarmers.take(6).toList(growable: false),
                  ),
              ],
            ),
    );
  }

  Widget _actionsPanel() {
    const actions = [
      (
        Icons.groups_2_outlined,
        'Farmers',
        'Search and open full farmer profiles',
        '/fpo/farmers',
      ),
      (
        Icons.assignment_turned_in_outlined,
        'Receive produce',
        'Scan final harvest QR',
        '/fpo/receiver',
      ),
      (
        Icons.grain_rounded,
        'Grade a lot',
        'Start counter grain grading',
        '/fpo/grain-grading',
      ),
      (
        Icons.account_tree_rounded,
        'All operations',
        'Procurement, stock, payments and reports',
        '/fpo/operations',
      ),
    ];
    return _Panel(
      title: 'What do you want to do?',
      subtitle: 'Start the most common FPC work in one tap.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 560
              ? 2
              : 1;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: _QuickActionTile(
                    icon: action.$1,
                    title: action.$2,
                    subtitle: action.$3,
                    onTap: () => action.$4 == '/fpo/grain-grading'
                        ? Get.toNamed(
                            action.$4,
                            arguments: FpcBottomNavBar.gradingArgs,
                          )
                        : Get.toNamed(action.$4),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _reviewsPanel() {
    final jobs = summary?.reviewJobs ?? const [];
    return _Panel(
      title: 'Quality queue',
      subtitle: 'Lots requiring an FPC decision.',
      trailing: IconButton(
        tooltip: UiStrings.fromEnglish('Open review queue'),
        onPressed: () => Get.toNamed('/fpo/grading-review'),
        icon: const Icon(Icons.open_in_new_rounded),
      ),
      child: loading
          ? const _Loading(compact: true)
          : summary?.reviews.failed == true
          ? const _Empty(
              icon: Icons.cloud_off_outlined,
              title: 'Review data unavailable',
              message: 'Open the review queue to retry.',
            )
          : jobs.isEmpty
          ? const _Empty(
              icon: Icons.task_alt_rounded,
              title: 'No review pending',
              message: 'New grading issues will appear here.',
            )
          : Column(
              children: [for (final job in jobs.take(3)) _ReviewTile(job: job)],
            ),
    );
  }

  Widget _receivedPanel() {
    final records = summary?.procurementRecords ?? const [];
    return _Panel(
      title: 'Recently received produce',
      subtitle: 'Latest harvest lots saved in this FPC ledger.',
      trailing: TextButton(
        onPressed: () => Get.toNamed('/fpo/receiver'),
        child: Text(UiStrings.fromEnglish('Open ledger')),
      ),
      child: loading
          ? const _Loading()
          : summary?.lots.failed == true
          ? const _Empty(
              icon: Icons.cloud_off_outlined,
              title: 'Receiving data unavailable',
              message: 'Refresh the dashboard to retry.',
            )
          : records.isEmpty
          ? const _Empty(
              icon: Icons.inventory_2_outlined,
              title: 'No produce received yet',
              message:
                  'Scan an approved harvest QR in Receiver to create the first entry.',
            )
          : Column(
              children: [
                for (final record in records.take(6))
                  _RecordTile(record: record),
              ],
            ),
    );
  }
}

List<_FarmerRegion> _farmerRegions(List<FpcFarmerProfile> farmers) {
  final grouped = <String, List<FpcFarmerProfile>>{};
  for (final farmer in farmers) {
    final region = farmer.village.trim().isEmpty
        ? 'Region not recorded'
        : farmer.village.trim();
    grouped.putIfAbsent(region, () => []).add(farmer);
  }
  final regions =
      grouped.entries.map((entry) {
        final crops =
            entry.value
                .map((farmer) => farmer.crop.trim())
                .where((crop) => crop.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        return _FarmerRegion(
          name: entry.key,
          farmerCount: entry.value.length,
          crops: crops,
        );
      }).toList()..sort((a, b) {
        final count = b.farmerCount.compareTo(a.farmerCount);
        return count == 0 ? a.name.compareTo(b.name) : count;
      });
  return regions;
}

class _FarmerRegion {
  final String name;
  final int farmerCount;
  final List<String> crops;

  const _FarmerRegion({
    required this.name,
    required this.farmerCount,
    required this.crops,
  });
}

class _FarmerNetworkOverview extends StatelessWidget {
  final int active;
  final int total;
  final int regions;
  final int verified;

  const _FarmerNetworkOverview({
    required this.active,
    required this.total,
    required this.regions,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      (Icons.check_circle_outline_rounded, '$active', 'Active'),
      (Icons.groups_2_outlined, '$total', 'Linked'),
      (Icons.map_outlined, '$regions', 'Regions'),
      (Icons.verified_user_outlined, '$verified', 'Verified'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenDark,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth >= 620
              ? (constraints.maxWidth - 30) / 4
              : (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final stat in stats)
                SizedBox(
                  width: itemWidth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(stat.$1, color: Colors.white, size: 21),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                LocaleText.digits(stat.$2),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                UiStrings.fromEnglish(stat.$3),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RegionCoverage extends StatelessWidget {
  final List<_FarmerRegion> regions;

  const _RegionCoverage({required this.regions});

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) {
      return const _Empty(
        icon: Icons.map_outlined,
        title: 'No active region coverage',
        message:
            'Village coverage appears after a linked farmer becomes active.',
      );
    }
    final highest = regions.first.farmerCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: AppTheme.greenDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  UiStrings.fromEnglish('Active farmers by region'),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          for (final region in regions.take(6)) ...[
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppTheme.greenPale,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.landscape_outlined,
                    color: AppTheme.greenDark,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        region.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        region.crops.isEmpty
                            ? UiStrings.fromEnglish('Crop not recorded')
                            : region.crops.take(3).join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  UiStrings.fromEnglish('${region.farmerCount} active'),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: region.farmerCount / highest,
                backgroundColor: Colors.white,
                color: AppTheme.green,
              ),
            ),
            if (region != regions.take(6).last) const SizedBox(height: 13),
          ],
        ],
      ),
    );
  }
}

class _ActiveFarmerGrid extends StatelessWidget {
  final List<FpcFarmerProfile> farmers;

  const _ActiveFarmerGrid({required this.farmers});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final farmer in farmers)
              SizedBox(
                width: width,
                child: _ActiveFarmerCard(farmer: farmer),
              ),
          ],
        );
      },
    );
  }
}

class _ActiveFarmerCard extends StatelessWidget {
  final FpcFarmerProfile farmer;

  const _ActiveFarmerCard({required this.farmer});

  @override
  Widget build(BuildContext context) {
    final crop = [
      farmer.crop,
      farmer.variety,
    ].where((value) => value.trim().isNotEmpty).join(' • ');
    final farm = [
      farmer.primaryFarm,
      farmer.area,
    ].where((value) => value.trim().isNotEmpty).join(' • ');
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: Color(0xFFDDE8D4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed(
          '/fpo/farmers',
          arguments: {'farmerId': farmer.farmerId},
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.greenPale,
                    child: Text(
                      _farmerInitials(farmer.name),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          farmer.name.trim().isEmpty ? 'Farmer' : farmer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          farmer.farmerId.trim().isEmpty
                              ? 'ID not recorded'
                              : farmer.farmerId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.greenPale,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      UiStrings.fromEnglish('Active'),
                      style: const TextStyle(
                        color: AppTheme.greenDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FarmerCardDetail(
                icon: Icons.location_on_outlined,
                value: farmer.village,
                fallback: 'Region not recorded',
              ),
              _FarmerCardDetail(
                icon: Icons.agriculture_outlined,
                value: crop,
                fallback: 'Crop not recorded',
              ),
              _FarmerCardDetail(
                icon: Icons.landscape_outlined,
                value: farm,
                fallback: 'Farm not recorded',
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(
                    farmer.isVerified
                        ? Icons.verified_rounded
                        : Icons.info_outline_rounded,
                    color: farmer.isVerified
                        ? AppTheme.green
                        : AppTheme.textMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      UiStrings.fromEnglish(
                        farmer.isVerified
                            ? 'Verified profile'
                            : 'Verification pending',
                      ),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    UiStrings.fromEnglish('Open details'),
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.greenDark,
                    size: 18,
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

class _FarmerCardDetail extends StatelessWidget {
  final IconData icon;
  final String value;
  final String fallback;

  const _FarmerCardDetail({
    required this.icon,
    required this.value,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              UiStrings.fromEnglish(value.trim().isEmpty ? fallback : value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _farmerInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return 'F';
  return parts.map((part) => part[0].toUpperCase()).join();
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppTheme.greenDark),
              ),
              const SizedBox(width: 10),
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
                      UiStrings.fromEnglish(subtitle),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final FpcAccountIdentity account;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _Header({
    required this.account,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: account.name,
      subtitle:
          'Track farmer produce, quality, buyback interest and receiving from one overview.',
      trailing: OutlinedButton.icon(
        onPressed: loading ? null : onRefresh,
        icon: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
        label: Text(UiStrings.fromEnglish('Refresh')),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4DF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            UiStrings.fromEnglish('Procurement planning'),
            style: const TextStyle(
              color: Color(0xFF8A4A00),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
  final bool failed;
  final bool loading;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
    required this.failed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (failed ? AppTheme.error : color).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  UiStrings.fromEnglish(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            )
          else
            Text(
              failed ? '--' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: failed ? AppTheme.error : AppTheme.greenDark,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            UiStrings.fromEnglish(failed ? 'Data unavailable' : note),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final GradingReviewJob job;

  const _ReviewTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final crop = [
      job.cropType.trim(),
      job.variety.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    final failed = job.status.toLowerCase() == 'failed';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.biotech_outlined, color: Color(0xFFC56A00)),
      title: Text(
        crop.isEmpty ? UiStrings.fromEnglish('Grain lot') : crop,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(job.farmerId.trim().isEmpty ? job.batchId : job.farmerId),
      trailing: _Pill(
        label: failed ? 'Failed' : job.reviewStatus.replaceAll('_', ' '),
      ),
      onTap: () => Get.toNamed('/fpo/grading-review'),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final FpcProcurementRecord record;

  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final product = [
      record.cropType.trim(),
      record.variety.trim(),
    ].where((value) => value.isNotEmpty).join(' · ');
    final farmer = record.customerName.trim().isEmpty
        ? record.farmerId
        : record.customerName.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: AppTheme.greenDark,
              ),
              title: Text(
                product.isEmpty
                    ? UiStrings.fromEnglish('Received grain lot')
                    : product,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(farmer.isEmpty ? record.batchId : farmer),
            ),
          ),
          _Pill(
            label: record.quantityKg == null
                ? 'Quantity --'
                : '${_number(record.quantityKg!)} kg',
          ),
          _Pill(
            label: record.grade.trim().isEmpty
                ? 'Grade --'
                : 'Grade ${record.grade}',
          ),
          _Pill(
            label: record.receivedAt == null
                ? 'Date --'
                : LocaleText.date(record.receivedAt!.toLocal()),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
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
                      UiStrings.fromEnglish(title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UiStrings.fromEnglish(subtitle),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE3EA)),
      ),
      child: Text(
        UiStrings.fromEnglish(label),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  final bool compact;

  const _Loading({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 70 : 105,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2.3)),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.greenDark, size: 28),
          const SizedBox(height: 7),
          Text(
            UiStrings.fromEnglish(title),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            UiStrings.fromEnglish(message),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _Warning({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFFF1D59B)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_rounded, color: Color(0xFF9A6700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              UiStrings.t('some_dashboard_stats_unavailable'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(UiStrings.t('try_again'))),
        ],
      ),
    );
  }
}

String _value(FpcDashboardMetric? metric) {
  final value = metric?.value;
  return value == null ? '--' : LocaleText.number(value);
}

String _number(num value) =>
    LocaleText.number(value, fractionDigits: value % 1 == 0 ? 0 : 1);
