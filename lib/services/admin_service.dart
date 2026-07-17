import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/stakeholder_land_record.dart';

class AdminServiceException implements Exception {
  final String message;

  const AdminServiceException(this.message);

  @override
  String toString() => message;
}

class AdminDashboardSnapshot {
  final DateTime? generatedAt;
  final Map<String, int> metrics;
  final List<AdminFarmerRecord> farmers;
  final List<AdminFpcRecord> fpcRecords;
  final List<AdminStakeholderRecord> stakeholders;

  const AdminDashboardSnapshot({
    required this.generatedAt,
    required this.metrics,
    required this.farmers,
    required this.fpcRecords,
    required this.stakeholders,
  });

  factory AdminDashboardSnapshot.fromJson(Map<String, dynamic> json) {
    final farms = _maps(json['farmerFarms']);
    final activities = _maps(json['farmerActivities']);
    final stakeholders = _maps(json['stakeholders']);
    final events = _maps(json['stakeholderEvents']);
    final stakeholderEventsById = <String, List<Map<String, dynamic>>>{};
    for (final event in events) {
      final appId = _text(event['application_id']);
      if (appId.isEmpty) continue;
      stakeholderEventsById.putIfAbsent(appId, () => []).add(event);
    }

    final fpcRecords = <AdminFpcRecord>[
      ..._maps(json['fpcJobs']).map(AdminFpcRecord.fromJob),
      ..._maps(json['fpcProcurements']).map(AdminFpcRecord.fromProcurement),
    ];
    fpcRecords.sort((a, b) {
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    return AdminDashboardSnapshot(
      generatedAt: _date(json['generatedAt'] ?? json['generated_at']),
      metrics: _intMap(json['metrics']),
      farmers: _maps(json['farmers'])
          .map(
            (row) => AdminFarmerRecord.fromJson(
              row,
              farms: farms,
              activities: activities,
            ),
          )
          .toList(growable: false),
      fpcRecords: fpcRecords,
      stakeholders: stakeholders
          .map(
            (row) => AdminStakeholderRecord.fromJson(
              row,
              events: stakeholderEventsById[_text(row['id'])] ?? const [],
            ),
          )
          .toList(growable: false),
    );
  }

  static AdminDashboardSnapshot empty() {
    return const AdminDashboardSnapshot(
      generatedAt: null,
      metrics: {},
      farmers: [],
      fpcRecords: [],
      stakeholders: [],
    );
  }
}

class AdminFarmerRecord {
  final String userId;
  final String phone;
  final String farmerId;
  final String farmerName;
  final String location;
  final String status;
  final int farmCount;
  final String latestActivity;
  final DateTime? updatedAt;

  const AdminFarmerRecord({
    required this.userId,
    required this.phone,
    required this.farmerId,
    required this.farmerName,
    required this.location,
    required this.status,
    required this.farmCount,
    required this.latestActivity,
    required this.updatedAt,
  });

  factory AdminFarmerRecord.fromJson(
    Map<String, dynamic> json, {
    required List<Map<String, dynamic>> farms,
    required List<Map<String, dynamic>> activities,
  }) {
    final farmerId = _text(json['farmer_id']);
    final phone = _normalizePhone(_text(json['phone']));
    final linkedFarms = farms
        .where((farm) {
          final farmFarmerId = _text(farm['farmer_id']);
          final farmPhone = _normalizePhone(_text(farm['farmer_phone']));
          return (farmerId.isNotEmpty && farmFarmerId == farmerId) ||
              (phone.isNotEmpty && farmPhone == phone);
        })
        .toList(growable: false);
    final activity = activities.cast<Map<String, dynamic>?>().firstWhere((row) {
      if (row == null) return false;
      final activityFarmerId = _text(row['farmer_id']);
      final activityPhone = _normalizePhone(_text(row['farmer_phone']));
      return (farmerId.isNotEmpty && activityFarmerId == farmerId) ||
          (phone.isNotEmpty && activityPhone == phone);
    }, orElse: () => null);
    return AdminFarmerRecord(
      userId: _text(json['user_id']),
      phone: phone,
      farmerId: farmerId,
      farmerName: _text(json['farmer_name'], 'Farmer'),
      location: _text(json['default_location']),
      status: _text(json['status'], 'active'),
      farmCount: linkedFarms.length,
      latestActivity: _text(
        activity?['activity_summary'],
        _text(activity?['activity_type']),
      ),
      updatedAt: _date(json['updated_at'] ?? json['created_at']),
    );
  }
}

class AdminFpcRecord {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String status;
  final String amount;
  final DateTime? createdAt;

  const AdminFpcRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.amount,
    required this.createdAt,
  });

