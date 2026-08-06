import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cross_file/cross_file.dart';

import '../models/fpc_operating_models.dart';
import '../models/fpc_farmer_profile.dart';
import '../models/farmer_delivery_timeline_item.dart';

class FpcOperatingException implements Exception {
  final String message;
  const FpcOperatingException(this.message);
  @override
  String toString() => message;
}

class FpcAnalyticsDay {
  final DateTime date;
  final double procurementKg;
  final double salesAmount;
  final int activityCount;

  const FpcAnalyticsDay({
    required this.date,
    required this.procurementKg,
    required this.salesAmount,
    required this.activityCount,
  });
}

class FpcAnalyticsSnapshot {
  final DateTime start;
  final DateTime end;
  final double procurementKg;
  final double salesAmount;
  final double stockMovementKg;
  final double farmerPayoutAmount;
  final int pendingPayments;
  final int activeFarmers;
  final int salesOrders;
  final List<FpcAnalyticsDay> daily;

  const FpcAnalyticsSnapshot({
    required this.start,
    required this.end,
    required this.procurementKg,
    required this.salesAmount,
    required this.stockMovementKg,
    required this.farmerPayoutAmount,
    required this.pendingPayments,
    required this.activeFarmers,
    required this.salesOrders,
    required this.daily,
  });
}

class FpcOperatingService {
  static const _fpcReadTimeout = Duration(seconds: 8);

  SupabaseClient get _client => Supabase.instance.client;

