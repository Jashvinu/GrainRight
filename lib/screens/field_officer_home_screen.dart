import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../controllers/main_auth_controller.dart';
import '../core/localization/locale_text.dart';
import '../core/theme/app_theme.dart';
import '../core/localization/ui_strings.dart';
import '../models/fpc_operating_models.dart';
import '../services/fpc_operating_service.dart';
import '../services/offline_field_queue_service.dart';

class FieldOfficerHomeScreen extends StatefulWidget {
  const FieldOfficerHomeScreen({super.key});

  @override
  State<FieldOfficerHomeScreen> createState() => _FieldOfficerHomeScreenState();
}

class _FieldOfficerHomeScreenState extends State<FieldOfficerHomeScreen> {
  final _service = FpcOperatingService();
  final _queue = OfflineFieldQueueService();
  FpcMembershipContext? _membership;
  List<FieldAssignmentRecord> _assignments = const [];
  List<OfflineFieldQueueItem> _queued = const [];
  List<Map<String, dynamic>> _notifications = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      try {
        await _queue.sync();
      } catch (_) {
        // A queued write remains durable and is retried on the next refresh.
      }
      FpcMembershipContext membership;
      List<FieldAssignmentRecord> assignments;
      try {
        membership = await _service.loadMembership();
        if (!membership.isFieldOfficer) {
          throw const FpcOperatingException('Field Officer access required.');
        }
        assignments = await _service.loadFieldAssignments();
        await _queue.cacheContext(membership, assignments);
      } catch (_) {
        final cached = await _queue.loadCachedContext();
        if (cached == null) rethrow;
        membership = cached.membership;
        assignments = cached.assignments;
      }
      final queued = await _queue.load();
      List<Map<String, dynamic>> notifications = const [];
      try {
        notifications = await _service.loadNotifications(unreadOnly: true);
      } catch (_) {
        // Assigned work remains available from the local cache while offline.
      }
      if (!mounted) return;
      setState(() {
        _membership = membership;
        _assignments = assignments;
        _queued = queued;
        _notifications = notifications;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    FieldAssignmentRecord? activeVisitAssignment;
    for (final assignment in _assignments) {
      if (assignment.status == 'in_progress') {
        activeVisitAssignment = assignment;
        break;
      }
    }
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(UiStrings.fromEnglish('Field Officer')),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.sync_rounded),
          ),
          IconButton(
            onPressed: Get.find<MainAuthController>().logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: activeVisitAssignment == null
            ? null
            : () => _recordVisit(activeVisitAssignment!),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(UiStrings.fromEnglish('Record visit')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: Text(UiStrings.fromEnglish('Retry')),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                children: [
                  _FieldHero(
                    fpcName: _membership?.fpcName ?? 'FPC',
                    assigned: _assignments.length,
                    queued: _queued.length,
                  ),
                  const SizedBox(height: 14),
                  const _AccessNote(),
                  if (_notifications.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      UiStrings.fromEnglish('Notifications'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    for (final notification in _notifications)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.notifications_outlined),
                        title: Text('${notification['title'] ?? ''}'),
                        subtitle: Text('${notification['body'] ?? ''}'),
                        trailing: IconButton(
                          tooltip: UiStrings.fromEnglish('Mark read'),
                          onPressed: () async {
                            await _service.markNotificationRead(
                              '${notification['id']}',
                            );
                            await _load();
                          },
                          icon: const Icon(Icons.done_rounded),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    UiStrings.fromEnglish('Assigned work'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_assignments.isEmpty)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          UiStrings.fromEnglish('No work is assigned yet.'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    for (final assignment in _assignments)
                      _AssignmentCard(
                        assignment: assignment,
                        onStart: assignment.status == 'assigned'
                            ? () => _setStatus(assignment, 'in_progress')
                            : null,
                        onVisit: assignment.status == 'in_progress'
                            ? () => _recordVisit(assignment)
                            : null,
                        onInsights: assignment.farmId.isEmpty
                            ? null
                            : () => _showFarmInsights(assignment),
                      ),
                  if (_queued.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      UiStrings.fromEnglish('Offline sync queue'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    for (final item in _queued)
                      ListTile(
                        leading: const Icon(Icons.cloud_upload_outlined),
                        title: Text(
                          item.payload['_queue_type'] == 'assignment_status'
                              ? UiStrings.t('field_assignment_status_update')
                              : '${item.payload['visit_type'] ?? 'Field visit'}',
                        ),
                        subtitle: Text(
                          item.error ??
                              UiStrings.t('field_waiting_for_network'),
                        ),
                        trailing: Text(item.status),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Future<void> _setStatus(
    FieldAssignmentRecord assignment,
    String status,
  ) async {
    try {
      await _service.updateAssignmentStatus(
        assignment.id,
        status,
        assignment.serverVersion,
      );
      await _load();
    } catch (error) {
      if (_queue.shouldQueueAfterError(error)) {
        await _queue.enqueueAssignmentStatus(assignment, status);
        await _load();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _showFarmInsights(FieldAssignmentRecord assignment) async {
    try {
      final insights = await _service.loadAssignedFarmInsights(
        assignment.farmId,
      );
      if (!mounted) return;
      final farm = insights['farm'] is Map
          ? Map<String, dynamic>.from(insights['farm'] as Map)
          : const <String, dynamic>{};
      final snapshot = insights['snapshot'] is Map
          ? Map<String, dynamic>.from(insights['snapshot'] as Map)
          : const <String, dynamic>{};
      final risks = insights['risk_cells'] is List
          ? insights['risk_cells'] as List
          : const [];
      final zones = insights['scout_zones'] is List
          ? insights['scout_zones'] as List
          : const [];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '${farm['name'] ?? assignment.title}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _insightLine('Crop', farm['crop'] ?? snapshot['crop']),
                _insightLine(
                  'Growth stage',
                  snapshot['growth_stage'] ?? farm['current_status_stage'],
                ),
                _insightLine(
                  'Temperature',
                  '${snapshot['temperature_c'] ?? '-'} °C',
                ),
                _insightLine(
                  'Humidity',
                  '${snapshot['humidity_percent'] ?? '-'}%',
                ),
                _insightLine('Rain', '${snapshot['rain_mm'] ?? '-'} mm'),
                _insightLine(
                  'NDVI',
                  risks.isEmpty ? '-' : (risks.first as Map)['ndvi'],
                ),
                _insightLine(
                  'Disease risk',
                  risks.isEmpty
                      ? snapshot['disease_risk']
                      : (risks.first as Map)['composite_risk'],
                ),
                _insightLine('Scout zones', zones.length),
                const SizedBox(height: 8),
                Text(
                  UiStrings.t('field_assigned_farm_read_only'),
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(UiStrings.fromEnglish('Close')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _insightLine(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Expanded(child: Text(UiStrings.fromEnglish(label))),
        Text(
          '${value ?? '-'}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );

  Future<void> _recordVisit(FieldAssignmentRecord assignment) async {
    if (assignment.status != 'in_progress') return;
    final checkInAt = DateTime.now().toUtc();
    final cropStage = TextEditingController();
    final harvestDate = TextEditingController();
    final quantity = TextEditingController();
    final grade = TextEditingController();
    final readiness = TextEditingController();
    final recommendation = TextEditingController();
    final centerRecommendation = TextEditingController();
    final contactPhone = TextEditingController();
    final kycStatus = TextEditingController();
    final reportedIssue = TextEditingController();
    final deliveredQuantity = TextEditingController();
    final notes = TextEditingController();
    final photos = <XFile>[];
    var checkpointOutcome = 'verified';
    final isSeedDelivery = assignment.seedIssueId.isNotEmpty;
    final isCropCheckpoint = assignment.cropProgramCheckId.isNotEmpty;
    final isKyc = assignment.type == 'farmer_kyc';
    final isHarvestWork = {
      'crop_monitoring',
      'harvest_survey',
      'procurement_support',
      'crop_program_check',
    }.contains(assignment.type);
    final isProcurementWork = {
      'harvest_survey',
      'procurement_support',
    }.contains(assignment.type);
    Position? position;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(assignment.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSeedDelivery) ...[
                  TextField(
                    controller: deliveredQuantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: UiStrings.t(
                        'field_delivered_seed_quantity_kg',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                if (isCropCheckpoint) ...[
                  DropdownButtonFormField<String>(
                    initialValue: checkpointOutcome,
                    decoration: InputDecoration(
                      labelText: UiStrings.t('field_crop_checkpoint_result'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'verified',
                        child: Text(UiStrings.fromEnglish('Verified')),
                      ),
                      DropdownMenuItem(
                        value: 'failed',
                        child: Text(UiStrings.fromEnglish('Failed')),
                      ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => checkpointOutcome = value ?? 'verified',
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                if (!isSeedDelivery && !isKyc) ...[
                  TextField(
                    controller: cropStage,
                    decoration: InputDecoration(
                      labelText: UiStrings.fromEnglish('Crop stage'),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                if (isHarvestWork) ...[
                  TextField(
                    controller: harvestDate,
                    decoration: InputDecoration(
                      labelText: UiStrings.t(
                        'field_expected_harvest_date_format',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: UiStrings.fromEnglish(
                        'Estimated quantity (kg)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: grade,
                    decoration: InputDecoration(
                      labelText: UiStrings.t('field_expected_grade'),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: readiness,
                    decoration: InputDecoration(
                      labelText: UiStrings.fromEnglish('Harvest readiness'),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                if (isProcurementWork) ...[
                  TextField(
                    controller: recommendation,
                    decoration: InputDecoration(
                      labelText: UiStrings.fromEnglish(
                        'Procurement recommendation',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: centerRecommendation,
                    decoration: InputDecoration(
                      labelText: UiStrings.t(
                        'field_collection_center_recommendation',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                if (isKyc) ...[
                  TextField(
                    controller: contactPhone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: UiStrings.t('field_farmer_contact_update'),
                    ),
                  ),
                  const SizedBox(height: 9),
                  TextField(
                    controller: kycStatus,
                    decoration: InputDecoration(
                      labelText: UiStrings.t('field_kyc_evidence_status'),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                if (!isSeedDelivery && !isKyc) ...[
                  TextField(
                    controller: reportedIssue,
                    decoration: InputDecoration(
                      labelText: UiStrings.t('field_reported_crop_issue'),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Visit notes'),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final photo = await ImagePicker().pickImage(
                          source: ImageSource.camera,
                          imageQuality: 82,
                          maxWidth: 1800,
                        );
                        if (photo != null) {
                          setDialogState(() => photos.add(photo));
                        }
                      },
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(
                        UiStrings.f('field_add_photo_count', {
                          'count': photos.length,
                        }),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        var permission = await Geolocator.checkPermission();
                        if (permission == LocationPermission.denied) {
                          permission = await Geolocator.requestPermission();
                        }
                        if (permission == LocationPermission.denied ||
                            permission == LocationPermission.deniedForever) {
                          return;
                        }
                        final captured = await Geolocator.getCurrentPosition();
                        setDialogState(() => position = captured);
                      },
                      icon: const Icon(Icons.my_location_rounded),
                      label: Text(
                        UiStrings.fromEnglish(
                          position == null
                              ? 'Add location'
                              : 'Location captured',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UiStrings.fromEnglish('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(UiStrings.fromEnglish('Save')),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    if (assignment.seedIssueId.isNotEmpty &&
        (double.tryParse(deliveredQuantity.text.trim()) ?? 0) <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UiStrings.t('field_enter_delivered_seed_quantity')),
          ),
        );
      }
      return;
    }
    if (isSeedDelivery && photos.isEmpty) {
      _showValidationMessage(UiStrings.t('field_add_delivery_photo'));
      return;
    }
    if (isSeedDelivery && position == null) {
      _showValidationMessage(UiStrings.t('field_capture_delivery_location'));
      return;
    }
    if (isCropCheckpoint && photos.isEmpty) {
      _showValidationMessage(UiStrings.t('field_add_checkpoint_photo'));
      return;
    }
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'assignment_id': assignment.id,
      'client_uuid': const Uuid().v4(),
      'farmer_id': assignment.farmerId,
      'farm_id': assignment.farmId,
      'visit_type': assignment.type,
      'crop_stage': cropStage.text.trim(),
      'expected_harvest_date': harvestDate.text.trim().isEmpty
          ? null
          : harvestDate.text.trim(),
      'estimated_quantity_kg': double.tryParse(quantity.text.trim()),
      'expected_grade': grade.text.trim(),
      'readiness': readiness.text.trim(),
      'recommendation': recommendation.text.trim(),
      'notes': notes.text.trim(),
      'photo_paths': photos.map((photo) => photo.path).toList(),
      'evidence': {
        'farmer_contact_update': contactPhone.text.trim(),
        'kyc_status': kycStatus.text.trim(),
        'reported_issue': reportedIssue.text.trim(),
        'collection_center_recommendation': centerRecommendation.text.trim(),
        if (assignment.seedIssueId.isNotEmpty)
          'delivered_quantity_kg': double.parse(deliveredQuantity.text.trim()),
        if (assignment.cropProgramCheckId.isNotEmpty)
          'checkpoint_outcome': checkpointOutcome,
      },
      'check_in': {
        'at': checkInAt.toIso8601String(),
        if (position != null) 'latitude': position!.latitude,
        if (position != null) 'longitude': position!.longitude,
        if (position != null) 'accuracy_m': position!.accuracy,
      },
      'check_out': {
        'at': now.toIso8601String(),
        if (position != null) 'latitude': position!.latitude,
        if (position != null) 'longitude': position!.longitude,
        if (position != null) 'accuracy_m': position!.accuracy,
      },
    };
    try {
      await _service.saveFieldVisit(payload);
      await _service.updateAssignmentStatus(
        assignment.id,
        'completed',
        assignment.serverVersion,
      );
    } catch (error) {
      if (_queue.shouldQueueAfterError(error)) {
        await _queue.enqueue(payload);
        await _queue.enqueueAssignmentStatus(assignment, 'completed');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }
        return;
      }
    }
    await _load();
  }

  void _showValidationMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FieldHero extends StatelessWidget {
  final String fpcName;
  final int assigned;
  final int queued;
  const _FieldHero({
    required this.fpcName,
    required this.assigned,
    required this.queued,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.greenDark,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fpcName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          UiStrings.f('field_assignment_sync_summary', {
            'assigned': assigned,
            'queued': queued,
          }),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _AccessNote extends StatelessWidget {
  const _AccessNote();
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: AppTheme.greenDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              UiStrings.fromEnglish(
                'Only assigned farmers, farms, visits and procurement-support work are available. Warehouse, finance, production, sales and settings stay restricted.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AssignmentCard extends StatelessWidget {
  final FieldAssignmentRecord assignment;
  final VoidCallback? onStart;
  final VoidCallback? onVisit;
  final VoidCallback? onInsights;
  const _AssignmentCard({
    required this.assignment,
    required this.onStart,
    required this.onVisit,
    this.onInsights,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  assignment.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Chip(
                label: Text(
                  UiStrings.option(assignment.status.replaceAll('_', ' ')),
                ),
              ),
            ],
          ),
          Text(
            [
              UiStrings.option(assignment.type.replaceAll('_', ' ')),
              if (assignment.farmerId.isNotEmpty)
                UiStrings.f('field_assignment_farmer_id', {
                  'id': assignment.farmerId,
                }),
              if (assignment.scheduledFor != null)
                '${UiStrings.fromEnglish('Scheduled')} '
                    '${LocaleText.date(assignment.scheduledFor!.toLocal())} '
                    '${LocaleText.time(assignment.scheduledFor!.toLocal())}',
            ].join(' · '),
            style: const TextStyle(color: AppTheme.textMuted),
          ),
          if (assignment.instructions.isNotEmpty) Text(assignment.instructions),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (assignment.status == 'assigned')
                OutlinedButton(
                  onPressed: onStart,
                  child: Text(UiStrings.t('field_start')),
                ),
              if (assignment.status == 'in_progress')
                FilledButton.icon(
                  onPressed: onVisit,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: Text(UiStrings.fromEnglish('Record visit')),
                ),
              if (onInsights != null)
                OutlinedButton.icon(
                  onPressed: onInsights,
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: Text(UiStrings.fromEnglish('Farm health')),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
