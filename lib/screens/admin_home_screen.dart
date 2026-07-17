import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kalsubai_farms/core/localization/locale_text.dart';
import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_logout_flow.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/admin_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../services/admin_service.dart';
import '../widgets/farm_hills_background.dart';

enum _AdminSection { overview, farmers, fpc, stakeholders }

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  _AdminSection _section = _AdminSection.stakeholders;

  @override
  void initState() {
    super.initState();
    final admin = Get.find<AdminController>();
    if (admin.snapshot.value == null && !admin.isLoading.value) {
      unawaited(admin.loadDashboard());
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = Get.find<AdminController>();
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(_titleForSection(_section)),
        actions: [
          Obx(
            () => IconButton(
              tooltip: UiStrings.t('refresh_workspace'),
              onPressed: admin.isLoading.value ? null : admin.loadDashboard,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
          IconButton(
            tooltip: UiStrings.t('logout'),
            onPressed: () => AppLogoutFlow.run(
              context,
              onLogout: Get.find<MainAuthController>().logout,
            ),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFCF5), AppTheme.surface],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 150,
              child: IgnorePointer(
                child: Opacity(opacity: 0.44, child: FarmHillsBackground()),
              ),
            ),
            Positioned.fill(
              child: Obx(() {
                final snapshot =
                    admin.snapshot.value ?? AdminDashboardSnapshot.empty();
                final initialLoading =
                    admin.isLoading.value && admin.snapshot.value == null;
                return Column(
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: admin.isLoading.value
                          ? const LinearProgressIndicator(
                              key: ValueKey('admin-loading'),
                              minHeight: 3,
                            )
                          : const SizedBox(
                              key: ValueKey('admin-idle'),
                              height: 3,
                            ),
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.fast,
                      child: admin.errorMessage.value.trim().isEmpty
                          ? const SizedBox.shrink()
                          : _AdminErrorBanner(
                              key: ValueKey(admin.errorMessage.value),
                              message: admin.errorMessage.value,
                              onRetry: admin.loadDashboard,
                            ),
                    ),
                    Expanded(
                      child: initialLoading
                          ? const _AdminLoadingSkeleton()
                          : AnimatedSwitcher(
                              duration: AppMotion.page,
                              switchInCurve: AppMotion.standard,
                              switchOutCurve: AppMotion.standard,
                              transitionBuilder: _adminSectionTransition,
                              child: KeyedSubtree(
                                key: ValueKey(_section),
                                child: _sectionBody(
                                  section: _section,
                                  snapshot: snapshot,
                                  admin: admin,
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _AdminBottomNavigation(
        selected: _section,
        onSelected: (section) {
          if (section == _section) return;
          setState(() => _section = section);
        },
      ),
    );
  }
}

Widget _adminSectionTransition(Widget child, Animation<double> animation) {
  final curved = CurvedAnimation(parent: animation, curve: AppMotion.standard);
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
  );
}

Widget _sectionBody({
  required _AdminSection section,
  required AdminDashboardSnapshot snapshot,
  required AdminController admin,
}) {
  switch (section) {
    case _AdminSection.overview:
      return _OverviewTab(snapshot: snapshot);
    case _AdminSection.farmers:
      return _FarmersTab(snapshot: snapshot);
    case _AdminSection.fpc:
      return _FpcTab(snapshot: snapshot);
    case _AdminSection.stakeholders:
      return _StakeholdersTab(snapshot: snapshot, admin: admin);
  }
}

String _titleForSection(_AdminSection section) {
  switch (section) {
    case _AdminSection.overview:
      return UiStrings.t('admin_overview');
    case _AdminSection.farmers:
      return UiStrings.t('farmer_records');
    case _AdminSection.fpc:
      return UiStrings.t('fpc_activity');
    case _AdminSection.stakeholders:
      return UiStrings.t('review_queue');
  }
}

class _AdminBottomNavigation extends StatelessWidget {
  final _AdminSection selected;
  final ValueChanged<_AdminSection> onSelected;

  const _AdminBottomNavigation({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0xFFDDE9D5)),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.greenDark.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      _AdminNavItemButton(
                        section: _AdminSection.overview,
                        icon: Icons.dashboard_outlined,
                        selectedIcon: Icons.dashboard_rounded,
                        label: 'Overview',
                        selected: selected == _AdminSection.overview,
                        onSelected: onSelected,
                      ),
                      _AdminNavItemButton(
                        section: _AdminSection.farmers,
                        icon: Icons.agriculture_outlined,
                        selectedIcon: Icons.agriculture_rounded,
                        label: 'Farmers',
                        selected: selected == _AdminSection.farmers,
                        onSelected: onSelected,
                      ),
                      _AdminNavItemButton(
                        section: _AdminSection.fpc,
                        icon: Icons.groups_2_outlined,
                        selectedIcon: Icons.groups_2_rounded,
                        label: 'FPC',
                        selected: selected == _AdminSection.fpc,
                        onSelected: onSelected,
                      ),
                      _AdminNavItemButton(
                        section: _AdminSection.stakeholders,
                        icon: Icons.fact_check_outlined,
                        selectedIcon: Icons.fact_check_rounded,
                        label: 'Review',
                        selected: selected == _AdminSection.stakeholders,
                        onSelected: onSelected,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminNavItemButton extends StatelessWidget {
  final _AdminSection section;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final ValueChanged<_AdminSection> onSelected;

  const _AdminNavItemButton({
    required this.section,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppTheme.textMuted;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: selected ? null : () => onSelected(section),
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? AppTheme.greenDark : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: selected
                  ? Border.all(color: AppTheme.gold.withValues(alpha: 0.28))
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: AppMotion.fast,
                  curve: AppMotion.emphasized,
                  scale: selected ? 1.1 : 1,
                  child: Icon(
                    selected ? selectedIcon : icon,
                    color: foreground,
                    size: selected ? 22 : 21,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                  child: Text(
                    UiStrings.fromEnglish(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final AdminDashboardSnapshot snapshot;

  const _OverviewTab({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricItem(
        'Farmers',
        snapshot.metrics['farmerProfiles'] ?? snapshot.farmers.length,
        Icons.agriculture_outlined,
      ),
      _MetricItem(
        'Linked farms',
        snapshot.metrics['linkedFarms'] ?? 0,
        Icons.map_outlined,
      ),
      _MetricItem(
        'FPC records',
        snapshot.metrics['fpcProcurements'] ?? snapshot.fpcRecords.length,
        Icons.inventory_2_outlined,
      ),
      _MetricItem(
        'Stakeholders',
        snapshot.metrics['stakeholderApplications'] ??
            snapshot.stakeholders.length,
        Icons.handshake_outlined,
      ),
      _MetricItem(
        'Pending',
        snapshot.metrics['pendingStakeholders'] ??
            _filterStakeholders(snapshot.stakeholders, 'pending').length,
        Icons.pending_actions_outlined,
      ),
      _MetricItem(
        'Paid',
        snapshot.metrics['paidStakeholders'] ??
            snapshot.stakeholders
                .where((item) => _isStakeholderPaid(item.paymentStatus))
                .length,
        Icons.verified_rounded,
      ),
    ];
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 760 ? 3 : 2;

    return RefreshIndicator(
      onRefresh: Get.find<AdminController>().loadDashboard,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            sliver: SliverList.list(
              children: [
                _AdminHeroPanel(
                  title: 'Production review console',
                  subtitle: UiStrings.t('production_review_console_desc'),
                  generatedAt: snapshot.generatedAt,
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: width < 380 ? 1.15 : 1.35,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _MetricCard(item: metrics[index]),
                childCount: metrics.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            sliver: SliverList.list(
              children: const [
                _AdminInfoPanel(
                  icon: Icons.fact_check_outlined,
                  title: 'Approval gate stays protected',
                  body:
                      'Stakeholder payments remain locked until admin approval is recorded.',
                ),
                SizedBox(height: 10),
                _AdminInfoPanel(
                  icon: Icons.history_rounded,
                  title: 'Review history is visible',
                  body:
                      'Every stakeholder decision keeps its status, note, actor and time in the review sheet.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FarmersTab extends StatelessWidget {
  final AdminDashboardSnapshot snapshot;

  const _FarmersTab({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: Get.find<AdminController>().loadDashboard,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            sliver: SliverToBoxAdapter(
              child: _AdminSectionHeader(
                icon: Icons.agriculture_outlined,
                title: 'Farmer applications and sync records',
                subtitle: UiStrings.f('farmer_and_linked_farm_counts', {
                  'farmers': snapshot.farmers.length,
                  'farms': snapshot.metrics['linkedFarms'] ?? 0,
                }),
              ),
            ),
          ),
          if (snapshot.farmers.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyAdminPanel(
                icon: Icons.agriculture_outlined,
                title: 'No farmer profiles found',
                body: 'Farmer records will appear here after signup or sync.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              sliver: SliverList.builder(
                itemCount: snapshot.farmers.length,
                itemBuilder: (context, index) {
                  final farmer = snapshot.farmers[index];
                  return _AdminRecordCard(
                    icon: Icons.agriculture_outlined,
                    title: farmer.farmerName,
                    status: farmer.status,
                    children: [
                      _AdminDetailRow('Farmer ID', farmer.farmerId),
                      _AdminDetailRow('Phone', farmer.phone),
                      _AdminDetailRow('Location', farmer.location),
                      _AdminDetailRow('Linked farms', '${farmer.farmCount}'),
                      _AdminDetailRow('Latest activity', farmer.latestActivity),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FpcTab extends StatelessWidget {
  final AdminDashboardSnapshot snapshot;

  const _FpcTab({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: Get.find<AdminController>().loadDashboard,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            sliver: SliverToBoxAdapter(
              child: _AdminSectionHeader(
                icon: Icons.groups_2_outlined,
                title: 'FPC activity',
                subtitle: UiStrings.f('fpc_record_count', {
                  'count': snapshot.fpcRecords.length,
                }),
              ),
            ),
          ),
          if (snapshot.fpcRecords.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyAdminPanel(
                icon: Icons.groups_2_outlined,
                title: 'No FPC records found',
                body: 'FPC grading and procurement records will appear here.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              sliver: SliverList.builder(
                itemCount: snapshot.fpcRecords.length,
                itemBuilder: (context, index) {
                  final record = snapshot.fpcRecords[index];
                  return _AdminRecordCard(
                    icon: record.type == 'Procurement'
                        ? Icons.inventory_2_outlined
                        : Icons.grain_rounded,
                    title: record.title,
                    status: record.status,
                    children: [
                      _AdminDetailRow('Workflow', record.type),
                      _AdminDetailRow('Details', record.subtitle),
                      _AdminDetailRow('Value', record.amount),
                      _AdminDetailRow('Record ID', record.id),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StakeholdersTab extends StatefulWidget {
  final AdminDashboardSnapshot snapshot;
  final AdminController admin;

  const _StakeholdersTab({required this.snapshot, required this.admin});

  @override
  State<_StakeholdersTab> createState() => _StakeholdersTabState();
}

class _StakeholdersTabState extends State<_StakeholdersTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final filter = widget.admin.stakeholderFilter.value;
      final allItems = _sortStakeholderQueue(widget.snapshot.stakeholders);
      final statusItems = _filterStakeholders(allItems, filter);
      final visibleItems = _query.trim().isEmpty
          ? statusItems
          : statusItems
                .where((item) => _matchesStakeholderSearch(item, _query))
                .toList(growable: false);
      final shortcutItem = _firstReviewableStakeholder(allItems);

      return RefreshIndicator(
        onRefresh: widget.admin.loadDashboard,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              sliver: SliverList.list(
                children: [
                  _StakeholderQueueHero(items: allItems),
                  const SizedBox(height: 10),
                  if (shortcutItem != null) ...[
                    _StakeholderReviewShortcut(
                      item: shortcutItem,
                      admin: widget.admin,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _StakeholderSearchField(
                    controller: _searchCtrl,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: _query.trim().isEmpty
                        ? null
                        : () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                  ),
                  const SizedBox(height: 10),
                  _StakeholderFilterBar(
                    selected: filter,
                    items: allItems,
                    onSelected: widget.admin.setStakeholderFilter,
                  ),
                ],
              ),
            ),
            if (allItems.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyAdminPanel(
                  icon: Icons.handshake_outlined,
                  title: 'No stakeholder applications found',
                  body:
                      'Applications submitted by farmer stakeholders appear here.',
                ),
              )
            else if (visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyAdminPanel(
                  icon: Icons.filter_alt_off_outlined,
                  title: _query.trim().isEmpty
                      ? 'No ${_filterLabel(filter).toLowerCase()} applications'
                      : 'No matching applications',
                  body: _query.trim().isEmpty
                      ? 'Change the filter or refresh the admin workspace.'
                      : 'Clear search or try farmer name, phone, ID or PAN.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                sliver: SliverList.builder(
                  itemCount: visibleItems.length,
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    return _StakeholderAdminCard(
                      key: ValueKey(item.id),
                      item: item,
                      admin: widget.admin,
                    );
                  },
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _StakeholderAdminCard extends StatelessWidget {
  final AdminStakeholderRecord item;
  final AdminController admin;

  const _StakeholderAdminCard({
    super.key,
    required this.item,
    required this.admin,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = item.status.trim().toLowerCase();
    final title = item.farmerFullName.trim().isEmpty
        ? item.farmerName
        : item.farmerFullName;
    return _AdminRecordCard(
      icon: Icons.handshake_outlined,
      title: title,
      status: item.status,
      onTap: () =>
          _openStakeholderReviewDetails(context, item: item, admin: admin),
      trailing: normalizedStatus == 'submitted'
          ? Obx(
              () => IconButton.filledTonal(
                tooltip: UiStrings.t('mark_under_review'),
                onPressed: admin.isReviewing.value
                    ? null
                    : () => _openStakeholderReviewAction(
                        context,
                        item: item,
                        admin: admin,
                        status: 'under_review',
                        label: 'Mark under review',
                      ),
                icon: const Icon(Icons.pending_actions_outlined),
              ),
            )
          : null,
      children: [
        _AdminDetailRow('Farmer ID', item.farmerId),
        _AdminDetailRow('Phone', item.farmerMobileNumber),
        _AdminDetailRow(
          'Amount / shares',
          'Rs ${item.selectedAmount.toStringAsFixed(0)} / ${item.estimatedShares}',
        ),
        _AdminDetailRow('Payment', item.paymentStatus),
        _StakeholderProofSummary(item: item),
        if (item.adminNote.trim().isNotEmpty)
          _AdminDetailRow('Admin note', item.adminNote),
        if (item.timeline.isNotEmpty)
          _AdminDetailRow('Latest update', item.timeline.last.title),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openStakeholderReviewDetails(
              context,
              item: item,
              admin: admin,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(UiStrings.t('open_full_review')),
          ),
        ),
      ],
    );
  }
}

class _StakeholderQueueHero extends StatelessWidget {
  final List<AdminStakeholderRecord> items;

  const _StakeholderQueueHero({required this.items});

  @override
  Widget build(BuildContext context) {
    final submitted = _countStakeholders(items, 'submitted');
    final review = _countStakeholders(items, 'under_review');
    final approved = _countStakeholders(items, 'approved');
    final paid = items
        .where((item) => _isStakeholderPaid(item.paymentStatus))
        .length;
    return _AdminSectionHeader(
      icon: Icons.fact_check_outlined,
      title: 'Stakeholder approval queue',
      subtitle: UiStrings.f('stakeholder_queue_counts', {
        'submitted': submitted,
        'review': review,
        'approved': approved,
        'paid': paid,
      }),
    );
  }
}

class _StakeholderReviewShortcut extends StatelessWidget {
  final AdminStakeholderRecord item;
  final AdminController admin;

  const _StakeholderReviewShortcut({required this.item, required this.admin});

  @override
  Widget build(BuildContext context) {
    final title = item.farmerFullName.trim().isEmpty
        ? item.farmerName
        : item.farmerFullName;
    void openReview() =>
        _openStakeholderReviewDetails(context, item: item, admin: admin);

    return GestureDetector(
      key: const ValueKey('admin-open-next-stakeholder-review'),
      behavior: HitTestBehavior.opaque,
      onTap: openReview,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _adminCardDecoration(tint: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.pending_actions_outlined,
                  color: AppTheme.greenDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        UiStrings.f('amount_and_shares', {
                          'amount': LocaleText.number(
                            item.selectedAmount,
                            fractionDigits: 0,
                          ),
                          'shares': item.estimatedShares,
                        }),
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: openReview,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(UiStrings.t('open_full_review')),
            ),
          ],
        ),
      ),
    );
  }
}

class _StakeholderSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const _StakeholderSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: onClear == null
            ? null
            : IconButton(
                tooltip: UiStrings.t('clear_search'),
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
        labelText: UiStrings.t('search_stakeholder_applications'),
        hintText: UiStrings.t('search_stakeholder_hint'),
      ),
    );
  }
}

class _StakeholderFilterBar extends StatelessWidget {
  final String selected;
  final List<AdminStakeholderRecord> items;
  final ValueChanged<String> onSelected;

  const _StakeholderFilterBar({
    required this.selected,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _stakeholderFilters
            .map(
              (filter) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected == filter.value,
                  label: Text(
                    '${filter.label} ${_stakeholderFilterCount(items, filter.value)}',
                  ),
                  onSelected: (_) {
                    if (selected != filter.value) onSelected(filter.value);
                  },
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _StakeholderProofSummary extends StatelessWidget {
  final AdminStakeholderRecord item;

  const _StakeholderProofSummary({required this.item});

  @override
  Widget build(BuildContext context) {
    final documents = [
      if (item.hasPanDocument) 'PAN',
      if (item.hasLandRecordDocument) '7/12',
      if (item.hasPassbookDocument) 'Passbook',
      if (item.farmerSignaturePath.trim().isNotEmpty) 'Farmer sign',
      if (item.nomineeSignaturePath.trim().isNotEmpty) 'Nominee sign',
    ];
    return _AdminDetailRow(
      'Proofs',
      [
        item.panSource,
        item.landRecordSource,
        item.bankSource,
        documents.isEmpty ? 'No uploads' : documents.join(', '),
      ].where((value) => value.trim().isNotEmpty).join(' • '),
    );
  }
}

class _StakeholderReviewSheet extends StatelessWidget {
  final AdminStakeholderRecord item;
  final AdminController admin;

  const _StakeholderReviewSheet({required this.item, required this.admin});

  @override
  Widget build(BuildContext context) {
    final title = item.farmerFullName.trim().isEmpty
        ? item.farmerName
        : item.farmerFullName;
    final location = [
      item.farmerVillage,
      item.farmerTaluka,
      item.farmerDistrict,
    ].where((part) => part.trim().isNotEmpty).join(', ');
    final bank = [
      item.accountHolderName,
      item.bankName,
      item.ifscCode,
    ].where((part) => part.trim().isNotEmpty).join(' • ');
    final nominee = item.nomineeCount == 2
        ? '${item.nomineeName} (${item.nomineeMobileNumber})\n${item.nominee2Name} (${item.nominee2MobileNumber})'
        : '${item.nomineeName} (${item.nomineeMobileNumber})';

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.95,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: AppTheme.greenDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
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
                          UiStrings.t('farmer_stakeholder_request'),
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(status: item.status),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                children: [
                  _AdminReviewSection(
                    title: 'Application',
                    children: [
                      _AdminDetailRow('Application ID', item.id),
                      _AdminDetailRow('Status', item.status),
                      _AdminDetailRow('Payment', item.paymentStatus),
                      _AdminDetailRow(
                        'Amount / shares',
                        'Rs ${item.selectedAmount.toStringAsFixed(0)} / ${item.estimatedShares}',
                      ),
                      _AdminDetailRow(
                        'Submitted',
                        _dateTimeLabel(item.submittedAt),
                      ),
                      _AdminDetailRow(
                        'Reviewed',
                        _dateTimeLabel(item.reviewedAt),
                      ),
                    ],
                  ),
                  _AdminReviewSection(
                    title: 'Farmer identity',
                    children: [
                      _AdminDetailRow('Farmer ID', item.farmerId),
                      _AdminDetailRow('Phone', item.farmerMobileNumber),
                      _AdminDetailRow('Father', item.farmerFatherName),
                      _AdminDetailRow('Location', location),
                      _AdminDetailRow('Land acres', item.farmerTotalLandAcres),
                    ],
                  ),
                  _AdminReviewSection(
                    title: 'KYC and land record',
                    children: [
                      _AdminDetailRow('PAN', item.panNumber),
                      _AdminDetailRow('PAN source', item.panSource),
                      _AdminDetailRow('7/12 source', item.landRecordSource),
                      _AdminDetailRow('7/12 details', item.landRecordDetails),
                    ],
                  ),
                  _AdminReviewSection(
                    title: 'Bank and nominee',
                    children: [
                      _AdminDetailRow('Bank', bank),
                      _AdminDetailRow('Bank source', item.bankSource),
                      _AdminDetailRow('Nominee', nominee),
                      _AdminDetailRow(
                        'Transfer ref',
                        item.bankTransferReference,
                      ),
                    ],
                  ),
                  _AdminReviewSection(
                    title: 'Uploaded proof documents',
                    children: [
                      _StakeholderDocumentActions(item: item, admin: admin),
                    ],
                  ),
                  _AdminReviewSection(
                    title: 'Admin record',
                    children: [
                      if (item.adminNote.trim().isNotEmpty)
                        _AdminDetailRow('Admin note', item.adminNote),
                      _StakeholderTimelineList(events: item.timeline),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
              child: _StakeholderReviewActions(item: item, admin: admin),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminReviewSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AdminReviewSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: _adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UiStrings.fromEnglish(title),
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _StakeholderDocumentActions extends StatelessWidget {
  final AdminStakeholderRecord item;
  final AdminController admin;

  const _StakeholderDocumentActions({required this.item, required this.admin});

  @override
  Widget build(BuildContext context) {
    final docs = [
      _StakeholderDocumentData('PAN', item.panDocumentPath),
      _StakeholderDocumentData('7/12', item.landRecordDocumentPath),
      _StakeholderDocumentData('Passbook', item.passbookDocumentPath),
      _StakeholderDocumentData('Farmer signature', item.farmerSignaturePath),
      _StakeholderDocumentData('Nominee signature', item.nomineeSignaturePath),
      if (item.nomineeCount == 2)
        _StakeholderDocumentData(
          'Nominee 2 signature',
          item.nominee2SignaturePath,
        ),
      _StakeholderDocumentData('Transfer proof', item.bankTransferProofPath),
    ].where((doc) => doc.path.trim().isNotEmpty).toList(growable: false);
    if (docs.isEmpty) {
      return Text(
        UiStrings.t('no_uploaded_documents_for_request'),
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: docs
          .map(
            (doc) => OutlinedButton.icon(
              onPressed: () => _openStakeholderDocument(
                context,
                admin: admin,
                documentPath: doc.path,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(UiStrings.fromEnglish(doc.label)),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StakeholderTimelineList extends StatelessWidget {
  final List<AdminStakeholderTimelineEntry> events;

  const _StakeholderTimelineList({required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Text(
        UiStrings.t('no_admin_history'),
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Column(
      children: events.reversed
          .map((event) => _TimelineReviewRow(event: event))
          .toList(growable: false),
    );
  }
}

class _TimelineReviewRow extends StatelessWidget {
  final AdminStakeholderTimelineEntry event;

  const _TimelineReviewRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final note = event.note.trim();
    final when = _dateTimeLabel(event.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_rounded, color: AppTheme.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    note,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
                if (when.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (event.actorRole.trim().isNotEmpty) event.actorRole,
                      when,
                    ].join(' • '),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StakeholderReviewActions extends StatelessWidget {
  final AdminStakeholderRecord item;
  final AdminController admin;

  const _StakeholderReviewActions({required this.item, required this.admin});

  @override
  Widget build(BuildContext context) {
    final status = item.status.trim().toLowerCase();
    return Obx(
      () => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: admin.isReviewing.value || status == 'under_review'
                ? null
                : () => _openStakeholderReviewAction(
                    context,
                    item: item,
                    admin: admin,
                    status: 'under_review',
                    label: 'Mark under review',
                  ),
            icon: const Icon(Icons.pending_actions_outlined),
            label: Text(UiStrings.t('review')),
          ),
          FilledButton.icon(
            onPressed: admin.isReviewing.value || status == 'approved'
                ? null
                : () => _openStakeholderReviewAction(
                    context,
                    item: item,
                    admin: admin,
                    status: 'approved',
                    label: 'Approve application',
                  ),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(UiStrings.t('approve')),
          ),
          OutlinedButton.icon(
            onPressed: admin.isReviewing.value || status == 'rejected'
                ? null
                : () => _openStakeholderReviewAction(
                    context,
                    item: item,
                    admin: admin,
                    status: 'rejected',
                    label: 'Reject application',
                  ),
            icon: const Icon(Icons.cancel_outlined),
            label: Text(UiStrings.t('reject')),
          ),
        ],
      ),
    );
  }
}

class _StakeholderFilterOption {
  final String value;
  final String label;

  const _StakeholderFilterOption(this.value, this.label);
}

class _StakeholderDocumentData {
  final String label;
  final String path;

  const _StakeholderDocumentData(this.label, this.path);
}

const _stakeholderFilters = [
  _StakeholderFilterOption('pending', 'Pending'),
  _StakeholderFilterOption('submitted', 'Submitted'),
  _StakeholderFilterOption('under_review', 'Under review'),
  _StakeholderFilterOption('approved', 'Approved'),
  _StakeholderFilterOption('rejected', 'Rejected'),
  _StakeholderFilterOption('paid', 'Paid'),
  _StakeholderFilterOption('all', 'All'),
];

void _openStakeholderReviewDetails(
  BuildContext context, {
  required AdminStakeholderRecord item,
  required AdminController admin,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _StakeholderReviewSheet(item: item, admin: admin),
  );
}

Future<void> _openStakeholderReviewAction(
  BuildContext context, {
  required AdminStakeholderRecord item,
  required AdminController admin,
  required String status,
  required String label,
}) async {
  final noteCtrl = TextEditingController(text: item.adminNote);
  final requiresReason = status == 'rejected';
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      String? noteError;
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(18, 6, 18, 18 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: requiresReason
                          ? 'Rejection reason'
                          : 'Admin note optional',
                      hintText: requiresReason
                          ? 'Explain why this request is rejected'
                          : 'Add review reason or next step',
                      errorText: noteError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Obx(
                    () => FilledButton.icon(
                      onPressed: admin.isReviewing.value
                          ? null
                          : () async {
                              final note = noteCtrl.text.trim();
                              if (requiresReason && note.length < 5) {
                                setModalState(() {
                                  noteError =
                                      'Add a clear rejection reason before rejecting.';
                                });
                                return;
                              }
                              final saved = await admin.reviewStakeholder(
                                applicationId: item.id,
                                status: status,
                                note: note,
                              );
                              if (context.mounted) {
                                Navigator.pop(context, saved);
                              }
                            },
                      icon: admin.isReviewing.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(UiStrings.fromEnglish(label)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  noteCtrl.dispose();
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          UiStrings.f('stakeholder_application_updated', {
            'status': UiStrings.option(status),
          }),
        ),
      ),
    );
  } else if (admin.errorMessage.value.trim().isNotEmpty && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(admin.errorMessage.value)));
  }
}

Future<void> _openStakeholderDocument(
  BuildContext context, {
  required AdminController admin,
  required String documentPath,
}) async {
  final url = await admin.stakeholderDocumentUrl(documentPath);
  if (!context.mounted) return;
  if (url == null || url.trim().isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(admin.errorMessage.value)));
    return;
  }
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(UiStrings.t('could_not_open_stakeholder_document')),
      ),
    );
  }
}

List<AdminStakeholderRecord> _sortStakeholderQueue(
  List<AdminStakeholderRecord> items,
) {
  final sorted = List<AdminStakeholderRecord>.from(items);
  sorted.sort((a, b) {
    final statusOrder = _stakeholderStatusPriority(
      a.status,
    ).compareTo(_stakeholderStatusPriority(b.status));
    if (statusOrder != 0) return statusOrder;
    final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });
  return sorted;
}

List<AdminStakeholderRecord> _filterStakeholders(
  List<AdminStakeholderRecord> items,
  String filter,
) {
  final selected = filter.trim().toLowerCase();
  if (selected == 'all') return items;
  if (selected == 'pending') {
    return items
        .where(
          (item) => const {
            'submitted',
            'under_review',
          }.contains(item.status.trim().toLowerCase()),
        )
        .toList(growable: false);
  }
  if (selected == 'paid') {
    return items
        .where((item) => _isStakeholderPaid(item.paymentStatus))
        .toList(growable: false);
  }
  return items
      .where((item) => item.status.trim().toLowerCase() == selected)
      .toList(growable: false);
}

AdminStakeholderRecord? _firstReviewableStakeholder(
  List<AdminStakeholderRecord> items,
) {
  if (items.isEmpty) return null;
  final pending = _filterStakeholders(items, 'pending');
  return pending.isEmpty ? items.first : pending.first;
}

bool _matchesStakeholderSearch(AdminStakeholderRecord item, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final haystack = [
    item.id,
    item.farmerId,
    item.farmerName,
    item.farmerFullName,
    item.farmerPhone,
    item.farmerMobileNumber,
    item.panNumber,
    item.farmerVillage,
    item.farmerTaluka,
    item.farmerDistrict,
    item.paymentStatus,
    item.status,
  ].join(' ').toLowerCase();
  return haystack.contains(needle);
}

int _stakeholderStatusPriority(String status) {
  switch (status.trim().toLowerCase()) {
    case 'submitted':
      return 0;
    case 'under_review':
      return 1;
    case 'approved':
      return 2;
    case 'rejected':
      return 3;
  }
  return 4;
}

bool _isStakeholderPaid(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized == 'gateway_verified' ||
      normalized == 'bank_transfer_submitted';
}

int _countStakeholders(List<AdminStakeholderRecord> items, String status) {
  return items
      .where((item) => item.status.trim().toLowerCase() == status)
      .length;
}

int _stakeholderFilterCount(List<AdminStakeholderRecord> items, String filter) {
  return _filterStakeholders(items, filter).length;
}

String _filterLabel(String value) {
  return _stakeholderFilters
      .firstWhere(
        (filter) => filter.value == value,
        orElse: () => const _StakeholderFilterOption('pending', 'Pending'),
      )
      .label;
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  return '${LocaleText.date(local)} ${LocaleText.time(local)}';
}

class _MetricItem {
  final String label;
  final int value;
  final IconData icon;

  const _MetricItem(this.label, this.value, this.icon);
}

class _MetricCard extends StatelessWidget {
  final _MetricItem item;

  const _MetricCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _adminCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.greenPale,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, color: AppTheme.greenDark),
            ),
            const Spacer(),
            Text(
              LocaleText.number(item.value),
              style: const TextStyle(
                color: AppTheme.textDark,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              UiStrings.fromEnglish(item.label),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminHeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final DateTime? generatedAt;

  const _AdminHeroPanel({
    required this.title,
    required this.subtitle,
    required this.generatedAt,
  });

  @override
  Widget build(BuildContext context) {
    final generatedLabel = _dateTimeLabel(generatedAt);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminCardDecoration(tint: const Color(0xFFF7FBF2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.greenDark,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(title),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  UiStrings.fromEnglish(subtitle),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (generatedLabel.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    UiStrings.f('last_synced_value', {
                      'value': generatedLabel,
                    }),
                    style: const TextStyle(
                      color: AppTheme.greenDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AdminSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _adminCardDecoration(tint: const Color(0xFFF7FBF2)),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppTheme.greenDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(title),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  UiStrings.fromEnglish(subtitle),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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

class _AdminInfoPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _AdminInfoPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _adminCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.greenPale,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppTheme.greenDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UiStrings.fromEnglish(title),
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  UiStrings.fromEnglish(body),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
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

class _AdminRecordCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String status;
  final Widget? trailing;
  final VoidCallback? onTap;
  final List<Widget> children;

  const _AdminRecordCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.children,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.greenPale,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppTheme.greenDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.trim().isEmpty ? '-' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: status),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}

class _AdminDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _AdminDetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              UiStrings.fromEnglish(label),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textDark,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().isEmpty
        ? 'pending'
        : status.trim().toLowerCase();
    final approved = normalized == 'approved' || normalized == 'active';
    final rejected = normalized == 'rejected' || normalized == 'blocked';
    final paid = _isStakeholderPaid(normalized);
    final color = approved || paid
        ? AppTheme.greenDark
        : rejected
        ? const Color(0xFFB91C1C)
        : const Color(0xFFB45309);
    return Container(
      constraints: const BoxConstraints(maxWidth: 116),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        UiStrings.option(normalized.replaceAll('_', ' ')),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AdminErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _AdminErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              UiStrings.fromEnglish(message),
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(UiStrings.t('retry')),
          ),
        ],
      ),
    );
  }
}

class _EmptyAdminPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyAdminPanel({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: _adminCardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.greenDark, size: 42),
              const SizedBox(height: 12),
              Text(
                UiStrings.fromEnglish(title),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                UiStrings.fromEnglish(body),
                textAlign: TextAlign.center,
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
    );
  }
}

class _AdminLoadingSkeleton extends StatelessWidget {
  const _AdminLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => Container(
        height: index == 0 ? 112 : 86,
        decoration: _adminCardDecoration(tint: const Color(0xFFF8FAF5)),
        padding: const EdgeInsets.all(14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: index == 0 ? 0.72 : 0.52,
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFE6EDE1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _adminCardDecoration({Color tint = Colors.white}) {
  return BoxDecoration(
    color: tint,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFE3EADD)),
    boxShadow: [
      BoxShadow(
        color: AppTheme.greenDark.withValues(alpha: 0.07),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ],
  );
}
