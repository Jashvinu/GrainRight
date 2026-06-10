import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/main_auth_controller.dart';
import '../widgets/brand_text.dart';

class FpoHomeScreen extends StatelessWidget {
  const FpoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<MainAuthController>();
    return Scaffold(
      backgroundColor: AppTheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed('/fpo/scan-farmer'),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Scan Farmer QR'),
      ),
      appBar: AppBar(
        title: const Text('FPO Dashboard'),
        leading: IconButton(
          tooltip: 'Change role',
          onPressed: auth.logout,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Admin login',
            onPressed: () => Get.toNamed('/satellite/login'),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          const _FpoHeader(),
          const SizedBox(height: 22),
          const Text(
            'Management',
            style: TextStyle(
              color: Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          _ManagementGrid(
            items: [
              _FpoAction(
                icon: Icons.groups_2_outlined,
                title: 'Farmers',
                subtitle: 'Scan QR and manage members',
                color: AppTheme.green,
                tint: AppTheme.greenPale,
                onTap: () => Get.toNamed('/fpo/scan-farmer'),
              ),
              _FpoAction(
                icon: Icons.inventory_2_outlined,
                title: 'Procurement',
                subtitle: 'Track crop lots',
                color: const Color(0xFF1976D2),
                tint: const Color(0xFFEAF4FF),
                onTap: () => Get.snackbar(
                  'Procurement',
                  'Procurement tracking will be connected here.',
                  snackPosition: SnackPosition.BOTTOM,
                ),
              ),
              _FpoAction(
                icon: Icons.map_outlined,
                title: 'Field Maps',
                subtitle: 'Offline map areas',
                color: const Color(0xFF673AB7),
                tint: const Color(0xFFF0EAFE),
                onTap: () => Get.toNamed('/offline-maps'),
              ),
              _FpoAction(
                icon: Icons.biotech_outlined,
                title: 'Diagnostics',
                subtitle: 'Farm health reports',
                color: const Color(0xFFE07800),
                tint: const Color(0xFFFFF4E5),
                onTap: () => Get.toNamed('/diagnostics'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _FpoSummary(),
          const SizedBox(height: 18),
          _FpoListTile(
            icon: Icons.satellite_alt_outlined,
            title: 'Satellite Monitoring',
            subtitle: 'Use admin credentials for farm satellite tools',
            onTap: () => Get.toNamed('/satellite/login'),
          ),
          _FpoListTile(
            icon: Icons.logout_rounded,
            title: 'Change Role',
            subtitle: 'Return to role selection',
            onTap: auth.logout,
          ),
        ],
      ),
    );
  }
}

class _FpoHeader extends StatelessWidget {
  const _FpoHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.groups_2_rounded,
              color: Color(0xFF1976D2),
              size: 40,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrandText(fontSize: 22),
                SizedBox(height: 6),
                Text(
                  'FPO / FPC workspace',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
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

class _FpoAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color tint;
  final VoidCallback onTap;

  const _FpoAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tint,
    required this.onTap,
  });
}

class _ManagementGrid extends StatelessWidget {
  final List<_FpoAction> items;

  const _ManagementGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.08,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: item.onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: item.tint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(item.icon, color: item.color, size: 31),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FpoSummary extends StatelessWidget {
  const _FpoSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Row(
        children: [
          _SummaryMetric(label: 'Farmers', value: '0'),
          _SummaryMetric(label: 'Lots', value: '0'),
          _SummaryMetric(label: 'Alerts', value: '0'),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.greenDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FpoListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FpoListTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.green),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
