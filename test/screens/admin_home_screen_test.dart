import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kalsubai_farms/config/supabase_config.dart';
import 'package:kalsubai_farms/controllers/admin_controller.dart';
import 'package:kalsubai_farms/controllers/main_auth_controller.dart';
import 'package:kalsubai_farms/screens/admin_home_screen.dart';
import 'package:kalsubai_farms/services/admin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  });

  tearDown(Get.reset);

  testWidgets('pending stakeholder details can open review action sheet', (
    tester,
  ) async {
    final service = _FakeAdminService(_snapshotWithStakeholder('submitted'));
    Get.put<AdminController>(AdminController(service: service));
    Get.put<MainAuthController>(MainAuthController());

    await tester.pumpWidget(const GetMaterialApp(home: AdminHomeScreen()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    final openReview = find.byKey(
      const ValueKey('admin-open-next-stakeholder-review'),
    );
    await tester.scrollUntilVisible(
      openReview,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(openReview);
    await tester.pumpAndSettle();

    expect(find.text('Farmer shareholder request'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mark under review'), findsWidgets);
    expect(find.text('Admin note optional'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Mark under review'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Shareholder application updated to under_review.'),
      findsOneWidget,
    );
  });

  testWidgets('admin can open the merged verified shareholder directory', (
    tester,
  ) async {
    final service = _FakeAdminService(
      AdminDashboardSnapshot.empty(),
      candidatePage: _candidatePage(),
    );
    Get.put<AdminController>(AdminController(service: service));
    Get.put<MainAuthController>(MainAuthController());

    await tester.pumpWidget(const GetMaterialApp(home: AdminHomeScreen()));
    await tester.pumpAndSettle();

    final directoryMode = find.byKey(
      const ValueKey('admin-shareholder-directory-mode'),
    );
    tester
        .widget<SegmentedButton<bool>>(directoryMode)
        .onSelectionChanged
        ?.call({true});
    await tester.pumpAndSettle();

    expect(service.candidateLoadCount, 1);
    expect(find.textContaining('Allotted shareholders'), findsOneWidget);
    expect(find.textContaining('No-KYC'), findsNothing);
    expect(find.textContaining('KYC pending'), findsNothing);
    final scrollable = find.byType(Scrollable).last;
    final searchField = find.byKey(
      const ValueKey('admin-shareholder-candidate-search'),
    );
    await tester.scrollUntilVisible(searchField, 150, scrollable: scrollable);
    expect(searchField, findsOneWidget);
    final villageFilter = find.byKey(
      const ValueKey('admin-shareholder-village-filter'),
    );
    await tester.scrollUntilVisible(villageFilter, 150, scrollable: scrollable);
    expect(villageFilter, findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Candidate Farmer'),
      250,
      scrollable: scrollable,
    );

    expect(find.text('Candidate Farmer'), findsOneWidget);
    expect(find.textContaining('Nalavanevadi'), findsWidgets);
    expect(find.textContaining('1 allotted share'), findsOneWidget);
    expect(find.text('Verified and approved shareholder'), findsOneWidget);
    expect(find.textContaining('pending consent'), findsNothing);
    expect(find.textContaining('Source:'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Registered Farmer'),
      250,
      scrollable: scrollable,
    );
    expect(find.text('Registered Farmer'), findsOneWidget);
    expect(find.textContaining('100 allotted shares'), findsOneWidget);
    expect(find.text('Verified and approved shareholder'), findsWidgets);
    expect(find.textContaining('pending consent'), findsNothing);
    expect(find.textContaining('Source:'), findsNothing);
    expect(find.text('Amount not recorded'), findsOneWidget);
    expect(service.candidateLoadCount, 1);
  });

  testWidgets('overview shows the complete shareholder directory count', (
    tester,
  ) async {
    final service = _FakeAdminService(
      _snapshotWithStakeholder(
        'submitted',
        metrics: const {
          'stakeholderApplications': 1,
          'pendingStakeholders': 1,
          'shareholderDirectoryTotal': 3237,
        },
      ),
    );
    Get.put<AdminController>(AdminController(service: service));
    Get.put<MainAuthController>(MainAuthController());

    await tester.pumpWidget(const GetMaterialApp(home: AdminHomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    expect(find.text('Shareholders'), findsOneWidget);
    expect(find.text('3,237'), findsOneWidget);
  });
}

class _FakeAdminService extends AdminService {
  AdminDashboardSnapshot _snapshot;
  final AdminShareholderCandidatePage? candidatePage;
  int candidateLoadCount = 0;

  _FakeAdminService(this._snapshot, {this.candidatePage});

  @override
  Future<AdminDashboardSnapshot> loadDashboard() async => _snapshot;

  @override
  Future<void> reviewStakeholder({
    required String applicationId,
    required String status,
    String adminNote = '',
  }) async {
    _snapshot = _snapshotWithStakeholder(status, adminNote: adminNote);
  }

  @override
  Future<AdminShareholderCandidatePage> loadShareholderCandidates({
    String search = '',
    String village = '',
    String taluka = '',
    String district = '',
    int offset = 0,
    int limit = 100,
  }) async {
    candidateLoadCount += 1;
    return candidatePage ?? AdminShareholderCandidatePage.empty();
  }
}

AdminShareholderCandidatePage _candidatePage() {
  return AdminShareholderCandidatePage(
    rows: [
      AdminShareholderCandidate(
        id: 'candidate-1',
        sourceRecordKey: List.filled(64, 'a').join(),
        directorySource: 'candidate_roster',
        sourceFile: 'electoral-roll-part-11.pdf',
        sourcePartNo: 11,
        sourcePage: 3,
        sourceOrdinal: 1,
        fullName: 'Candidate Farmer',
        gender: 'Female',
        village: 'Nalavanevadi (Shenit)',
        mainVillage: 'Shenit Bk',
        taluka: 'Akole',
        district: 'Ahmednagar',
        proposedShareCount: 1,
        shareUnitValue: 100,
        proposedTotalAmount: 100,
        farmerStatus: 'unverified',
        candidateStatus: 'pending_consent_kyc_payment',
        ocrConfidence: 94.5,
        adminPromoted: true,
        adminPromotionBasis: 'admin_override_without_kyc',
        verificationStatus: 'verified_shareholder_override',
      ),
      const AdminShareholderCandidate(
        id: 'register-1',
        sourceRecordKey: 'register:register-1',
        directorySource: 'shareholder_register',
        sourceFile: 'SHARE HOLDER LIST FORMAT.xlsx',
        sourceSheet: 'Sheet1',
        sourcePartNo: 0,
        sourcePage: 0,
        sourceOrdinal: 8,
        fullName: 'Registered Farmer',
        gender: '',
        village: 'Kondani',
        mainVillage: 'Ranad Bk',
        taluka: 'Akole',
        district: 'Ahmednagar',
        memberAddress: 'At Kondani Post Ranad Bk Tal Akole Dist Ahilynagar',
        proposedShareCount: 100,
        shareUnitValue: 0,
        proposedTotalAmount: 0,
        amountRecorded: false,
        shareStatus: 'allotted',
        farmerStatus: 'not_recorded',
        candidateStatus: 'verified_shareholder',
        ocrConfidence: 0,
        adminPromotionBasis: 'audited_shareholder_register',
        verificationStatus: 'verified_shareholder',
      ),
    ],
    totalCount: 3237,
    offset: 0,
    limit: 100,
    villages: const ['Kondani', 'Nalavanevadi (Shenit)'],
    talukas: const ['Akole'],
    districts: const ['Ahmednagar'],
    summary: const {
      'totalRecords': 3237,
      'verifiedShareholders': 3237,
      'adminPromotedWithoutKyc': 3000,
      'candidateRecords': 3000,
      'verifiedFarmers': 0,
      'pendingKyc': 3000,
      'allottedShares': 2424,
      'proposedShares': 3000,
      'proposedCapital': 300000,
    },
  );
}

AdminDashboardSnapshot _snapshotWithStakeholder(
  String status, {
  String adminNote = '',
  Map<String, int> metrics = const {
    'stakeholderApplications': 1,
    'pendingStakeholders': 1,
  },
}) {
  final now = DateTime.utc(2026, 7, 3, 10);
  return AdminDashboardSnapshot(
    generatedAt: now,
    metrics: metrics,
    farmers: const [],
    fpcRecords: const [],
    stakeholders: [
      AdminStakeholderRecord(
        id: 'stakeholder-app-1',
        farmerId: 'FARM-101',
        farmerName: 'Kalsubai Farmer',
        farmerPhone: '9876543210',
        farmerFullName: 'Kalsubai Farmer',
        farmerFatherName: 'Ramesh',
        farmerMobileNumber: '9876543210',
        farmerVillage: 'Akole',
        farmerTaluka: 'Akole',
        farmerDistrict: 'Ahmednagar',
        farmerTotalLandAcres: '3.5',
        nomineeName: 'Nominee One',
        nomineeMobileNumber: '9876501234',
        nomineeCount: 1,
        nominee2Name: '',
        nominee2MobileNumber: '',
        panNumber: 'ABCDE1234F',
        bankName: 'Kalsubai Bank',
        accountHolderName: 'Kalsubai Farmer',
        ifscCode: 'KALS0123456',
        selectedAmount: 5000,
        estimatedShares: 50,
        status: status,
        paymentStatus: 'pending',
        adminNote: adminNote,
        panSource: 'Manual details',
        panDocumentPath: '',
        landRecordSource: 'Manual details',
        landRecordDetails:
            'Survey 12, Gat 34, Village Akole, Taluka Akole, District Ahmednagar',
        landRecordDocumentPath: '',
        bankSource: 'Manual details',
        passbookDocumentPath: '',
        farmerSignaturePath: 'local/farmer-signature.png',
        nomineeSignaturePath: 'local/nominee-signature.png',
        nominee2SignaturePath: '',
        bankTransferReference: '',
        bankTransferProofPath: '',
        hasPanDocument: false,
        hasLandRecordDocument: false,
        hasPassbookDocument: false,
        timeline: [
          AdminStakeholderTimelineEntry(
            status: status,
            title: 'Application submitted',
            note: 'Ready for admin review.',
            actorRole: 'stakeholder',
            createdAt: now,
          ),
        ],
        submittedAt: now,
        reviewedAt: null,
        updatedAt: now,
      ),
    ],
  );
}
