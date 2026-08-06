import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final marketplace = File(
    'lib/screens/apmc_market_screen.dart',
  ).readAsStringSync();
  final fpcNavigation = File(
    'lib/widgets/fpc_bottom_nav.dart',
  ).readAsStringSync();
  final fpcLogin = File('lib/screens/fpc_login_screen.dart').readAsStringSync();
  final auth = File(
    'lib/controllers/main_auth_controller.dart',
  ).readAsStringSync();
  final farmerProgram = File(
    'lib/widgets/farmer_crop_program_card.dart',
  ).readAsStringSync();
  final farmerHome = File(
    'lib/screens/farmer_home_screen.dart',
  ).readAsStringSync();
  final farmerSeeds = File(
    'lib/widgets/farmer_seeds_page.dart',
  ).readAsStringSync();
  final fpcModule = File(
    'lib/widgets/fpc_module_workspace.dart',
  ).readAsStringSync();
  final fpcSeeds = File('lib/screens/fpc_seeds_screen.dart').readAsStringSync();
  final fpcSetup = File('lib/screens/fpc_setup_screen.dart').readAsStringSync();
  final fpcOperating = File(
    'lib/screens/fpc_operating_system_screen.dart',
  ).readAsStringSync();
  final fpcService = File(
    'lib/services/fpc_operating_service.dart',
  ).readAsStringSync();
  final routes = File('lib/app/routes/app_pages.dart').readAsStringSync();
  final fieldTeam = File('lib/screens/fpc_team_screen.dart').readAsStringSync();
  final fieldOfficer = File(
    'lib/screens/field_officer_home_screen.dart',
  ).readAsStringSync();

  test('FPC marketplace relies on the shared single language selector', () {
    expect(
      marketplace,
      isNot(
        contains(
          "title: _marketText('Marketplace'),\n"
          '        actions: [_languageSelector(), const SizedBox(width: 10)]',
        ),
      ),
    );
    expect(fpcNavigation, contains('LanguageSelectorButton('));
  });

  test('FPC side navigation omits verification and grading shortcuts', () {
    final start = fpcNavigation.indexOf('class FpcSideNavigation');
    final end = fpcNavigation.indexOf('class _FpcAccountHeader');
    final sideNavigation = fpcNavigation.substring(start, end);

    expect(sideNavigation, isNot(contains("title: 'Farmer verification'")));
    expect(sideNavigation, isNot(contains("title: 'Grain grading'")));
    expect(sideNavigation, contains("title: 'Farmer directory'"));
    expect(sideNavigation, contains("title: 'Seeds'"));
    expect(sideNavigation, contains("route: '/fpo/seeds'"));
  });

  test('Farmer and FPC Seeds pages have distinct operational purposes', () {
    expect(farmerHome, contains('FarmerSeedsPage('));
    expect(farmerHome, contains('onOpenSeeds: _openSeedsTab'));
    expect(farmerHome, contains("UiStrings.t('farmer_seeds_nav_desc')"));
    expect(farmerSeeds, contains("UiStrings.t('farmer_seeds_purpose')"));
    expect(farmerSeeds, contains('FarmerCropProgramCard('));
    expect(
      farmerSeeds.indexOf("UiStrings.t('farmer_seeds_available_programs')"),
      lessThan(farmerSeeds.indexOf('FarmerCropProgramCard(')),
    );
    expect(
      farmerSeeds.indexOf('FarmerCropProgramCard('),
      lessThan(farmerSeeds.lastIndexOf('_SeedsPurposeCard()')),
    );
    expect(farmerProgram, contains('snapshot.availablePrograms'));
    expect(farmerProgram, contains('snapshot.requestablePrograms'));
    expect(farmerProgram, contains('snapshot.hasFarmMatchingProgram'));
    expect(farmerProgram, contains("'seed_program_from_fpc'"));
    expect(farmerProgram, contains("'seed_program_choose_matching_farm'"));
    expect(
      farmerHome,
      isNot(contains('FarmerCropProgramCard(farmId: selected.remoteFarmId)')),
    );

    expect(fpcNavigation, contains('FpcNavTab.seeds'));
    expect(fpcSeeds, contains("current: FpcNavTab.seeds"));
    expect(fpcSeeds, contains("'seed_request'"));
    expect(fpcSeeds, contains("'seed_batch'"));
    expect(fpcSeeds, contains("'program'"));
    expect(routes, contains("name: '/fpo/seeds'"));
  });

  test('setup uses one seed stock or crop program requirement', () {
    expect(fpcSetup, contains("item.key == 'seed_stock'"));
    expect(fpcSetup, contains('await Get.toNamed'));
    expect(fpcSetup, contains('if (mounted) unawaited(_load())'));
    expect(fpcSetup, contains("'tab': 'programs'"));
    expect(
      fpcSetup,
      isNot(contains("'open_operation': 'create_crop_program'")),
    );
    expect(fpcSeeds, contains('initialIndex: _initialTabIndex'));
    expect(fpcSeeds, contains("allowedOperations.contains(_initialOperation)"));
    expect(fpcSetup, isNot(contains("item.key == 'grains'")));
    expect(fpcService, isNot(contains("key: 'grains'")));
    expect(fpcService, contains("key: 'seed_stock'"));
    expect(
      fpcService,
      contains('complete: hasSeedOrProgram,\n          required: false,'),
    );
    expect(
      fpcService.indexOf("key: 'seed_stock'"),
      lessThan(fpcService.indexOf("key: 'collection_center'")),
    );
    expect(
      fpcService,
      contains('final hasSeedOrProgram = counts[2] > 0 || counts[3] > 0'),
    );
    expect(fpcService, contains('complete: hasSeedOrProgram'));
    expect(
      fpcService,
      contains(
        'Register seed stock or create a crop program before distribution.',
      ),
    );
    expect(fpcService, contains('seed batch'));
    expect(fpcSetup, contains('onTap: onOpen'));
  });

  test(
    'collection center setup is optional and uses the original card layout',
    () {
      expect(fpcSetup, contains("item.key == 'collection_center'"));
      expect(fpcSetup, contains("'module': 'collection_center'"));
      expect(fpcSetup, contains("'return_to_setup': true"));
      expect(
        fpcService,
        contains("complete: counts[1] > 0,\n          required: false,"),
      );
      expect(fpcOperating, contains('_returnToSetup'));
      expect(fpcOperating, contains('onBack: _returnToSetup'));
      expect(fpcOperating, contains('? Get.back'));
      expect(fpcService, contains("'active': true"));
      expect(
        fpcService.indexOf("'center',"),
        lessThan(fpcService.indexOf("'receipt',")),
      );
      expect(fpcService, contains(".order('active', ascending: false)"));
      expect(fpcService, contains(".order('village')"));
      expect(fpcService, contains(".order('id')"));
      expect(fpcModule, contains('_CollectionCenterWorkspace'));
      expect(fpcModule, contains('_compareCollectionCenters'));
      expect(fpcModule, contains("_fpcRaw(left['id'])"));
      expect(fpcModule, contains('_compareCollectionReceipts'));
      expect(fpcModule, contains('_CollectionReadinessCard'));
      expect(fpcModule, contains('Ready for receiving'));
      expect(fpcModule, contains(r'Step $step: $title'));
      expect(fpcModule, contains('_CollectionMetricCard'));
      expect(fpcModule, isNot(contains('Inactive centers')));
      expect(fpcModule, contains('Recent receipts'));
      expect(fpcModule, contains('Daily handling capacity kg'));
      expect(fpcModule, contains('Address / landmark'));
      expect(fpcModule, contains('Enter zero or a positive capacity'));
    },
  );

  test('setup Field Officer step uses the authoritative team source', () {
    expect(fpcSetup, contains("item.key == 'field_team'"));
    expect(fpcSetup, contains("'open_action': 'create_field_officer'"));
    expect(
      fieldTeam,
      contains("arguments['open_action'] == 'create_field_officer'"),
    );
    expect(fieldTeam, contains('unawaited(_createOfficer())'));
    expect(fpcService, contains('final fieldOfficerCount = counts[0]'));
    expect(fpcService, contains('Future.wait<int>(['));
    expect(fpcService, contains('_countActiveFieldOfficers(context.fpcId)'));
    expect(
      fpcService,
      contains('final memberships = await loadMemberships(fpcId)'),
    );
    expect(
      fpcService,
      contains("row['role'] == 'field_officer' && row['status'] == 'active'"),
    );
  });

  test('shared FPC login routes Field Officers without role-selection UI', () {
    expect(fpcLogin, contains('loginFpc('));
    expect(fpcLogin, isNot(contains('RoleLoginInfoStrip(\n          icon:')));
    expect(auth, contains("membership['role']"));
    expect(auth, contains("membershipRole == 'field_officer'"));
    expect(auth, contains("return '/field'"));
    expect(auth, contains("return '/fpo';"));
  });

  test('seed and field-work actions are connected in the app UI', () {
    expect(farmerProgram, contains("UiStrings.t('seed_request_from_fpc')"));
    expect(farmerProgram, contains("UiStrings.t('crop_program_confirm_seed')"));
    expect(fpcModule, contains('Approve Farmer seed request'));
    expect(fpcModule, contains('Issue requested seed'));
    expect(fieldTeam, contains("UiStrings.t('fpc_linked_farmer_farm')"));
    expect(fieldTeam, contains("UiStrings.fromEnglish('No linked farmer')"));
    expect(fieldTeam, contains('_fieldOfficers.isEmpty'));
    expect(
      fieldTeam,
      isNot(contains('_fieldOfficers.isEmpty || _farmers.isEmpty')),
    );
    expect(fieldTeam, contains('scheduledFor: scheduledFor'));
    expect(fieldOfficer, contains("assignment.status == 'in_progress'"));
    expect(fieldOfficer, contains('isSeedDelivery && photos.isEmpty'));
    expect(fieldOfficer, contains('isSeedDelivery && position == null'));
    expect(fieldOfficer, contains('isCropCheckpoint && photos.isEmpty'));
    expect(
      fieldOfficer,
      contains("enqueueAssignmentStatus(assignment, 'completed')"),
    );
  });
}