  factory AdminFpcRecord.fromJob(Map<String, dynamic> json) {
    return AdminFpcRecord(
      id: _text(json['id']),
      type: 'Grading',
      title: _text(
        json['fpc_customer_name'],
        _text(json['farmer_id'], 'Grading review'),
      ),
      subtitle: [
        _text(json['crop']),
        _text(json['grade']),
        _text(json['farm_id']),
      ].where((value) => value.isNotEmpty).join(' - '),
      status: _text(json['review_status'], _text(json['status'], 'pending')),
      amount: _text(json['total_kg']).isEmpty ? '' : '${json['total_kg']} kg',
      createdAt: _date(json['created_at'] ?? json['reviewed_at']),
    );
  }

  factory AdminFpcRecord.fromProcurement(Map<String, dynamic> json) {
    final value = _double(json['total_value']);
    return AdminFpcRecord(
      id: _text(json['id']),
      type: 'Procurement',
      title: _text(json['customer_name'], _text(json['farmer_id'], 'Farmer')),
      subtitle: [
        _text(json['crop_type']),
        _text(json['variety']),
        _text(json['grade']),
      ].where((item) => item.isNotEmpty).join(' - '),
      status: _text(json['delivery_status'], 'received'),
      amount: value == null ? '' : 'Rs ${value.toStringAsFixed(0)}',
      createdAt: _date(json['received_at'] ?? json['created_at']),
    );
  }
}

class AdminStakeholderRecord {
  final String id;
  final String farmerId;
  final String farmerName;
  final String farmerPhone;
  final String farmerFullName;
  final String farmerFatherName;
  final String farmerMobileNumber;
  final String farmerVillage;
  final String farmerTaluka;
  final String farmerDistrict;
  final String farmerTotalLandAcres;
  final String nomineeName;
  final String nomineeMobileNumber;
  final int nomineeCount;
  final String nominee2Name;
  final String nominee2MobileNumber;
  final String panNumber;
  final String bankName;
  final String accountHolderName;
  final String ifscCode;
  final double selectedAmount;
  final int estimatedShares;
  final String status;
  final String paymentStatus;
  final String adminNote;
  final String panSource;
  final String panDocumentPath;
  final String landRecordSource;
  final String landRecordDetails;
  final String landRecordDocumentPath;
  final String bankSource;
  final String passbookDocumentPath;
  final String farmerSignaturePath;
  final String nomineeSignaturePath;
  final String nominee2SignaturePath;
  final String bankTransferReference;
  final String bankTransferProofPath;
  final bool hasPanDocument;
  final bool hasLandRecordDocument;
  final bool hasPassbookDocument;
  final List<AdminStakeholderTimelineEntry> timeline;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final DateTime? updatedAt;

  const AdminStakeholderRecord({
    required this.id,
    required this.farmerId,
    required this.farmerName,
    required this.farmerPhone,
    required this.farmerFullName,
    required this.farmerFatherName,
    required this.farmerMobileNumber,
    required this.farmerVillage,
    required this.farmerTaluka,
    required this.farmerDistrict,
    required this.farmerTotalLandAcres,
    required this.nomineeName,
    required this.nomineeMobileNumber,
    required this.nomineeCount,
    required this.nominee2Name,
    required this.nominee2MobileNumber,
    required this.panNumber,
    required this.bankName,
    required this.accountHolderName,
    required this.ifscCode,
    required this.selectedAmount,
    required this.estimatedShares,
    required this.status,
    required this.paymentStatus,
    required this.adminNote,
    required this.panSource,
    required this.panDocumentPath,
    required this.landRecordSource,
    required this.landRecordDetails,
    required this.landRecordDocumentPath,
    required this.bankSource,
    required this.passbookDocumentPath,
    required this.farmerSignaturePath,
    required this.nomineeSignaturePath,
    required this.nominee2SignaturePath,
    required this.bankTransferReference,
    required this.bankTransferProofPath,
    required this.hasPanDocument,
    required this.hasLandRecordDocument,
    required this.hasPassbookDocument,
    required this.timeline,
    required this.submittedAt,
    required this.reviewedAt,
    required this.updatedAt,
  });

