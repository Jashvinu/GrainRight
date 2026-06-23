import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../config/ui_strings.dart';
import '../../controllers/auth_controller.dart';
import '../../widgets/app_back_button.dart';
import 'dashboard_screen.dart';
import 'yield_screen.dart';
import 'advanced_screen.dart';
import 'diagnostics_screen.dart';

class SatelliteShell extends StatefulWidget {
  const SatelliteShell({super.key});

  @override
  State<SatelliteShell> createState() => _SatelliteShellState();
}

class _SatelliteShellState extends State<SatelliteShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final auth = Get.find<AuthController>();
    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.offAllNamed('/satellite/login');
      });
    }
  }

  static const _tabs = [
    DashboardScreen(),
    YieldScreen(),
    AdvancedScreen(),
    DiagnosticsScreen(),
  ];

  static const _titleKeys = [
    'dashboard',
    'yield_prediction',
    'advanced_monitoring',
    'field_diagnostics',
  ];

  void _showProfileDialog() {
    final auth = Get.find<AuthController>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(UiStrings.t('profile')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              UiStrings.t('signed_in_as'),
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              auth.currentUser.value?.email ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UiStrings.t('close')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              auth.logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(UiStrings.t('logout')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(UiStrings.t(_titleKeys[_index])),
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(
          context,
          onPressed: () => Get.offAllNamed('/login'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: _showProfileDialog,
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.greenPale,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard, color: AppTheme.greenDark),
            label: UiStrings.t('dashboard'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart, color: AppTheme.greenDark),
            label: UiStrings.t('yield'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.analytics_outlined),
            selectedIcon:
                const Icon(Icons.analytics, color: AppTheme.greenDark),
            label: UiStrings.t('advanced'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.biotech_outlined),
            selectedIcon: const Icon(Icons.biotech, color: AppTheme.greenDark),
            label: UiStrings.t('diagnostics'),
          ),
        ],
      ),
    );
  }
}