  Future<FpcMembershipContext> loadMembership() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const FpcOperatingException('Login required.');
    final row = await _client
        .from('fpc_memberships')
        .select(
          'id,fpc_id,role,status,must_change_password,'
          'fpcs!inner(id,name,legal_name,status,email,phone,'
          'registration_number,gstin,address)',
        )
        .eq('user_id', userId)
        .eq('status', 'active')
        .maybeSingle()
        .timeout(_fpcReadTimeout);
    if (row == null) {
      throw const FpcOperatingException('No active FPC membership was found.');
    }
    final fpc = row['fpcs'];
    if (fpc is! Map || '${fpc['status'] ?? ''}' != 'active') {
      throw const FpcOperatingException('This FPC is not active.');
    }
    return FpcMembershipContext.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FpcSessionContext> loadSessionContext() async {
    final membership = await loadMembership();
    final results = await Future.wait<Object?>([
      _client
          .from('fpcs')
          .select()
          .eq('id', membership.fpcId)
          .maybeSingle()
          .timeout(_fpcReadTimeout)
          .catchError((_) => null),
      _client
          .from('fpc_subscriptions')
          .select()
          .eq('fpc_id', membership.fpcId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(_fpcReadTimeout)
          .catchError((_) => null),
      loadSetupReadiness(membership)
          .timeout(_fpcReadTimeout)
          .catchError((_) => _fallbackReadiness(membership)),
    ]);
    return FpcSessionContext(
      membership: membership,
      fpc: _map(results[0]),
      subscription: _map(results[1]),
      readiness: results[2] is FpcSetupReadiness
          ? results[2] as FpcSetupReadiness
          : _fallbackReadiness(membership),
    );
  }

  Future<FpcSetupReadiness> loadSetupReadiness([
    FpcMembershipContext? membership,
  ]) async {
    final context = membership ?? await loadMembership();
    final counts = await Future.wait<int>([
      _countActiveFieldOfficers(context.fpcId),
      _countWhere('collection_centers', {
        'fpc_id': context.fpcId,
        'active': true,
      }),
      _countWhere('fpc_seed_batches', {'fpc_id': context.fpcId}),
      _countWhere('fpc_crop_programs', {'fpc_id': context.fpcId}),
      _countWhere('fpc_farmer_links', {'fpc_id': context.fpcId}),
      _countWhere('quality_certificates', {'fpc_id': context.fpcId}),
    ]);
    final fieldOfficerCount = counts[0];
    final hasProfile =
        context.fpcId.isNotEmpty &&
        context.fpcName.trim().isNotEmpty &&
        context.fpcStatus == 'active';
    final hasSeedOrProgram = counts[2] > 0 || counts[3] > 0;
    return FpcSetupReadiness(
      items: [
        FpcSetupItem(
          key: 'profile',
          title: 'FPC profile active',
          description:
              'Approved organization, active membership and server profile are required.',
          route: '/fpo/profile',
          complete: hasProfile,
        ),
        FpcSetupItem(
          key: 'field_team',
          title: 'Create Field Officer',
          description:
              'Add an active Field Officer before farmer visits and seed delivery.',
          route: '/fpo/team',
          complete: fieldOfficerCount > 0,
        ),
        FpcSetupItem(
          key: 'seed_stock',
          title: 'Seed stock or crop program',
          description: hasSeedOrProgram
              ? '${counts[3]} crop program${counts[3] == 1 ? '' : 's'} and ${counts[2]} seed batch${counts[2] == 1 ? '' : 'es'} found.'
              : 'Register seed stock or create a crop program before distribution.',
          route: '/fpo/seeds',
          complete: hasSeedOrProgram,
          required: false,
        ),
        FpcSetupItem(
          key: 'collection_center',
          title: 'Collection center ready',
          description: counts[1] > 0
              ? '${counts[1]} active collection center${counts[1] == 1 ? '' : 's'} ready for receiving.'
              : 'Create an active collection center before receiving farmer produce.',
          route: '/fpo/operations',
          complete: counts[1] > 0,
          required: false,
        ),
        FpcSetupItem(
          key: 'farmer_network',
          title: 'Farmer network started',
          description: 'Link farmers through verified QR scan.',
          route: '/fpo/farmers',
          complete: counts[4] > 0,
          required: false,
        ),
        FpcSetupItem(
          key: 'quality_flow',
          title: 'Quality workflow used',
          description: 'Run grading or quality certificate review.',
          route: '/fpo/grain-grading',
          complete: counts[5] > 0,
          required: false,
        ),
      ],
    );
  }

  Future<PlatformFpcSnapshot> loadPlatformSnapshot() async {
    final response = await _client.functions.invoke(
      'fpc-platform-admin',
      headers: _authHeaders(),
      body: const {'action': 'list'},
    );
    final data = _map(response.data);
    _throwIfFailed(data, 'Could not load FPC organizations.');
    return PlatformFpcSnapshot.fromJson(data);
  }

  Future<void> reviewApplication({
    required String applicationId,
    required String decision,
    String note = '',
  }) async {
    final response = await _client.functions.invoke(
      'fpc-platform-admin',
      headers: _authHeaders(),
      body: {
        'action': 'review',
        'applicationId': applicationId,
        'decision': decision,
        'note': note,
      },
    );
    _throwIfFailed(_map(response.data), 'Could not review FPC application.');
  }

  Future<void> setFpcStatus(String fpcId, String status) async {
    final response = await _client.functions.invoke(
      'fpc-platform-admin',
      headers: _authHeaders(),
      body: {'action': 'set_fpc_status', 'fpcId': fpcId, 'status': status},
    );
    _throwIfFailed(_map(response.data), 'Could not update FPC status.');
  }

  Future<void> updateFpc({
    required String fpcId,
    required String name,
    required String legalName,
    required String registrationNumber,
    required String gstin,
    required String email,
    required String phone,
    Map<String, dynamic> address = const {},
  }) async {
    final response = await _client.functions.invoke(
      'fpc-platform-admin',
      headers: _authHeaders(),
      body: {
        'action': 'update_fpc',
        'fpcId': fpcId,
        'name': name,
        'legalName': legalName,
        'registrationNumber': registrationNumber,
        'gstin': gstin,
        'email': email,
        'phone': phone,
        'address': address,
      },
    );
    _throwIfFailed(_map(response.data), 'Could not update FPC details.');
  }

  Future<void> updateSubscription({
    required String fpcId,
    required String planCode,
    required String status,
    required double amount,
    required double taxRate,
    required String startsOn,
    String endsOn = '',
    Map<String, dynamic> limits = const {},
    bool issueInvoice = false,
  }) async {
    final response = await _client.functions.invoke(
      'fpc-platform-admin',
      headers: _authHeaders(),
      body: {
        'action': 'update_subscription',
        'fpcId': fpcId,
        'planCode': planCode,
        'status': status,
        'amount': amount,
        'taxRate': taxRate,
        'startsOn': startsOn,
        'endsOn': endsOn,
        'limits': limits,
        'issueInvoice': issueInvoice,
      },
    );
    _throwIfFailed(_map(response.data), 'Could not update subscription.');
  }

  Future<List<Map<String, dynamic>>> loadPlatformSettings() async {
    final rows = await _client
        .from('platform_settings')
        .select()
        .order('category');
    return _rows(rows);
  }

  Future<void> savePlatformSetting({
    required String key,
    required String category,
    required bool enabled,
    Map<String, dynamic> config = const {},
  }) async {
    await _client.from('platform_settings').upsert({
      'key': key,
      'category': category,
      'enabled': enabled,
      'config': config,
      'updated_by': _client.auth.currentUser?.id,
    });
  }

  Future<List<Map<String, dynamic>>> loadNotificationTemplates() async {
    final rows = await _client
        .from('notification_templates')
        .select()
        .order('event_key');
    return _rows(rows);
  }

  Future<void> saveNotificationTemplate({
    required String eventKey,
    required String title,
    required String body,
    required bool enabled,
    List<String> channels = const ['in_app'],
  }) async {
    await _client.from('notification_templates').upsert({
      'event_key': eventKey,
      'title_template': title,
      'body_template': body,
      'channels': channels,
      'enabled': enabled,
      'updated_by': _client.auth.currentUser?.id,
    }, onConflict: 'event_key');
  }

  Future<List<Map<String, dynamic>>> loadAuditEvents() async {
    final rows = await _client
        .from('audit_events')
        .select()
        .order('created_at', ascending: false)
        .limit(300);
    return _rows(rows);
  }

  Future<List<Map<String, dynamic>>> loadMemberships([String? fpcId]) async {
    final response = await _client.functions.invoke(
      'fpc-user-admin',
      headers: _authHeaders(),
      // ignore: use_null_aware_elements
      body: {'action': 'list', if (fpcId != null) 'fpcId': fpcId},
    );
    final data = _map(response.data);
    _throwIfFailed(data, 'Could not load FPC users.');
    return _rows(data['memberships']);
  }

  Future<void> createFpcUser({
    String? fpcId,
    required String role,
    required String displayName,
    required String email,
    required String phone,
    required String temporaryPassword,
  }) async {
    final response = await _client.functions.invoke(
      'fpc-user-admin',
      headers: _authHeaders(),
      body: {
        'action': 'create',
        // ignore: use_null_aware_elements
        if (fpcId != null) 'fpcId': fpcId,
        'role': role,
        'displayName': displayName,
        'email': email,
        'phone': phone,
        'temporaryPassword': temporaryPassword,
      },
    );
    _throwIfFailed(_map(response.data), 'Could not create FPC user.');
  }

  Future<void> setMembershipStatus({
    required String fpcId,
    required String membershipId,
    required String status,
  }) async {
    final response = await _client.functions.invoke(
      'fpc-user-admin',
      headers: _authHeaders(),
      body: {
        'action': 'set_status',
        'fpcId': fpcId,
        'membershipId': membershipId,
        'status': status,
      },
    );
    _throwIfFailed(_map(response.data), 'Could not update FPC user.');
  }

  Future<void> resetMembershipPassword({
    required String fpcId,
    required String membershipId,
    required String temporaryPassword,
  }) async {
    final response = await _client.functions.invoke(
      'fpc-user-admin',
      headers: _authHeaders(),
      body: {
        'action': 'reset_password',
        'fpcId': fpcId,
        'membershipId': membershipId,
        'temporaryPassword': temporaryPassword,
      },
    );
    _throwIfFailed(_map(response.data), 'Could not reset FPC user password.');
  }

  Future<List<FieldAssignmentRecord>> loadFieldAssignments() async {
    final rows = await _client
        .from('field_assignments')
        .select()
        .order('scheduled_for')
        .limit(200);
    return _rows(
      rows,
    ).map(FieldAssignmentRecord.fromJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> loadAssignedFarmInsights(String farmId) async {
    if (farmId.isEmpty) return const {};
    final results = await Future.wait([
      _client.from('farms').select().eq('id', farmId).maybeSingle(),
      _client
          .from('farm_data_snapshots')
          .select()
          .eq('farm_id', farmId)
          .order('snapshot_date', ascending: false)
          .limit(1),
      _client
          .from('disease_risk_cells')
          .select(
            'scan_date,crop,growth_stage,composite_risk,ndvi,weather_risk',
          )
          .eq('farm_id', farmId)
          .order('scan_date', ascending: false)
          .limit(20),
      _client
          .from('disease_scout_zones')
          .select('scan_date,max_risk_score,disease_candidates,status')
          .eq('farm_id', farmId)
          .order('scan_date', ascending: false)
          .limit(20),
      _client
          .from('farm_timeline_events')
          .select('event_type,title,message,stage,severity,created_at')
          .eq('farm_id', farmId)
          .order('created_at', ascending: false)
          .limit(20),
    ]);
    return {
      'farm': results[0],
      'snapshot': _rows(results[1]).firstOrNull,
      'risk_cells': _rows(results[2]),
      'scout_zones': _rows(results[3]),
      'timeline': _rows(results[4]),
    };
  }

  Future<void> createFieldAssignment({
    required FpcMembershipContext membership,
    required String officerUserId,
    required String type,
    required String title,
    required String instructions,
    String farmerId = '',
    String farmId = '',
    DateTime? scheduledFor,
  }) async {
    await _client.from('field_assignments').insert({
      'fpc_id': membership.fpcId,
      'officer_user_id': officerUserId,
      'assignment_type': type,
      'title': title,
      'instructions': instructions,
      'farmer_id': farmerId,
      'farm_id': farmId,
      if (scheduledFor != null)
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> updateAssignmentStatus(
    String id,
    String status,
    int version,
  ) async {
    final saved = await _client
        .from('field_assignments')
        .update({'status': status, 'server_version': version + 1})
        .eq('id', id)
        .eq('server_version', version)
        .select('id')
        .maybeSingle();
    if (saved == null) {
      throw const FpcOperatingException(
        'This assignment changed on the server. Refresh and retry.',
      );
    }
  }

  Future<void> saveFieldVisit(Map<String, dynamic> payload) async {
    final membership = await loadMembership();
    final userId = _client.auth.currentUser?.id;
    if (userId == null || !membership.isFieldOfficer) {
      throw const FpcOperatingException('Field Officer access required.');
    }
    final savedPayload = Map<String, dynamic>.from(payload);
    final localPhotos = payload['photo_paths'] is List
        ? List<String>.from(
            (payload['photo_paths'] as List).map((item) => '$item'),
          )
        : const <String>[];
    final uploadedPhotos = <Map<String, dynamic>>[];
    for (var index = 0; index < localPhotos.length; index++) {
      final localPath = localPhotos[index];
      final extension = localPath.contains('.')
          ? localPath.split('.').last.toLowerCase()
          : 'jpg';
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'image/jpeg',
      };
      final clientUuid = '${payload['client_uuid'] ?? const Uuid().v4()}';
      final storagePath =
          '${membership.fpcId}/$userId/$clientUuid/evidence-$index.$extension';
      await _client.storage
          .from('fpc-field-evidence')
          .uploadBinary(
            storagePath,
            await XFile(localPath).readAsBytes(),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      uploadedPhotos.add({
        'bucket': 'fpc-field-evidence',
        'path': storagePath,
        'content_type': contentType,
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    savedPayload.remove('photo_paths');
    if (uploadedPhotos.isNotEmpty) savedPayload['photos'] = uploadedPhotos;
    await _client.from('field_visits').upsert({
      ...savedPayload,
      'fpc_id': membership.fpcId,
      'officer_user_id': userId,
      'sync_status': 'synced',
    }, onConflict: 'officer_user_id,client_uuid');
  }

  Future<void> linkFarmer(Map<String, dynamic> qrPayload) async {
    await _client.rpc(
      'link_farmer_to_current_fpc',
      params: {'payload': qrPayload},
    );
  }

  Future<List<FpcFarmerProfile>> loadFarmerDirectory() async {
    final rows = await loadModuleRows('farmer_network');
    return rows.map(FpcFarmerProfile.fromLinkRow).toList(growable: false);
  }

  Future<List<FarmerDeliveryTimelineItem>> loadFarmerDeliveryTimeline(
    String farmerId,
  ) async {
    final id = farmerId.trim();
    if (id.isEmpty) return const [];
    final rows = await _client
        .from('farmer_delivery_timeline')
        .select()
        .eq('farmer_id', id)
        .order('occurred_at', ascending: false)
        .limit(300);
    return _rows(
      rows,
    ).map(FarmerDeliveryTimelineItem.fromJson).toList(growable: false);
  }

  Future<Map<String, int>> loadOperationalCounts() async {
    final results = await Future.wait([
      _count('fpc_farmer_links'),
      _count('fpc_seed_requests'),
      _count('fpc_farmer_links'),
      _count('harvest_plans'),
      _count('procurement_lots'),
      _count('fpc_procurement_records'),
      _count('quality_certificates'),
      _count('warehouses'),
      _count('production_runs'),
      _count('packaging_batches'),
      _count('stock_ledger'),
      _count('sales_orders'),
      _count('dispatches'),
      _count('farmer_payment_ledger'),
      _count('fpc_report_exports'),
      _count('ai_insights'),
    ]);
    const modules = [
      'farmer_network',
      'crop_programs',
      'farm_monitoring',
      'harvest_planning',
      'procurement',
      'collection_center',
      'quality',
      'warehouse',
      'production',
      'packaging',
      'inventory',
      'sales',
      'logistics',
      'farmer_payments',
      'reports',
      'ai_insights',
    ];
    return {
      for (var index = 0; index < modules.length; index++)
        modules[index]: results[index],
    };
  }

  Future<List<Map<String, dynamic>>> loadModuleRows(String module) async {
    if (module == 'crop_programs') {
      return _combined([
        (
          'seed_request',
          await _client
              .from('fpc_seed_requests')
              .select(
                '*,program:fpc_crop_programs(name,crop,variety),'
                'enrollment:fpc_program_enrollments(status)',
              )
              .order('updated_at', ascending: false)
              .limit(300),
        ),
        (
          'program',
          await _client
              .from('fpc_crop_programs')
              .select()
              .order('created_at', ascending: false)
              .limit(100),
        ),
        (
          'seed_batch',
          await _client
              .from('fpc_seed_batches')
              .select()
              .order('created_at', ascending: false)
              .limit(200),
        ),
        (
          'enrollment',
          await _client
              .from('fpc_program_enrollments')
              .select()
              .order('updated_at', ascending: false)
              .limit(300),
        ),
        (
          'seed_issue',
          await _client
              .from('fpc_seed_issues')
              .select(
                '*,enrollment:fpc_program_enrollments(farmer_id,farm_id,crop,status)',
              )
              .order('updated_at', ascending: false)
              .limit(300),
        ),
        (
          'seed_payment',
          await _client
              .from('fpc_seed_payment_attempts')
              .select(
                '*,seed_request:fpc_seed_requests(farmer_id,farm_id,status,payment_status)',
              )
              .order('updated_at', ascending: false)
              .limit(300),
        ),
        (
          'evaluation',
          await _client
              .from('fpc_compliance_evaluations')
              .select()
              .order('created_at', ascending: false)
              .limit(300),
        ),
      ]);
    }
    if (module == 'procurement') {
      return _combined([
        (
          'schedule',
          await _client
              .from('procurement_schedules')
              .select()
              .order('scheduled_at', ascending: false)
              .limit(200),
        ),
        (
          'lot',
          await _client
              .from('procurement_lots')
              .select()
              .order('received_at', ascending: false)
              .limit(300),
        ),
        (
          'vehicle',
          await _client
              .from('vehicle_assignments')
              .select()
              .order('created_at', ascending: false)
              .limit(100),
        ),
      ]);
    }
    if (module == 'collection_center') {
      return _combined([
        (
          'center',
          await _client
              .from('collection_centers')
              .select()
              .order('active', ascending: false)
              .order('name')
              .order('village')
              .order('id')
              .limit(100),
        ),
        (
          'receipt',
          await _client
              .from('fpc_procurement_records')
              .select()
              .order('received_at', ascending: false)
              .limit(300),
        ),
      ]);
    }
    if (module == 'warehouse') {
      return _combined([
        (
          'warehouse',
          await _client.from('warehouses').select().order('name').limit(100),
        ),
        (
          'location',
          await _client
              .from('warehouse_locations')
              .select()
              .order('code')
              .limit(300),
        ),
      ]);
    }
    if (module == 'farm_monitoring') {
      final links = _rows(
        await _client
            .from('fpc_farmer_links')
            .select()
            .order('updated_at', ascending: false)
            .limit(300),
      );
      final farmIds = links
          .map((row) => '${row['farm_id'] ?? ''}')
          .where(
            (id) => RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
            ).hasMatch(id),
          )
          .toSet()
          .toList();
      if (farmIds.isEmpty) return _combined([('farmer_link', links)]);
      return _combined([
        ('farmer_link', links),
        ('farm', await _client.from('farms').select().inFilter('id', farmIds)),
        (
          'snapshot',
          await _client
              .from('farm_data_snapshots')
              .select()
              .inFilter('farm_id', farmIds)
              .order('snapshot_date', ascending: false)
              .limit(300),
        ),
      ]);
    }
    if (module == 'sales') {
      return _combined([
        (
          'order',
          await _client
              .from('sales_orders')
              .select('*,buyers(name,buyer_type),sales_order_items(*)')
              .order('ordered_at', ascending: false)
              .limit(300),
        ),
        (
          'buyer',
          await _client.from('buyers').select().order('name').limit(300),
        ),
        (
          'payment',
          await _client
              .from('sales_payment_ledger')
              .select('*,sales_orders(order_number,invoice_number)')
              .order('recorded_at', ascending: false)
              .limit(300),
        ),
        (
          'credit_note',
          await _client
              .from('sales_credit_notes')
              .select()
              .order('issued_at', ascending: false)
              .limit(300),
        ),
      ]);
    }
    final result = switch (module) {
      'farmer_network' =>
        _client
            .from('fpc_farmer_links')
            .select()
            .order('updated_at', ascending: false)
            .limit(300),
      'harvest_planning' =>
        _client
            .from('harvest_plans')
            .select()
            .order('expected_harvest_date')
            .limit(300),
      'quality' =>
        _client
            .from('quality_certificates')
            .select()
            .order('created_at', ascending: false)
            .limit(300),
      'production' =>
        _client
            .from('production_runs')
            .select()
            .order('created_at', ascending: false)
            .limit(300),
      'packaging' =>
        _client
            .from('packaging_batches')
            .select()
            .order('created_at', ascending: false)
            .limit(300),
      'inventory' =>
        _client
            .from('stock_ledger')
            .select()
            .order('occurred_at', ascending: false)
            .limit(500),
      'logistics' =>
        _client
            .from('dispatches')
            .select('*,sales_orders(order_number,invoice_number,total)')
            .order('created_at', ascending: false)
            .limit(300),
      'farmer_payments' =>
        _client
            .from('farmer_payment_ledger')
            .select('*,procurement_lots(batch_id,crop)')
            .order('created_at', ascending: false)
            .limit(300),
      'reports' =>
        _client
            .from('fpc_report_exports')
            .select()
            .order('generated_at', ascending: false)
            .limit(100),
      'ai_insights' =>
        _client
            .from('ai_insights')
            .select()
            .order('generated_at', ascending: false)
            .limit(100),
      _ => throw const FpcOperatingException('Unsupported FPC module.'),
    };
    return _rows(await result);
  }

  Future<List<Map<String, dynamic>>> loadLookup(String table) async {
    const allowed = {
      'fpc_farmer_links',
      'harvest_plans',
      'collection_centers',
      'fpc_memberships',
      'procurement_schedules',
      'procurement_lots',
      'analysis_jobs',
      'warehouses',
      'warehouse_locations',
      'production_runs',
      'packaging_batches',
      'buyers',
      'sales_orders',
      'dispatches',
      'fpc_crop_programs',
      'fpc_seed_batches',
      'fpc_program_enrollments',
      'fpc_seed_requests',
    };
    if (!allowed.contains(table)) {
      throw const FpcOperatingException('Unsupported lookup.');
    }
    return _rows(await _client.from(table).select().limit(500));
  }

  Future<Map<String, dynamic>> executeOperation(
    String operation,
    Map<String, dynamic> payload, {
    String? requestId,
  }) async {
    final result = await _client.rpc(
      'fpc_execute_operation',
      params: {
        'operation_name': operation,
        'payload': payload,
        'client_request_id': requestId ?? const Uuid().v4(),
      },
    );
    if (result is! Map) return const {};
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> loadDashboardMetrics() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).toIso8601String();
    final results = await Future.wait([
      _client.from('harvest_plans').select('expected_quantity_kg,readiness'),
      _client
          .from('fpc_procurement_records')
          .select('net_weight_kg,received_at')
          .gte('received_at', today),
      _client.from('procurement_lots').select('status'),
      _client.from('warehouses').select('capacity_kg'),
      _client.from('stock_ledger').select('quantity_kg'),
      _client
          .from('production_runs')
          .select('output_kg,completed_at,status')
          .gte('completed_at', today),
      _client
          .from('sales_orders')
          .select('total,ordered_at,status')
          .gte('ordered_at', today),
      _client.from('farmer_payment_ledger').select('final_amount,status'),
      _client.from('ai_insights').select('id').limit(100),
    ]);
    final harvest = _rows(results[0]);
    final procurement = _rows(results[1]);
    final lots = _rows(results[2]);
    final warehouses = _rows(results[3]);
    final stock = _rows(results[4]);
    final production = _rows(results[5]);
    final sales = _rows(results[6]);
    final payments = _rows(results[7]);
    return {
      'ready_farms': harvest
          .where((row) => '${row['readiness']}' == 'ready')
          .length,
      'expected_procurement_kg': _sum(harvest, 'expected_quantity_kg'),
      'today_procurement_kg': _sum(procurement, 'net_weight_kg'),
      'open_lots': lots
          .where(
            (row) => !{'completed', 'cancelled'}.contains('${row['status']}'),
          )
          .length,
      'warehouse_capacity_kg': _sum(warehouses, 'capacity_kg'),
      'stock_kg': _sum(stock, 'quantity_kg'),
      'today_production_kg': _sum(production, 'output_kg'),
      'today_sales': _sum(sales, 'total'),
      'pending_payments': payments
          .where((row) => !{'paid', 'reversed'}.contains('${row['status']}'))
          .length,
      'pending_payment_amount': _sum(
        payments
            .where((row) => !{'paid', 'reversed'}.contains('${row['status']}'))
            .toList(),
        'final_amount',
      ),
      'ai_alerts': _rows(results[8]).length,
    };
  }

  Future<FpcAnalyticsSnapshot> loadAnalytics({
    required DateTime start,
    required DateTime end,
  }) async {
    final rangeStart = DateTime(start.year, start.month, start.day).toUtc();
    final rangeEnd = DateTime(end.year, end.month, end.day).toUtc();
    if (rangeEnd.isBefore(rangeStart)) {
      throw const FpcOperatingException(
        'Choose an end date after the start date.',
      );
    }
    final exclusiveEnd = rangeEnd.add(const Duration(days: 1));
    final results = await Future.wait([
      _client
          .from('fpc_procurement_records')
          .select('net_weight_kg,received_at,farmer_id')
          .gte('received_at', rangeStart.toIso8601String())
          .lt('received_at', exclusiveEnd.toIso8601String())
          .limit(5000),
      _client
          .from('sales_orders')
          .select('total,ordered_at,status')
          .gte('ordered_at', rangeStart.toIso8601String())
          .lt('ordered_at', exclusiveEnd.toIso8601String())
          .limit(5000),
      _client
          .from('stock_ledger')
          .select('quantity_kg,created_at')
          .gte('created_at', rangeStart.toIso8601String())
          .lt('created_at', exclusiveEnd.toIso8601String())
          .limit(5000),
      _client
          .from('farmer_payment_ledger')
          .select('final_amount,status,created_at')
          .gte('created_at', rangeStart.toIso8601String())
          .lt('created_at', exclusiveEnd.toIso8601String())
          .limit(5000),
    ]);
    final procurement = _rows(results[0]);
    final sales = _rows(
      results[1],
    ).where((row) => '${row['status']}' != 'cancelled').toList(growable: false);
    final stock = _rows(results[2]);
    final payments = _rows(results[3]);
    final daily = <DateTime, _AnalyticsDayBuilder>{};

    void addToDay(Object? value, void Function(_AnalyticsDayBuilder day) add) {
      final parsed = value == null ? null : DateTime.tryParse('$value');
      if (parsed == null) return;
      final date = DateTime(parsed.year, parsed.month, parsed.day);
      add(daily.putIfAbsent(date, () => _AnalyticsDayBuilder()));
    }

    for (final row in procurement) {
      addToDay(row['received_at'], (day) {
        day.procurementKg += _number(row['net_weight_kg']);
        day.activityCount++;
      });
    }
    for (final row in sales) {
      addToDay(row['ordered_at'], (day) {
        day.salesAmount += _number(row['total']);
        day.activityCount++;
      });
    }
    for (final row in payments) {
      addToDay(row['created_at'], (day) => day.activityCount++);
    }

    final days = <FpcAnalyticsDay>[];
    for (
      var date = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
      !date.isAfter(rangeEnd);
      date = date.add(const Duration(days: 1))
    ) {
      final day = daily[date] ?? _AnalyticsDayBuilder();
      days.add(
        FpcAnalyticsDay(
          date: date,
          procurementKg: day.procurementKg,
          salesAmount: day.salesAmount,
          activityCount: day.activityCount,
        ),
      );
    }

    return FpcAnalyticsSnapshot(
      start: rangeStart,
      end: rangeEnd,
      procurementKg: _sum(procurement, 'net_weight_kg'),
      salesAmount: _sum(sales, 'total'),
      stockMovementKg: _sum(stock, 'quantity_kg').abs(),
      farmerPayoutAmount: _sum(
        payments.where((row) => '${row['status']}' == 'paid').toList(),
        'final_amount',
      ),
      pendingPayments: payments
          .where((row) => !{'paid', 'reversed'}.contains('${row['status']}'))
          .length,
      activeFarmers: procurement
          .map((row) => '${row['farmer_id'] ?? ''}'.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .length,
      salesOrders: sales.length,
      daily: days,
    );
  }

  Future<List<Map<String, dynamic>>> loadNotifications({
    bool unreadOnly = false,
  }) async {
    var query = _client.from('fpc_notifications').select();
    if (unreadOnly) query = query.isFilter('read_at', null);
    return _rows(await query.order('created_at', ascending: false).limit(100));
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('fpc_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId);
  }

  Future<List<Map<String, dynamic>>> loadReportRows(String reportType) async {
    if (reportType == 'farmers') {
      final links = _rows(await _client.from('fpc_farmer_links').select());
      final farmIds = links
          .map((row) => '${row['farm_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final farms = farmIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : _rows(await _client.from('farms').select().inFilter('id', farmIds));
      return _combined([('farmer_link', links), ('farm', farms)]);
    }
    if (reportType == 'quality') {
      return _combined([
        ('certificate', await _client.from('quality_certificates').select()),
        (
          'grading_job',
          await _client
              .from('analysis_jobs')
              .select(
                'id,batch_id,crop_type,status,final_grade,final_score,moisture_percent,review_status,created_at',
              ),
        ),
      ]);
    }
    if (reportType == 'finance') {
      return _combined([
        (
          'farmer_payment',
          await _client.from('farmer_payment_ledger').select(),
        ),
        ('buyer_payment', await _client.from('sales_payment_ledger').select()),
        ('credit_note', await _client.from('sales_credit_notes').select()),
      ]);
    }
    if (reportType == 'warehouse') {
      return _combined([
        ('warehouse', await _client.from('warehouses').select()),
        ('location', await _client.from('warehouse_locations').select()),
        ('stock_movement', await _client.from('stock_ledger').select()),
      ]);
    }
    final table = switch (reportType) {
      'procurement' => 'fpc_procurement_records',
      'inventory' => 'stock_ledger',
      'production' => 'production_runs',
      'packaging' => 'packaging_batches',
      'sales' => 'sales_orders',
      'logistics' => 'dispatches',
      _ => throw const FpcOperatingException('Unsupported report type.'),
    };
    return _rows(await _client.from(table).select().limit(5000));
  }

  Future<int> _count(String table) async {
    final result = await _client
        .from(table)
        .select('id')
        .count(CountOption.exact);
    return result.count;
  }

  Future<int> _countWhere(String table, Map<String, Object?> filters) async {
    try {
      dynamic query = _client.from(table).select('id').count(CountOption.exact);
      for (final entry in filters.entries) {
        final value = entry.value;
        if (value is String && value.isEmpty) continue;
        if (value != null) query = query.eq(entry.key, value);
      }
      final result = await query;
      return result.count as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _countActiveFieldOfficers(String fpcId) async {
    try {
      final memberships = await loadMemberships(fpcId);
      return memberships
          .where(
            (row) =>
                row['role'] == 'field_officer' && row['status'] == 'active',
          )
          .length;
    } catch (_) {
      return _countWhere('fpc_memberships', {
        'fpc_id': fpcId,
        'role': 'field_officer',
        'status': 'active',
      });
    }
  }

  FpcSetupReadiness _fallbackReadiness(FpcMembershipContext membership) {
    final hasProfile =
        membership.fpcId.isNotEmpty &&
        membership.fpcName.trim().isNotEmpty &&
        membership.fpcStatus == 'active';
    return FpcSetupReadiness(
      items: [
        FpcSetupItem(
          key: 'profile',
          title: 'FPC profile active',
          description:
              'Approved organization, active membership and server profile are required.',
          route: '/fpo/profile',
          complete: hasProfile,
        ),
      ],
    );
  }

  double _sum(List<Map<String, dynamic>> rows, String key) => rows.fold(
    0,
    (sum, row) => sum + (num.tryParse('${row[key] ?? 0}')?.toDouble() ?? 0),
  );

  double _number(Object? value) =>
      num.tryParse('${value ?? 0}')?.toDouble() ?? 0;

  List<Map<String, dynamic>> _combined(List<(String, Object?)> groups) => [
    for (final group in groups)
      for (final row in _rows(group.$2)) {...row, '_entity': group.$1},
  ];

  Map<String, String>? _authHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    return token == null ? null : {'Authorization': 'Bearer $token'};
  }

  void _throwIfFailed(Map<String, dynamic> data, String fallback) {
    if (data['success'] == false) {
      throw FpcOperatingException('${data['error'] ?? fallback}');
    }
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}

class _AnalyticsDayBuilder {
  double procurementKg = 0;
  double salesAmount = 0;
  int activityCount = 0;
}
