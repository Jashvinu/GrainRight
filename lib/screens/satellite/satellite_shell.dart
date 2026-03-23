import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../config/theme.dart';
import '../../controllers/auth_controller.dart';
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

  static const _titles = [
    'Dashboard',
    'Yield Prediction',
    'Advanced Monitoring',
    'Field Diagnostics',
  ];

  void _showProfileDialog() {
    final auth = Get.find<AuthController>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Signed in as',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
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
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              auth.logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.offAllNamed('/home'),
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppTheme.greenDark),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: AppTheme.greenDark),
            label: 'Yield',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics, color: AppTheme.greenDark),
            label: 'Advanced',
          ),
          NavigationDestination(
            icon: Icon(Icons.biotech_outlined),
            selectedIcon: Icon(Icons.biotech, color: AppTheme.greenDark),
            label: 'Diagnostics',
          ),
        ],
      ),
    );
  }
}
