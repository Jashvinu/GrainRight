import 'package:flutter/material.dart';

import '../models/fpc_operating_models.dart';
import '../core/localization/ui_strings.dart';
import '../services/fpc_operating_service.dart';
import '../widgets/fpc_bottom_nav.dart';

class FpcTeamScreen extends StatefulWidget {
  const FpcTeamScreen({super.key});

  @override
  State<FpcTeamScreen> createState() => _FpcTeamScreenState();
}

class _FpcTeamScreenState extends State<FpcTeamScreen> {
  final _service = FpcOperatingService();
  FpcMembershipContext? _membership;
  List<Map<String, dynamic>> _members = const [];
  List<FieldAssignmentRecord> _assignments = const [];
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
      final membership = await _service.loadMembership();
      final members = await _service.loadMemberships();
      final assignments = await _service.loadFieldAssignments();
      if (!mounted) return;
      setState(() {
        _membership = membership;
        _members = members;
        _assignments = assignments;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FpcWorkspaceScaffold(
    current: FpcNavTab.team,
    title: 'Field team',
    actions: [
      IconButton(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error.isNotEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error),
                FilledButton(
                  onPressed: _load,
                  child: Text(UiStrings.fromEnglish('Retry')),
                ),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 112),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _createOfficer,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(UiStrings.fromEnglish('Create Field Officer')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _fieldOfficers.isEmpty
                        ? null
                        : _createAssignment,
                    icon: const Icon(Icons.assignment_add),
                    label: Text(UiStrings.fromEnglish('Assign field work')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                UiStrings.fromEnglish('Users'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final member in _members)
                Card(
                  child: ListTile(
                    leading: Icon(
                      member['role'] == 'field_officer'
                          ? Icons.directions_walk_rounded
                          : Icons.admin_panel_settings_rounded,
                    ),
                    title: Text(
                      '${member['display_name'] ?? member['email']}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${member['role'] ?? ''} · ${member['email'] ?? ''}',
                    ),
                    trailing: Chip(label: Text('${member['status'] ?? ''}')),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                UiStrings.fromEnglish('Assignments'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (_assignments.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      UiStrings.fromEnglish('No field assignments yet.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              for (final assignment in _assignments)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.assignment_turned_in_outlined),
                    title: Text(
                      assignment.title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      '${assignment.type.replaceAll('_', ' ')} · ${assignment.instructions}',
                    ),
                    trailing: Chip(
                      label: Text(assignment.status.replaceAll('_', ' ')),
                    ),
                  ),
                ),
            ],
          ),
  );

  List<Map<String, dynamic>> get _fieldOfficers => _members
      .where(
        (member) =>
            member['role'] == 'field_officer' && member['status'] == 'active',
      )
      .toList(growable: false);

  Future<void> _createOfficer() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UiStrings.fromEnglish('Create Field Officer')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: UiStrings.fromEnglish('Name *'),
                ),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: email,
                decoration: InputDecoration(
                  labelText: UiStrings.fromEnglish('Email *'),
                ),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: phone,
                decoration: InputDecoration(
                  labelText: UiStrings.fromEnglish('Phone'),
                ),
              ),
              const SizedBox(height: 9),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: UiStrings.fromEnglish(
                    'Temporary password (8+ characters) *',
                  ),
                ),
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
            child: Text(UiStrings.fromEnglish('Create')),
          ),
        ],
      ),
    );
    if (save != true) return;
    try {
      await _service.createFpcUser(
        role: 'field_officer',
        displayName: name.text,
        email: email.text,
        phone: phone.text,
        temporaryPassword: password.text,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _createAssignment() async {
    final membership = _membership;
    if (membership == null) return;
    String officerId = '${_fieldOfficers.first['user_id']}';
    String type = 'farm_verification';
    final title = TextEditingController();
    final instructions = TextEditingController();
    final farmerId = TextEditingController();
    final farmId = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Assign field work')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: officerId,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Field Officer'),
                  ),
                  items: [
                    for (final officer in _fieldOfficers)
                      DropdownMenuItem(
                        value: '${officer['user_id']}',
                        child: Text(
                          '${officer['display_name'] ?? officer['email']}',
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => officerId = value ?? officerId),
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Assignment type'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'farmer_kyc',
                      child: Text(UiStrings.fromEnglish('Farmer KYC')),
                    ),
                    DropdownMenuItem(
                      value: 'farm_verification',
                      child: Text(UiStrings.fromEnglish('Farm verification')),
                    ),
                    DropdownMenuItem(
                      value: 'crop_monitoring',
                      child: Text(UiStrings.fromEnglish('Crop monitoring')),
                    ),
                    DropdownMenuItem(
                      value: 'harvest_survey',
                      child: Text(UiStrings.fromEnglish('Harvest survey')),
                    ),
                    DropdownMenuItem(
                      value: 'procurement_support',
                      child: Text(UiStrings.fromEnglish('Procurement support')),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Title *'),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: farmerId,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Farmer ID'),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: farmId,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Farm ID'),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: instructions,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Instructions'),
                  ),
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
              child: Text(UiStrings.fromEnglish('Assign')),
            ),
          ],
        ),
      ),
    );
    if (save != true || title.text.trim().isEmpty) return;
    try {
      await _service.createFieldAssignment(
        membership: membership,
        officerUserId: officerId,
        type: type,
        title: title.text.trim(),
        instructions: instructions.text.trim(),
        farmerId: farmerId.text.trim(),
        farmId: farmId.text.trim(),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
