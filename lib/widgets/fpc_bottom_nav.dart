import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:kalsubai_farms/core/localization/ui_strings.dart';
import 'package:kalsubai_farms/core/theme/app_motion.dart';
import 'package:kalsubai_farms/core/theme/app_theme.dart';
import 'package:kalsubai_farms/core/widgets/app_logout_flow.dart';
import 'package:kalsubai_farms/core/widgets/language_selector_button.dart';
import '../controllers/language_controller.dart';
import '../controllers/main_auth_controller.dart';
import '../models/fpc_account_identity.dart';
import '../models/fpc_operating_models.dart';
import '../services/fpc_notification_realtime_service.dart';
import '../services/fpc_operating_service.dart';

enum FpcNavTab {
  home,
  operations,
  seeds,
  team,
  qrHub,
  farmerScan,
  marketplace,
  receiver,
  grading,
  review,
  analytics,
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
      case FpcNavTab.operations:
        Get.offNamed('/fpo/operations');
        return;
      case FpcNavTab.seeds:
        Get.offNamed('/fpo/seeds');
        return;
      case FpcNavTab.team:
        Get.offNamed('/fpo/team');
        return;
      case FpcNavTab.qrHub:
        Get.offNamed('/fpo/qr');
        return;
      case FpcNavTab.farmerScan:
        Get.offNamed('/fpo/farmers');
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
      case FpcNavTab.analytics:
        Get.offNamed('/fpo/analytics');
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

class FpcWorkspaceScaffold extends StatefulWidget {
  final FpcNavTab current;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool extendBody;
  final bool showBottomNav;
  final bool showQrAction;
  final bool allowSetupGate;

  const FpcWorkspaceScaffold({
    super.key,
    required this.current,
    required this.title,
    required this.body,
    this.actions = const [],
    this.extendBody = true,
    this.showBottomNav = true,
    this.showQrAction = true,
    this.allowSetupGate = true,
  });

  @override
  State<FpcWorkspaceScaffold> createState() => _FpcWorkspaceScaffoldState();
}

class _FpcWorkspaceScaffoldState extends State<FpcWorkspaceScaffold> {
  final _notificationService = FpcOperatingService();
  final _realtimeService = FpcNotificationRealtimeService();
  List<Map<String, dynamic>> _notifications = const [];
  FpcSessionContext? _session;
  bool _notificationsLoading = false;
  bool _popupVisible = false;

  int get _unreadCount =>
      _notifications.where((row) => row['read_at'] == null).length;

  String _notificationText(Object? value, {String fallback = ''}) {
    final text = '${value ?? fallback}'.trim();
    return UiStrings.fromEnglish(text);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSession());
    unawaited(_loadNotifications());
    unawaited(
      _realtimeService.start(onNotification: _handleRealtimeNotification),
    );
  }

  @override
  void dispose() {
    unawaited(_realtimeService.stop());
    super.dispose();
  }

  Future<void> _loadSession() async {
    try {
      final session = await _notificationService.loadSessionContext();
      if (!mounted) return;
      setState(() => _session = session);
    } catch (_) {
      // Route middleware and page services still enforce access. The shell
      // does not hide page content when the optional readiness check fails.
    }
  }

  Future<void> _loadNotifications() async {
    if (mounted) setState(() => _notificationsLoading = true);
    try {
      final rows = await _notificationService.loadNotifications();
      if (mounted) setState(() => _notifications = rows);
    } catch (_) {
      // The shell remains usable when notification sync is temporarily down.
    } finally {
      if (mounted) setState(() => _notificationsLoading = false);
    }
  }

