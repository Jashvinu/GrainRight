import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_logout_flow.dart';
import '../controllers/main_auth_controller.dart';
import '../models/fpc_account_identity.dart';

enum FpcNavTab {
  home,
  farmerScan,
  marketplace,
  receiver,
  grading,
  review,
  profile,
  settings,
  activity,
  support,
}

class FpcBottomNavBar extends StatelessWidget {
  final FpcNavTab current;

  const FpcBottomNavBar({super.key, required this.current});

  static const Map<String, String> gradingArgs = {
    'mode': 'fpc',
    'farmerId': 'FPC-WALK-IN',
    'farmerName': 'Walk-in customer',
    'fpcCustomerId': 'FPC-WALK-IN',
    'fpcCustomerName': 'Walk-in customer',
    'farmId': 'FPC-COUNTER',
    'farmName': 'FPC Procurement Lot',
    'crop': 'Finger Millet',
    'variety': 'Local',
    'village': 'FPC collection center',
    'product': 'Grain lot',
  };

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFDDE8D4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 72,
                child: Row(
                  children: [
                    _NavItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Home',
                      selected: current == FpcNavTab.home,
                      onTap: () => _go(FpcNavTab.home),
                    ),
                    _NavItem(
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Farmers',
                      selected: current == FpcNavTab.farmerScan,
                      onTap: () => _go(FpcNavTab.farmerScan),
                    ),
                    _NavItem(
                      icon: Icons.storefront_rounded,
                      label: 'Market',
                      selected: current == FpcNavTab.marketplace,
                      onTap: () => _go(FpcNavTab.marketplace),
                    ),
                    _NavItem(
                      icon: Icons.assignment_turned_in_outlined,
                      label: 'Receiver',
                      selected: current == FpcNavTab.receiver,
                      onTap: () => _go(FpcNavTab.receiver),
                    ),
                    _NavItem(
                      icon: Icons.grain_rounded,
                      label: 'Grading',
                      selected: current == FpcNavTab.grading,
                      onTap: () => _go(FpcNavTab.grading),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _go(FpcNavTab tab) {
    if (tab == current) return;
    switch (tab) {
      case FpcNavTab.home:
        Get.offNamed('/fpo');
        return;
      case FpcNavTab.farmerScan:
        Get.offNamed('/fpo/scan-farmer');
        return;
      case FpcNavTab.marketplace:
        Get.offNamed('/fpo/marketplace');
        return;
      case FpcNavTab.receiver:
        Get.offNamed('/fpo/receiver');
        return;
      case FpcNavTab.grading:
        Get.offNamed('/fpo/grain-grading', arguments: gradingArgs);
        return;
      case FpcNavTab.review:
        Get.offNamed('/fpo/grading-review');
        return;
      case FpcNavTab.profile:
        Get.offNamed('/fpo/profile');
        return;
      case FpcNavTab.settings:
        Get.offNamed('/fpo/settings');
        return;
      case FpcNavTab.activity:
        Get.offNamed('/fpo/activity');
        return;
      case FpcNavTab.support:
        Get.offNamed('/fpo/help');
        return;
    }
  }
}

class FpcWorkspaceScaffold extends StatelessWidget {
  final FpcNavTab current;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool extendBody;
  final bool showBottomNav;

  const FpcWorkspaceScaffold({
    super.key,
    required this.current,
    required this.title,
    required this.body,
    this.actions = const [],
    this.extendBody = true,
    this.showBottomNav = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        return Scaffold(
          backgroundColor: AppTheme.surface,
          extendBody: extendBody && !wide,
          drawer: wide ? null : FpcWorkspaceDrawer(current: current),
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: wide
                ? null
                : Builder(
                    builder: (context) => IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).openAppDrawerTooltip,
                      onPressed: () => Scaffold.of(context).openDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ),
            title: Text(UiStrings.fromEnglish(title)),
            actions: actions,
          ),
          bottomNavigationBar: showBottomNav && !wide
              ? FpcBottomNavBar(current: current)
              : null,
          body: wide
              ? Row(
                  children: [
                    FpcSideNavigation(current: current),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        );
      },
    );
  }
}

class FpcWorkspaceDrawer extends StatelessWidget {
  final FpcNavTab current;

  const FpcWorkspaceDrawer({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: FpcSideNavigation(current: current, closeDrawerOnTap: true),
    );
  }
}

class FpcSideNavigation extends StatelessWidget {
  final FpcNavTab current;
  final bool closeDrawerOnTap;

