import 'package:get/get.dart';

import '../../screens/admin_home_screen.dart';
import '../../screens/admin_login_screen.dart';
import '../../screens/apmc_market_screen.dart';
import '../../screens/chatbot_survey_screen.dart';
import '../../screens/diagnostics_home_screen.dart';
import '../../screens/farmer_ai_chat_screen.dart';
import '../../screens/farmer_ai_grading_screen.dart';
import '../../screens/farmer_home_screen.dart';
import '../../screens/farmer_login_screen.dart';
import '../../screens/farmer_signup_screen.dart';
import '../../screens/fpc_login_screen.dart';
import '../../screens/fpc_analytics_screen.dart';
import '../../screens/fpc_qr_hub_screen.dart';
import '../../screens/fpc_seeds_screen.dart';
import '../../screens/fpc_setup_screen.dart';
import '../../screens/fpo_farmer_qr_scan_screen.dart';
import '../../screens/fpc_farmer_directory_screen.dart';
import '../../screens/fpo_grading_review_screen.dart';
import '../../screens/fpo_home_screen.dart';
import '../../screens/fpo_receiver_screen.dart';
import '../../screens/fpc_workspace_screen.dart';
import '../../screens/fpc_operating_system_screen.dart';
import '../../screens/field_officer_home_screen.dart';
import '../../screens/required_password_change_screen.dart';
import '../../screens/fpc_team_screen.dart';
import '../../screens/harvest_qr_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/landing_screen.dart';
import '../../screens/main_login_screen.dart';
import '../../screens/offline_maps_screen.dart';
import '../../screens/public_trace_screen.dart';
import '../../screens/role_account_signup_screen.dart';
import '../../screens/satellite/draw_polygon_screen.dart';
import '../../screens/satellite/login_screen.dart';
import '../../screens/satellite/satellite_shell.dart';
import '../../screens/satellite/signup_screen.dart';
import '../../screens/splash_screen.dart';
import '../../screens/stakeholder_home_screen.dart';
import '../../screens/stakeholder_login_screen.dart';
import '../../screens/survey_form_screen.dart';
import '../../screens/whatsapp_farm_boundary_screen.dart';
import '../bindings/app_bindings.dart';
import 'role_route_middleware.dart';

class AppRoutes {
  const AppRoutes._();

  static const splash = '/';
}

class AppPages {
  const AppPages._();

  static const initial = AppRoutes.splash;

