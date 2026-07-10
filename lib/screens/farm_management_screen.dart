import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../config/theme.dart';
import '../controllers/farm_controller.dart';
import '../models/satellite/farm_model.dart';
import '../widgets/app_back_button.dart';

class FarmManagementScreen extends StatefulWidget {
  const FarmManagementScreen({super.key});

  @override
  State<FarmManagementScreen> createState() => _FarmManagementScreenState();
}

class _FarmManagementScreenState extends State<FarmManagementScreen> {
  late final FarmController _farmCtrl;

  @override
  void initState() {
    super.initState();
    _farmCtrl = Get.isRegistered<FarmController>()
        ? Get.find<FarmController>()
        : Get.put(FarmController());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _farmCtrl.loadFarms(forceRefresh: true);
    });
  }

  Future<void> _confirmDelete(Farm farm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete farm?'),
        content: Text(
          'This removes "${farm.name}" and its linked farm records from the database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _farmCtrl.deleteFarm(farm);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Manage farms'),
        leadingWidth: appBackButtonLeadingWidth,
        leading: appBackButtonLeading(context),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _farmCtrl.loadFarms(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Add farm',
            onPressed: () => Get.toNamed('/satellite/draw-polygon'),
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      body: Obx(() {
        if (_farmCtrl.isLoading.value && _farmCtrl.farms.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.green),
          );
        }
        if (_farmCtrl.farms.isEmpty) {
          return RefreshIndicator(
            color: AppTheme.green,
            onRefresh: () => _farmCtrl.loadFarms(forceRefresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 96),
                Icon(Icons.grass_outlined, size: 64, color: AppTheme.textMuted),
                SizedBox(height: 18),
                Text(
                  'No farms found',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 8),
                Text(
                  'Add a farm boundary, then it will appear here for this login.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          color: AppTheme.green,
          onRefresh: () => _farmCtrl.loadFarms(forceRefresh: true),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: _farmCtrl.farms.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final farm = _farmCtrl.farms[index];
              final selected = _farmCtrl.selectedFarm.value?.id == farm.id;
              return _FarmTile(
                farm: farm,
                selected: selected,
                deleting: _farmCtrl.isLoading.value,
                onSelect: () => _farmCtrl.selectFarm(farm),
                onDelete: () => _confirmDelete(farm),
              );
            },
          ),
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.green,
        foregroundColor: Colors.white,
        onPressed: () => Get.toNamed('/satellite/draw-polygon'),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add farm'),
      ),
    );
  }
}

class _FarmTile extends StatelessWidget {
  final Farm farm;
  final bool selected;
  final bool deleting;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _FarmTile({
    required this.farm,
    required this.selected,
    required this.deleting,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final area = farm.areaAcres == null
        ? 'Area not set'
        : '${farm.areaAcres!.toStringAsFixed(2)} acres';
    final crop = [
      farm.crop,
      farm.variety,
    ].where((value) => value != null && value.trim().isNotEmpty).join(' - ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.green : const Color(0xFFE5E7EB),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.greenPale
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.grass_outlined,
                  color: selected ? AppTheme.green : AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      crop.isEmpty ? area : '$crop • $area',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete farm',
                onPressed: deleting ? null : onDelete,
                color: Colors.redAccent,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
