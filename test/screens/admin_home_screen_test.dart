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

    expect(find.text('Farmer stakeholder request'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Review'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mark under review'), findsWidgets);
    expect(find.text('Admin note optional'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Mark under review'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Stakeholder application updated to under_review.'),
      findsOneWidget,
    );
  });
}

class _FakeAdminService extends AdminService {
  AdminDashboardSnapshot _snapshot;

  _FakeAdminService(this._snapshot);

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
}

AdminDashboardSnapshot _snapshotWithStakeholder(
  String status, {
  String adminNote = '',
}) {
  final now = DateTime.utc(2026, 7, 3, 10);
  return AdminDashboardSnapshot(
    generatedAt: now,
    metrics: const {'stakeholderApplications': 1, 'pendingStakeholders': 1},
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
