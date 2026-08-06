import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/localization/locale_text.dart';
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
  List<Map<String, dynamic>> _farmers = const [];
  List<FieldAssignmentRecord> _assignments = const [];
  bool _loading = true;
  bool _openCreateOfficerOnLoad = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final arguments = Get.arguments;
    if (arguments is Map &&
        arguments['open_action'] == 'create_field_officer') {
      _openCreateOfficerOnLoad = true;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final membership = await _service.loadMembership();
      final members = await _service.loadMemberships();
      final farmers = await _service.loadModuleRows('farmer_network');
      final assignments = await _service.loadFieldAssignments();
      if (!mounted) return;
      setState(() {
        _membership = membership;
        _members = members;
        _farmers = farmers;
        _assignments = assignments;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        final openCreateOfficer = _openCreateOfficerOnLoad && _error.isEmpty;
        _openCreateOfficerOnLoad = false;
        setState(() => _loading = false);
        if (openCreateOfficer) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_createOfficer());
          });
        }
      }
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
                      '${UiStrings.option('${member['role'] ?? ''}'.replaceAll('_', ' '))} · ${member['email'] ?? ''}',
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            UiStrings.option('${member['status'] ?? ''}'),
                          ),
                        ),
                        if (_membership != null)
                          PopupMenuButton<String>(
                            onSelected: (action) =>
                                _handleMemberAction(member, action),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'reset_password',
                                child: Text(
                                  UiStrings.fromEnglish(
                                    'Reset temporary password',
                                  ),
                                ),
                              ),
                              if ('${member['status'] ?? ''}' == 'active')
                                PopupMenuItem(
                                  value: 'inactive',
                                  child: Text(
                                    UiStrings.fromEnglish('Disable user'),
                                  ),
                                )
                              else
                                PopupMenuItem(
                                  value: 'active',
                                  child: Text(
                                    UiStrings.fromEnglish('Reactivate user'),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
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
                      [
                        UiStrings.f('fpc_assignment_officer', {
                          'name': _officerName(assignment.officerUserId),
                        }),
                        UiStrings.f('fpc_assignment_farmer', {
                          'name': _farmerName(assignment.farmerId),
                        }),
                        UiStrings.option(assignment.type.replaceAll('_', ' ')),
                        if (assignment.scheduledFor != null)
                          '${LocaleText.date(assignment.scheduledFor!.toLocal())} '
                              '${LocaleText.time(assignment.scheduledFor!.toLocal())}',
                        assignment.instructions,
                      ].where((value) => value.trim().isNotEmpty).join('\n'),
                    ),
                    trailing: Chip(
                      label: Text(
                        UiStrings.option(
                          assignment.status.replaceAll('_', ' '),
                        ),
                      ),
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

  String _officerName(String userId) {
    for (final officer in _fieldOfficers) {
      if ('${officer['user_id'] ?? ''}' == userId) {
        return '${officer['display_name'] ?? officer['email'] ?? userId}';
      }
    }
    return userId;
  }

  String _farmerName(String farmerId) {
    for (final farmer in _farmers) {
      if ('${farmer['farmer_id'] ?? ''}' == farmerId) {
        return '${farmer['farmer_name'] ?? farmerId}';
      }
    }
    return farmerId;
  }

  Future<void> _createOfficer() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    try {
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
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Email *'),
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
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
      final validation = _validateOfficer(name.text, email.text, password.text);
      if (validation != null) {
        _showError(validation);
        return;
      }
      await _service.createFpcUser(
        role: 'field_officer',
        displayName: name.text.trim(),
        email: email.text.trim(),
        phone: phone.text.trim(),
        temporaryPassword: password.text,
      );
      await _load();
    } catch (error) {
      _showError('$error');
    } finally {
      name.dispose();
      email.dispose();
      phone.dispose();
      password.dispose();
    }
  }

  String? _validateOfficer(String name, String email, String password) {
    if (name.trim().length < 2) {
      return UiStrings.fromEnglish('Enter the Field Officer name.');
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      return UiStrings.fromEnglish('Enter a valid Field Officer email.');
    }
    final duplicate = _members.any(
      (member) =>
          '${member['email'] ?? ''}'.trim().toLowerCase() ==
          email.trim().toLowerCase(),
    );
    if (duplicate) {
      return UiStrings.fromEnglish('This email is already in the FPC team.');
    }
    if (password.length < 8) {
      return UiStrings.fromEnglish('Temporary password must be 8+ characters.');
    }
    return null;
  }

  Future<void> _handleMemberAction(
    Map<String, dynamic> member,
    String action,
  ) async {
    final membership = _membership;
    if (membership == null) return;
    try {
      if (action == 'reset_password') {
        final password = await _requestTemporaryPassword();
        if (password == null) return;
        await _service.resetMembershipPassword(
          fpcId: membership.fpcId,
          membershipId: '${member['id']}',
          temporaryPassword: password,
        );
      } else {
        await _service.setMembershipStatus(
          fpcId: membership.fpcId,
          membershipId: '${member['id']}',
          status: action,
        );
      }
      await _load();
    } catch (error) {
      _showError('$error');
    }
  }

  Future<String?> _requestTemporaryPassword() async {
    final controller = TextEditingController();
    try {
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Reset temporary password')),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              labelText: UiStrings.fromEnglish('New temporary password'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UiStrings.fromEnglish('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(UiStrings.fromEnglish('Reset')),
            ),
          ],
        ),
      );
      if (save != true) return null;
      if (controller.text.length < 8) {
        _showError(
          UiStrings.fromEnglish('Temporary password must be 8+ characters.'),
        );
        return null;
      }
      return controller.text;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createAssignment() async {
    final membership = _membership;
    if (membership == null) return;
    String officerId = '${_fieldOfficers.first['user_id']}';
    String type = 'farm_verification';
    String farmerLinkId = _farmers.isEmpty ? '' : '${_farmers.first['id']}';
    DateTime scheduledFor = DateTime.now().add(const Duration(days: 1));
    final instructions = TextEditingController();
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
                  initialValue: farmerLinkId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: UiStrings.t('fpc_linked_farmer_farm'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        UiStrings.fromEnglish('No linked farmer'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final farmer in _farmers)
                      DropdownMenuItem(
                        value: '${farmer['id']}',
                        child: Text(
                          [
                            '${farmer['farmer_name'] ?? farmer['farmer_id']}',
                            '${farmer['farm_name'] ?? ''}',
                            '${farmer['village'] ?? ''}',
                          ].where((value) => value.isNotEmpty).join(' · '),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => farmerLinkId = value ?? farmerLinkId,
                  ),
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
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: scheduledFor,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(scheduledFor),
                    );
                    if (time == null) return;
                    setDialogState(() {
                      scheduledFor = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    '${UiStrings.t('fpc_schedule')}: '
                    '${LocaleText.date(scheduledFor)} '
                    '${LocaleText.time(scheduledFor)}',
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
    if (save != true) return;
    final farmer = farmerLinkId.isEmpty
        ? const <String, dynamic>{}
        : _farmers.firstWhere((row) => '${row['id']}' == farmerLinkId);
    final farmerName =
        '${farmer['farmer_name'] ?? farmer['farmer_id'] ?? 'Field Officer'}';
    final assignmentLabel = switch (type) {
      'farmer_kyc' => 'Farmer KYC',
      'farm_verification' => 'Farm verification',
      'crop_monitoring' => 'Crop monitoring',
      'harvest_survey' => 'Harvest survey',
      'procurement_support' => 'Procurement support',
      _ => 'Field work',
    };
    try {
      await _service.createFieldAssignment(
        membership: membership,
        officerUserId: officerId,
        type: type,
        title: farmerLinkId.isEmpty
            ? '$assignmentLabel assignment'
            : '$assignmentLabel · $farmerName',
        instructions: instructions.text.trim(),
        farmerId: '${farmer['farmer_id'] ?? ''}',
        farmId: '${farmer['farm_id'] ?? ''}',
        scheduledFor: scheduledFor,
      );
      await _load();
    } catch (error) {
      _showError('$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