  factory AdminStakeholderRecord.fromJson(
    Map<String, dynamic> json, {
    List<Map<String, dynamic>> events = const [],
  }) {
    final hasPanManual = RegExp(
      r'^[A-Z]{5}[0-9]{4}[A-Z]$',
    ).hasMatch(_text(json['pan_number']).toUpperCase());
    final hasPanDocument = _text(json['pan_document_path']).isNotEmpty;
    final landRecordDetails = _text(json['land_record_details']);
    final hasLandRecordManual = StakeholderLandRecordDetails.isCompleteSummary(
      landRecordDetails,
    );
    final hasLandRecord = _text(json['land_record_document_path']).isNotEmpty;
    final hasBankManual =
        _text(json['bank_name']).length >= 2 &&
        _text(json['account_holder_name']).length >= 2 &&
        RegExp(r'^[0-9]{6,20}$').hasMatch(_text(json['bank_account_number'])) &&
        RegExp(
          r'^[A-Z]{4}0[A-Z0-9]{6}$',
        ).hasMatch(_text(json['ifsc_code']).toUpperCase());
    final hasPassbook = _text(json['passbook_document_path']).isNotEmpty;
    final farmerPhone = _normalizePhone(_text(json['farmer_phone']));
    final farmerMobileNumber = _normalizePhone(
      _text(json['farmer_mobile_number']),
    );
    return AdminStakeholderRecord(
      id: _text(json['id']),
      farmerId: _text(json['farmer_id']),
      farmerName: _text(json['farmer_name'], 'Farmer'),
      farmerPhone: farmerPhone,
      farmerFullName: _text(json['farmer_full_name'] ?? json['farmer_name']),
      farmerFatherName: _text(json['farmer_father_name']),
      farmerMobileNumber: farmerMobileNumber.isEmpty
          ? farmerPhone
          : farmerMobileNumber,
      farmerVillage: _text(json['farmer_village']),
      farmerTaluka: _text(json['farmer_taluka']),
      farmerDistrict: _text(json['farmer_district']),
      farmerTotalLandAcres: _text(json['farmer_total_land_acres']),
      nomineeName: _text(json['nominee_name']),
      nomineeMobileNumber: _normalizePhone(
        _text(json['nominee_mobile_number']),
      ),
      nomineeCount: ((_int(json['nominee_count']) ?? 1).clamp(1, 2).toInt()),
      nominee2Name: _text(json['nominee2_name']),
      nominee2MobileNumber: _normalizePhone(
        _text(json['nominee2_mobile_number']),
      ),
      panNumber: _text(json['pan_number']).toUpperCase(),
      bankName: _text(json['bank_name']),
      accountHolderName: _text(json['account_holder_name']),
      ifscCode: _text(json['ifsc_code']).toUpperCase(),
      selectedAmount: _double(json['selected_amount']) ?? 0,
      estimatedShares: _int(json['estimated_shares']) ?? 0,
      status: _text(json['status'], 'submitted'),
      paymentStatus: _text(json['payment_status'], 'pending'),
      adminNote: _text(json['admin_note']),
      panSource: _sourceLabel(hasPanManual, hasPanDocument, 'PAN document'),
      panDocumentPath: _text(json['pan_document_path']),
      landRecordSource: _sourceLabel(
        hasLandRecordManual,
        hasLandRecord,
        '7/12 image',
      ),
      landRecordDetails: landRecordDetails,
      landRecordDocumentPath: _text(json['land_record_document_path']),
      bankSource: _sourceLabel(hasBankManual, hasPassbook, 'Passbook'),
      passbookDocumentPath: _text(json['passbook_document_path']),
      farmerSignaturePath: _text(json['farmer_signature']),
      nomineeSignaturePath: _text(json['nominee_signature']),
      nominee2SignaturePath: _text(json['nominee2_signature']),
      bankTransferReference: _text(json['bank_transfer_reference']),
      bankTransferProofPath: _text(json['bank_transfer_proof_path']),
      hasPanDocument: hasPanDocument,
      hasLandRecordDocument: hasLandRecord,
      hasPassbookDocument: hasPassbook,
      timeline: events
          .map(AdminStakeholderTimelineEntry.fromJson)
          .where((event) => event.title.isNotEmpty || event.status.isNotEmpty)
          .toList(growable: false),
      submittedAt: _date(json['submitted_at']),
      reviewedAt: _date(json['reviewed_at']),
      updatedAt: _date(json['updated_at'] ?? json['submitted_at']),
    );
  }
}

class AdminStakeholderTimelineEntry {
  final String status;
  final String title;
  final String note;
  final String actorRole;
  final DateTime? createdAt;

