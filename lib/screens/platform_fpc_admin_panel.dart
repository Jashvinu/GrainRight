import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/localization/ui_strings.dart';
import '../models/fpc_operating_models.dart';
import '../services/fpc_operating_service.dart';
import '../services/fpc_report_service.dart';

class PlatformFpcAdminPanel extends StatefulWidget {
  const PlatformFpcAdminPanel({super.key});

  @override
  State<PlatformFpcAdminPanel> createState() => _PlatformFpcAdminPanelState();
}

class _PlatformFpcAdminPanelState extends State<PlatformFpcAdminPanel>
    with SingleTickerProviderStateMixin {
  final _service = FpcOperatingService();
  late final TabController _tabs;
  PlatformFpcSnapshot? _snapshot;
  List<Map<String, dynamic>> _settings = const [];
  List<Map<String, dynamic>> _templates = const [];
  List<Map<String, dynamic>> _audit = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final values = await Future.wait([
        _service.loadPlatformSnapshot(),
        _service.loadPlatformSettings(),
        _service.loadAuditEvents(),
        _service.loadNotificationTemplates(),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = values[0] as PlatformFpcSnapshot;
        _settings = values[1] as List<Map<String, dynamic>>;
        _audit = values[2] as List<Map<String, dynamic>>;
        _templates = values[3] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _load,
              child: Text(UiStrings.fromEnglish('Retry')),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: [
              Tab(text: UiStrings.fromEnglish('Organizations')),
              Tab(text: UiStrings.fromEnglish('FPC Users')),
              Tab(text: UiStrings.fromEnglish('Analytics')),
              Tab(text: UiStrings.fromEnglish('Settings')),
              Tab(text: UiStrings.fromEnglish('Audit')),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _organizations(),
              _users(),
              _analytics(),
              _settingsPanel(),
              _auditPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _organizations() {
    final snapshot = _snapshot!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            title: 'FPC applications',
            subtitle:
                '${snapshot.applications.where((item) => item['status'] == 'pending').length} waiting for review',
          ),
          const SizedBox(height: 10),
          if (snapshot.applications.isEmpty)
            const _Empty(message: 'No FPC applications found.'),
          for (final application in snapshot.applications)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${application['organization_name'] ?? 'FPC'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Chip(label: Text('${application['status'] ?? ''}')),
                      ],
                    ),
                    Text(
                      '${application['display_name'] ?? ''} · ${application['email'] ?? ''} · ${application['phone'] ?? ''}',
                    ),
                    if (application['status'] == 'pending' ||
                        application['status'] == 'under_review')
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _review(application, 'approved'),
                              icon: const Icon(Icons.check_rounded),
                              label: Text(UiStrings.fromEnglish('Approve')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _review(application, 'rejected'),
                              icon: const Icon(Icons.close_rounded),
                              label: Text(UiStrings.fromEnglish('Reject')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const _SectionHeader(
            title: 'Registered organizations',
            subtitle: 'Activate, suspend and review subscription status.',
          ),
          const SizedBox(height: 10),
          for (final fpc in snapshot.fpcs)
            Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.business_rounded),
                ),
                title: Text(
                  '${fpc['name'] ?? 'FPC'}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('${fpc['email'] ?? ''} · ${fpc['phone'] ?? ''}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: UiStrings.fromEnglish('Edit organization'),
                      onPressed: () => _showEditFpc(fpc),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: UiStrings.fromEnglish('Manage subscription'),
                      onPressed: () => _showSubscription(fpc),
                      icon: const Icon(Icons.workspace_premium_outlined),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (status) =>
                          _setStatus('${fpc['id']}', status),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'active',
                          child: Text(UiStrings.fromEnglish('Activate')),
                        ),
                        PopupMenuItem(
                          value: 'suspended',
                          child: Text(UiStrings.fromEnglish('Suspend')),
                        ),
                        PopupMenuItem(
                          value: 'inactive',
                          child: Text(UiStrings.fromEnglish('Deactivate')),
                        ),
                      ],
                      child: Chip(label: Text('${fpc['status'] ?? ''}')),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _users() {
    final snapshot = _snapshot!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: _SectionHeader(
                title: 'FPC users',
                subtitle: 'FPC Admin and Field Officer memberships.',
              ),
            ),
            FilledButton.icon(
              onPressed: _showCreateUser,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(UiStrings.fromEnglish('Create user')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (snapshot.memberships.isEmpty)
          const _Empty(message: 'No FPC memberships found.'),
        for (final member in snapshot.memberships)
          Card(
            child: ListTile(
              leading: Icon(
                member['role'] == 'field_officer'
                    ? Icons.directions_walk_rounded
                    : Icons.admin_panel_settings_outlined,
              ),
              title: Text(
                '${member['display_name'] ?? member['email'] ?? 'User'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${member['role'] ?? ''} · ${member['email'] ?? ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) => _handleMemberAction(member, action),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: member['status'] == 'active' ? 'disabled' : 'active',
                    child: Text(
                      UiStrings.fromEnglish(
                        member['status'] == 'active'
                            ? 'Disable user'
                            : 'Activate user',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reset_password',
                    child: Text(UiStrings.fromEnglish('Reset password')),
                  ),
                ],
                child: Chip(label: Text('${member['status'] ?? ''}')),
              ),
            ),
          ),
      ],
    );
  }

  Widget _analytics() {
    final metrics = _snapshot!.analytics;
    final items = <MapEntry<String, Object?>>[
      MapEntry('Total FPCs', metrics['totalFpcs']),
      MapEntry('Active FPCs', metrics['activeFpcs']),
      MapEntry('Active users', metrics['activeUsers']),
      MapEntry('Linked farmers', metrics['linkedFarmers']),
      MapEntry('Procurement kg', metrics['procurementVolumeKg']),
      MapEntry('Stock on hand kg', metrics['stockOnHandKg']),
      MapEntry('Production output kg', metrics['productionOutputKg']),
      MapEntry('Sales value', metrics['salesValue']),
      MapEntry('AI usage', metrics['aiUsage']),
      MapEntry('Notification usage', metrics['notificationUsage']),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: _SectionHeader(
                  title: 'Platform analytics',
                  subtitle:
                      'Global operating totals with FPC and date-filtered exports.',
                ),
              ),
              FilledButton.icon(
                onPressed: _showPlatformReport,
                icon: const Icon(Icons.download_rounded),
                label: Text(UiStrings.fromEnglish('Export report')),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              childAspectRatio: 1.65,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, index) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[index].key,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${items[index].value ?? 0}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.greenDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsPanel() {
    const defaults = [
      ('weather_api', 'Weather API'),
      ('satellite_api', 'Satellite API'),
      ('ai_configuration', 'AI Configuration'),
      ('in_app_notifications', 'In-app notifications'),
      ('sms_adapter', 'SMS adapter'),
      ('whatsapp_adapter', 'WhatsApp adapter'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionHeader(
          title: 'Platform settings',
          subtitle:
              'Only non-secret enabled state is stored here. Provider secrets remain server-side.',
        ),
        const SizedBox(height: 10),
        for (final item in defaults)
          Builder(
            builder: (_) {
              final existing = _settings
                  .where((row) => row['key'] == item.$1)
                  .firstOrNull;
              final enabled = existing?['enabled'] == true;
              return Card(
                child: SwitchListTile(
                  value: enabled,
                  title: Text(
                    item.$2,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    item.$1.endsWith('adapter')
                        ? 'Adapter available; live provider disabled by default.'
                        : 'Platform-wide configuration reference.',
                  ),
                  onChanged: (value) async {
                    await _service.savePlatformSetting(
                      key: item.$1,
                      category: item.$1.split('_').first,
                      enabled: value,
                    );
                    await _load();
                  },
                ),
              );
            },
          ),
        const SizedBox(height: 18),
        _SectionHeader(
          title: UiStrings.t('platform_notification_templates'),
          subtitle: UiStrings.t('platform_notification_templates_status'),
        ),
        const SizedBox(height: 10),
        for (final eventKey in const [
          'fpc_approval',
          'field_assignment',
          'procurement_schedule',
          'quality_status',
          'payment_verification',
          'low_stock',
          'expiry_alert',
          'delivery_status',
        ])
          Builder(
            builder: (_) {
              final template = _templates
                  .where((row) => row['event_key'] == eventKey)
                  .firstOrNull;
              return Card(
                child: ListTile(
                  leading: Icon(
                    template?['enabled'] == true
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  title: Text(
                    eventKey.replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${template?['title_template'] ?? 'Template not configured'}',
                  ),
                  trailing: IconButton(
                    tooltip: UiStrings.fromEnglish('Edit template'),
                    onPressed: () => _showTemplate(eventKey, template),
                    icon: const Icon(Icons.edit_notifications_outlined),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _auditPanel() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _SectionHeader(
        title: 'Audit log',
        subtitle:
            'Organization, user, configuration, stock and finance events.',
      ),
      const SizedBox(height: 10),
      if (_audit.isEmpty)
        const _Empty(message: 'No audit events recorded yet.'),
      for (final event in _audit)
        Card(
          child: ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(
              '${event['action'] ?? 'event'}'.replaceAll('_', ' '),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${event['target_type'] ?? ''} · ${event['target_id'] ?? ''}\n${event['created_at'] ?? ''}',
            ),
            isThreeLine: true,
          ),
        ),
    ],
  );

  Future<void> _review(
    Map<String, dynamic> application,
    String decision,
  ) async {
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          UiStrings.fromEnglish(
            decision == 'approved' ? 'Approve FPC' : 'Reject FPC',
          ),
        ),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: UiStrings.fromEnglish(
              decision == 'approved'
                  ? 'Approval note (optional)'
                  : 'Rejection reason *',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UiStrings.fromEnglish('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              UiStrings.fromEnglish(
                decision == 'approved' ? 'Approve' : 'Reject',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.reviewApplication(
        applicationId: '${application['id']}',
        decision: decision,
        note: note.text,
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

  Future<void> _setStatus(String fpcId, String status) async {
    try {
      await _service.setFpcStatus(fpcId, status);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _showPlatformReport() async {
    var reportType = 'organizations';
    var format = 'pdf';
    var fpcId = '';
    final startsOn = TextEditingController();
    final endsOn = TextEditingController();
    final generate = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Export platform report')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reportType,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Report type'),
                  ),
                  items: [
                    for (final value in const [
                      'organizations',
                      'farmers',
                      'procurement',
                      'quality',
                      'inventory',
                      'production',
                      'sales',
                      'finance',
                      'audit',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(UiStrings.fromEnglish(value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => reportType = value ?? reportType),
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: fpcId,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('FPC filter'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(UiStrings.fromEnglish('All FPCs')),
                    ),
                    for (final fpc in _snapshot!.fpcs)
                      DropdownMenuItem(
                        value: '${fpc['id']}',
                        child: Text('${fpc['name']}'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => fpcId = value ?? ''),
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: format,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Format'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'pdf',
                      child: Text(UiStrings.fromEnglish('PDF')),
                    ),
                    DropdownMenuItem(
                      value: 'xlsx',
                      child: Text(UiStrings.fromEnglish('Excel')),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => format = value ?? format),
                ),
                const SizedBox(height: 9),
                _dialogField(startsOn, 'Start date (YYYY-MM-DD)'),
                _dialogField(endsOn, 'End date (YYYY-MM-DD)'),
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
              child: Text(UiStrings.fromEnglish('Generate')),
            ),
          ],
        ),
      ),
    );
    if (generate != true) return;
    try {
      final result = await FpcReportService().generatePlatformAndShare(
        reportType: reportType,
        format: format,
        fpcId: fpcId,
        startsOn: startsOn.text.trim(),
        endsOn: endsOn.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              UiStrings.fromEnglish(
                '${result.fileName} contains ${result.rowCount} records.',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showTemplate(
    String eventKey,
    Map<String, dynamic>? template,
  ) async {
    final title = TextEditingController(
      text: '${template?['title_template'] ?? ''}',
    );
    final body = TextEditingController(
      text: '${template?['body_template'] ?? ''}',
    );
    var enabled = template?['enabled'] == true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Edit notification template')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eventKey.replaceAll('_', ' '),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                _dialogField(title, 'Notification title *'),
                TextField(
                  controller: body,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Notification body *'),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  title: Text(UiStrings.fromEnglish('Enabled')),
                  onChanged: (value) => setDialogState(() => enabled = value),
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
    try {
      await _service.saveNotificationTemplate(
        eventKey: eventKey,
        title: title.text,
        body: body.text,
        enabled: enabled,
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showEditFpc(Map<String, dynamic> fpc) async {
    final name = TextEditingController(text: '${fpc['name'] ?? ''}');
    final legalName = TextEditingController(text: '${fpc['legal_name'] ?? ''}');
    final registration = TextEditingController(
      text: '${fpc['registration_number'] ?? ''}',
    );
    final gstin = TextEditingController(text: '${fpc['gstin'] ?? ''}');
    final email = TextEditingController(text: '${fpc['email'] ?? ''}');
    final phone = TextEditingController(text: '${fpc['phone'] ?? ''}');
    final addressValue = fpc['address'];
    final address = TextEditingController(
      text: addressValue is Map
          ? '${addressValue['text'] ?? addressValue['address'] ?? ''}'
          : '$addressValue',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UiStrings.fromEnglish('Edit FPC organization')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(name, 'Organization name *'),
              _dialogField(legalName, 'Legal name'),
              _dialogField(registration, 'Registration number'),
              _dialogField(gstin, 'GSTIN'),
              _dialogField(email, 'Email'),
              _dialogField(phone, 'Phone'),
              _dialogField(address, 'Address'),
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
    );
    if (save != true) return;
    try {
      await _service.updateFpc(
        fpcId: '${fpc['id']}',
        name: name.text,
        legalName: legalName.text,
        registrationNumber: registration.text,
        gstin: gstin.text,
        email: email.text,
        phone: phone.text,
        address: {'text': address.text},
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _showSubscription(Map<String, dynamic> fpc) async {
    final existing = _snapshot!.subscriptions
        .where((row) => row['fpc_id'] == fpc['id'])
        .firstOrNull;
    final plan = TextEditingController(
      text: '${existing?['plan_code'] ?? 'managed-prototype'}',
    );
    final amount = TextEditingController(text: '${existing?['amount'] ?? 0}');
    final tax = TextEditingController(text: '${existing?['tax_rate'] ?? 0}');
    final startsOn = TextEditingController(
      text:
          '${existing?['starts_on'] ?? DateTime.now().toIso8601String().substring(0, 10)}',
    );
    final endsOn = TextEditingController(text: '${existing?['ends_on'] ?? ''}');
    final limits = existing?['limits'] is Map
        ? Map<String, dynamic>.from(existing!['limits'] as Map)
        : <String, dynamic>{};
    final farmers = TextEditingController(text: '${limits['farmers'] ?? 5000}');
    final officers = TextEditingController(
      text: '${limits['fieldOfficers'] ?? 25}',
    );
    final storage = TextEditingController(
      text: '${limits['storageMb'] ?? 2048}',
    );
    var status = '${existing?['status'] ?? 'active'}';
    var issueInvoice = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Manage subscription')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(plan, 'Plan code *'),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Subscription status'),
                  ),
                  items: [
                    for (final value in const [
                      'trial',
                      'active',
                      'past_due',
                      'suspended',
                      'cancelled',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(UiStrings.fromEnglish(value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => status = value ?? status),
                ),
                _dialogField(amount, 'Amount'),
                _dialogField(tax, 'Tax percent'),
                _dialogField(startsOn, 'Starts on (YYYY-MM-DD)'),
                _dialogField(endsOn, 'Ends on (YYYY-MM-DD)'),
                _dialogField(farmers, 'Farmer limit'),
                _dialogField(officers, 'Field Officer limit'),
                _dialogField(storage, 'Storage limit MB'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: issueInvoice,
                  title: Text(
                    UiStrings.fromEnglish('Issue GST subscription invoice'),
                  ),
                  onChanged: (value) =>
                      setDialogState(() => issueInvoice = value),
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
    try {
      await _service.updateSubscription(
        fpcId: '${fpc['id']}',
        planCode: plan.text,
        status: status,
        amount: double.tryParse(amount.text) ?? 0,
        taxRate: double.tryParse(tax.text) ?? 0,
        startsOn: startsOn.text,
        endsOn: endsOn.text,
        limits: {
          'farmers': int.tryParse(farmers.text) ?? 0,
          'fieldOfficers': int.tryParse(officers.text) ?? 0,
          'storageMb': int.tryParse(storage.text) ?? 0,
        },
        issueInvoice: issueInvoice,
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _handleMemberAction(
    Map<String, dynamic> member,
    String action,
  ) async {
    try {
      if (action == 'active' || action == 'disabled') {
        await _service.setMembershipStatus(
          fpcId: '${member['fpc_id']}',
          membershipId: '${member['id']}',
          status: action,
        );
      } else if (action == 'reset_password') {
        final password = TextEditingController();
        final save = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(UiStrings.fromEnglish('Reset temporary password')),
            content: TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: UiStrings.fromEnglish(
                  'Temporary password (8+ characters)',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(UiStrings.fromEnglish('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(UiStrings.fromEnglish('Reset password')),
              ),
            ],
          ),
        );
        if (save != true) return;
        await _service.resetMembershipPassword(
          fpcId: '${member['fpc_id']}',
          membershipId: '${member['id']}',
          temporaryPassword: password.text,
        );
      }
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Widget _dialogField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: UiStrings.fromEnglish(label)),
        ),
      );

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _showCreateUser() async {
    final fpcs = _snapshot!.fpcs;
    if (fpcs.isEmpty) return;
    String fpcId = '${fpcs.first['id']}';
    String role = 'field_officer';
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UiStrings.fromEnglish('Create FPC user')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: fpcId,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('FPC'),
                  ),
                  items: [
                    for (final fpc in fpcs)
                      DropdownMenuItem(
                        value: '${fpc['id']}',
                        child: Text('${fpc['name']}'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => fpcId = value ?? fpcId),
                ),
                const SizedBox(height: 9),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: InputDecoration(
                    labelText: UiStrings.fromEnglish('Role'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'field_officer',
                      child: Text(UiStrings.fromEnglish('Field Officer')),
                    ),
                    DropdownMenuItem(
                      value: 'fpc_admin',
                      child: Text(UiStrings.fromEnglish('FPC Admin')),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
                ),
                const SizedBox(height: 9),
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
                    labelText: UiStrings.fromEnglish('Temporary password *'),
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
      ),
    );
    if (save != true) return;
    try {
      await _service.createFpcUser(
        fpcId: fpcId,
        role: role,
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: AppTheme.textMuted)),
    ],
  );
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(message)),
    ),
  );
}
