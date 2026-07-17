import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/controllers/admin_controller.dart';
import 'package:kalsubai_farms/services/admin_service.dart';

class _FakeAdminService extends AdminService {
  int reviewCalls = 0;
  String lastStatus = '';
  String lastNote = '';

  @override
  Future<AdminDashboardSnapshot> loadDashboard() async {
    return AdminDashboardSnapshot.empty();
  }

  @override
  Future<void> reviewStakeholder({
    required String applicationId,
    required String status,
    String adminNote = '',
  }) async {
    reviewCalls += 1;
    lastStatus = status;
    lastNote = adminNote;
  }
}

void main() {
  test('requires a clear reason before rejecting stakeholder request', () async {
    final service = _FakeAdminService();
    final controller = AdminController(service: service);

    final saved = await controller.reviewStakeholder(
      applicationId: 'app-1',
      status: 'rejected',
      note: 'bad',
    );

    expect(saved, isFalse);
    expect(service.reviewCalls, 0);
    expect(
      controller.errorMessage.value,
      'Add a clear rejection reason before rejecting.',
    );
  });

  test('passes approval note to admin service and refreshes dashboard', () async {
    final service = _FakeAdminService();
    final controller = AdminController(service: service);

    final saved = await controller.reviewStakeholder(
      applicationId: 'app-1',
      status: 'approved',
      note: 'KYC verified',
    );

    expect(saved, isTrue);
    expect(service.reviewCalls, 1);
    expect(service.lastStatus, 'approved');
    expect(service.lastNote, 'KYC verified');
  });
}