  const AdminStakeholderTimelineEntry({
    required this.status,
    required this.title,
    required this.note,
    required this.actorRole,
    required this.createdAt,
  });

  factory AdminStakeholderTimelineEntry.fromJson(Map<String, dynamic> json) {
    return AdminStakeholderTimelineEntry(
      status: _text(json['status']),
      title: _text(json['title'], _text(json['status'])),
      note: _text(json['note']),
      actorRole: _text(json['actor_role']),
      createdAt: _date(json['created_at']),
    );
  }
}

class AdminService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<AdminDashboardSnapshot> loadDashboard() async {
    try {
      final response = await _invokeFunction('admin-workflow-sync', {
        'action': 'load',
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        if (_isFunctionNotFoundData(data)) {
          return _loadDashboardFallback();
        }
        throw AdminServiceException(
          '${data['error'] ?? 'Admin workflow sync failed.'}',
        );
      }
      return AdminDashboardSnapshot.fromJson(data);
    } on AdminServiceException {
      rethrow;
    } catch (error) {
      if (_isFunctionNotFound(error)) {
        return _loadDashboardFallback();
      }
      throw AdminServiceException(
        _cleanRemoteError(error, 'Admin workflow sync failed.'),
      );
    }
  }

  Future<void> reviewStakeholder({
    required String applicationId,
    required String status,
    String adminNote = '',
  }) async {
    _validateStakeholderReviewInput(
      applicationId: applicationId,
      status: status,
      adminNote: adminNote,
    );
    try {
      final response = await _invokeFunction('stakeholder-plan-sync', {
        'action': 'admin_review_application',
        'applicationId': applicationId,
        'status': status,
        'adminNote': adminNote,
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw AdminServiceException(
          '${data['error'] ?? 'Stakeholder review failed.'}',
        );
      }
    } on AdminServiceException {
      rethrow;
    } catch (error) {
      if (_isFunctionNotFound(error)) {
        await _reviewStakeholderDirect(
          applicationId: applicationId,
          status: status,
          adminNote: adminNote,
        );
        return;
      }
      throw AdminServiceException(
        _cleanRemoteError(error, 'Stakeholder review failed.'),
      );
    }
  }

  Future<String> createStakeholderDocumentUrl(String documentPath) async {
    try {
      final response = await _invokeFunction('stakeholder-plan-sync', {
        'action': 'admin_signed_document_url',
        'documentPath': documentPath,
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        throw AdminServiceException(
          '${data['error'] ?? 'Could not open stakeholder document.'}',
        );
      }
      return _text(data['signedUrl']);
    } on AdminServiceException {
      rethrow;
    } catch (error) {
      if (_isFunctionNotFound(error)) {
        return _createStakeholderDocumentUrlDirect(documentPath);
      }
      throw AdminServiceException(
        _cleanRemoteError(error, 'Could not open stakeholder document.'),
      );
    }
  }

  Future<AdminDashboardSnapshot> _loadDashboardFallback() async {
    final stakeholderSnapshot = await _loadStakeholdersViaFunction();
    if (stakeholderSnapshot != null) return stakeholderSnapshot;
    return _loadDashboardDirect();
  }

  Future<AdminDashboardSnapshot?> _loadStakeholdersViaFunction() async {
    try {
      final response = await _invokeFunction('stakeholder-plan-sync', {
        'action': 'admin_list_applications',
      });
      final data = _responseMap(response.data);
      if (data['success'] == false) {
        if (_isFunctionNotFoundData(data)) return null;
        throw AdminServiceException(
          '${data['error'] ?? 'Stakeholder admin sync failed.'}',
        );
      }
      return _snapshotFromRows(
        farmers: const [],
        farmerFarms: const [],
        farmerActivities: const [],
        fpcJobs: const [],
        fpcProcurements: const [],
        stakeholders: _maps(data['applications'] ?? data['stakeholders']),
        stakeholderEvents: _maps(data['events'] ?? data['stakeholderEvents']),
      );
    } catch (error) {
      if (_isFunctionNotFound(error)) return null;
      rethrow;
    }
  }

  Future<AdminDashboardSnapshot> _loadDashboardDirect() async {
    final farmers = await _fetchRowsDirect(
      'farmer_phone_profiles',
      select:
          'user_id, phone, farmer_id, farmer_name, default_location, preferred_language, status, profile_completed_at, source, agri_record_id, aadhaar_last4, identity_document_path, updated_at, created_at',
      order: 'updated_at',
      limit: 200,
    );
    final farmerFarms = await _fetchRowsDirect(
      'v_farmer_farm_export',
      order: 'farm_updated_at',
      limit: 200,
    );
    final farmerActivities = await _fetchRowsDirect(
      'v_farmer_core_activity_export',
      order: 'created_at',
      limit: 200,
    );
    final fpcJobs = await _fetchRowsDirect(
      'analysis_jobs',
      order: 'created_at',
      limit: 120,
    );
    final fpcProcurements = await _fetchRowsDirect(
      'fpc_procurement_records',
      order: 'received_at',
      limit: 120,
    );
    final stakeholders = await _fetchRowsDirect(
      'stakeholder_applications',
      order: 'updated_at',
      limit: 200,
    );
    final stakeholderEvents = await _fetchRowsDirect(
      'stakeholder_application_events',
      order: 'created_at',
      ascending: true,
      limit: 500,
    );
    return _snapshotFromRows(
      farmers: farmers,
      farmerFarms: farmerFarms,
      farmerActivities: farmerActivities,
      fpcJobs: fpcJobs,
      fpcProcurements: fpcProcurements,
      stakeholders: stakeholders,
      stakeholderEvents: stakeholderEvents,
    );
  }

  AdminDashboardSnapshot _snapshotFromRows({
    required List<Map<String, dynamic>> farmers,
    required List<Map<String, dynamic>> farmerFarms,
    required List<Map<String, dynamic>> farmerActivities,
    required List<Map<String, dynamic>> fpcJobs,
    required List<Map<String, dynamic>> fpcProcurements,
    required List<Map<String, dynamic>> stakeholders,
    required List<Map<String, dynamic>> stakeholderEvents,
  }) {
    final activeFarmers = farmers
        .where((row) => _text(row['status']).toLowerCase() != 'inactive')
        .length;
    final pendingStakeholders = stakeholders
        .where(
          (row) => const {
            'submitted',
            'under_review',
          }.contains(_text(row['status']).toLowerCase()),
        )
        .length;
    final approvedStakeholders = stakeholders
        .where((row) => _text(row['status']).toLowerCase() == 'approved')
        .length;
    final paidStakeholders = stakeholders
        .where(
          (row) => const {
            'gateway_verified',
            'bank_transfer_submitted',
          }.contains(_text(row['payment_status']).toLowerCase()),
        )
        .length;
    return AdminDashboardSnapshot.fromJson({
      'generatedAt': DateTime.now().toIso8601String(),
      'metrics': {
        'farmerProfiles': farmers.length,
        'activeFarmers': activeFarmers,
        'linkedFarms': _latestByCount(farmerFarms, 'farm_id'),
        'fpcJobs': fpcJobs.length,
        'fpcProcurements': fpcProcurements.length,
        'stakeholderApplications': stakeholders.length,
        'pendingStakeholders': pendingStakeholders,
        'approvedStakeholders': approvedStakeholders,
        'paidStakeholders': paidStakeholders,
      },
      'farmers': farmers,
      'farmerFarms': farmerFarms,
      'farmerActivities': farmerActivities,
      'fpcJobs': fpcJobs,
      'fpcProcurements': fpcProcurements,
      'stakeholders': stakeholders,
      'stakeholderEvents': stakeholderEvents,
    });
  }

  Future<List<Map<String, dynamic>>> _fetchRowsDirect(
    String table, {
    String select = '*',
    String? order,
    bool ascending = false,
    int? limit,
  }) async {
    try {
      dynamic query = _client.from(table).select(select);
      if (order != null) {
        query = query.order(order, ascending: ascending);
      }
      if (limit != null) query = query.limit(limit);
      final data = await query;
      return _maps(data);
    } catch (error) {
      if (_readErrorIsOptional(error)) return const [];
      rethrow;
    }
  }

  Future<void> _reviewStakeholderDirect({
    required String applicationId,
    required String status,
    required String adminNote,
  }) async {
    _validateStakeholderReviewInput(
      applicationId: applicationId,
      status: status,
      adminNote: adminNote,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final cleanNote = adminNote.trim();
    final saved = await _client
        .from('stakeholder_applications')
        .update({
          'status': status,
          'admin_note': cleanNote,
          'reviewed_by': _client.auth.currentUser?.id,
          'reviewed_at': now,
          'kyc_reviewed_at': now,
        })
        .eq('id', applicationId)
        .select()
        .maybeSingle();
    if (saved == null) {
      throw const AdminServiceException(
        'Stakeholder application was not found.',
      );
    }
    final title = switch (status) {
      'approved' => 'Application approved',
      'rejected' => 'Application rejected',
      _ => 'Application under review',
    };
    final note = cleanNote.isNotEmpty
        ? cleanNote
        : status == 'approved'
        ? 'Kalsubai Farms admin approved this stakeholder request for payment.'
        : 'Kalsubai Farms admin started review of this stakeholder request.';
    await _client.from('stakeholder_application_events').insert({
      'application_id': applicationId,
      'status': status,
      'title': title,
      'note': note,
      'actor_role': 'admin',
    });
  }

  Future<String> _createStakeholderDocumentUrlDirect(
    String documentPath,
  ) async {
    try {
      final response = await _client.storage
          .from('stakeholder-documents')
          .createSignedUrl(documentPath, 300);
      return response;
    } catch (error) {
      throw AdminServiceException(
        _cleanRemoteError(error, 'Could not open stakeholder document.'),
      );
    }
  }

  Future<dynamic> _invokeFunction(
    String functionName,
    Map<String, Object?> body,
  ) {
    return _client.functions.invoke(
      functionName,
      headers: _functionAuthHeaders(),
      body: body,
    );
  }

  Map<String, String>? _functionAuthHeaders() {
    final token = _client.auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Map<String, dynamic> _responseMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  String _cleanRemoteError(Object error, String fallback) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (_isFunctionNotFound(error)) return fallback;
    if (_isMissingBucket(error)) {
      return 'Stakeholder document storage is not configured.';
    }
    return text.isEmpty ? fallback : text;
  }

  bool _isFunctionNotFound(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('statuscode: 404') ||
        text.contains('status code: 404') ||
        text.contains('status: 404') ||
        text.contains('http 404') ||
        text.contains('function not found') ||
        text.contains('edge function not found');
  }

  bool _isFunctionNotFoundData(Map<String, dynamic> data) {
    final code = '${data['code'] ?? ''}'.toLowerCase();
    final error = '${data['error'] ?? data['message'] ?? ''}'.toLowerCase();
    return code == 'not_found' ||
        code == 'function_not_found' ||
        error.contains('function not found') ||
        error.contains('edge function not found');
  }

  bool _isMissingBucket(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('bucket') &&
        (text.contains('not found') ||
            text.contains('does not exist') ||
            text.contains('missing'));
  }

  bool _readErrorIsOptional(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('does not exist') ||
        text.contains('not found') ||
        text.contains('could not find the table') ||
        text.contains('schema cache') ||
        text.contains('pgrst205') ||
        text.contains('permission denied') ||
        text.contains('row-level security') ||
        text.contains('rls');
  }

  void _validateStakeholderReviewInput({
    required String applicationId,
    required String status,
    required String adminNote,
  }) {
    if (applicationId.trim().isEmpty) {
      throw const AdminServiceException('Select a stakeholder application.');
    }
    final normalized = status.trim().toLowerCase();
    if (!const {'under_review', 'approved', 'rejected'}.contains(normalized)) {
      throw const AdminServiceException('Select a valid review status.');
    }
    if (normalized == 'rejected' && adminNote.trim().length < 5) {
      throw const AdminServiceException(
        'Add a clear rejection reason before rejecting.',
      );
    }
  }
}

List<Map<String, dynamic>> _maps(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

Map<String, int> _intMap(Object? raw) {
  if (raw is! Map) return const {};
  return Map<String, int>.fromEntries(
    raw.entries.map(
      (entry) => MapEntry('${entry.key}', _int(entry.value) ?? 0),
    ),
  );
}

String _sourceLabel(bool hasManual, bool hasDocument, String documentLabel) {
  if (hasManual && hasDocument) return 'Manual + $documentLabel';
  if (hasManual) return 'Manual details';
  if (hasDocument) return documentLabel;
  return 'Missing';
}

String _text(Object? raw, [String fallback = '']) {
  final text = raw == null ? '' : '$raw'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
}

String _normalizePhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length <= 10 ? digits : digits.substring(digits.length - 10);
}

DateTime? _date(Object? raw) {
  final text = _text(raw);
  return text.isEmpty ? null : DateTime.tryParse(text);
}

double? _double(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(_text(raw));
}

int? _int(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(_text(raw));
}

int _latestByCount(List<Map<String, dynamic>> items, String key) {
  final seen = <String>{};
  for (final item in items) {
    final id = _text(item[key]);
    if (id.isNotEmpty) seen.add(id);
  }
  return seen.length;
}