  Future<void> _handleRealtimeNotification(
    Map<String, dynamic> notification,
  ) async {
    if (!mounted) return;
    setState(() {
      _notifications = [
        notification,
        ..._notifications.where((row) => row['id'] != notification['id']),
      ];
    });
    if (_popupVisible) return;
    _popupVisible = true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.notifications_active_rounded,
          color: AppTheme.greenDark,
        ),
        title: Text(
          _notificationText(notification['title'], fallback: 'FPC update'),
        ),
        content: Text(_notificationText(notification['body'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UiStrings.fromEnglish('Later')),
          ),
          FilledButton(
            onPressed: () async {
              await _markRead(notification);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(UiStrings.fromEnglish('Mark read')),
          ),
        ],
      ),
    );
    _popupVisible = false;
  }

  Future<void> _markRead(Map<String, dynamic> notification) async {
    final id = '${notification['id'] ?? ''}'.trim();
    if (id.isEmpty || notification['read_at'] != null) return;
    await _notificationService.markNotificationRead(id);
    if (!mounted) return;
    final now = DateTime.now().toUtc().toIso8601String();
    setState(() {
      _notifications = [
        for (final row in _notifications)
          if (row['id'] == notification['id'])
            {...row, 'read_at': now}
          else
            row,
      ];
    });
  }

  Future<void> _showNotificationInbox() async {
    await _loadNotifications();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.notifications_rounded),
            const SizedBox(width: 8),
            Expanded(child: Text(UiStrings.fromEnglish('FPC notifications'))),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: _notificationsLoading
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
              ? Text(UiStrings.fromEnglish('No notifications yet.'))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final unread = notification['read_at'] == null;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        unread
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color: unread ? AppTheme.greenDark : AppTheme.textMuted,
                      ),
                      title: Text(
                        _notificationText(
                          notification['title'],
                          fallback: 'FPC update',
                        ),
                        style: TextStyle(
                          fontWeight: unread
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(_notificationText(notification['body'])),
                      onTap: () => _markRead(notification),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UiStrings.fromEnglish('Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final language = Get.isRegistered<LanguageController>()
            ? Get.find<LanguageController>()
            : null;
        final body = _guardedBody(wide);
        return Scaffold(
          backgroundColor: AppTheme.surface,
          extendBody: widget.extendBody && !wide,
          drawer: wide ? null : FpcWorkspaceDrawer(current: widget.current),
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
            title: Text(UiStrings.fromEnglish(widget.title)),
            actions: [
              ...widget.actions,
              IconButton(
                key: const Key('fpc-notification-inbox'),
                tooltip: UiStrings.fromEnglish('Notifications'),
                onPressed: _showNotificationInbox,
                icon: Badge(
                  isLabelVisible: _unreadCount > 0,
                  label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
              if (language != null)
                Obx(
                  () => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: LanguageSelectorButton(
                        code: language.language.value,
                        onChanged: language.setLanguage,
                        compact: constraints.maxWidth < 520,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: widget.showBottomNav && !wide
              ? FpcBottomNavBar(current: widget.current)
              : null,
          floatingActionButton: widget.showQrAction
              ? FloatingActionButton.extended(
                  key: const Key('fpc-qr-floating-action'),
                  onPressed: () => Get.toNamed('/fpo/qr'),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(UiStrings.fromEnglish('Scan QR')),
                )
              : null,
          body: wide
              ? Row(
                  children: [
                    FpcSideNavigation(current: widget.current),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
        );
      },
    );
  }

  Widget _guardedBody(bool wide) {
    if (!widget.allowSetupGate) return widget.body;
    final session = _session;
    final readiness = session?.readiness;
    if (session?.isAdmin == true &&
        readiness != null &&
        !readiness.isComplete) {
      final onSetupRoute = Get.currentRoute == '/fpo/setup';
      if (Get.currentRoute == '/fpo') {
        return FpcSetupRequiredPanel(readiness: readiness);
      }
      if (!onSetupRoute) {
        return Column(
          children: [
            _FpcReadinessBanner(readiness: readiness),
            Expanded(child: widget.body),
          ],
        );
      }
    }
    return widget.body;
  }
}

class FpcSetupRequiredPanel extends StatelessWidget {
  final FpcSetupReadiness readiness;

  const FpcSetupRequiredPanel({super.key, required this.readiness});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
      children: [
        _FpcShellStateCard(
          icon: Icons.rule_folder_outlined,
          title: 'Complete FPC setup first',
          message:
              'Required items are still missing: '
              '${readiness.missingRequiredItems.map((item) => item.title).join(', ')}.',
          actionLabel: 'Open setup checklist',
          onAction: () => Get.offNamed('/fpo/setup'),
        ),
      ],
    );
  }
}

class _FpcReadinessBanner extends StatelessWidget {
  final FpcSetupReadiness readiness;

  const _FpcReadinessBanner({required this.readiness});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7ED),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  UiStrings.fromEnglish(
                    'FPC setup incomplete: ${readiness.missingRequiredItems.length} required item(s) remaining.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => Get.toNamed('/fpo/setup'),
                child: Text(UiStrings.fromEnglish('Fix setup')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FpcShellStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _FpcShellStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppTheme.greenDark, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    UiStrings.fromEnglish(title),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    UiStrings.fromEnglish(message),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onAction,
                    child: Text(UiStrings.fromEnglish(actionLabel)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
                label: 'FPC workspace',
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
                    tab: FpcNavTab.operations,
                    icon: Icons.account_tree_rounded,
                    title: 'Operating system',
                    subtitle: 'All FPC modules',
                    route: '/fpo/operations',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.seeds,
                    icon: Icons.spa_rounded,
                    title: 'Seeds',
                    subtitle: 'Programs, stock and distribution',
                    route: '/fpo/seeds',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.team,
                    icon: Icons.badge_outlined,
                    title: 'Field team',
                    subtitle: 'Officers and assignments',
                    route: '/fpo/team',
                  ),
                  _FpcNavEntry(
                    tab: FpcNavTab.farmerScan,
                    icon: Icons.groups_2_outlined,
                    title: 'Farmer directory',
                    subtitle: 'Profiles, farms and crop history',
                    route: '/fpo/farmers',
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
                    title: 'Receive center',
                    subtitle: 'Received lot ledger',
                    route: '/fpo/receiver',
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
                label: 'FPC account',
                current: current,
                closeDrawerOnTap: closeDrawerOnTap,
                items: const [
                  _FpcNavEntry(
                    tab: FpcNavTab.analytics,
                    icon: Icons.analytics_rounded,
                    title: 'Analytics',
                    subtitle: 'Performance and trends',
                    route: '/fpo/analytics',
                  ),
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
                    title: 'Tasks',
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

class _FpcAccountHeader extends StatefulWidget {
  const _FpcAccountHeader();

  @override
  State<_FpcAccountHeader> createState() => _FpcAccountHeaderState();
}

class _FpcAccountHeaderState extends State<_FpcAccountHeader> {
  FpcAccountIdentity _account = FpcAccountIdentity.current();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAuthoritativeAccount());
  }

  Future<void> _loadAuthoritativeAccount() async {
    try {
      final membership = await FpcOperatingService().loadMembership();
      final fallback = FpcAccountIdentity.current();
      if (!mounted) return;
      setState(() {
        _account = FpcAccountIdentity(
          organizationName: membership.fpcName,
          displayName: fallback.displayName,
          email: fallback.email,
          role: membership.role,
          userId: fallback.userId,
          phone: fallback.phone,
        );
      });
    } catch (_) {
      // Keep the lightweight Auth metadata fallback while the shell loads or
      // when the session is already being redirected out.
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;

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
            UiStrings.fromEnglish(account.name),
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
                          : UiStrings.t('fpc_account_label'),
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
                  UiStrings.f('role_access', {'role': account.roleLabel}),
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