  static final pages = <GetPage>[
    GetPage(name: '/', page: () => const SplashScreen()),
    GetPage(name: '/login', page: () => const MainLoginScreen()),
    GetPage(name: '/admin/login', page: () => const AdminLoginScreen()),
    GetPage(
      name: '/admin',
      page: () => const AdminHomeScreen(),
      binding: BindingsBuilder(AppBindings.bindAdmin),
      middlewares: [AdminRouteMiddleware()],
    ),
    GetPage(name: '/farmer/login', page: () => const FarmerLoginScreen()),
    GetPage(
      name: '/stakeholder/login',
      page: () => const StakeholderLoginScreen(),
    ),
    GetPage(
      name: '/stakeholder',
      page: () => const StakeholderHomeScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/plan',
      page: () => const StakeholderPlanDetailScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/pan-kyc',
      page: () => const StakeholderPanKycScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/land-record',
      page: () => const StakeholderLandRecordScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/bank-details',
      page: () => const StakeholderBankDetailsScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/select-amount',
      page: () => const StakeholderSelectAmountScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/status',
      page: () => const StakeholderStatusScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/profile',
      page: () => const StakeholderProfileScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/documents',
      page: () => const StakeholderDocumentsScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(
      name: '/stakeholder/help',
      page: () => const StakeholderHelpScreen(),
      binding: BindingsBuilder(AppBindings.bindStakeholder),
    ),
    GetPage(name: '/farmer/signup', page: () => const FarmerSignupScreen()),
    GetPage(
      name: '/whatsapp-farm-boundary',
      page: () => const WhatsappFarmBoundaryScreen(),
    ),
    GetPage(name: '/fpc/login', page: () => const FpcLoginScreen()),
    GetPage(name: '/fpc/signup', page: () => const FpcSignupScreen()),
    GetPage(
      name: '/farmer',
      page: () => const FarmerHomeScreen(),
      binding: BindingsBuilder(AppBindings.bindSatelliteFarmFlow),
    ),
    GetPage(
      name: '/farmer/ai-chat',
      page: () => const FarmerAiChatScreen(),
      binding: BindingsBuilder(AppBindings.bindSatelliteFarmFlow),
    ),
    GetPage(
      name: '/farmer/ai-grading',
      page: () => const FarmerAiGradingScreen(),
    ),
    GetPage(name: '/farmer/harvest-qr', page: () => const HarvestQrScreen()),
    GetPage(
      name: '/fpo',
      page: () => const FpoHomeScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/setup',
      page: () => const FpcSetupScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/operations',
      page: () => const FpcOperatingSystemScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/analytics',
      page: () => const FpcAnalyticsScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/seeds',
      page: () => const FpcSeedsScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/team',
      page: () => const FpcTeamScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/field',
      page: () => const FieldOfficerHomeScreen(),
      middlewares: [FieldOfficerRouteMiddleware()],
    ),
    GetPage(
      name: '/account/change-password',
      page: () => const RequiredPasswordChangeScreen(),
      middlewares: [FpcLoginRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/farmers',
      page: () => const FpcFarmerDirectoryScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/qr',
      page: () => const FpcQrHubScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/scan-farmer',
      page: () => const FpoFarmerQrScanScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/grading-review',
      page: () => const FpoGradingReviewScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/grain-grading',
      page: () => const FarmerAiGradingScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/marketplace',
      page: () => const MarketplacePage(inventoryLots: [], buyerMode: true),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/receiver',
      page: () => const FpoReceiverScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/profile',
      page: () => const FpcProfileScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/settings',
      page: () => const FpcSettingsScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/activity',
      page: () => const FpcActivityScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(
      name: '/fpo/help',
      page: () => const FpcHelpScreen(),
      middlewares: [FpcAdminRouteMiddleware()],
    ),
    GetPage(name: '/trace/:token', page: () => const PublicTraceScreen()),
    GetPage(name: '/home', page: () => const LandingScreen()),
    GetPage(
      name: '/surveys',
      page: () => const HomeScreen(),
      binding: BindingsBuilder(AppBindings.bindSurveyFlow),
    ),
    GetPage(
      name: '/form',
      page: () => const ChatbotSurveyScreen(),
      binding: BindingsBuilder(AppBindings.bindSurveyFlow),
    ),
    GetPage(
      name: '/form/classic',
      page: () => const SurveyFormScreen(),
      binding: BindingsBuilder(AppBindings.bindSurveyFlow),
    ),
    GetPage(name: '/diagnostics', page: () => const DiagnosticsHomeScreen()),
    GetPage(name: '/offline-maps', page: () => const OfflineMapsScreen()),
    GetPage(
      name: '/satellite/login',
      page: () => const LoginScreen(),
      binding: BindingsBuilder(AppBindings.bindSatelliteAuth),
    ),
    GetPage(
      name: '/satellite/signup',
      page: () => const SignupScreen(),
      binding: BindingsBuilder(AppBindings.bindSatelliteAuth),
    ),
    GetPage(
      name: '/satellite/draw-polygon',
      page: () => const DrawPolygonScreen(),
      binding: BindingsBuilder(AppBindings.bindSatelliteFarmFlow),
    ),
    GetPage(
      name: '/satellite/shell',
      page: () => const SatelliteShell(),
      binding: BindingsBuilder(AppBindings.bindSatelliteShell),
    ),
  ];
}