  const FpcSideNavigation({
    super.key,
    required this.current,
    this.closeDrawerOnTap = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: 282,
        child: Material(
          color: Colors.white,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            children: [
              const _FpcAccountHeader(),
              const SizedBox(height: 18),
              _FpcNavGroup(
                label: 'Workspace',
                current: current,
                closeDrawerOnTap: closeDrawerOnTap,
                items: const [
                  _FpcNavEntry(
                    tab: FpcNavTab.home,
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    subtitle: 'FPC overview',
                    route: '/fpo',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.farmerScan,
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Farmer verification',
                    subtitle: 'Scan farmer profile QR',
                    route: '/fpo/scan-farmer',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.marketplace,
                    icon: Icons.storefront_rounded,
                    title: 'Marketplace',
                    subtitle: 'Buyer listings',
                    route: '/fpo/marketplace',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.receiver,
                    icon: Icons.assignment_turned_in_outlined,
                    title: 'Receiver',
                    subtitle: 'Received lot ledger',
                    route: '/fpo/receiver',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.grading,
                    icon: Icons.grain_rounded,
                    title: 'Grain grading',
                    subtitle: 'Counter grading flow',
                    route: '/fpo/grain-grading',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.review,
                    icon: Icons.fact_check_outlined,
                    title: 'Review queue',
                    subtitle: 'Approve grading jobs',
                    route: '/fpo/grading-review',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _FpcNavGroup(
                label: 'Account',
                current: current,
                closeDrawerOnTap: closeDrawerOnTap,
                items: const [
                  _FpcNavEntry(
                    tab: FpcNavTab.profile,
                    icon: Icons.badge_outlined,
                    title: 'FPC profile',
                    subtitle: 'Account and role details',
                    route: '/fpo/profile',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.settings,
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    subtitle: 'Workspace preferences',
                    route: '/fpo/settings',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.activity,
                    icon: Icons.timeline_rounded,
                    title: 'Activity',
                    subtitle: 'Operational checklist',
                    route: '/fpo/activity',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.support,
                    icon: Icons.support_agent_rounded,
                    title: 'Help',
                    subtitle: 'Support and SOPs',
                    route: '/fpo/help',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _FpcLogoutTile(closeDrawerOnTap: closeDrawerOnTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _FpcAccountHeader extends StatelessWidget {
  const _FpcAccountHeader();

  @override
  Widget build(BuildContext context) {
    final account = FpcAccountIdentity.current();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            account.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.groups_2_rounded,
                  color: AppTheme.greenDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName.isNotEmpty
                          ? account.displayName
                          : 'FPC account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFDDE8D4)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  '${account.roleLabel} access',
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FpcNavGroup extends StatelessWidget {
  final String label;
  final List<_FpcNavEntry> items;
  final FpcNavTab current;
  final bool closeDrawerOnTap;

  const _FpcNavGroup({
    required this.label,
    required this.items,
    required this.current,
    required this.closeDrawerOnTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Text(
            UiStrings.fromEnglish(label).toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ...items.map(
          (item) => _FpcSideNavTile(
            entry: item,
            selected: current == item.tab,
            closeDrawerOnTap: closeDrawerOnTap,
          ),
        ),
      ],
    );
  }
}

class _FpcNavEntry {
  final FpcNavTab tab;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _FpcNavEntry({
    required this.tab,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _FpcSideNavTile extends StatelessWidget {
  final _FpcNavEntry entry;
  final bool selected;
  final bool closeDrawerOnTap;

  const _FpcSideNavTile({
    required this.entry,
    required this.selected,
    required this.closeDrawerOnTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppTheme.greenPale : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: selected
              ? null
              : () {
                  if (closeDrawerOnTap) Get.back();
                  _navigate(entry);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  color: selected ? AppTheme.greenDark : AppTheme.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UiStrings.fromEnglish(entry.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? AppTheme.greenDark
                              : AppTheme.textDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        UiStrings.fromEnglish(entry.subtitle),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(_FpcNavEntry entry) {
    if (entry.tab == FpcNavTab.grading) {
      Get.offNamed(entry.route, arguments: FpcBottomNavBar.gradingArgs);
      return;
    }
    Get.offNamed(entry.route);
  }
}

class _FpcLogoutTile extends StatelessWidget {
  final bool closeDrawerOnTap;

  const _FpcLogoutTile({required this.closeDrawerOnTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        if (closeDrawerOnTap) Get.back();
        AppLogoutFlow.run(
          context,
          onLogout: Get.find<MainAuthController>().logout,
        );
      },
      icon: const Icon(Icons.logout_rounded),
      label: Text(UiStrings.t('sign_out')),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              decoration: BoxDecoration(
                color: selected ? AppTheme.greenPale : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SizedBox(
                height: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 23,
                      color: selected ? AppTheme.greenDark : AppTheme.textMuted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UiStrings.fromEnglish(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppTheme.greenDark
                            : AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
