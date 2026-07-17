import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_logout_flow.dart';
import '../controllers/main_auth_controller.dart';
import '../models/fpc_account_identity.dart';
import '../models/fpc_dashboard_summary.dart';
import '../models/marketplace_listing.dart';
import '../services/fpc_dashboard_service.dart';
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
  FpcDashboardSummary? _summary;
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
    final summary = await _service.load();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    return FpcWorkspaceScaffold(
      current: FpcNavTab.home,
      title: UiStrings.t('fpo_dashboard'),
      actions: [
        IconButton(
          tooltip: UiStrings.fromEnglish('Refresh dashboard'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: UiStrings.t('admin_login'),
          onPressed: () => Get.toNamed('/admin/login'),
          icon: const Icon(Icons.admin_panel_settings_outlined),
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
                    loading: _loading,
                    onRefresh: _load,
                    onLogout: () =>
                        AppLogoutFlow.run(context, onLogout: auth.logout),
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
  final bool loading;
  final Future<void> Function() onRefresh;
  final VoidCallback onLogout;

  const _DashboardView({
    required this.account,
    required this.summary,
    required this.loading,
    required this.onRefresh,
    required this.onLogout,
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
        _workflow(),
        if (!loading && (summary?.hasErrors ?? false)) ...[
          const SizedBox(height: 14),
          _Warning(onRetry: onRefresh),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final main = _producePanel();
            final side = Column(
              children: [
                _actionsPanel(),
                const SizedBox(height: 14),
                _reviewsPanel(),
              ],
            );
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
        const SizedBox(height: 14),
        _roleNote(),
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
        'Open farm lots',
        _value(summary?.listings),
        'Ready for planning',
        Icons.inventory_2_outlined,
        const Color(0xFF1D67A8),
        summary?.listings.failed ?? false,
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
        'Buyback interest',
        summary == null ? '--' : LocaleText.number(summary!.interestedListings),
        'Lots selected by FPC',
        Icons.handshake_outlined,
        const Color(0xFF7C3FA0),
        false,
      ),
      (
        'Received lots',
        _value(summary?.lots),
        'Saved in FPC ledger',
        Icons.assignment_turned_in_outlined,
        const Color(0xFF00897B),
        summary?.lots.failed ?? false,
      ),
      (
        'Received quantity',
        summary == null
            ? '--'
            : '${LocaleText.number(summary!.receivedQuantityKg, fractionDigits: 0)} kg',
        'Total recorded quantity',
        Icons.scale_outlined,
        const Color(0xFF6D5A00),
        false,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 6
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

  Widget _workflow() {
    final stages = [
      ('Seed issued', 'Seed issue record required', Icons.grass_outlined),
      (
        'Farmer linked',
        'Verify farmer profile QR',
        Icons.verified_user_outlined,
      ),
      (
        'Quality review',
        '${_value(summary?.reviews)} need attention',
        Icons.biotech_outlined,
      ),
      (
        'Buyback interest',
        '${summary?.interestedListings ?? 0} lots selected',
        Icons.handshake_outlined,
      ),
      (
        'Produce received',
        '${_value(summary?.lots)} lots received',
        Icons.inventory_outlined,
      ),
    ];
    return _Panel(
      title: 'Farmer-to-FPC workflow',
      subtitle: 'Follow produce from seed handover to final receiving.',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < stages.length; index++) ...[
              Container(
                width: 176,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.greenPale.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFDDE8D4)),
                ),
                child: Row(
                  children: [
                    Icon(stages[index].$3, color: AppTheme.greenDark, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${UiStrings.fromEnglish(stages[index].$1)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            UiStrings.fromEnglish(stages[index].$2),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index != stages.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _producePanel() {
    final listings = summary?.activeMarketplaceListings ?? const [];
    return _Panel(
      title: 'Farmer produce for planning',
      subtitle: 'Review live farmer lots and save FPC buyback interest.',
      trailing: TextButton(
        onPressed: () => Get.toNamed('/fpo/marketplace'),
        child: Text(UiStrings.fromEnglish('Open marketplace')),
      ),
      child: loading
          ? const _Loading()
          : summary?.listings.failed == true
          ? const _Empty(
              icon: Icons.cloud_off_outlined,
              title: 'Marketplace data unavailable',
              message: 'Refresh the dashboard to retry.',
            )
          : listings.isEmpty
          ? const _Empty(
              icon: Icons.agriculture_outlined,
              title: 'No farmer lots ready yet',
              message:
                  'Lots appear after farmer inventory is synced and listed for FPC buyers.',
            )
          : Column(
              children: [
                for (final listing in listings.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ListingCard(listing: listing),
                  ),
              ],
            ),
    );
  }

  Widget _actionsPanel() {
    const actions = [
      (
        Icons.qr_code_scanner_rounded,
        'Verify farmer',
        'Scan verified farmer QR',
        '/fpo/scan-farmer',
      ),
      (
        Icons.fact_check_outlined,
        'Review quality',
        'Approve or request recapture',
        '/fpo/grading-review',
      ),
      (
        Icons.handshake_outlined,
        'Plan buyback',
        'Review lots and save interest',
        '/fpo/marketplace',
      ),
      (
        Icons.assignment_turned_in_outlined,
        'Receive harvest',
        'Scan final harvest QR',
        '/fpo/receiver',
      ),
    ];
    return _Panel(
      title: 'FPC actions',
      subtitle: 'Open the next operational step.',
      child: Column(
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                tileColor: AppTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(action.$1, color: AppTheme.greenDark),
                title: Text(
                  UiStrings.fromEnglish(action.$2),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(UiStrings.fromEnglish(action.$3)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.toNamed(action.$4),
              ),
            ),
        ],
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

  Widget _roleNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE3EA)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.account_tree_outlined, color: Color(0xFF41546A)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Text(
              UiStrings.fromEnglish(
                'This overview is for FPC operations. Farmer input shopping and downstream bulk-buyer purchasing remain separate role-based marketplace experiences.',
              ),
              style: const TextStyle(
                color: Color(0xFF41546A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.switch_account_outlined),
            label: Text(UiStrings.t('change_role')),
          ),
        ],
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

class _ListingCard extends StatelessWidget {
  final MarketplaceListing listing;

  const _ListingCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final farmer = listing.farmerId.trim().isEmpty
        ? 'Verified farmer'
        : listing.farmerId.trim();
    final farm = listing.farmName.trim().isEmpty
        ? 'Farm not named'
        : listing.farmName.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: listing.interestedByMe ? AppTheme.greenPale : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: listing.interestedByMe
              ? const Color(0xFFBFD8B8)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grain_rounded, color: AppTheme.green),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.displayProductName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$farmer · $farm',
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
              _Pill(
                label: listing.interestedByMe ? 'Interest saved' : 'Open lot',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(label: '${_number(listing.quantity)} ${listing.unit}'),
              _Pill(
                label: listing.grade.trim().isEmpty
                    ? 'Grade pending'
                    : 'Grade ${listing.grade}',
              ),
              if (listing.askingPricePerUnit != null)
                _Pill(
                  label:
                      '₹${_number(listing.askingPricePerUnit!)}/${listing.unit}',
                ),
              if (listing.moisturePercent != null)
                _Pill(
                  label:
                      '${LocaleText.number(listing.moisturePercent!, fractionDigits: 1)}% moisture',
                ),
              OutlinedButton.icon(
                onPressed: () => Get.toNamed('/fpo/marketplace'),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: Text(UiStrings.fromEnglish('Review lot')),
              ),
            ],
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
