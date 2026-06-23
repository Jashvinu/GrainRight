import 'package:get/get.dart';

import '../controllers/language_controller.dart';
import 'locale_text.dart';

/// Shared locale-aware strings for the core farmer-facing shell screens
/// (entry/role select, farmer login). Mirrors [GradingStrings] so the
/// Marathi/Hindi-first audience sees regional text immediately, instead of the
/// Marathi-only legacy `AppTranslations`. See docs/10_uiux_flow_audit.md §3.1.
class UiStrings {
  UiStrings._();

  static String _lang() {
    var code = Get.locale?.languageCode ?? 'en';
    if (Get.isRegistered<LanguageController>()) {
      code = Get.find<LanguageController>().language.value;
    }
    return (code == 'mr' || code == 'hi') ? code : 'en';
  }

  static String t(String key) {
    final row = _data[key];
    if (row == null) return key;
    final text = row[_lang()] ?? row['en'] ?? key;
    return LocaleText.digits(text);
  }

  static String f(String key, Map<String, Object?> values) {
    var text = t(key);
    values.forEach((name, value) {
      text = text.replaceAll('{$name}', localizedValue(value));
    });
    return LocaleText.digits(text);
  }

  static String timeGreeting([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour >= 4 && hour < 12) return t('good_morning');
    if (hour >= 12 && hour < 17) return t('good_afternoon');
    if (hour >= 17 && hour < 21) return t('good_evening');
    return t('good_night');
  }

  static String localizedValue(Object? value) {
    if (value == null) return '';
    if (value is num) return LocaleText.number(value);
    final text = value.toString();
    final trimmed = text.trim();
    final acres = RegExp(
      r'^(\d+(?:\.\d+)?)\s*acres?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (acres != null) {
      return f('acres_value', {'value': acres.group(1)});
    }
    final kg = RegExp(
      r'^(\d+(?:\.\d+)?)\s*kg$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (kg != null) {
      return f('kg_value', {'value': kg.group(1)});
    }
    return option(text);
  }

  static String label(Object? value) => localizedValue(value);

  static String option(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return value;
    final key = _optionKeyByValue[normalized];
    return key == null ? LocaleText.digits(value) : t(key);
  }

  static String authError(String message) {
    final text = message.trim();
    final normalized = text.toLowerCase();
    if (normalized.contains('to sign up')) {
      return t('signup_phone_required');
    }
    if (normalized.contains('valid 10 digit') ||
        normalized.contains('10 digit mobile')) {
      return t('invalid_phone');
    }
    if (normalized.contains('redirecting to sign up')) {
      return t('farmer_not_found_redirect');
    }
    if (normalized.contains('no approved farmer profile') ||
        normalized.contains('no farmer profile found') ||
        normalized.contains('create a new farmer account') ||
        normalized.contains('not verified') ||
        normalized.contains('not approved') ||
        normalized.contains('create account') ||
        normalized.contains('farmer_not_found')) {
      return t('farmer_not_found');
    }
    if (normalized.contains('already has a farmer profile') ||
        normalized.contains('please login instead') ||
        normalized.contains('already registered')) {
      return t('farmer_already_exists');
    }
    if (normalized.contains('enter farmer name')) {
      return t('enter_farmer_name_error');
    }
    if (normalized.contains('could not start farmer session')) {
      return t('farmer_session_error');
    }
    if (normalized.contains('network issue')) {
      return t('network_issue_error');
    }
    if (normalized.contains('server sync failed')) {
      return t('server_sync_failed_error');
    }
    if (normalized.contains('offline')) {
      return t('offline_cached_session');
    }
    if (normalized.contains('farm data sync failed')) {
      return t('farm_data_missing_error');
    }
    if (normalized.contains('session expired')) {
      return t('session_expired_error');
    }
    if (normalized.contains('could not create farmer profile')) {
      return t('farmer_create_error');
    }
    if (normalized.contains('could not register farmer')) {
      return t('farmer_register_error');
    }
    if (normalized.contains('could not verify farmer profile')) {
      return t('farmer_verify_error');
    }
    if (normalized.contains('could not confirm farmer profile')) {
      return t('farmer_confirm_error');
    }
    return text;
  }

  static const Map<String, String> _optionKeyByValue = {
    'all crops': 'all_crops',
    'all farms': 'all_farms',
    'north field': 'opt_north_field',
    'south plot': 'opt_south_plot',
    'east block': 'opt_east_block',
    'main farm': 'opt_main_farm',
    'brown top': 'brown_top',
    'gira': 'opt_gira',
    'phule nachni': 'opt_phule_nachni',
    'pragati': 'pragati',
    'sips-1': 'opt_sips_1',
    'bhu-8': 'opt_bhu_8',
    'kalyan': 'opt_kalyan',
    'indrayani': 'opt_indrayani',
    'basmati': 'opt_basmati',
    'kolum': 'opt_kolum',
    'ictp-8203': 'opt_ictp_8203',
    'ictp 8203': 'opt_ictp_8203',
    'shanti': 'opt_shanti',
    'hhb-67': 'opt_hhb_67',
    'saburi': 'opt_saburi',
    'dhanshakti': 'opt_dhanshakti',
    'general': 'general',
    'farm profile': 'farm_profile',
    'active': 'active',
    'medium': 'medium',
    'lot': 'lot',
    'pending': 'pending',
    'not rated': 'not_rated',
    'last season': 'last_season',
    'fpc procurement': 'fpc_procurement',
    'market': 'market',
    'weather': 'weather',
    'storage': 'storage',
    'today': 'opt_today',
    'yesterday': 'yesterday',
    'two days ago': 'two_days_ago',
    'finger millet': 'opt_finger_millet',
    'foxtail millet': 'opt_foxtail_millet',
    'little millet': 'little_millet',
    'kodo millet': 'kodo_millet',
    'pearl millet': 'pearl_millet',
    'millet': 'millet',
    'millet lots': 'millet_lots',
    'rice': 'opt_rice',
    'bajra': 'opt_bajra',
    'vegetables': 'opt_vegetables',
    'fallow': 'opt_fallow',
    'kharif': 'opt_kharif',
    'rabi': 'opt_rabi',
    'summer': 'opt_summer',
    'rainfed': 'opt_rainfed',
    'well': 'opt_well',
    'borewell': 'opt_borewell',
    'canal': 'opt_canal',
    'drip': 'opt_drip',
    'black soil': 'opt_black_soil',
    'red soil': 'opt_red_soil',
    'sandy loam': 'opt_sandy_loam',
    'clay loam': 'opt_clay_loam',
    'owned': 'opt_owned',
    'leased': 'opt_leased',
    'shared': 'opt_shared',
    'forest patta': 'opt_forest_patta',
    'own saved': 'opt_own_saved',
    'fpo': 'opt_fpo',
    'local market': 'opt_local_market',
    'government source': 'opt_government_source',
    'home use': 'opt_home_use',
    'market sale': 'opt_market_sale',
    'seed saving': 'opt_seed_saving',
    'processing': 'opt_processing',
    'tomorrow': 'tomorrow',
    'wed': 'wednesday_short',
    'thu': 'thursday_short',
    'fri': 'friday_short',
    'sat': 'saturday_short',
    'sunny': 'weather_sunny',
    'partly cloudy': 'weather_partly_cloudy',
    'light showers': 'weather_light_showers',
    'cloudy': 'weather_cloudy',
    'clear': 'weather_clear',
    'overcast': 'weather_cloudy',
    'fog': 'weather_fog',
    'drizzle': 'weather_drizzle',
    'rain': 'rain',
    'showers': 'weather_showers',
    'thunderstorm': 'weather_thunderstorm',
    'humid': 'weather_humid',
    'dry': 'weather_dry',
    'high': 'demand_high',
    'good': 'good',
    'stable': 'demand_stable',
    'ready': 'ready',
    'failed': 'failed',
    'paused': 'paused',
    'prepare': 'prepare',
    'low': 'low',
    'moderate': 'moderate',
    'loading': 'loading',
    'improving': 'improving',
    'declining': 'declining',
    'strong': 'strong',
    'fair': 'fair',
    'sparse': 'sparse',
    'healthy': 'healthy',
    'stressed': 'stressed',
    'important': 'important',
    'watch': 'watch',
    'disease risk': 'disease_risk',
    'crop stage': 'crop_stage',
    'sowing': 'stage_sowing',
    'establishment': 'stage_establishment',
    'vegetative': 'stage_vegetative',
    'flowering': 'stage_flowering',
    'grain filling': 'stage_grain_filling',
    'maturity': 'stage_maturity',
  };

  static const Map<String, Map<String, String>> _data = {
    // ── Role selection (main login) ──
    'welcome': {'en': 'Welcome!', 'hi': 'स्वागत है!', 'mr': 'स्वागत आहे!'},
    'choose_continue': {
      'en': 'Choose how you want to continue',
      'hi': 'आगे कैसे बढ़ना है चुनें',
      'mr': 'पुढे कसे जायचे ते निवडा',
    },
    'role_farmer': {'en': 'Farmer', 'hi': 'किसान', 'mr': 'शेतकरी'},
    'role_farmer_sub': {
      'en': 'Login with mobile',
      'hi': 'मोबाइल से लॉगिन',
      'mr': 'मोबाइलने लॉगिन',
    },
    'role_fpo': {
      'en': 'FPO / FPC',
      'hi': 'किसान उत्पादक संस्था / कंपनी',
      'mr': 'शेतकरी उत्पादक संस्था / कंपनी',
    },
    'role_fpo_sub': {
      'en': 'Login with FPC details',
      'hi': 'किसान उत्पादक कंपनी की जानकारी से लॉगिन',
      'mr': 'शेतकरी उत्पादक कंपनीच्या माहितीने लॉगिन',
    },
    'role_admin': {'en': 'Admin', 'hi': 'एडमिन', 'mr': 'अ‍ॅडमिन'},
    'role_admin_sub': {
      'en': 'System administration',
      'hi': 'सिस्टम प्रशासन',
      'mr': 'सिस्टम प्रशासन',
    },
    'guest': {
      'en': 'Continue as Guest',
      'hi': 'मेहमान के रूप में जारी रखें',
      'mr': 'पाहुणा म्हणून सुरू ठेवा',
    },
    'guest_sub': {
      'en': 'Fill survey form only\n(Limited Access)',
      'hi': 'केवल सर्वे फॉर्म भरें\n(सीमित पहुँच)',
      'mr': 'फक्त सर्वे फॉर्म भरा\n(मर्यादित प्रवेश)',
    },
    'or': {'en': 'or', 'hi': 'या', 'mr': 'किंवा'},
    'data_safe': {
      'en': 'Your data is safe and secure with us',
      'hi': 'आपका डेटा हमारे पास सुरक्षित है',
      'mr': 'तुमचा डेटा आमच्याकडे सुरक्षित आहे',
    },

    // ── Farmer login ──
    'farmer_login': {
      'en': 'Farmer Login',
      'hi': 'किसान लॉगिन',
      'mr': 'शेतकरी लॉगिन',
    },
    'mobile_number': {
      'en': 'Mobile Number',
      'hi': 'मोबाइल नंबर',
      'mr': 'मोबाइल नंबर',
    },
    'enter_mobile': {
      'en': 'Enter mobile number',
      'hi': 'मोबाइल नंबर लिखें',
      'mr': 'मोबाइल नंबर लिहा',
    },
    'continue_': {'en': 'Continue', 'hi': 'आगे बढ़ें', 'mr': 'पुढे चला'},
    'please_wait': {
      'en': 'Please wait',
      'hi': 'कृपया रुकें',
      'mr': 'कृपया थांबा',
    },
    'secure_private': {
      'en': 'Secure & Private',
      'hi': 'सुरक्षित और निजी',
      'mr': 'सुरक्षित आणि खाजगी',
    },
    'need_help': {
      'en': 'Need help? Contact support',
      'hi': 'मदद चाहिए? सहायता से संपर्क करें',
      'mr': 'मदत हवी? सपोर्टशी संपर्क करा',
    },
    'login_note': {
      'en': 'Use the mobile number registered with your field coordinator.',
      'hi': 'अपने फील्ड समन्वयक के पास पंजीकृत मोबाइल नंबर का उपयोग करें।',
      'mr': 'तुमच्या फील्ड समन्वयकाकडे नोंदवलेला मोबाइल नंबर वापरा.',
    },
    'checking_farmer_number': {
      'en': 'Checking this mobile number in the farmer database.',
      'hi': 'इस मोबाइल नंबर को किसान डेटाबेस में जांचा जा रहा है।',
      'mr': 'हा मोबाइल नंबर शेतकरी डेटाबेसमध्ये तपासत आहोत.',
    },
    'farmer_profile_found': {
      'en': 'Farmer profile found. Preparing secure login.',
      'hi': 'किसान प्रोफ़ाइल मिल गई। सुरक्षित लॉगिन तैयार हो रहा है।',
      'mr': 'शेतकरी प्रोफाइल सापडली. सुरक्षित लॉगिन तयार होत आहे.',
    },
    'starting_farmer_session': {
      'en': 'Starting farmer session for this number.',
      'hi': 'इस नंबर के लिए किसान सत्र शुरू हो रहा है।',
      'mr': 'या नंबरसाठी शेतकरी सत्र सुरू होत आहे.',
    },
    'linking_farmer_profile': {
      'en': 'Linking farmer profile with Supabase.',
      'hi': 'किसान प्रोफ़ाइल Supabase से लिंक हो रही है।',
      'mr': 'शेतकरी प्रोफाइल Supabase शी जोडत आहोत.',
    },
    'syncing_farmer_session': {
      'en': 'Syncing secure farm access.',
      'hi': 'सुरक्षित खेत एक्सेस सिंक हो रहा है।',
      'mr': 'सुरक्षित शेत प्रवेश सिंक होत आहे.',
    },
    'syncing_farm_records': {
      'en': 'Syncing farm records linked to this mobile number.',
      'hi': 'इस मोबाइल नंबर से जुड़े खेत रिकॉर्ड सिंक हो रहे हैं।',
      'mr': 'या मोबाइल नंबरशी जोडलेले शेत रेकॉर्ड सिंक होत आहेत.',
    },
    'farm_records_synced': {
      'en': '{count} farm records synced.',
      'hi': '{count} खेत रिकॉर्ड सिंक हुए।',
      'mr': '{count} शेत रेकॉर्ड सिंक झाले.',
    },
    'no_farm_records_found': {
      'en': 'No farm records found. First farm setup will open next.',
      'hi': 'कोई खेत रिकॉर्ड नहीं मिला। आगे पहला खेत सेटअप खुलेगा।',
      'mr': 'शेत रेकॉर्ड सापडले नाहीत. पुढे पहिले शेत सेटअप उघडेल.',
    },
    'opening_farmer_dashboard': {
      'en': 'Opening farmer dashboard.',
      'hi': 'किसान डैशबोर्ड खुल रहा है।',
      'mr': 'शेतकरी डॅशबोर्ड उघडत आहे.',
    },
    'offline_cached_session': {
      'en': 'You are offline. Last saved farm data will open when available.',
      'hi': 'आप ऑफलाइन हैं। उपलब्ध होने पर पिछला सेव खेत डेटा खुलेगा।',
      'mr':
          'तुम्ही ऑफलाइन आहात. उपलब्ध असल्यास मागील सेव्ह केलेला शेत डेटा उघडेल.',
    },
    'repairing_empty_farm_cache': {
      'en': 'Repairing farm cache and checking remote farms again.',
      'hi': 'खेत कैश ठीक कर रिमोट खेत दोबारा जांचे जा रहे हैं।',
      'mr': 'शेत कॅश दुरुस्त करून रिमोट शेते पुन्हा तपासत आहोत.',
    },
    'network_issue_error': {
      'en': 'Network issue. Check internet and try again.',
      'hi': 'नेटवर्क समस्या है। इंटरनेट जांचें और फिर प्रयास करें।',
      'mr': 'नेटवर्क समस्या आहे. इंटरनेट तपासा आणि पुन्हा प्रयत्न करा.',
    },
    'server_sync_failed_error': {
      'en': 'Server sync failed. Try again in a moment.',
      'hi': 'सर्वर सिंक विफल हुआ। थोड़ी देर में फिर प्रयास करें।',
      'mr': 'सर्व्हर सिंक अयशस्वी झाले. थोड्या वेळाने पुन्हा प्रयत्न करा.',
    },
    'farm_data_missing_error': {
      'en': 'Farm data missing. Refresh farm sync or contact support.',
      'hi': 'खेत डेटा नहीं मिला। खेत सिंक रिफ्रेश करें या सहायता लें।',
      'mr': 'शेत डेटा मिळाला नाही. शेत सिंक रिफ्रेश करा किंवा मदत घ्या.',
    },
    'session_expired_error': {
      'en': 'Session expired. Login again.',
      'hi': 'सत्र समाप्त हो गया। फिर से लॉगिन करें।',
      'mr': 'सत्र संपले. पुन्हा लॉगिन करा.',
    },
    'login_step_checking_farmer_number': {
      'en': 'Checking number',
      'hi': 'नंबर जांच रहे हैं',
      'mr': 'नंबर तपासत आहोत',
    },
    'login_step_farmer_profile_found': {
      'en': 'Farmer found',
      'hi': 'किसान मिला',
      'mr': 'शेतकरी सापडला',
    },
    'login_step_starting_farmer_session': {
      'en': 'Starting session',
      'hi': 'सत्र शुरू हो रहा है',
      'mr': 'सत्र सुरू होत आहे',
    },
    'login_step_syncing_farm_records': {
      'en': 'Syncing farms',
      'hi': 'खेत सिंक हो रहे हैं',
      'mr': 'शेते सिंक होत आहेत',
    },
    'login_step_opening_farmer_dashboard': {
      'en': 'Opening dashboard',
      'hi': 'डैशबोर्ड खुल रहा है',
      'mr': 'डॅशबोर्ड उघडत आहे',
    },
    'farm_count_value': {
      'en': '{count} farms',
      'hi': '{count} खेत',
      'mr': '{count} शेते',
    },
    'last_sync_value': {
      'en': 'Last sync: {value}',
      'hi': 'अंतिम सिंक: {value}',
      'mr': 'शेवटचे सिंक: {value}',
    },
    'last_sync_not_available': {
      'en': 'Last sync not available',
      'hi': 'अंतिम सिंक उपलब्ध नहीं',
      'mr': 'शेवटचे सिंक उपलब्ध नाही',
    },
    'login_status_code_value': {
      'en': 'Status: {code}',
      'hi': 'स्थिति: {code}',
      'mr': 'स्थिती: {code}',
    },
    'login_health_check': {
      'en': 'Login health check',
      'hi': 'लॉगिन स्वास्थ्य जांच',
      'mr': 'लॉगिन स्थिती तपासणी',
    },
    'login_health_check_desc': {
      'en': 'Farmer, session, farm sync, and offline readiness',
      'hi': 'किसान, सत्र, खेत सिंक और ऑफलाइन तैयारी',
      'mr': 'शेतकरी, सत्र, शेत सिंक आणि ऑफलाइन तयारी',
    },
    'health_farmer_verified': {
      'en': 'Farmer verified',
      'hi': 'किसान सत्यापित',
      'mr': 'शेतकरी सत्यापित',
    },
    'health_session_linked': {
      'en': 'Session linked',
      'hi': 'सत्र लिंक हुआ',
      'mr': 'सत्र जोडले',
    },
    'health_farm_sync': {'en': 'Farm sync', 'hi': 'खेत सिंक', 'mr': 'शेत सिंक'},
    'health_offline_cache': {
      'en': 'Offline cache',
      'hi': 'ऑफलाइन कैश',
      'mr': 'ऑफलाइन कॅश',
    },
    'health_ready': {'en': 'Ready', 'hi': 'तैयार', 'mr': 'तयार'},
    'health_waiting': {'en': 'Waiting', 'hi': 'प्रतीक्षा', 'mr': 'प्रतीक्षा'},
    'last_farmer': {
      'en': 'Last logged-in farmer',
      'hi': 'पिछला लॉगिन किसान',
      'mr': 'मागील लॉगिन शेतकरी',
    },
    'login': {'en': 'Login', 'hi': 'लॉगिन', 'mr': 'लॉगिन'},
    'call_support': {'en': 'Call', 'hi': 'कॉल करें', 'mr': 'कॉल करा'},
    'whatsapp': {'en': 'WhatsApp', 'hi': 'WhatsApp', 'mr': 'WhatsApp'},
    'support_contact_copied': {
      'en': 'Support contact copied: {phone}',
      'hi': 'सहायता संपर्क कॉपी हुआ: {phone}',
      'mr': 'सपोर्ट संपर्क कॉपी झाला: {phone}',
    },
    'invalid_phone': {
      'en': 'Enter a valid 10 digit mobile number',
      'hi': '10 अंकों का सही मोबाइल नंबर लिखें',
      'mr': '10 अंकी योग्य मोबाइल नंबर लिहा',
    },
    'support_title': {'en': 'Support', 'hi': 'सहायता', 'mr': 'मदत'},
    'support_body': {
      'en': 'Contact your field coordinator for login help.',
      'hi': 'लॉगिन में मदद के लिए अपने फील्ड समन्वयक से संपर्क करें।',
      'mr': 'लॉगिनसाठी तुमच्या फील्ड समन्वयकाशी संपर्क साधा.',
    },
    'back': {'en': 'Back', 'hi': 'पीछे', 'mr': 'मागे'},
    'menu': {'en': 'Menu', 'hi': 'मेनू', 'mr': 'मेनू'},
    'change_language': {
      'en': 'Change language',
      'hi': 'भाषा बदलें',
      'mr': 'भाषा बदला',
    },
    'signup_phone_required': {
      'en': 'Enter 10 digit mobile number to sign up',
      'hi': 'साइन अप के लिए 10 अंकों का मोबाइल नंबर लिखें',
      'mr': 'साइन अपसाठी 10 अंकी मोबाइल नंबर लिहा',
    },
    'new_farmer_number': {
      'en': 'New farmer number?',
      'hi': 'नया किसान नंबर?',
      'mr': 'नवीन शेतकरी नंबर?',
    },
    'new_farmer_create_profile': {
      'en': 'New farmer? Create profile',
      'hi': 'नए किसान हैं? प्रोफ़ाइल बनाएं',
      'mr': 'नवीन शेतकरी? प्रोफाइल तयार करा',
    },
    'create_profile_this_mobile': {
      'en': 'Create profile with this mobile number.',
      'hi': 'इस मोबाइल नंबर से प्रोफ़ाइल बनाएं।',
      'mr': 'या मोबाइल नंबरने प्रोफाइल तयार करा.',
    },
    'sign_up': {'en': 'Sign up', 'hi': 'साइन अप', 'mr': 'साइन अप'},
    'create_farmer_profile': {
      'en': 'Create Farmer Profile',
      'hi': 'किसान प्रोफ़ाइल बनाएं',
      'mr': 'शेतकरी प्रोफाइल तयार करा',
    },
    'farmer_signup_subtitle': {
      'en':
          'Your mobile number is new. Add basic details first, then mark your farm.',
      'hi':
          'आपका मोबाइल नंबर नया है। पहले मूल जानकारी जोड़ें, फिर अपना खेत चिन्हित करें।',
      'mr':
          'तुमचा मोबाइल नंबर नवीन आहे. आधी मूलभूत माहिती भरा, मग तुमचे शेत मार्क करा.',
    },
    'farmer_name': {
      'en': 'Farmer name',
      'hi': 'किसान का नाम',
      'mr': 'शेतकऱ्याचे नाव',
    },
    'enter_full_name': {
      'en': 'Enter full name',
      'hi': 'पूरा नाम लिखें',
      'mr': 'पूर्ण नाव लिहा',
    },
    'enter_farmer_name_error': {
      'en': 'Enter farmer name',
      'hi': 'किसान का नाम लिखें',
      'mr': 'शेतकऱ्याचे नाव लिहा',
    },
    'village_or_location': {
      'en': 'Village or location',
      'hi': 'गाँव या स्थान',
      'mr': 'गाव किंवा ठिकाण',
    },
    'location_example': {
      'en': 'Example: Rajur, Akole',
      'hi': 'उदाहरण: राजूर, अकोले',
      'mr': 'उदा: राजूर, अकोले',
    },
    'creating_profile': {
      'en': 'Creating profile',
      'hi': 'प्रोफ़ाइल बन रही है',
      'mr': 'प्रोफाइल तयार होत आहे',
    },
    'continue_to_farm_setup': {
      'en': 'Continue to farm setup',
      'hi': 'खेत सेटअप पर जाएं',
      'mr': 'शेत सेटअपकडे पुढे चला',
    },
    'registered_mobile_number': {
      'en': 'Registered mobile number',
      'hi': 'पंजीकृत मोबाइल नंबर',
      'mr': 'नोंदणीकृत मोबाइल नंबर',
    },
    'farmer_not_found_redirect': {
      'en': 'Create a new farmer account. Tap Sign up to continue.',
      'hi': 'नया किसान अकाउंट बनाएं। आगे बढ़ने के लिए साइन अप पर टैप करें।',
      'mr': 'नवीन शेतकरी खाते तयार करा. पुढे जाण्यासाठी साइन अपवर टॅप करा.',
    },
    'farmer_not_found': {
      'en': 'Create a new farmer account. Tap Sign up to continue.',
      'hi': 'नया किसान अकाउंट बनाएं। आगे बढ़ने के लिए साइन अप पर टैप करें।',
      'mr': 'नवीन शेतकरी खाते तयार करा. पुढे जाण्यासाठी साइन अपवर टॅप करा.',
    },
    'creating_farmer_profile': {
      'en': 'Creating farmer profile and secure farm access.',
      'hi': 'किसान प्रोफ़ाइल और सुरक्षित खेत एक्सेस बनाया जा रहा है।',
      'mr': 'शेतकरी प्रोफाइल आणि सुरक्षित शेत प्रवेश तयार होत आहे.',
    },
    'initial_farm_sync_title': {
      'en': 'Syncing your farm',
      'hi': 'आपका खेत सिंक हो रहा है',
      'mr': 'तुमचे शेत सिंक होत आहे',
    },
    'initial_farm_sync_message': {
      'en':
          'Loading this farm, weather, risk cells, scout zones and history before opening.',
      'hi':
          'खोलने से पहले खेत, मौसम, जोखिम सेल, स्काउट जोन और इतिहास लोड हो रहे हैं।',
      'mr':
          'उघडण्यापूर्वी शेत, हवामान, धोका सेल, स्काउट झोन आणि इतिहास लोड होत आहेत.',
    },
    'farm_page_sync_message': {
      'en':
          'Refreshing weather, risk cells, scout zones, advice and history for this farm.',
      'hi':
          'इस खेत के लिए मौसम, जोखिम सेल, स्काउट जोन, सलाह और इतिहास रीफ्रेश हो रहे हैं।',
      'mr':
          'या शेतासाठी हवामान, धोका सेल, स्काउट झोन, सल्ला आणि इतिहास रीफ्रेश होत आहेत.',
    },
    'first_farm_loading_title': {
      'en': 'Setting up your farm',
      'hi': 'आपका खेत सेट हो रहा है',
      'mr': 'तुमचे शेत सेट होत आहे',
    },
    'first_farm_saving_remote': {
      'en': 'Saving this farm to the remote database.',
      'hi': 'यह खेत रिमोट डेटाबेस में सहेजा जा रहा है।',
      'mr': 'हे शेत रिमोट डेटाबेसमध्ये सेव्ह होत आहे.',
    },
    'first_farm_loading_remote': {
      'en': 'Loading the saved farm in the app. This can take a few seconds.',
      'hi': 'सहेजा हुआ खेत ऐप में लोड हो रहा है। इसमें कुछ सेकंड लग सकते हैं।',
      'mr': 'सेव्ह केलेले शेत अॅपमध्ये लोड होत आहे. काही सेकंद लागू शकतात.',
    },
    'first_farm_loading_hint': {
      'en': 'Weather, risk detection and farm history will sync next.',
      'hi': 'इसके बाद मौसम, जोखिम जांच और खेत इतिहास सिंक होंगे।',
      'mr': 'यानंतर हवामान, धोका तपासणी आणि शेत इतिहास सिंक होतील.',
    },
    'farmer_already_exists': {
      'en':
          'This mobile number already has a farmer profile. Please login instead.',
      'hi': 'इस मोबाइल नंबर पर किसान प्रोफ़ाइल पहले से है। कृपया लॉगिन करें।',
      'mr': 'या मोबाइल नंबरवर शेतकरी प्रोफाइल आधीच आहे. कृपया लॉगिन करा.',
    },
    'farmer_session_error': {
      'en': 'Could not start farmer session.',
      'hi': 'किसान सत्र शुरू नहीं हो सका।',
      'mr': 'शेतकरी सत्र सुरू करता आले नाही.',
    },
    'farmer_create_error': {
      'en': 'Could not create farmer profile.',
      'hi': 'किसान प्रोफ़ाइल नहीं बन सकी।',
      'mr': 'शेतकरी प्रोफाइल तयार करता आले नाही.',
    },
    'farmer_register_error': {
      'en':
          'Could not register farmer in remote database. Check connection and try again.',
      'hi':
          'रिमोट डेटाबेस में किसान पंजीकृत नहीं हो सका। कनेक्शन जांचें और फिर कोशिश करें।',
      'mr':
          'रिमोट डेटाबेसमध्ये शेतकरी नोंदवता आला नाही. कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.',
    },
    'farmer_verify_error': {
      'en':
          'Could not verify farmer profile. Check the number or contact admin.',
      'hi':
          'किसान प्रोफ़ाइल सत्यापित नहीं हो सकी। नंबर जांचें या एडमिन से संपर्क करें।',
      'mr':
          'शेतकरी प्रोफाइल पडताळता आले नाही. नंबर तपासा किंवा अ‍ॅडमिनशी संपर्क करा.',
    },
    'farmer_confirm_error': {
      'en': 'Could not confirm farmer profile after signup.',
      'hi': 'साइन अप के बाद किसान प्रोफ़ाइल की पुष्टि नहीं हो सकी।',
      'mr': 'साइन अपनंतर शेतकरी प्रोफाइलची पुष्टी करता आली नाही.',
    },
    'syncing_farms': {
      'en': 'Syncing farms',
      'hi': 'खेत सिंक हो रहे हैं',
      'mr': 'शेते सिंक होत आहेत',
    },
    'checking_farms_for_mobile': {
      'en':
          'Checking the remote database for farms linked to this mobile number.',
      'hi':
          'इस मोबाइल नंबर से जुड़े खेतों के लिए रिमोट डेटाबेस जांचा जा रहा है।',
      'mr': 'या मोबाइल नंबरशी जोडलेली शेते रिमोट डेटाबेसमध्ये तपासत आहोत.',
    },
    'farm_setup_required': {
      'en': 'Farm setup required',
      'hi': 'खेत सेटअप आवश्यक है',
      'mr': 'शेत सेटअप आवश्यक आहे',
    },
    'add_sync_first_farm_before_use': {
      'en': 'Add and sync the first farm before using this section.',
      'hi': 'इस सेक्शन का उपयोग करने से पहले पहला खेत जोड़कर सिंक करें।',
      'mr': 'हा विभाग वापरण्यापूर्वी पहिले शेत जोडा आणि सिंक करा.',
    },
    'add_first_farm': {
      'en': 'Add your first farm',
      'hi': 'अपना पहला खेत जोड़ें',
      'mr': 'तुमचे पहिले शेत जोडा',
    },
    'first_farm_dialog_body': {
      'en':
          'Farm setup is required for this new farmer login so weather, market, diagnosis, harvest, and grading data stay linked to the right farm.',
      'hi':
          'इस नए किसान लॉगिन के लिए खेत सेटअप आवश्यक है ताकि मौसम, बाजार, निदान, कटाई और ग्रेडिंग डेटा सही खेत से जुड़ा रहे।',
      'mr':
          'या नवीन शेतकरी लॉगिनसाठी शेत सेटअप आवश्यक आहे, जेणेकरून हवामान, बाजार, निदान, कापणी आणि ग्रेडिंग डेटा योग्य शेताशी जोडलेला राहील.',
    },
    'mark_boundary': {
      'en': 'Mark boundary',
      'hi': 'सीमा चिन्हित करें',
      'mr': 'सीमा मार्क करा',
    },
    'draw_farm_area': {
      'en': 'Draw the farm area on the map.',
      'hi': 'मैप पर खेत का क्षेत्र बनाएं।',
      'mr': 'नकाशावर शेताचे क्षेत्र रेखाटा.',
    },
    'add_crop_details': {
      'en': 'Add crop details',
      'hi': 'फसल जानकारी जोड़ें',
      'mr': 'पीक माहिती जोडा',
    },
    'confirm_crop_details': {
      'en': 'Confirm crop, variety, soil, and sowing date.',
      'hi': 'फसल, किस्म, मिट्टी और बुवाई तारीख की पुष्टि करें।',
      'mr': 'पीक, वाण, माती आणि पेरणी तारीख निश्चित करा.',
    },
    'sync_farmer_data': {
      'en': 'Sync farmer data',
      'hi': 'किसान डेटा सिंक करें',
      'mr': 'शेतकरी डेटा सिंक करा',
    },
    'save_phone_linked_profile': {
      'en': 'Save it to the phone-linked farmer profile.',
      'hi': 'इसे मोबाइल नंबर से जुड़ी किसान प्रोफ़ाइल में सहेजें।',
      'mr': 'ते मोबाइल नंबरशी जोडलेल्या शेतकरी प्रोफाइलमध्ये जतन करा.',
    },
    'start_farm_setup': {
      'en': 'Start farm setup',
      'hi': 'खेत सेटअप शुरू करें',
      'mr': 'शेत सेटअप सुरू करा',
    },
    'farm_sync_required': {
      'en': 'Farm sync required',
      'hi': 'खेत सिंक आवश्यक है',
      'mr': 'शेत सिंक आवश्यक आहे',
    },
    'first_farm_remote_required': {
      'en': 'This farm must be saved to the remote database before continuing.',
      'hi': 'आगे बढ़ने से पहले यह खेत रिमोट डेटाबेस में सहेजना जरूरी है।',
      'mr': 'पुढे जाण्यापूर्वी हे शेत रिमोट डेटाबेसमध्ये जतन होणे आवश्यक आहे.',
    },
    'syncing_farm_data': {
      'en': 'Syncing farm data',
      'hi': 'खेत डेटा सिंक हो रहा है',
      'mr': 'शेत डेटा सिंक होत आहे',
    },
    'checking_supabase_farms': {
      'en': 'Checking Supabase for farms linked to {phone}.',
      'hi': '{phone} से जुड़े खेतों के लिए Supabase जांचा जा रहा है।',
      'mr': '{phone} शी जोडलेली शेते Supabase मध्ये तपासत आहोत.',
    },
    'first_farm_setup_required_tools': {
      'en':
          'Farm setup is required before market, AI, weather, grading, and harvest tools can sync for this farmer.',
      'hi':
          'इस किसान के लिए बाजार, AI, मौसम, ग्रेडिंग और कटाई टूल सिंक होने से पहले खेत सेटअप जरूरी है।',
      'mr':
          'या शेतकऱ्यासाठी बाजार, AI, हवामान, ग्रेडिंग आणि कापणी साधने सिंक होण्यापूर्वी शेत सेटअप आवश्यक आहे.',
    },
    'save_and_sync': {
      'en': 'Save and sync',
      'hi': 'सहेजें और सिंक करें',
      'mr': 'जतन करा आणि सिंक करा',
    },
    'farm_must_remote': {
      'en': 'The farm must be saved to the remote profile.',
      'hi': 'खेत रिमोट प्रोफ़ाइल में सहेजा जाना चाहिए।',
      'mr': 'शेत रिमोट प्रोफाइलमध्ये जतन झाले पाहिजे.',
    },
    'waiting_for_sync': {
      'en': 'Waiting for sync',
      'hi': 'सिंक का इंतज़ार',
      'mr': 'सिंकची प्रतीक्षा',
    },
    'check_remote_farms_again': {
      'en': 'Check remote farms again',
      'hi': 'रिमोट खेत फिर जांचें',
      'mr': 'रिमोट शेते पुन्हा तपासा',
    },
    'millet': {'en': 'Millet', 'hi': 'मिलेट', 'mr': 'मिलेट'},
    'select_variety': {
      'en': 'Select variety',
      'hi': 'किस्म चुनें',
      'mr': 'वाण निवडा',
    },
    'zero_acres': {'en': '0 acres', 'hi': '0 एकड़', 'mr': '0 एकर'},
    'acres_unit': {'en': 'acres', 'hi': 'एकड़', 'mr': 'एकर'},
    'setup_required': {
      'en': 'Setup required',
      'hi': 'सेटअप आवश्यक है',
      'mr': 'सेटअप आवश्यक आहे',
    },
    'too_few_points': {
      'en': 'Too few points',
      'hi': 'बहुत कम पॉइंट',
      'mr': 'खूप कमी पॉइंट',
    },
    'add_boundary_points_before_save': {
      'en': 'Add at least 3 boundary points before saving the farm.',
      'hi': 'खेत सेव करने से पहले कम से कम 3 सीमा पॉइंट जोड़ें।',
      'mr': 'शेत जतन करण्यापूर्वी किमान 3 सीमा पॉइंट जोडा.',
    },
    'login_required': {
      'en': 'Login required',
      'hi': 'लॉगिन आवश्यक है',
      'mr': 'लॉगिन आवश्यक आहे',
    },
    'farm_link_login_required': {
      'en':
          'Could not link this farm to the current farmer login. Please login again.',
      'hi':
          'यह खेत मौजूदा किसान लॉगिन से लिंक नहीं हो सका। कृपया फिर से लॉगिन करें।',
      'mr':
          'हे शेत सध्याच्या शेतकरी लॉगिनशी जोडता आले नाही. कृपया पुन्हा लॉगिन करा.',
    },
    'error': {'en': 'Error', 'hi': 'त्रुटि', 'mr': 'त्रुटी'},
    'could_not_save_farm': {
      'en': 'Could not save farm',
      'hi': 'खेत सेव नहीं हो सका',
      'mr': 'शेत जतन करता आले नाही',
    },
    'farm_save_auth_required': {
      'en': 'Please login again, then save this farm.',
      'hi': 'कृपया फिर से लॉगिन करें, फिर यह खेत सेव करें।',
      'mr': 'कृपया पुन्हा लॉगिन करा, नंतर हे शेत जतन करा.',
    },
    'farm_save_boundary_required': {
      'en': 'Mark the farm boundary again before saving.',
      'hi': 'सेव करने से पहले खेत की सीमा फिर से मार्क करें।',
      'mr': 'जतन करण्यापूर्वी शेताची सीमा पुन्हा मार्क करा.',
    },
    'farm_save_farmer_mismatch': {
      'en':
          'This farm does not match the current farmer login. Please login again.',
      'hi':
          'यह खेत मौजूदा किसान लॉगिन से मेल नहीं खाता। कृपया फिर से लॉगिन करें।',
      'mr':
          'हे शेत सध्याच्या शेतकरी लॉगिनशी जुळत नाही. कृपया पुन्हा लॉगिन करा.',
    },
    'farm_save_network_retry': {
      'en': 'Network or server issue. Check connection and try again.',
      'hi': 'नेटवर्क या सर्वर समस्या है। कनेक्शन जांचें और फिर कोशिश करें।',
      'mr':
          'नेटवर्क किंवा सर्व्हर समस्या आहे. कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.',
    },
    'farm_setup_q_farm_name': {
      'en': 'First, tell me your farm name.',
      'hi': 'पहले अपने खेत का नाम बताएं।',
      'mr': 'सुरुवातीला तुमच्या शेताचे नाव सांगा.',
    },
    'farm_setup_q_mark_polygon': {
      'en':
          'Mark the farm boundary on the map. I will calculate land area in acres automatically.',
      'hi':
          'मैप पर खेत की सीमा चिन्हित करें। क्षेत्रफल एकड़ में अपने आप निकलेगा।',
      'mr':
          'नकाशावर शेताची सीमा मार्क करा. क्षेत्रफळ एकरमध्ये आपोआप मोजले जाईल.',
    },
    'farm_setup_q_crop': {
      'en': 'Choose the crop grown on this farm.',
      'hi': 'इस खेत में उगाई गई फसल चुनें।',
      'mr': 'या शेतातील पीक निवडा.',
    },
    'farm_setup_q_variety': {
      'en': 'Choose the crop variety.',
      'hi': 'फसल की किस्म चुनें।',
      'mr': 'पिकाचा वाण निवडा.',
    },
    'farm_setup_q_previous_crop': {
      'en': 'Which crop was sown here previously?',
      'hi': 'यहाँ पहले कौन सी फसल बोई गई थी?',
      'mr': 'यापूर्वी येथे कोणते पीक घेतले होते?',
    },
    'farm_setup_q_season': {
      'en': 'Which season is this crop for?',
      'hi': 'यह फसल किस मौसम के लिए है?',
      'mr': 'हे पीक कोणत्या हंगामासाठी आहे?',
    },
    'farm_setup_q_irrigation': {
      'en': 'What is the irrigation source or water condition?',
      'hi': 'सिंचाई स्रोत या पानी की स्थिति क्या है?',
      'mr': 'सिंचन स्रोत किंवा पाण्याची स्थिती काय आहे?',
    },
    'farm_setup_q_soil': {
      'en': 'What is the soil type?',
      'hi': 'मिट्टी का प्रकार क्या है?',
      'mr': 'मातीचा प्रकार काय आहे?',
    },
    'farm_setup_q_ownership': {
      'en': 'What is the land ownership type?',
      'hi': 'जमीन के स्वामित्व का प्रकार क्या है?',
      'mr': 'जमिनीच्या मालकीचा प्रकार काय आहे?',
    },
    'farm_setup_q_seed_source': {
      'en': 'Where did the seed come from?',
      'hi': 'बीज कहाँ से आया?',
      'mr': 'बियाणे कुठून आले?',
    },
    'farm_setup_q_harvest_intent': {
      'en': 'What is the main harvest use?',
      'hi': 'कटाई का मुख्य उपयोग क्या है?',
      'mr': 'कापणीचा मुख्य उपयोग काय आहे?',
    },
    'farm_setup_q_sowing_date': {
      'en': 'When did you sow? Select from menu or type yyyy-mm-dd.',
      'hi': 'बुवाई कब की? मेन्यू से चुनें या yyyy-mm-dd लिखें।',
      'mr': 'पेरणी कधी केली? मेन्यूमधून निवडा किंवा yyyy-mm-dd लिहा.',
    },
    'review_and_continue': {
      'en': 'Review and continue',
      'hi': 'जांचें और आगे बढ़ें',
      'mr': 'तपासा आणि पुढे जा',
    },
    'farm_label': {'en': 'Farm', 'hi': 'खेत', 'mr': 'शेत'},
    'land_marked_label': {
      'en': 'Land marked',
      'hi': 'चिन्हित भूमि',
      'mr': 'मार्क केलेली जमीन',
    },
    'crop_label': {'en': 'Crop', 'hi': 'फसल', 'mr': 'पीक'},
    'variety_label': {'en': 'Variety', 'hi': 'किस्म', 'mr': 'वाण'},
    'previous_crop_label': {
      'en': 'Previous crop',
      'hi': 'पिछली फसल',
      'mr': 'मागील पीक',
    },
    'season_label': {'en': 'Season', 'hi': 'मौसम', 'mr': 'हंगाम'},
    'irrigation_label': {'en': 'Irrigation', 'hi': 'सिंचाई', 'mr': 'सिंचन'},
    'soil_label': {'en': 'Soil', 'hi': 'मिट्टी', 'mr': 'माती'},
    'ownership_label': {'en': 'Ownership', 'hi': 'स्वामित्व', 'mr': 'मालकी'},
    'seed_source_label': {
      'en': 'Seed source',
      'hi': 'बीज स्रोत',
      'mr': 'बियाणे स्रोत',
    },
    'harvest_use_label': {
      'en': 'Harvest use',
      'hi': 'कटाई उपयोग',
      'mr': 'कापणी उपयोग',
    },
    'sowing_date_label': {
      'en': 'Sowing date',
      'hi': 'बुवाई तारीख',
      'mr': 'पेरणी तारीख',
    },
    'boundary_not_captured': {
      'en': 'Boundary not captured. Mark at least 3 points on the map.',
      'hi': 'सीमा कैप्चर नहीं हुई। मैप पर कम से कम 3 पॉइंट चिन्हित करें।',
      'mr': 'सीमा कॅप्चर झाली नाही. नकाशावर किमान 3 पॉइंट मार्क करा.',
    },
    'farm_marked_area': {
      'en': 'Farm marked with {points} points. Land area fetched as {area}.',
      'hi': 'खेत {points} पॉइंट से चिन्हित हुआ। क्षेत्रफल {area} मिला।',
      'mr': 'शेत {points} पॉइंटने मार्क झाले. क्षेत्रफळ {area} मिळाले.',
    },
    'date_parse_error': {
      'en': 'I could not parse this date. Use yyyy-mm-dd.',
      'hi': 'यह तारीख समझ नहीं आई। yyyy-mm-dd उपयोग करें।',
      'mr': 'ही तारीख समजली नाही. yyyy-mm-dd वापरा.',
    },
    'type_answer_first': {
      'en': 'Type an answer first',
      'hi': 'पहले जवाब लिखें',
      'mr': 'आधी उत्तर लिहा',
    },
    'mark_boundary_first': {
      'en': 'Mark the farm boundary first.',
      'hi': 'पहले खेत की सीमा चिन्हित करें।',
      'mr': 'आधी शेताची सीमा मार्क करा.',
    },
    'choose_crop_error': {
      'en': 'Choose a crop.',
      'hi': 'फसल चुनें।',
      'mr': 'पीक निवडा.',
    },
    'choose_variety_error': {
      'en': 'Choose a variety.',
      'hi': 'किस्म चुनें।',
      'mr': 'वाण निवडा.',
    },
    'add_sowing_date_error': {
      'en': 'Add sowing date.',
      'hi': 'बुवाई तारीख जोड़ें।',
      'mr': 'पेरणी तारीख जोडा.',
    },
    'complete_all_fields_before_save': {
      'en': 'Please complete all fields before saving.',
      'hi': 'सेव करने से पहले सभी जानकारी पूरी करें।',
      'mr': 'जतन करण्यापूर्वी सर्व माहिती पूर्ण करा.',
    },
    'add_farm_title': {'en': 'Add farm', 'hi': 'खेत जोड़ें', 'mr': 'शेत जोडा'},
    'open_map_mark_land': {
      'en': 'Open map and mark land',
      'hi': 'मैप खोलें और भूमि चिन्हित करें',
      'mr': 'नकाशा उघडा आणि जमीन मार्क करा',
    },
    'remark_land': {
      'en': 'Re-mark land',
      'hi': 'भूमि फिर चिन्हित करें',
      'mr': 'जमीन पुन्हा मार्क करा',
    },
    'polygon_points_land': {
      'en': 'Polygon points: {points} • Land marked: {area}',
      'hi': 'पॉलीगॉन पॉइंट: {points} • चिन्हित भूमि: {area}',
      'mr': 'पॉलीगॉन पॉइंट: {points} • मार्क केलेली जमीन: {area}',
    },
    'save_farm': {'en': 'Save farm', 'hi': 'खेत सेव करें', 'mr': 'शेत जतन करा'},
    'type_answer_hint': {
      'en': 'Type your answer...',
      'hi': 'अपना जवाब लिखें...',
      'mr': 'तुमचे उत्तर लिहा...',
    },
    'send': {'en': 'Send', 'hi': 'भेजें', 'mr': 'पाठवा'},
    'nav_home': {'en': 'Home', 'hi': 'होम', 'mr': 'होम'},
    'nav_farm': {'en': 'Farm', 'hi': 'खेत', 'mr': 'शेत'},
    'nav_apmc_short': {'en': 'APMC', 'hi': 'बाजार समिति', 'mr': 'बाजार समिती'},
    'nav_harvest': {'en': 'Harvest', 'hi': 'कटाई', 'mr': 'कापणी'},
    'ai_chat': {'en': 'AI Chat', 'hi': 'AI चैट', 'mr': 'AI चॅट'},
    'apmc_market': {
      'en': 'APMC Market',
      'hi': 'कृषि उपज मंडी',
      'mr': 'कृषी उत्पन्न बाजार समिती',
    },
    'news': {'en': 'News', 'hi': 'समाचार', 'mr': 'बातम्या'},
    'schemes': {'en': 'Schemes', 'hi': 'योजनाएँ', 'mr': 'योजना'},
    'grain_grading': {
      'en': 'Grain Grading',
      'hi': 'अनाज ग्रेडिंग',
      'mr': 'धान्य ग्रेडिंग',
    },
    'farm_history': {
      'en': 'Farm History',
      'hi': 'खेत इतिहास',
      'mr': 'शेत इतिहास',
    },
    'inventory': {'en': 'Inventory', 'hi': 'इन्वेंटरी', 'mr': 'साठा'},
    'profile': {'en': 'Profile', 'hi': 'प्रोफ़ाइल', 'mr': 'प्रोफाइल'},
    'settings': {'en': 'Settings', 'hi': 'सेटिंग्स', 'mr': 'सेटिंग्ज'},
    'farmer_session_passport': {
      'en': 'Farmer session passport',
      'hi': 'किसान सत्र पासपोर्ट',
      'mr': 'शेतकरी सत्र पासपोर्ट',
    },
    'verified_login_sync_summary': {
      'en': 'Verified login, farm count, and last sync status',
      'hi': 'सत्यापित लॉगिन, खेत संख्या और अंतिम सिंक स्थिति',
      'mr': 'सत्यापित लॉगिन, शेत संख्या आणि शेवटचे सिंक स्थिती',
    },
    'synced_farms_count': {
      'en': 'Synced farms',
      'hi': 'सिंक खेत',
      'mr': 'सिंक शेते',
    },
    'last_sync': {'en': 'Last sync', 'hi': 'अंतिम सिंक', 'mr': 'शेवटचे सिंक'},
    'active_farm': {
      'en': 'Active farm',
      'hi': 'सक्रिय खेत',
      'mr': 'सक्रिय शेत',
    },
    'account': {'en': 'Account', 'hi': 'खाता', 'mr': 'खाते'},
    'farmer_identity': {
      'en': 'Farmer identity',
      'hi': 'किसान पहचान',
      'mr': 'शेतकरी ओळख',
    },
    'farmer_account': {
      'en': 'Farmer account',
      'hi': 'किसान खाता',
      'mr': 'शेतकरी खाते',
    },
    'profile_id_label': {
      'en': 'Profile ID',
      'hi': 'प्रोफ़ाइल पहचान क्रमांक',
      'mr': 'प्रोफाइल ओळख क्रमांक',
    },
    'mobile_login': {
      'en': 'Mobile login',
      'hi': 'मोबाइल लॉगिन',
      'mr': 'मोबाइल लॉगिन',
    },
    'mobile_linked_profile': {
      'en': 'This number is linked to your farmer profile.',
      'hi': 'यह नंबर आपकी किसान प्रोफ़ाइल से जुड़ा है।',
      'mr': 'हा नंबर तुमच्या शेतकरी प्रोफाइलशी जोडलेला आहे.',
    },
    'language': {'en': 'Language', 'hi': 'भाषा', 'mr': 'भाषा'},
    'language_options': {
      'en': 'English, Hindi, Marathi',
      'hi': 'अंग्रेज़ी, हिंदी, मराठी',
      'mr': 'इंग्रजी, हिंदी, मराठी',
    },
    'language_login_selector_hint': {
      'en': 'Use the language selector on the login screen.',
      'hi': 'लॉगिन स्क्रीन पर भाषा चयन का उपयोग करें।',
      'mr': 'लॉगिन स्क्रीनवरील भाषा निवड वापरा.',
    },
    'farms_and_sync': {
      'en': 'Farms And Sync',
      'hi': 'खेत और सिंक',
      'mr': 'शेते आणि सिंक',
    },
    'farm_data_sync': {
      'en': 'Farm data sync',
      'hi': 'खेत डेटा सिंक',
      'mr': 'शेत डेटा सिंक',
    },
    'farm_sync_not_available': {
      'en': 'Farm sync is not available on this screen',
      'hi': 'इस स्क्रीन पर खेत सिंक उपलब्ध नहीं है',
      'mr': 'या स्क्रीनवर शेत सिंक उपलब्ध नाही',
    },
    'open_home_to_sync': {
      'en': 'Open the farmer home page to sync farm data.',
      'hi': 'खेत डेटा सिंक करने के लिए किसान होम पेज खोलें।',
      'mr': 'शेत डेटा सिंक करण्यासाठी शेतकरी होम पेज उघडा.',
    },
    'syncing_farms_from_cloud': {
      'en': 'Syncing farms from cloud',
      'hi': 'क्लाउड से खेत सिंक हो रहे हैं',
      'mr': 'क्लाउडवरून शेते सिंक होत आहेत',
    },
    'synced_farm': {'en': 'synced farm', 'hi': 'सिंक खेत', 'mr': 'सिंक शेत'},
    'synced_farms': {'en': 'synced farms', 'hi': 'सिंक खेत', 'mr': 'सिंक शेते'},
    'farm_data_refreshed': {
      'en': 'Farm data refreshed.',
      'hi': 'खेत डेटा रीफ्रेश हुआ।',
      'mr': 'शेत डेटा रीफ्रेश झाला.',
    },
    'add_or_mark_farm': {
      'en': 'Add or mark farm',
      'hi': 'खेत जोड़ें या चिन्हित करें',
      'mr': 'शेत जोडा किंवा मार्क करा',
    },
    'farm_boundary_crop_details': {
      'en': 'Boundary, crop, variety, sowing date',
      'hi': 'सीमा, फसल, किस्म, बुवाई तारीख',
      'mr': 'सीमा, पीक, वाण, पेरणी तारीख',
    },
    'offline_access': {
      'en': 'Offline access',
      'hi': 'ऑफलाइन एक्सेस',
      'mr': 'ऑफलाइन प्रवेश',
    },
    'offline_context_available': {
      'en': 'Keep key farm context available offline',
      'hi': 'मुख्य खेत जानकारी ऑफलाइन उपलब्ध रखें',
      'mr': 'मुख्य शेत माहिती ऑफलाइन उपलब्ध ठेवा',
    },
    'auto_sync_after_login': {
      'en': 'Auto sync after login',
      'hi': 'लॉगिन के बाद ऑटो सिंक',
      'mr': 'लॉगिननंतर ऑटो सिंक',
    },
    'refresh_farms_on_open': {
      'en': 'Refresh farms when you open the app',
      'hi': 'ऐप खोलते समय खेत रीफ्रेश करें',
      'mr': 'अ‍ॅप उघडताना शेते रीफ्रेश करा',
    },
    'notifications': {'en': 'Notifications', 'hi': 'सूचनाएँ', 'mr': 'सूचना'},
    'farm_health_alerts': {
      'en': 'Farm health alerts',
      'hi': 'खेत स्वास्थ्य अलर्ट',
      'mr': 'शेत आरोग्य सूचना',
    },
    'farm_health_alerts_desc': {
      'en': 'Disease, weather, and growth stage updates',
      'hi': 'रोग, मौसम और वृद्धि अवस्था अपडेट',
      'mr': 'रोग, हवामान आणि वाढीच्या अवस्थेचे अपडेट',
    },
    'market_price_updates': {
      'en': 'Market price updates',
      'hi': 'बाजार भाव अपडेट',
      'mr': 'बाजारभाव अपडेट',
    },
    'market_price_updates_desc': {
      'en': 'APMC price movements and listing reminders',
      'hi': 'मंडी भाव बदलाव और लिस्टिंग रिमाइंडर',
      'mr': 'बाजार समिती भाव बदल आणि लिस्टिंग स्मरणपत्रे',
    },
    'grading_qr_reminders': {
      'en': 'Grading and QR reminders',
      'hi': 'ग्रेडिंग और क्यूआर रिमाइंडर',
      'mr': 'ग्रेडिंग आणि क्यूआर स्मरणपत्रे',
    },
    'grading_qr_reminders_desc': {
      'en': 'Harvest grading, bag QR, and FPC review alerts',
      'hi': 'कटाई ग्रेडिंग, बोरी क्यूआर और किसान उत्पादक कंपनी समीक्षा अलर्ट',
      'mr':
          'कापणी ग्रेडिंग, पोते क्यूआर आणि शेतकरी उत्पादक कंपनी पुनरावलोकन सूचना',
    },
    'privacy_support': {
      'en': 'Privacy And Support',
      'hi': 'गोपनीयता और सहायता',
      'mr': 'गोपनीयता आणि मदत',
    },
    'privacy_data': {
      'en': 'Privacy and data',
      'hi': 'गोपनीयता और डेटा',
      'mr': 'गोपनीयता आणि डेटा',
    },
    'privacy_data_desc': {
      'en': 'Phone, farm, and grading data stay account-linked',
      'hi': 'फोन, खेत और ग्रेडिंग डेटा खाते से जुड़ा रहता है',
      'mr': 'फोन, शेत आणि ग्रेडिंग डेटा खात्याशी जोडलेला राहतो',
    },
    'privacy_data_message': {
      'en':
          'Your farm data syncs only with the farmer profile linked to this mobile number.',
      'hi':
          'आपका खेत डेटा केवल इस मोबाइल नंबर से जुड़ी किसान प्रोफ़ाइल से सिंक होता है।',
      'mr':
          'तुमचा शेत डेटा फक्त या मोबाइल नंबरशी जोडलेल्या शेतकरी प्रोफाइलशी सिंक होतो.',
    },
    'help_and_support': {
      'en': 'Help and support',
      'hi': 'मदद और सहायता',
      'mr': 'मदत आणि सहाय्य',
    },
    'support_account_farm': {
      'en': 'Coordinator help for account and farm issues',
      'hi': 'खाता और खेत समस्याओं के लिए समन्वयक सहायता',
      'mr': 'खाते आणि शेत समस्यांसाठी समन्वयक मदत',
    },
    'support_account_help': {
      'en': 'Contact your field coordinator for account help.',
      'hi': 'खाता सहायता के लिए अपने फील्ड समन्वयक से संपर्क करें।',
      'mr': 'खाते मदतीसाठी तुमच्या फील्ड समन्वयकाशी संपर्क करा.',
    },
    'about_grainright': {
      'en': 'About GrainRight',
      'hi': 'GrainRight के बारे में',
      'mr': 'GrainRight बद्दल',
    },
    'grainright_about_desc': {
      'en': 'Farmer intelligence and traceability app',
      'hi': 'किसान इंटेलिजेंस and ट्रेसबिलिटी ऐप',
      'mr': 'शेतकरी माहिती आणि ट्रेसिबिलिटी अ‍ॅप',
    },
    'return_to_role_selection': {
      'en': 'Return to role selection',
      'hi': 'भूमिका चयन पर वापस जाएं',
      'mr': 'भूमिका निवडीकडे परत जा',
    },
    'verified_farmer_short': {
      'en': 'Verified farmer',
      'hi': 'सत्यापित किसान',
      'mr': 'पडताळलेला शेतकरी',
    },
    'no_active_farm': {
      'en': 'No active farm',
      'hi': 'कोई सक्रिय खेत नहीं',
      'mr': 'सक्रिय शेत नाही',
    },
    'enabled': {'en': 'Enabled', 'hi': 'चालू', 'mr': 'चालू'},
    'disabled': {'en': 'Disabled', 'hi': 'बंद', 'mr': 'बंद'},
    'opt_north_field': {
      'en': 'North Field',
      'hi': 'उत्तर खेत',
      'mr': 'उत्तर शेत',
    },
    'opt_south_plot': {
      'en': 'South Plot',
      'hi': 'दक्षिण प्लॉट',
      'mr': 'दक्षिण प्लॉट',
    },
    'opt_east_block': {
      'en': 'East Block',
      'hi': 'पूर्व ब्लॉक',
      'mr': 'पूर्व ब्लॉक',
    },
    'opt_main_farm': {'en': 'Main Farm', 'hi': 'मुख्य खेत', 'mr': 'मुख्य शेत'},
    'opt_gira': {'en': 'Gira', 'hi': 'गीरा', 'mr': 'गिरा'},
    'opt_phule_nachni': {
      'en': 'Phule Nachni',
      'hi': 'फुले नाचनी',
      'mr': 'फुले नाचणी',
    },
    'opt_sips_1': {'en': 'SiPS-1', 'hi': 'SiPS-1', 'mr': 'SiPS-1'},
    'opt_bhu_8': {'en': 'BHU-8', 'hi': 'BHU-8', 'mr': 'BHU-8'},
    'opt_kalyan': {'en': 'Kalyan', 'hi': 'कल्याण', 'mr': 'कल्याण'},
    'opt_indrayani': {'en': 'Indrayani', 'hi': 'इंद्रायणी', 'mr': 'इंद्रायणी'},
    'opt_basmati': {'en': 'Basmati', 'hi': 'बासमती', 'mr': 'बासमती'},
    'opt_kolum': {'en': 'Kolum', 'hi': 'कोलम', 'mr': 'कोलम'},
    'opt_ictp_8203': {'en': 'ICTP-8203', 'hi': 'ICTP-8203', 'mr': 'ICTP-8203'},
    'opt_shanti': {'en': 'Shanti', 'hi': 'शांति', 'mr': 'शांती'},
    'opt_hhb_67': {'en': 'HHB-67', 'hi': 'HHB-67', 'mr': 'HHB-67'},
    'opt_saburi': {'en': 'Saburi', 'hi': 'सबुरी', 'mr': 'सबुरी'},
    'opt_dhanshakti': {'en': 'Dhanshakti', 'hi': 'धनशक्ति', 'mr': 'धनशक्ती'},
    'opt_mark_polygon': {
      'en': 'Mark polygon',
      'hi': 'पॉलीगॉन चिन्हित करें',
      'mr': 'पॉलीगॉन मार्क करा',
    },
    'opt_finger_millet': {'en': 'Finger Millet', 'hi': 'रागी', 'mr': 'नाचणी'},
    'opt_foxtail_millet': {
      'en': 'Foxtail Millet',
      'hi': 'कांगनी',
      'mr': 'कांग',
    },
    'opt_rice': {'en': 'Rice', 'hi': 'धान', 'mr': 'भात'},
    'opt_bajra': {'en': 'Bajra', 'hi': 'बाजरा', 'mr': 'बाजरी'},
    'opt_vegetables': {'en': 'Vegetables', 'hi': 'सब्जियां', 'mr': 'भाज्या'},
    'opt_fallow': {'en': 'Fallow', 'hi': 'परती', 'mr': 'पडीत'},
    'opt_kharif': {'en': 'Kharif', 'hi': 'खरीफ', 'mr': 'खरीप'},
    'opt_rabi': {'en': 'Rabi', 'hi': 'रबी', 'mr': 'रब्बी'},
    'opt_summer': {'en': 'Summer', 'hi': 'ग्रीष्म', 'mr': 'उन्हाळा'},
    'opt_rainfed': {
      'en': 'Rainfed',
      'hi': 'वर्षा आधारित',
      'mr': 'पावसावर अवलंबून',
    },
    'opt_well': {'en': 'Well', 'hi': 'कुआं', 'mr': 'विहीर'},
    'opt_borewell': {'en': 'Borewell', 'hi': 'बोरवेल', 'mr': 'बोअरवेल'},
    'opt_canal': {'en': 'Canal', 'hi': 'नहर', 'mr': 'कालवा'},
    'opt_drip': {'en': 'Drip', 'hi': 'ड्रिप', 'mr': 'ठिबक'},
    'opt_black_soil': {
      'en': 'Black soil',
      'hi': 'काली मिट्टी',
      'mr': 'काळी माती',
    },
    'opt_red_soil': {'en': 'Red soil', 'hi': 'लाल मिट्टी', 'mr': 'लाल माती'},
    'opt_sandy_loam': {
      'en': 'Sandy loam',
      'hi': 'रेतीली दोमट',
      'mr': 'वालुकामय दोमट',
    },
    'opt_clay_loam': {'en': 'Clay loam', 'hi': 'चिकनी दोमट', 'mr': 'चिकण दोमट'},
    'opt_owned': {'en': 'Owned', 'hi': 'स्वयं की', 'mr': 'स्वतःची'},
    'opt_leased': {'en': 'Leased', 'hi': 'पट्टे पर', 'mr': 'भाडेपट्टी'},
    'opt_shared': {'en': 'Shared', 'hi': 'साझा', 'mr': 'सामायिक'},
    'opt_forest_patta': {
      'en': 'Forest patta',
      'hi': 'वन पट्टा',
      'mr': 'वन पट्टा',
    },
    'opt_own_saved': {
      'en': 'Own saved',
      'hi': 'अपना बचाया हुआ',
      'mr': 'स्वतः जतन केलेले',
    },
    'opt_fpo': {
      'en': 'FPO',
      'hi': 'किसान उत्पादक संस्था',
      'mr': 'शेतकरी उत्पादक संस्था',
    },
    'opt_local_market': {
      'en': 'Local market',
      'hi': 'स्थानीय बाजार',
      'mr': 'स्थानिक बाजार',
    },
    'opt_government_source': {
      'en': 'Government source',
      'hi': 'सरकारी स्रोत',
      'mr': 'सरकारी स्रोत',
    },
    'opt_home_use': {'en': 'Home use', 'hi': 'घर उपयोग', 'mr': 'घरगुती वापर'},
    'opt_market_sale': {
      'en': 'Market sale',
      'hi': 'बाजार बिक्री',
      'mr': 'बाजार विक्री',
    },
    'opt_seed_saving': {
      'en': 'Seed saving',
      'hi': 'बीज बचत',
      'mr': 'बियाणे जतन',
    },
    'opt_processing': {
      'en': 'Processing',
      'hi': 'प्रोसेसिंग',
      'mr': 'प्रक्रिया',
    },
    'opt_today': {'en': 'Today', 'hi': 'आज', 'mr': 'आज'},
    'opt_yesterday': {'en': 'Yesterday', 'hi': 'कल', 'mr': 'काल'},
    'opt_three_days_ago': {
      'en': '3 days ago',
      'hi': '3 दिन पहले',
      'mr': '3 दिवसांपूर्वी',
    },
    'opt_one_week_ago': {
      'en': '1 week ago',
      'hi': '1 सप्ताह पहले',
      'mr': '1 आठवड्यापूर्वी',
    },

    // ── Profile ──
    'detailed_profile': {
      'en': 'Detailed Profile',
      'hi': 'विस्तृत प्रोफ़ाइल',
      'mr': 'सविस्तर प्रोफाइल',
    },
    'detailed_farmer_profile': {
      'en': 'Detailed Farmer Profile',
      'hi': 'विस्तृत किसान प्रोफ़ाइल',
      'mr': 'सविस्तर शेतकरी प्रोफाइल',
    },
    'verified_farmer': {
      'en': 'Verified Farmer',
      'hi': 'सत्यापित किसान',
      'mr': 'पडताळलेला शेतकरी',
    },
    'farmer_identity_qr': {
      'en': 'Farmer Identity QR',
      'hi': 'किसान पहचान क्यूआर',
      'mr': 'शेतकरी ओळख क्यूआर',
    },
    'personal_information': {
      'en': 'Personal Information',
      'hi': 'व्यक्तिगत जानकारी',
      'mr': 'वैयक्तिक माहिती',
    },
    'phone_number': {'en': 'Phone Number', 'hi': 'फ़ोन नंबर', 'mr': 'फोन नंबर'},
    'gender': {'en': 'Gender', 'hi': 'लिंग', 'mr': 'लिंग'},
    'male': {'en': 'Male', 'hi': 'पुरुष', 'mr': 'पुरुष'},
    'age': {'en': 'Age', 'hi': 'उम्र', 'mr': 'वय'},
    'years': {'en': 'years', 'hi': 'वर्ष', 'mr': 'वर्षे'},
    'farm_statistics': {
      'en': 'Farm Statistics',
      'hi': 'खेत आँकड़े',
      'mr': 'शेत आकडेवारी',
    },
    'primary_farm': {
      'en': 'Primary Farm',
      'hi': 'मुख्य खेत',
      'mr': 'मुख्य शेत',
    },
    'total_area': {
      'en': 'Total Area',
      'hi': 'कुल क्षेत्र',
      'mr': 'एकूण क्षेत्र',
    },
    'current_crop': {
      'en': 'Current Crop',
      'hi': 'वर्तमान फसल',
      'mr': 'सध्याचे पीक',
    },
    'soil_health': {
      'en': 'Soil Health',
      'hi': 'मृदा स्वास्थ्य',
      'mr': 'माती आरोग्य',
    },
    'excellent': {'en': 'Excellent', 'hi': 'उत्कृष्ट', 'mr': 'उत्कृष्ट'},
    'rewards_achievements': {
      'en': 'Rewards & Achievements',
      'hi': 'पुरस्कार और उपलब्धियाँ',
      'mr': 'बक्षिसे आणि यश',
    },
    'top_harvester': {
      'en': 'Top Harvester',
      'hi': 'शीर्ष कटाईकर्ता',
      'mr': 'अव्वल कापणीदार',
    },
    'organic_pro': {
      'en': 'Organic Pro',
      'hi': 'ऑर्गेनिक प्रो',
      'mr': 'सेंद्रिय प्रो',
    },
    'early_adopter': {
      'en': 'Early Adopter',
      'hi': 'अर्ली अडॉप्टर',
      'mr': 'लवकर स्वीकारणारा',
    },
    'settings_support': {
      'en': 'Settings & Support',
      'hi': 'सेटिंग्स और सहायता',
      'mr': 'सेटिंग्ज आणि मदत',
    },
    'trusted_profile': {
      'en': 'Trusted Profile',
      'hi': 'विश्वसनीय प्रोफ़ाइल',
      'mr': 'विश्वासार्ह प्रोफाइल',
    },
    'account_settings': {
      'en': 'Account Settings',
      'hi': 'खाता सेटिंग्स',
      'mr': 'खाते सेटिंग्ज',
    },
    'help_support': {
      'en': 'Help & Support',
      'hi': 'मदद और सहायता',
      'mr': 'मदत आणि सहाय्य',
    },
    'logout': {'en': 'Logout', 'hi': 'लॉग आउट', 'mr': 'बाहेर पडा'},
    'available_next_update': {
      'en': 'Available in next update.',
      'hi': 'अगले अपडेट में उपलब्ध।',
      'mr': 'पुढील अपडेटमध्ये उपलब्ध.',
    },
    'contact_coordinator': {
      'en': 'Contact your local coordinator for help.',
      'hi': 'मदद के लिए अपने स्थानीय समन्वयक से संपर्क करें।',
      'mr': 'मदतीसाठी तुमच्या स्थानिक समन्वयकाशी संपर्क करा.',
    },
    'verified_for_access': {
      'en': 'Verified for farm access:',
      'hi': 'खेत पहुँच हेतु सत्यापित:',
      'mr': 'शेत प्रवेशासाठी पडताळले:',
    },

    // ── Farmer app pages ──
    'all_crops': {'en': 'All crops', 'hi': 'सभी फसलें', 'mr': 'सर्व पिके'},
    'all_farms': {'en': 'All farms', 'hi': 'सभी खेत', 'mr': 'सर्व शेत'},
    'little_millet': {'en': 'Little Millet', 'hi': 'कुटकी', 'mr': 'सावा'},
    'kodo_millet': {'en': 'Kodo Millet', 'hi': 'कोदो', 'mr': 'कोदो'},
    'pearl_millet': {'en': 'Pearl Millet', 'hi': 'बाजरा', 'mr': 'बाजरी'},
    'millet_lots': {'en': 'millet lots', 'hi': 'मिलेट लॉट', 'mr': 'मिलेट लॉट'},
    'tomorrow': {'en': 'Tomorrow', 'hi': 'कल', 'mr': 'उद्या'},
    'wednesday_short': {'en': 'Wed', 'hi': 'बुध', 'mr': 'बुध'},
    'thursday_short': {'en': 'Thu', 'hi': 'गुरु', 'mr': 'गुरु'},
    'friday_short': {'en': 'Fri', 'hi': 'शुक्र', 'mr': 'शुक्र'},
    'weather_sunny': {'en': 'Sunny', 'hi': 'धूप', 'mr': 'ऊन'},
    'weather_partly_cloudy': {
      'en': 'Partly Cloudy',
      'hi': 'आंशिक बादल',
      'mr': 'अंशतः ढगाळ',
    },
    'weather_light_showers': {
      'en': 'Light showers',
      'hi': 'हल्की बारिश',
      'mr': 'हलका पाऊस',
    },
    'weather_cloudy': {'en': 'Cloudy', 'hi': 'बादल', 'mr': 'ढगाळ'},
    'weather_clear': {'en': 'Clear', 'hi': 'साफ़', 'mr': 'स्वच्छ'},
    'weather_fog': {'en': 'Fog', 'hi': 'कोहरा', 'mr': 'धुके'},
    'weather_drizzle': {'en': 'Drizzle', 'hi': 'फुहार', 'mr': 'रिमझिम'},
    'weather_showers': {
      'en': 'Showers',
      'hi': 'बारिश की बौछार',
      'mr': 'पावसाच्या सरी',
    },
    'weather_thunderstorm': {
      'en': 'Thunderstorm',
      'hi': 'आंधी-तूफान',
      'mr': 'वादळासह पाऊस',
    },
    'ai_chat_title': {
      'en': 'AI Farm Assistant',
      'hi': 'AI खेत सहायक',
      'mr': 'AI शेत सहाय्यक',
    },
    'ai_chat_active_farm': {
      'en': 'your active farm',
      'hi': 'आपका सक्रिय खेत',
      'mr': 'तुमचे सक्रिय शेत',
    },
    'ai_chat_welcome': {
      'en':
          'Hi! I am the Crop Intelligence Assistant for {subject}. Ask me about crop health, irrigation timing, market trend, or what data to capture before inspection.',
      'hi':
          'नमस्ते! मैं {subject} के लिए फसल इंटेलिजेंस सहायक हूँ। फसल स्वास्थ्य, सिंचाई समय, बाजार रुझान या निरीक्षण से पहले कौन सा डेटा लेना है, पूछें।',
      'mr':
          'नमस्कार! मी {subject} साठी पीक माहिती सहाय्यक आहे. पीक आरोग्य, सिंचन वेळ, बाजार कल किंवा तपासणीपूर्वी कोणता डेटा घ्यायचा ते विचारा.',
    },
    'ask_about_farm': {
      'en': 'Ask about your farm...',
      'hi': 'अपने खेत के बारे में पूछें...',
      'mr': 'तुमच्या शेताबद्दल विचारा...',
    },
    'ai_chat_thinking': {
      'en': 'Checking your farm data...',
      'hi': 'आपके खेत का डेटा देख रहा हूँ...',
      'mr': 'तुमच्या शेताचा डेटा तपासत आहे...',
    },
    'ai_chat_sync_required': {
      'en': 'Sync your selected farm first, then ask again.',
      'hi': 'पहले अपना चुना हुआ खेत सिंक करें, फिर दोबारा पूछें।',
      'mr': 'आधी निवडलेले शेत सिंक करा, मग पुन्हा विचारा.',
    },
    'ai_chat_login_required': {
      'en': 'Your farmer login needs to be refreshed before I can answer.',
      'hi': 'उत्तर देने से पहले आपका किसान लॉगिन फिर से ताज़ा करना होगा।',
      'mr': 'उत्तर देण्यापूर्वी तुमचे शेतकरी लॉगिन पुन्हा ताजे करावे लागेल.',
    },
    'ai_chat_retry': {
      'en':
          'I could not get a clean answer right now. Refresh farm data and try again.',
      'hi':
          'अभी साफ़ उत्तर नहीं मिल पाया। खेत डेटा रिफ्रेश करके फिर कोशिश करें।',
      'mr':
          'आत्ता स्पष्ट उत्तर मिळाले नाही. शेत डेटा रिफ्रेश करून पुन्हा प्रयत्न करा.',
    },
    'ai_chat_service_not_ready': {
      'en':
          'The AI farm assistant service is not ready yet. Sync farm data and try again.',
      'hi':
          'AI खेत सहायक सेवा अभी तैयार नहीं है। खेत डेटा सिंक करके फिर प्रयास करें।',
      'mr':
          'AI शेत सहाय्यक सेवा अजून तयार नाही. शेत डेटा सिंक करून पुन्हा प्रयत्न करा.',
    },
    'ai_chat_service_error': {
      'en': 'The AI assistant could not answer yet: {error}',
      'hi': 'AI सहायक अभी उत्तर नहीं दे पाया: {error}',
      'mr': 'AI सहाय्यक आत्ता उत्तर देऊ शकला नाही: {error}',
    },
    'ai_chat_next_steps': {
      'en': 'Next steps',
      'hi': 'अगले कदम',
      'mr': 'पुढील पावले',
    },
    'ai_chat_cautions': {'en': 'Cautions', 'hi': 'सावधानियाँ', 'mr': 'काळजी'},
    'ai_chat_prompt_disease': {
      'en': 'What disease risk is highest today?',
      'hi': 'आज सबसे बड़ा रोग जोखिम क्या है?',
      'mr': 'आज सर्वात मोठा रोग धोका कोणता आहे?',
    },
    'ai_chat_prompt_photo': {
      'en': 'Analyze disease photo',
      'hi': 'रोग की फोटो जांचें',
      'mr': 'रोगाचा फोटो तपासा',
    },
    'ai_chat_photo_user': {
      'en': 'Analyze this crop disease photo.',
      'hi': 'इस फसल रोग फोटो की जांच करें।',
      'mr': 'या पीक रोगाच्या फोटोची तपासणी करा.',
    },
    'ai_chat_photo_upload_description': {
      'en': 'Disease photo uploaded from AI Farm Assistant for {farm}',
      'hi': '{farm} के लिए AI खेत सहायक से रोग फोटो अपलोड की गई',
      'mr': '{farm} साठी AI शेत सहाय्यकातून रोगाचा फोटो अपलोड केला',
    },
    'ai_chat_photo_thinking': {
      'en': 'Analyzing the photo with your farm data...',
      'hi': 'आपके खेत डेटा के साथ फोटो की जांच हो रही है...',
      'mr': 'तुमच्या शेत डेटासह फोटो तपासत आहे...',
    },
    'ai_chat_photo_cancelled': {
      'en': 'No photo was selected.',
      'hi': 'कोई फोटो नहीं चुनी गई।',
      'mr': 'फोटो निवडला नाही.',
    },
    'ai_chat_photo_camera_subtitle': {
      'en': 'Take a fresh leaf, stem, or panicle photo.',
      'hi': 'पत्ती, तना या बालियों की नई फोटो लें।',
      'mr': 'पान, खोड किंवा कणसाचा नवीन फोटो घ्या.',
    },
    'ai_chat_photo_gallery_subtitle': {
      'en': 'Use an existing clear field photo.',
      'hi': 'पहले से ली गई साफ़ खेत फोटो चुनें।',
      'mr': 'आधी घेतलेला स्पष्ट शेत फोटो निवडा.',
    },
    'ai_chat_photo_result': {
      'en': 'Photo disease analysis',
      'hi': 'फोटो रोग विश्लेषण',
      'mr': 'फोटो रोग विश्लेषण',
    },
    'ai_chat_visual_findings': {
      'en': 'Visual finding',
      'hi': 'फोटो में संकेत',
      'mr': 'फोटोतील संकेत',
    },
    'ai_chat_confidence': {'en': 'Confidence', 'hi': 'भरोसा', 'mr': 'विश्वास'},
    'ai_chat_severity': {'en': 'Severity', 'hi': 'गंभीरता', 'mr': 'तीव्रता'},
    'ai_chat_evidence': {
      'en': 'Visible evidence',
      'hi': 'दिखने वाले संकेत',
      'mr': 'दिसणारे संकेत',
    },
    'ai_chat_possible_causes': {
      'en': 'Possible causes',
      'hi': 'संभावित कारण',
      'mr': 'संभाव्य कारणे',
    },
    'ai_chat_scout_action': {
      'en': 'Scout action',
      'hi': 'खेत में जांच का कदम',
      'mr': 'शेत तपासणीची कृती',
    },
    'ai_chat_farm_advice': {
      'en': 'Farm-specific advice',
      'hi': 'खेत के अनुसार सलाह',
      'mr': 'शेतानुसार सल्ला',
    },
    'ai_chat_photo_followup_question': {
      'en':
          'Use this visual disease result with the selected farm data and tell the safest next steps.',
      'hi':
          'इस फोटो रोग परिणाम को चुने हुए खेत डेटा के साथ देखकर सबसे सुरक्षित अगले कदम बताएं।',
      'mr':
          'हा फोटो रोग निकाल निवडलेल्या शेत डेटासह वापरून सर्वात सुरक्षित पुढील पावले सांगा.',
    },
    'ai_chat_prompt_water': {
      'en': 'Should I irrigate today?',
      'hi': 'क्या आज सिंचाई करनी चाहिए?',
      'mr': 'आज सिंचन करावे का?',
    },
    'ai_chat_prompt_next_action': {
      'en': 'What should I do next for this crop?',
      'hi': 'इस फसल के लिए अगला काम क्या करूँ?',
      'mr': 'या पिकासाठी पुढे काय करावे?',
    },
    'ai_chat_prompt_yield': {
      'en': 'How can I improve crop productivity?',
      'hi': 'फसल उत्पादकता कैसे बढ़ाऊँ?',
      'mr': 'पीक उत्पादकता कशी वाढवू?',
    },
    'ai_reply_disease': {
      'en':
          'Capture a clear leaf image and check for yellowing, spots, or lesions. I can help you decide if it needs inspection.',
      'hi':
          'पत्ती की साफ़ फोटो लें और पीलापन, धब्बे या घाव देखें। मैं बता सकता हूँ कि निरीक्षण ज़रूरी है या नहीं।',
      'mr':
          'पानाचा स्पष्ट फोटो घ्या आणि पिवळेपणा, डाग किंवा जखमा तपासा. तपासणी हवी का ते ठरवायला मी मदत करेन.',
    },
    'ai_reply_irrigation': {
      'en':
          'Track last irrigation time and moisture status; avoid overwatering before rain. A short dry spell of 2-3 days can support root oxygenation.',
      'hi':
          'पिछली सिंचाई का समय और नमी देखें; बारिश से पहले अधिक पानी न दें। 2-3 दिन का हल्का सूखा जड़ों में ऑक्सीजन बढ़ाता है।',
      'mr':
          'शेवटचे सिंचन आणि ओलावा नोंदवा; पावसापूर्वी जास्त पाणी देऊ नका. 2-3 दिवसांचा हलका कोरडा काळ मुळांना ऑक्सिजन देतो.',
    },
    'ai_reply_market': {
      'en':
          'Current millet prices vary by lot quality. Keep grain moisture below 12 percent and track moisture tests daily to negotiate better rates.',
      'hi':
          'मिलेट भाव लॉट की गुणवत्ता पर बदलते हैं। बेहतर भाव के लिए नमी 12 प्रतिशत से कम रखें और रोज़ नमी टेस्ट नोट करें।',
      'mr':
          'मिलेट दर लॉटच्या गुणवत्तेनुसार बदलतात. चांगल्या दरासाठी धान्य ओलावा 12 टक्क्यांखाली ठेवा आणि रोज ओलावा तपासा.',
    },
    'ai_reply_default': {
      'en':
          'I can help with farming guidance, crop risk checks, and next best action for this farm. Ask a specific question and I will help.',
      'hi':
          'मैं खेती मार्गदर्शन, फसल जोखिम जांच और इस खेत के अगले सही कदम में मदद कर सकता हूँ। स्पष्ट सवाल पूछें।',
      'mr':
          'मी शेती मार्गदर्शन, पीक धोका तपासणी आणि या शेतासाठी पुढील योग्य कृतीत मदत करू शकतो. विशिष्ट प्रश्न विचारा.',
    },
    'today_mandi_rates': {
      'en': 'Today mandi rates',
      'hi': 'आज के मंडी भाव',
      'mr': 'आजचे बाजार समिती दर',
    },
    'markets_count': {
      'en': '{count} markets',
      'hi': '{count} बाजार',
      'mr': '{count} बाजार',
    },
    'lots_count': {
      'en': '{count} lots',
      'hi': '{count} लॉट',
      'mr': '{count} लॉट',
    },
    'no_mandi_rate_found': {
      'en': 'No mandi rate found',
      'hi': 'मंडी भाव नहीं मिला',
      'mr': 'बाजार समिती दर सापडला नाही',
    },
    'try_all_crops_market_sync': {
      'en': 'Try All crops or check again after market sync.',
      'hi': 'सभी फसलें चुनें या बाजार सिंक के बाद फिर जांचें।',
      'mr': 'सर्व पिके निवडा किंवा बाजार सिंकनंतर पुन्हा तपासा.',
    },
    'your_lot_readiness': {
      'en': 'Your lot readiness',
      'hi': 'आपके लॉट की तैयारी',
      'mr': 'तुमच्या लॉटची तयारी',
    },
    'no_graded_lot_ready': {
      'en': 'No graded lot ready',
      'hi': 'कोई ग्रेडेड लॉट तैयार नहीं',
      'mr': 'ग्रेडेड लॉट तयार नाही',
    },
    'graded_lot_empty_message': {
      'en':
          'After harvest grading, your sale-ready lots will appear here with moisture, grade, and value estimate.',
      'hi':
          'कटाई ग्रेडिंग के बाद बिक्री-तैयार लॉट यहाँ नमी, ग्रेड और मूल्य अनुमान के साथ दिखेंगे।',
      'mr':
          'कापणी ग्रेडिंगनंतर विक्रीस तयार लॉट येथे ओलावा, ग्रेड आणि मूल्य अंदाजासह दिसतील.',
    },
    'nearby_market_choices': {
      'en': 'Nearby market choices',
      'hi': 'नज़दीकी बाजार विकल्प',
      'mr': 'जवळचे बाजार पर्याय',
    },
    'route_plan': {'en': 'Route plan', 'hi': 'रूट योजना', 'mr': 'मार्ग योजना'},
    'live_mandi_board': {
      'en': 'Live mandi board',
      'hi': 'लाइव मंडी बोर्ड',
      'mr': 'लाईव्ह बाजार समिती बोर्ड',
    },
    'remote_market_rates': {
      'en': 'Remote rates live',
      'hi': 'रिमोट भाव लाइव',
      'mr': 'रिमोट दर लाईव्ह',
    },
    'local_market_backup': {
      'en': 'Local backup rates',
      'hi': 'स्थानीय बैकअप भाव',
      'mr': 'स्थानिक बॅकअप दर',
    },
    'refresh_market_rates': {
      'en': 'Refresh market rates',
      'hi': 'मंडी भाव रीफ्रेश करें',
      'mr': 'बाजार दर रीफ्रेश करा',
    },
    'best_modal': {
      'en': 'Best modal',
      'hi': 'सर्वश्रेष्ठ मॉडल भाव',
      'mr': 'सर्वोत्तम मोडल दर',
    },
    'per_qtl': {'en': 'per qtl', 'hi': 'प्रति क्विंटल', 'mr': 'प्रति क्विंटल'},
    'ready_lots': {'en': 'Ready lots', 'hi': 'तैयार लॉट', 'mr': 'तयार लॉट'},
    'graded': {'en': 'graded', 'hi': 'ग्रेडेड', 'mr': 'ग्रेडेड'},
    'apmc_hero_body': {
      'en':
          'Compare nearby APMC rates, arrival pressure, demand, and lot readiness before creating a sale plan.',
      'hi':
          'बिक्री योजना बनाने से पहले नज़दीकी मंडी भाव, आवक दबाव, मांग और लॉट तैयारी की तुलना करें।',
      'mr':
          'विक्री योजना करण्यापूर्वी जवळचे बाजार समिती दर, आवक दबाव, मागणी आणि लॉट तयारी तुलना करा.',
    },
    'best_sale_window': {
      'en': 'Best sale window',
      'hi': 'सबसे अच्छा बिक्री समय',
      'mr': 'सर्वोत्तम विक्री वेळ',
    },
    'apmc_sale_window_body': {
      'en':
          'Move {crop} before 11:30 if moisture is below 12 percent. Current modal benchmark is {currency} {rate} per {unit}.',
      'hi':
          'यदि नमी 12 प्रतिशत से कम है तो {crop} को 11:30 से पहले भेजें। वर्तमान मोडल भाव {currency} {rate} प्रति {unit} है।',
      'mr':
          'ओलावा 12 टक्क्यांपेक्षा कमी असल्यास {crop} 11:30 पूर्वी पाठवा. सध्याचा मोडल दर {currency} {rate} प्रति {unit} आहे.',
    },
    'updated_at': {
      'en': 'updated {time}',
      'hi': '{time} पर अपडेट',
      'mr': '{time} ला अपडेट',
    },
    'min_rate': {'en': 'Min', 'hi': 'न्यूनतम', 'mr': 'किमान'},
    'modal_rate': {'en': 'Modal', 'hi': 'मॉडल', 'mr': 'मोडल'},
    'max_rate': {'en': 'Max', 'hi': 'अधिकतम', 'mr': 'कमाल'},
    'demand_high': {'en': 'High', 'hi': 'अधिक', 'mr': 'जास्त'},
    'demand_good': {'en': 'Good', 'hi': 'अच्छी', 'mr': 'चांगली'},
    'demand_stable': {'en': 'Stable', 'hi': 'स्थिर', 'mr': 'स्थिर'},
    'apmc_note_clean_lots': {
      'en': 'Clean graded lots are getting faster bids.',
      'hi': 'साफ़ ग्रेडेड लॉट को तेज़ बोली मिल रही है।',
      'mr': 'स्वच्छ ग्रेडेड लॉटना जलद बोली मिळत आहे.',
    },
    'apmc_note_dry_lots': {
      'en': 'Buyers prefer dry lots below 12 percent moisture.',
      'hi': 'खरीदार 12 प्रतिशत से कम नमी वाले सूखे लॉट पसंद करते हैं।',
      'mr': 'खरेदीदार 12 टक्क्यांपेक्षा कमी ओलावा असलेले कोरडे लॉट पसंत करतात.',
    },
    'apmc_note_sorted_grain': {
      'en': 'Premium for sorted grain and uniform bag weight.',
      'hi': 'छंटे हुए अनाज और समान बोरी वजन पर प्रीमियम मिलता है।',
      'mr': 'छाननी केलेले धान्य आणि समान पोते वजनासाठी प्रीमियम मिळतो.',
    },
    'apmc_note_high_arrival': {
      'en': 'Arrival is higher today; hold if moisture is high.',
      'hi': 'आज आवक अधिक है; नमी अधिक हो तो रोकें।',
      'mr': 'आज आवक जास्त आहे; ओलावा जास्त असल्यास थांबा.',
    },
    'apmc_note_bulk_buyers': {
      'en': 'Bulk buyers active for clean farm-gate pickup.',
      'hi': 'साफ़ फार्म-गेट पिकअप के लिए थोक खरीदार सक्रिय हैं।',
      'mr': 'स्वच्छ फार्म-गेट पिकअपसाठी मोठे खरेदीदार सक्रिय आहेत.',
    },
    'apmc_agent': {
      'en': 'APMC agent',
      'hi': 'मंडी एजेंट',
      'mr': 'बाजार समिती एजंट',
    },
    'request_sent_for_market': {
      'en': 'Request sent for {market}',
      'hi': '{market} के लिए अनुरोध भेजा गया',
      'mr': '{market} साठी विनंती पाठवली',
    },
    'contact': {'en': 'Contact', 'hi': 'संपर्क', 'mr': 'संपर्क'},
    'sale_plan': {
      'en': 'Sale plan',
      'hi': 'बिक्री योजना',
      'mr': 'विक्री योजना',
    },
    'sale_plan_prepared_for_crop': {
      'en': 'Sale plan prepared for {crop}',
      'hi': '{crop} के लिए बिक्री योजना तैयार',
      'mr': '{crop} साठी विक्री योजना तयार',
    },
    'plan_sale': {
      'en': 'Plan sale',
      'hi': 'बिक्री योजना',
      'mr': 'विक्री योजना',
    },
    'ready': {'en': 'Ready', 'hi': 'तैयार', 'mr': 'तयार'},
    'prepare': {'en': 'Prepare', 'hi': 'तैयार करें', 'mr': 'तयार करा'},
    'grade_value': {
      'en': 'Grade {grade}',
      'hi': 'ग्रेड {grade}',
      'mr': 'ग्रेड {grade}',
    },
    'estimated_value_modal': {
      'en': 'Estimated value at modal rate: {currency} {value}',
      'hi': 'मॉडल भाव पर अनुमानित मूल्य: {currency} {value}',
      'mr': 'मोडल दरानुसार अंदाजे मूल्य: {currency} {value}',
    },
    'before_going_apmc': {
      'en': 'Before going to APMC',
      'hi': 'मंडी जाने से पहले',
      'mr': 'बाजार समितीत जाण्यापूर्वी',
    },
    'apmc_check_bag_count': {
      'en': 'Confirm bag count and net weight.',
      'hi': 'बोरी संख्या और शुद्ध वजन की पुष्टि करें।',
      'mr': 'पोत्यांची संख्या आणि निव्वळ वजन तपासा.',
    },
    'apmc_check_moisture_grade': {
      'en': 'Keep moisture reading and grade score ready.',
      'hi': 'नमी रीडिंग और ग्रेड स्कोर तैयार रखें।',
      'mr': 'ओलावा रीडिंग आणि ग्रेड स्कोअर तयार ठेवा.',
    },
    'apmc_check_farmer_qr': {
      'en': 'Carry farmer ID and lot QR if available.',
      'hi': 'किसान पहचान क्रमांक और उपलब्ध हो तो लॉट क्यूआर साथ रखें।',
      'mr': 'शेतकरी ओळख क्रमांक आणि उपलब्ध असल्यास लॉट क्यूआर सोबत ठेवा.',
    },
    'apmc_check_morning_arrival': {
      'en': 'Prefer morning arrival for faster auction.',
      'hi': 'तेज़ नीलामी के लिए सुबह पहुँचें।',
      'mr': 'जलद लिलावासाठी सकाळी पोहोचा.',
    },
    'best_for_small_millet_lots': {
      'en': 'Best for small millet lots',
      'hi': 'छोटे मिलेट लॉट के लिए बेहतर',
      'mr': 'लहान मिलेट लॉटसाठी उत्तम',
    },
    'good_buyer_depth': {
      'en': 'Good buyer depth',
      'hi': 'खरीदार संख्या अच्छी',
      'mr': 'खरेदीदारांची चांगली संख्या',
    },
    'premium_sorted_grain_market': {
      'en': 'Premium sorted grain market',
      'hi': 'छंटे हुए अनाज का प्रीमियम बाजार',
      'mr': 'छाननी धान्यासाठी प्रीमियम बाजार',
    },
    'lots': {'en': 'Lots', 'hi': 'लॉट', 'mr': 'लॉट'},
    'total_bags': {'en': 'Total bags', 'hi': 'कुल बोरी', 'mr': 'एकूण पोती'},
    'qty': {'en': 'Qty', 'hi': 'मात्रा', 'mr': 'प्रमाण'},
    'search_inventory_hint': {
      'en': 'Search batch id, crop, variety, grade',
      'hi': 'बैच पहचान क्रमांक, फसल, किस्म, ग्रेड खोजें',
      'mr': 'बॅच ओळख क्रमांक, पीक, वाण, ग्रेड शोधा',
    },
    'sort_newest': {'en': 'Newest', 'hi': 'सबसे नया', 'mr': 'नवीनतम'},
    'sort_recommended': {
      'en': 'Recommended',
      'hi': 'अनुशंसित',
      'mr': 'शिफारस केलेले',
    },
    'sort_highest_grade': {
      'en': 'Highest grade',
      'hi': 'सबसे ऊँचा ग्रेड',
      'mr': 'सर्वोच्च ग्रेड',
    },
    'sort_lowest_moisture': {
      'en': 'Lowest moisture',
      'hi': 'सबसे कम नमी',
      'mr': 'सर्वात कमी ओलावा',
    },
    'sort_most_yield': {
      'en': 'Most yield',
      'hi': 'सबसे अधिक उपज',
      'mr': 'सर्वाधिक उत्पादन',
    },
    'sort_highest_qty': {
      'en': 'Highest qty',
      'hi': 'सबसे अधिक मात्रा',
      'mr': 'सर्वाधिक प्रमाण',
    },
    'clear_search': {
      'en': 'Clear search',
      'hi': 'खोज साफ़ करें',
      'mr': 'शोध साफ करा',
    },
    'bags': {'en': 'Bags', 'hi': 'बोरी', 'mr': 'पोती'},
    'moisture_label': {'en': 'Moisture', 'hi': 'नमी', 'mr': 'ओलावा'},
    'quality_score': {
      'en': 'Quality score',
      'hi': 'गुणवत्ता स्कोर',
      'mr': 'गुणवत्ता स्कोअर',
    },
    'estimated_qty': {
      'en': 'Est. qty',
      'hi': 'अनुमानित मात्रा',
      'mr': 'अंदाजे प्रमाण',
    },
    'list_for_sale': {
      'en': 'List for sale',
      'hi': 'बिक्री में डालें',
      'mr': 'विक्रीसाठी नोंदवा',
    },
    'view_lot': {'en': 'View lot', 'hi': 'लॉट देखें', 'mr': 'लॉट पहा'},
    'avg_moisture': {
      'en': 'Avg moisture',
      'hi': 'औसत नमी',
      'mr': 'सरासरी ओलावा',
    },
    'avg_grade_score': {
      'en': 'Avg grade score',
      'hi': 'औसत ग्रेड स्कोर',
      'mr': 'सरासरी ग्रेड स्कोअर',
    },
    'no_lot_found_inventory': {
      'en':
          'No lot found. Harvest is graded, then grading summary appears here automatically.',
      'hi':
          'कोई लॉट नहीं मिला। कटाई ग्रेड होने के बाद ग्रेडिंग सारांश यहाँ अपने आप दिखेगा।',
      'mr':
          'लॉट सापडला नाही. कापणी ग्रेड झाल्यावर ग्रेडिंग सारांश येथे आपोआप दिसेल.',
    },
    'harvested_at': {
      'en': 'Harvested {time}',
      'hi': '{time} को कटाई',
      'mr': '{time} ला कापणी',
    },
    'coordinates_value': {
      'en': 'Coordinates: {lat}, {lng}',
      'hi': 'निर्देशांक: {lat}, {lng}',
      'mr': 'निर्देशांक: {lat}, {lng}',
    },
    'farm_inventory_snapshot': {
      'en': 'Farm inventory snapshot',
      'hi': 'खेत इन्वेंटरी सारांश',
      'mr': 'शेत साठा सारांश',
    },
    'good_morning': {'en': 'Good Morning', 'hi': 'सुप्रभात', 'mr': 'शुभ सकाळ'},
    'good_afternoon': {
      'en': 'Good Afternoon',
      'hi': 'नमस्कार',
      'mr': 'शुभ दुपार',
    },
    'good_evening': {
      'en': 'Good Evening',
      'hi': 'शुभ संध्या',
      'mr': 'शुभ संध्याकाळ',
    },
    'good_night': {'en': 'Good Night', 'hi': 'शुभ रात्रि', 'mr': 'शुभ रात्री'},
    'farm_value': {
      'en': 'Farm: {value}',
      'hi': 'खेत: {value}',
      'mr': 'शेत: {value}',
    },
    'harvest_readiness': {
      'en': 'Harvest Readiness',
      'hi': 'कटाई तैयारी',
      'mr': 'कापणी तैयारी',
    },
    'crop_batch_grade_ready': {
      'en': '{crop} batch can be graded before QR sticker.',
      'hi': '{crop} बैच QR स्टिकर से पहले ग्रेड किया जा सकता है।',
      'mr': '{crop} बॅच QR स्टिकरपूर्वी ग्रेड करता येईल.',
    },
    'estimated_bags': {
      'en': 'Est. bags',
      'hi': 'अनुमानित बोरी',
      'mr': 'अंदाजे पोती',
    },
    'quality': {'en': 'Quality', 'hi': 'गुणवत्ता', 'mr': 'गुणवत्ता'},
    'yield_prediction': {
      'en': 'Yield Prediction',
      'hi': 'उपज अनुमान',
      'mr': 'उत्पन्न अंदाज',
    },
    'stage_summary': {
      'en': 'Stage summary',
      'hi': 'अवस्था सारांश',
      'mr': 'अवस्था सारांश',
    },
    'variety': {'en': 'Variety', 'hi': 'किस्म', 'mr': 'वाण'},
    'health': {'en': 'Health', 'hi': 'स्वास्थ्य', 'mr': 'आरोग्य'},
    'ready_window': {
      'en': 'Ready Window',
      'hi': 'तैयारी समय',
      'mr': 'तयारी वेळ',
    },
    'expected_yield': {
      'en': 'Expected yield',
      'hi': 'अपेक्षित उपज',
      'mr': 'अपेक्षित उत्पादन',
    },
    'water_heat_stress': {
      'en': 'Water/heat stress',
      'hi': 'पानी/गर्मी तनाव',
      'mr': 'पाणी/उष्णता ताण',
    },
    'scout_zone': {
      'en': 'Scout zone',
      'hi': 'निरीक्षण क्षेत्र',
      'mr': 'निरीक्षण क्षेत्र',
    },
    'confidence_value': {
      'en': 'Confidence: {value}',
      'hi': 'विश्वास: {value}',
      'mr': 'खात्री: {value}',
    },
    'images_value': {
      'en': 'Images: {value}',
      'hi': 'चित्र: {value}',
      'mr': 'चित्रे: {value}',
    },
    'all_news': {'en': 'All News', 'hi': 'सभी समाचार', 'mr': 'सर्व बातम्या'},
    'msp_markets': {
      'en': 'MSP & Markets',
      'hi': 'न्यूनतम समर्थन मूल्य और बाजार',
      'mr': 'किमान आधारभूत किंमत आणि बाजार',
    },
    'weather_alerts': {
      'en': 'Weather Alerts',
      'hi': 'मौसम अलर्ट',
      'mr': 'हवामान अलर्ट',
    },
    'farming_tips': {
      'en': 'Farming Tips',
      'hi': 'खेती सुझाव',
      'mr': 'शेती टिप्स',
    },
    'identity_verified': {
      'en': 'Identity Verified',
      'hi': 'पहचान सत्यापित',
      'mr': 'ओळख पडताळली',
    },
    'market_desk': {
      'en': 'Market Desk',
      'hi': 'मार्केट डेस्क',
      'mr': 'मार्केट डेस्क',
    },
    'market_desk_farm': {
      'en': 'Market desk • {farm}',
      'hi': 'मार्केट डेस्क • {farm}',
      'mr': 'मार्केट डेस्क • {farm}',
    },
    'market_desk_desc': {
      'en':
          'Create a lot-focused listing, compare grade impact, and review demand trend quickly.',
      'hi':
          'लॉट-केंद्रित लिस्टिंग बनाएं, ग्रेड प्रभाव की तुलना करें और मांग रुझान जल्दी देखें।',
      'mr':
          'लॉट-केंद्रित लिस्टिंग तयार करा, ग्रेड परिणाम तुलना करा आणि मागणी कल पटकन पहा.',
    },
    'active_lots': {
      'en': 'Active lots',
      'hi': 'सक्रिय लॉट',
      'mr': 'सक्रिय लॉट',
    },
    'qty_kg': {'en': 'Qty (kg)', 'hi': 'मात्रा (kg)', 'mr': 'प्रमाण (kg)'},
    'avg_score': {'en': 'Avg score', 'hi': 'औसत स्कोर', 'mr': 'सरासरी स्कोअर'},
    'sort_by': {'en': 'Sort by', 'hi': 'क्रमबद्ध करें', 'mr': 'क्रमवारी'},
    'no_active_market_lots': {
      'en': 'No active market lots',
      'hi': 'कोई सक्रिय बाजार लॉट नहीं',
      'mr': 'सक्रिय बाजार लॉट नाहीत',
    },
    'market_empty_all_farms': {
      'en': 'Harvest lots from all farms will appear here after grading.',
      'hi': 'सभी खेतों के कटाई लॉट ग्रेडिंग के बाद यहाँ दिखेंगे।',
      'mr': 'सर्व शेतांचे कापणी लॉट ग्रेडिंगनंतर येथे दिसतील.',
    },
    'market_empty_farm': {
      'en':
          'No graded lot is ready for {farm} yet. Complete harvest grading first, then create a market listing.',
      'hi':
          '{farm} के लिए अभी कोई ग्रेडेड लॉट तैयार नहीं। पहले कटाई ग्रेडिंग पूरी करें, फिर बाजार लिस्टिंग बनाएं।',
      'mr':
          '{farm} साठी अजून ग्रेडेड लॉट तयार नाही. आधी कापणी ग्रेडिंग पूर्ण करा, मग बाजार लिस्टिंग तयार करा.',
    },
    'awaiting_harvest': {
      'en': 'Awaiting harvest',
      'hi': 'कटाई प्रतीक्षा',
      'mr': 'कापणी प्रतीक्षा',
    },
    'grade_required': {
      'en': 'Grade required',
      'hi': 'ग्रेड ज़रूरी',
      'mr': 'ग्रेड आवश्यक',
    },
    'remote_ready': {
      'en': 'Remote-ready',
      'hi': 'रिमोट तैयार',
      'mr': 'रिमोट तैयार',
    },
    'score_value': {
      'en': 'Score {score}',
      'hi': 'स्कोर {score}',
      'mr': 'स्कोअर {score}',
    },
    'expected_lot_value': {
      'en': 'Expected lot value: Rs {value}',
      'hi': 'अनुमानित लॉट मूल्य: Rs {value}',
      'mr': 'अंदाजे लॉट मूल्य: Rs {value}',
    },
    'market': {'en': 'Market', 'hi': 'बाजार', 'mr': 'बाजार'},
    'prepare_listing_for': {
      'en': 'Prepare listing for {batch}',
      'hi': '{batch} के लिए लिस्टिंग तैयार करें',
      'mr': '{batch} साठी लिस्टिंग तयार करा',
    },
    'opening_demand_trend_for': {
      'en': 'Opening demand trend for {batch}',
      'hi': '{batch} का मांग रुझान खुल रहा है',
      'mr': '{batch} चा मागणी कल उघडत आहे',
    },
    'market_sync_context': {
      'en':
          'Showing synced inventory context for {scope}. Listings update after harvest grading is saved.',
      'hi':
          '{scope} के लिए सिंक इन्वेंटरी संदर्भ दिख रहा है। कटाई ग्रेडिंग सेव होने के बाद लिस्टिंग अपडेट होती है।',
      'mr':
          '{scope} साठी सिंक साठा संदर्भ दाखवत आहे. कापणी ग्रेडिंग जतन झाल्यावर लिस्टिंग अपडेट होते.',
    },
    'farm_snapshot': {
      'en': 'Farm Snapshot',
      'hi': 'खेत सारांश',
      'mr': 'शेत सारांश',
    },
    'recent_activity': {
      'en': 'Recent Activity',
      'hi': 'हाल की गतिविधि',
      'mr': 'अलीकडील कृती',
    },
    'farm_activity_detail': {
      'en': '{farm} • {detail}',
      'hi': '{farm} • {detail}',
      'mr': '{farm} • {detail}',
    },
    'open': {'en': 'Open', 'hi': 'खोलें', 'mr': 'उघडा'},
    'view': {'en': 'View', 'hi': 'देखें', 'mr': 'पहा'},
    'harvest': {'en': 'Harvest', 'hi': 'कटाई', 'mr': 'कापणी'},
    'harvest_hub': {'en': 'Harvest Hub', 'hi': 'कटाई हब', 'mr': 'कापणी हब'},
    'harvest_checklist': {
      'en': 'Harvest Checklist',
      'hi': 'कटाई चेकलिस्ट',
      'mr': 'कापणी चेकलिस्ट',
    },
    'add_moisture_meter_photo': {
      'en': 'Moisture meter image',
      'hi': 'नमी मीटर इमेज',
      'mr': 'ओलावा मीटर इमेज',
    },
    'open_camera': {
      'en': 'Open camera',
      'hi': 'कैमरा खोलें',
      'mr': 'कॅमेरा उघडा',
    },
    'click_new_machine_photo': {
      'en': 'Capture moisture meter image',
      'hi': 'नमी मीटर इमेज लें',
      'mr': 'ओलावा मीटर इमेज घ्या',
    },
    'select_from_gallery': {
      'en': 'Select from gallery',
      'hi': 'गैलरी से चुनें',
      'mr': 'गॅलरीतून निवडा',
    },
    'use_existing_machine_image': {
      'en': 'Use existing meter image',
      'hi': 'मौजूदा मीटर इमेज उपयोग करें',
      'mr': 'आधीची मीटर इमेज वापरा',
    },
    'live_location_required': {
      'en': 'Live location required',
      'hi': 'लाइव स्थान आवश्यक है',
      'mr': 'लाईव्ह स्थान आवश्यक आहे',
    },
    'capture_moisture_after_location': {
      'en': 'Fetch live location first. Then capture moisture meter photo.',
      'hi': 'पहले लाइव स्थान लें। फिर नमी मीटर की फोटो लें।',
      'mr': 'प्रथम लाईव्ह ठिकाण घ्या. त्यानंतर ओलावा मीटर फोटो घ्या.',
    },
    'moisture_photo_added': {
      'en': 'Moisture meter photo added',
      'hi': 'नमी मीटर फोटो जोड़ा गया',
      'mr': 'ओलावा मीटरचा फोटो जोडला गेला',
    },
    'meter_photo_linked_to_location': {
      'en': 'Meter photo linked to location {location}.',
      'hi': 'मीटर फोटो को स्थान से जोड़ा गया: {location}.',
      'mr': 'मीटर फोटो स्थानाशी जोडला गेला: {location}.',
    },
    'image_capture_error': {
      'en': 'Image failed',
      'hi': 'छवि असफल',
      'mr': 'प्रतिमा अयशस्वी',
    },
    'image_capture_retry': {
      'en':
          'Could not open camera or gallery. Check permissions and try again.',
      'hi': 'कैमरा या गैलरी नहीं खुली। अनुमति जांचकर दोबारा प्रयास करें।',
      'mr':
          'कॅमेरा किंवा गॅलरी उघडली नाही. परवानगी तपासा आणि पुन्हा प्रयत्न करा.',
    },
    'moisture_photo_required': {
      'en': 'Moisture meter photo required',
      'hi': 'नमी मीटर फोटो आवश्यक है',
      'mr': 'ओलावा मीटर फोटो आवश्यक',
    },
    'capture_meter_photo_first': {
      'en': 'Capture the moisture meter photo first.',
      'hi': 'पहले नमी मीटर का फोटो लें।',
      'mr': 'प्रथम ओलावा मीटरचा फोटो घ्या.',
    },
    'moisture_read_failed_title': {
      'en': 'Moisture read failed',
      'hi': 'नमी रीडिंग विफल',
      'mr': 'ओलावा वाचन अयशस्वी',
    },
    'moisture_read_retry': {
      'en': 'Could not read the meter image. Try again.',
      'hi': 'मीटर इमेज नहीं पढ़ी जा सकी। फिर से प्रयास करें।',
      'mr': 'मीटर प्रतिमा वाचता आली नाही. पुन्हा प्रयत्न करा.',
    },
    'location_unavailable_title': {
      'en': 'Location unavailable',
      'hi': 'स्थान उपलब्ध नहीं',
      'mr': 'स्थान उपलब्ध नाही',
    },
    'location_unavailable_body': {
      'en': 'Unable to fetch farm location right now. Please try again.',
      'hi': 'फार्म स्थान अभी नहीं मिल सका। बाद में दोबारा कोशिश करें।',
      'mr': 'सध्या शेत स्थान मिळू शकत नाही. पुन्हा प्रयत्न करा.',
    },
    'location_error_title': {
      'en': 'Location error',
      'hi': 'स्थान त्रुटि',
      'mr': 'स्थान त्रुटी',
    },
    'location_error_body': {
      'en': 'Could not read live location. Enable permission and try again.',
      'hi': 'लाइव स्थान पढ़ नहीं पाए। अनुमति सक्षम करें और फिर प्रयास करें।',
      'mr':
          'लाईव्ह स्थान वाचता आले नाही. परवानगी सक्षम करा आणि पुन्हा प्रयत्न करा.',
    },
    'run_grading_message': {
      'en': 'Run grading to generate verified lot score.',
      'hi': 'सत्यापित लॉट स्कोर जनरेट करने के लिए ग्रेडिंग चलाएं।',
      'mr': 'सत्यापित लॉट स्कोअर निर्माण करण्यासाठी ग्रेडिंग चालवा.',
    },
    'moisture_grade_message': {
      'en':
          'Microservice result: BIS/ISO grain quality standard mapping completed.',
      'hi':
          'माइक्रोसर्विस परिणाम: BIS/ISO अनाज गुणवत्ता मानक मानचित्रण पूरा हुआ।',
      'mr': 'मायक्रोसर्विस परिणाम: BIS/ISO धान्य गुणवत्ता मानक मॅपिंग पूर्ण.',
    },
    'harvest_grading_complete': {
      'en': 'Grading complete',
      'hi': 'ग्रेडिंग पूरी हुई',
      'mr': 'ग्रेडिंग पूर्ण',
    },
    'harvest_grading_complete_body': {
      'en':
          'Grade {grade} with score {score} is ready. Add it to inventory or generate QR.',
      'hi':
          'ग्रेड {grade} स्कोर {score} तैयार है। इसे इन्वेंटरी में जोड़ें या क्यूआर बनाएं।',
      'mr':
          'ग्रेड {grade} स्कोअर {score} तयार आहे. ते साठ्यात जोडा किंवा क्यूआर तयार करा.',
    },
    'add_product_inventory': {
      'en': 'Add product to inventory',
      'hi': 'उत्पाद इन्वेंटरी में जोड़ें',
      'mr': 'उत्पादन साठ्यात जोडा',
    },
    'view_inventory': {
      'en': 'View inventory',
      'hi': 'इन्वेंटरी देखें',
      'mr': 'साठा पहा',
    },
    'product_added_inventory': {
      'en': '{batch} added to inventory.',
      'hi': '{batch} इन्वेंटरी में जोड़ा गया।',
      'mr': '{batch} साठ्यात जोडले.',
    },
    'harvest_grade_required': {
      'en': 'Grade required',
      'hi': 'ग्रेड आवश्यक है',
      'mr': 'ग्रेड आवश्यक आहे',
    },
    'harvest_grade_required_body': {
      'en':
          'Run grading first. Grade is required before Harvest QR is generated.',
      'hi': 'पहले ग्रेडिंग चलाएं। कापणी क्यूआर बनने से पहले ग्रेड जरूरी है।',
      'mr':
          'प्रथम ग्रेडिंग चालवा. कापणी क्यूआर निर्माण करण्यापूर्वी ग्रेड आवश्यक आहे.',
    },
    'harvest_qr_inputs_required_title': {
      'en': 'Update required',
      'hi': 'अपडेट आवश्यक',
      'mr': 'अद्यतन आवश्यक',
    },
    'harvest_qr_inputs_required_body': {
      'en':
          'Location, moisture meter image, grain image, and bag details are required before generating QR.',
      'hi':
          'क्यूआर बनाने से पहले स्थान, नमी मीटर इमेज, अनाज इमेज और बोरी विवरण जरूरी हैं।',
      'mr':
          'क्यूआर निर्माण करण्यापूर्वी ठिकाण, ओलावा मीटर इमेज, धान्य इमेज आणि पोती तपशील आवश्यक आहेत.',
    },
    'harvest_progress_step_1': {
      'en': '1 · Location',
      'hi': '1 · स्थान',
      'mr': '1 · स्थान',
    },
    'harvest_progress_step_2': {
      'en': '2 · Moisture image',
      'hi': '2 · नमी इमेज',
      'mr': '2 · ओलावा इमेज',
    },
    'harvest_progress_step_3': {
      'en': '3 · Grain image',
      'hi': '3 · अनाज इमेज',
      'mr': '3 · धान्य इमेज',
    },
    'harvest_progress_step_4': {
      'en': '4 · Grade grain',
      'hi': '4 · अनाज ग्रेड करें',
      'mr': '4 · धान्य ग्रेड करा',
    },
    'moisture_capture_section': {
      'en': 'Moisture meter image',
      'hi': 'नमी मीटर इमेज',
      'mr': 'ओलावा मीटर इमेज',
    },
    'moisture_capture_subtitle': {
      'en': 'Capture the meter display and read the moisture value.',
      'hi': 'मीटर डिस्प्ले कैप्चर करें और नमी वैल्यू पढ़ें।',
      'mr': 'मीटर डिस्प्ले कॅप्चर करा आणि ओलावा मूल्य वाचा.',
    },
    'harvest_location_missing': {
      'en': 'Location not captured',
      'hi': 'स्थान नहीं कैप्चर हुआ',
      'mr': 'स्थान कॅप्चर झाले नाही',
    },
    'harvest_location_captured': {
      'en': 'Location captured',
      'hi': 'स्थान कैप्चर हुआ',
      'mr': 'स्थान कॅप्चर झाले',
    },
    'harvest_photo_ready': {
      'en': 'Moisture photo ready',
      'hi': 'नमी फोटो तैयार',
      'mr': 'ओलावा फोटो तैयार',
    },
    'harvest_photo_missing': {
      'en': 'Moisture photo missing',
      'hi': 'नमी फोटो उपलब्ध नहीं',
      'mr': 'ओलावा फोटो नाही',
    },
    'capture_moisture_photo': {
      'en': 'Moisture meter image',
      'hi': 'नमी मीटर इमेज',
      'mr': 'ओलावा मीटर इमेज',
    },
    'retake_moisture_photo': {
      'en': 'Retake moisture meter image',
      'hi': 'नमी मीटर इमेज फिर लें',
      'mr': 'ओलावा मीटर इमेज पुन्हा घ्या',
    },
    'moisture_capture_guidance': {
      'en':
          'Capture the moisture photo only from a clear meter display. Avoid blur and keep the number in focus.',
      'hi':
          'नमी फोटो केवल साफ मीटर डिस्प्ले से लें। ब्लर से बचें और नंबर को स्पष्ट रखें।',
      'mr':
          'ओलावा फोटो फक्त स्पष्ट मीटर डिस्प्लेवरून घ्या. धूसरपणा टाळा आणि संख्या स्पष्ट ठेवा.',
    },
    'harvest_moisture_photo_name': {
      'en': 'Moisture meter photo: {name}',
      'hi': 'नमी मीटर फोटो: {name}',
      'mr': 'ओलावा मीटर फोटो: {name}',
    },
    'grain_image_section': {
      'en': 'Grain image',
      'hi': 'अनाज इमेज',
      'mr': 'धान्य इमेज',
    },
    'capture_grain_image': {
      'en': 'Grain image',
      'hi': 'अनाज इमेज',
      'mr': 'धान्य इमेज',
    },
    'retake_grain_image': {
      'en': 'Retake grain image',
      'hi': 'अनाज इमेज फिर लें',
      'mr': 'धान्य इमेज पुन्हा घ्या',
    },
    'grain_image_ready': {
      'en': 'Grain image ready',
      'hi': 'अनाज इमेज तैयार',
      'mr': 'धान्य इमेज तयार',
    },
    'grain_image_added': {
      'en': 'Grain image added',
      'hi': 'अनाज इमेज जोड़ी गई',
      'mr': 'धान्य इमेज जोडली',
    },
    'grain_image_required': {
      'en': 'Grain image required',
      'hi': 'अनाज इमेज जरूरी है',
      'mr': 'धान्य इमेज आवश्यक आहे',
    },
    'capture_grain_image_first': {
      'en': 'Capture the grain image first.',
      'hi': 'पहले अनाज इमेज लें।',
      'mr': 'प्रथम धान्य इमेज घ्या.',
    },
    'read_meter_moisture': {
      'en': 'Read meter moisture',
      'hi': 'मीटर नमी पढ़ें',
      'mr': 'मीटर ओलावा वाचा',
    },
    'manual_moisture_fallback': {
      'en': 'Or type moisture %',
      'hi': 'या नमी % मैन्युअली डालें',
      'mr': 'किंवा ओलावा % लिहा',
    },
    'moisture_input_label': {
      'en': 'Moisture % (from meter / manual)',
      'hi': 'नमी % (मीटर/मैन्युअल)',
      'mr': 'ओलावा % (मीटर/मॅन्युअल)',
    },
    'bag_details': {
      'en': 'Bag details',
      'hi': 'बोरी की जानकारी',
      'mr': 'पोती तपशील',
    },
    'bag_details_subtitle': {
      'en': 'Enter total bags and bag size for the harvest lot.',
      'hi': 'हार्वेस्ट लॉट के लिए कुल बोरी और बोरी आकार दर्ज करें।',
      'mr': 'कापणी लॉटसाठी एकूण पोती आणि पोतीचा आकार भरा.',
    },
    'bag_size_label': {
      'en': 'Bag size (kg)',
      'hi': 'बोरी का आकार (kg)',
      'mr': 'पोतीचा आकार (kg)',
    },
    'bag_count_label': {
      'en': 'Number of bags',
      'hi': 'बोरीयों की संख्या',
      'mr': 'पोतींची संख्या',
    },
    'live_location_value': {
      'en': 'Live location: {value}',
      'hi': 'लाइव स्थान: {value}',
      'mr': 'लाईव्ह ठिकाण: {value}',
    },
    'running_grading': {
      'en': 'Running grading...',
      'hi': 'ग्रेडिंग चल रही है...',
      'mr': 'ग्रेडिंग चालू आहे...',
    },
    'run_grading_action': {
      'en': 'Run grading',
      'hi': 'ग्रेडिंग चलाएं',
      'mr': 'ग्रेडिंग चालवा',
    },
    'grade_grain_action': {
      'en': 'Grade grain',
      'hi': 'अनाज ग्रेड करें',
      'mr': 'धान्य ग्रेड करा',
    },
    'grade_result': {
      'en': 'Grade result',
      'hi': 'ग्रेड परिणाम',
      'mr': 'ग्रेड परिणाम',
    },
    'grade_summary_line': {
      'en': '{grade} • {score}/100 • {message}',
      'hi': '{grade} • {score}/100 • {message}',
      'mr': '{grade} • {score}/100 • {message}',
    },
    'harvest_verified_with_standard': {
      'en': 'Verified with {crop} BIS standard.',
      'hi': '{crop} BIS standard के साथ सत्यापित',
      'mr': '{crop} BIS मानकासह सत्यापित.',
    },
    'generate_harvest_qr': {
      'en': 'Generate harvest QR',
      'hi': 'कापणी क्यूआर बनाएं',
      'mr': 'कापणी क्यूआर तयार करा',
    },
    'grade_first_unlock_qr': {
      'en': 'Grade first to unlock QR',
      'hi': 'क्यूआर के लिए पहले ग्रेड करें',
      'mr': 'क्यूआर अनलॉक करण्यासाठी प्रथम ग्रेड करा',
    },
    'storage_prep': {
      'en': 'Storage Prep',
      'hi': 'भंडारण तैयारी',
      'mr': 'साठवण तैयारी',
    },
    'storage_prep_tip': {
      'en':
          'Dry grains to safe moisture before bagging. Validate lot records and use QR-enabled sacks for better planning.',
      'hi':
          'बैग करने से पहले दानों की नमी सुरक्षित स्तर तक सुखाएं। लॉट रिकॉर्ड की जांच करें और बेहतर योजना के लिए क्यूआर-सक्षम बोरियों का उपयोग करें।',
      'mr':
          'पोती भरण्याच्या आधी धान्य सुरक्षित ओलाव्यावर वाळवून घ्या. लॉट नोंदी तपासा आणि चांगल्या नियोजनासाठी क्यूआर सक्षम पिशव्या वापरा.',
    },
    'moisture_reading_title': {
      'en': 'Moisture meter reading',
      'hi': 'नमी मीटर रीडिंग',
      'mr': 'ओलावा मीटर रीडिंग',
    },
    'moisture_reading_meta': {
      'en': '{source} • {confidence}% confidence',
      'hi': '{source} • {confidence}% भरोसा',
      'mr': '{source} • {confidence}% खात्री',
    },
    'moisture_risk_good': {
      'en': 'Good moisture zone',
      'hi': 'अच्छा नमी क्षेत्र',
      'mr': 'छान ओलावा झोन',
    },
    'moisture_risk_watch': {
      'en': 'Watch moisture level',
      'hi': 'नमी का स्तर देखें',
      'mr': 'ओलावा पातळीवर नजर ठेवा',
    },
    'moisture_risk_high': {
      'en': 'High moisture risk',
      'hi': 'उच्च नमी जोखिम',
      'mr': 'उच्च ओलावा धोका',
    },
    'ask_ai_harvest_action': {
      'en': 'Ask AI for harvest action',
      'hi': 'कटाई सलाह के लिए AI से पूछें',
      'mr': 'कापणी कृतीसाठी AI ला विचारा',
    },
    'live_location': {
      'en': 'Live location',
      'hi': 'लाइव स्थान',
      'mr': 'लाईव्ह ठिकाण',
    },
    'mark_disease_zone': {
      'en': 'Mark disease zone',
      'hi': 'रोग क्षेत्र चिन्हित करें',
      'mr': 'रोग क्षेत्र मार्क करा',
    },
    'save_diagnosis': {
      'en': 'Save diagnosis',
      'hi': 'जांच सेव करें',
      'mr': 'तपासणी जतन करा',
    },
    'disease_risk_checked': {
      'en': 'Disease Risk Checked',
      'hi': 'रोग जोखिम जांचा गया',
      'mr': 'रोग धोका तपासला',
    },
    'ai_guidance': {
      'en': 'AI Guidance',
      'hi': 'AI मार्गदर्शन',
      'mr': 'AI मार्गदर्शन',
    },
    'need_ai_check': {
      'en': 'Need AI check',
      'hi': 'AI जांच चाहिए',
      'mr': 'AI तपासणी हवी',
    },
    'farm_alerts': {'en': 'Farm', 'hi': 'खेत', 'mr': 'शेत'},
    'open_full_farm_view': {
      'en': 'Open full farm view',
      'hi': 'पूरा खेत दृश्य खोलें',
      'mr': 'पूर्ण शेत दृश्य उघडा',
    },
    'full_view': {'en': 'Full view', 'hi': 'पूरा दृश्य', 'mr': 'पूर्ण दृश्य'},
    'status': {'en': 'Status', 'hi': 'स्थिति', 'mr': 'स्थिती'},
    'scout_zones': {
      'en': 'Scout zones',
      'hi': 'निरीक्षण क्षेत्र',
      'mr': 'निरीक्षण क्षेत्र',
    },
    'risk_cells': {'en': 'Risk cells', 'hi': 'जोखिम सेल', 'mr': 'धोका सेल'},
    'max_risk': {'en': 'Max risk', 'hi': 'अधिकतम जोखिम', 'mr': 'कमाल धोका'},
    'alert_refresh_failed': {
      'en': 'Alert refresh failed',
      'hi': 'अलर्ट रीफ्रेश विफल',
      'mr': 'अलर्ट रीफ्रेश अयशस्वी',
    },
    'important': {'en': 'Important', 'hi': 'महत्वपूर्ण', 'mr': 'महत्त्वाचे'},
    'important_alerts': {
      'en': 'Important alerts',
      'hi': 'महत्वपूर्ण अलर्ट',
      'mr': 'महत्त्वाचे अलर्ट',
    },
    'current_status': {
      'en': 'Current status',
      'hi': 'वर्तमान स्थिति',
      'mr': 'सध्याची स्थिती',
    },
    'current_status_for_farm': {
      'en': 'Current status • {farm}',
      'hi': 'वर्तमान स्थिति • {farm}',
      'mr': 'सध्याची स्थिती • {farm}',
    },
    'no_important_alerts': {
      'en': 'No important alerts yet',
      'hi': 'अभी कोई महत्वपूर्ण अलर्ट नहीं',
      'mr': 'अजून महत्त्वाचे अलर्ट नाहीत',
    },
    'no_weather_alert': {
      'en': 'No weather alert yet',
      'hi': 'अभी मौसम अलर्ट नहीं',
      'mr': 'अजून हवामान अलर्ट नाही',
    },
    'choose_farm': {'en': 'Choose Farm', 'hi': 'खेत चुनें', 'mr': 'शेत निवडा'},
    'humidity': {'en': 'Humidity', 'hi': 'आर्द्रता', 'mr': 'आर्द्रता'},
    'rain': {'en': 'Rain', 'hi': 'बारिश', 'mr': 'पाऊस'},
    'wetness': {'en': 'Wetness', 'hi': 'नमी समय', 'mr': 'ओलसरपणा'},
    'temp': {'en': 'Temp', 'hi': 'तापमान', 'mr': 'तापमान'},
    'try_again': {
      'en': 'Try again',
      'hi': 'फिर कोशिश करें',
      'mr': 'पुन्हा प्रयत्न करा',
    },
    'take_photo': {'en': 'Take photo', 'hi': 'फोटो लें', 'mr': 'फोटो घ्या'},
    'from_gallery': {'en': 'From gallery', 'hi': 'गैलरी से', 'mr': 'गॅलरीतून'},
    'risk_detail_title': {
      'en': 'Farm risk detail',
      'hi': 'खेत जोखिम विवरण',
      'mr': 'शेत जोखीम तपशील',
    },
    'risk_summary': {
      'en': 'Risk summary',
      'hi': 'जोखिम सारांश',
      'mr': 'जोखीम सारांश',
    },
    'problem': {'en': 'Problem', 'hi': 'समस्या', 'mr': 'समस्या'},
    'why_it_happened': {
      'en': 'Why it happened',
      'hi': 'यह क्यों हुआ',
      'mr': 'हे का झाले',
    },
    'what_to_do_now': {
      'en': 'What to do now',
      'hi': 'अब क्या करें',
      'mr': 'आता काय करावे',
    },
    'photo_check': {
      'en': 'Photo check',
      'hi': 'फोटो जांच',
      'mr': 'फोटो तपासणी',
    },
    'backend_status': {
      'en': 'Backend status',
      'hi': 'बैकएंड स्थिति',
      'mr': 'बॅकएंड स्थिती',
    },
    'refresh_advice': {
      'en': 'Refresh advice',
      'hi': 'सलाह रिफ्रेश करें',
      'mr': 'सल्ला रिफ्रेश करा',
    },
    'mark_visited': {
      'en': 'Mark visited',
      'hi': 'देखा गया चिन्हित करें',
      'mr': 'भेट दिली म्हणून चिन्हांकित करा',
    },
    'visited': {'en': 'Visited', 'hi': 'देखा गया', 'mr': 'भेट दिली'},
    'risk_visit_saved_title': {
      'en': 'Visit saved',
      'hi': 'दौरा सेव हुआ',
      'mr': 'भेट सेव्ह झाली',
    },
    'risk_visit_saved_desc': {
      'en': '{farm} risk visit has been synced.',
      'hi': '{farm} जोखिम दौरा सिंक हो गया है।',
      'mr': '{farm} जोखीम भेट सिंक झाली आहे.',
    },
    'risk_score': {'en': 'Risk score', 'hi': 'जोखिम स्कोर', 'mr': 'जोखीम गुण'},
    'risk_growth_stage_value': {
      'en': 'Stage: {stage}',
      'hi': 'चरण: {stage}',
      'mr': 'टप्पा: {stage}',
    },
    'days_after_sowing_value': {
      'en': '{days} days after sowing',
      'hi': 'बुवाई के {days} दिन बाद',
      'mr': 'पेरणीनंतर {days} दिवस',
    },
    'day_value': {'en': 'Day {day}', 'hi': 'दिन {day}', 'mr': 'दिवस {day}'},
    'day_range_value': {
      'en': 'Day {start}-{end}',
      'hi': 'दिन {start}-{end}',
      'mr': 'दिवस {start}-{end}',
    },
    'backend_source': {'en': 'Source', 'hi': 'स्रोत', 'mr': 'स्रोत'},
    'satellite_risk_cell': {
      'en': 'Satellite risk cell',
      'hi': 'सैटेलाइट जोखिम सेल',
      'mr': 'उपग्रह जोखीम सेल',
    },
    'guidance_status': {'en': 'Guidance', 'hi': 'सलाह', 'mr': 'सल्ला'},
    'guidance_ready': {'en': 'Ready', 'hi': 'तैयार', 'mr': 'तयार'},
    'guidance_loading': {
      'en': 'Loading',
      'hi': 'लोड हो रहा है',
      'mr': 'लोड होत आहे',
    },
    'guidance_failed': {'en': 'Failed', 'hi': 'विफल', 'mr': 'अयशस्वी'},
    'weather_status': {'en': 'Weather', 'hi': 'मौसम', 'mr': 'हवामान'},
    'weather_available': {'en': 'Available', 'hi': 'उपलब्ध', 'mr': 'उपलब्ध'},
    'weather_missing': {
      'en': 'Missing',
      'hi': 'उपलब्ध नहीं',
      'mr': 'उपलब्ध नाही',
    },
    'last_risk_scan': {
      'en': 'Last risk scan',
      'hi': 'अंतिम जोखिम स्कैन',
      'mr': 'शेवटचा जोखीम स्कॅन',
    },
    'risk_scan_time_not_available': {
      'en': 'Scan time not provided by backend',
      'hi': 'स्कैन समय बैकएंड से नहीं मिला',
      'mr': 'स्कॅन वेळ बॅकएंडकडून मिळाली नाही',
    },
    'photo_status': {'en': 'Photo', 'hi': 'फोटो', 'mr': 'फोटो'},
    'photo_ready': {
      'en': 'Diagnosis ready',
      'hi': 'जांच तैयार',
      'mr': 'तपासणी तयार',
    },
    'photo_needed': {
      'en': 'Photo needed',
      'hi': 'फोटो चाहिए',
      'mr': 'फोटो आवश्यक',
    },
    'photo_failed_status': {
      'en': 'Photo failed',
      'hi': 'फोटो विफल',
      'mr': 'फोटो अयशस्वी',
    },
    'tracking_sync_failed': {
      'en': 'Tracking sync failed: {error}',
      'hi': 'ट्रैकिंग सिंक विफल: {error}',
      'mr': 'ट्रॅकिंग सिंक अयशस्वी: {error}',
    },
    'risk_found_guidance_unavailable': {
      'en': 'Risk found, guidance unavailable.',
      'hi': 'जोखिम मिला, सलाह उपलब्ध नहीं है।',
      'mr': 'जोखीम आढळली, सल्ला उपलब्ध नाही.',
    },
    'advice_empty_title': {
      'en': 'No action returned',
      'hi': 'कोई कार्रवाई नहीं मिली',
      'mr': 'कोणतीही कृती मिळाली नाही',
    },
    'advice_empty_detail': {
      'en': 'Risk is saved, but advisor did not return a specific action.',
      'hi': 'जोखिम सेव है, लेकिन सलाहकार ने खास कार्रवाई नहीं दी।',
      'mr': 'जोखीम सेव्ह आहे, पण सल्लागाराने ठराविक कृती दिली नाही.',
    },
    'risk_signals': {
      'en': 'Risk signals',
      'hi': 'जोखिम संकेत',
      'mr': 'जोखीम संकेत',
    },
    'ndvi_signal': {
      'en': 'NDVI',
      'hi': 'वनस्पति सूचकांक',
      'mr': 'वनस्पती निर्देशांक',
    },
    'moisture_signal': {'en': 'Moisture', 'hi': 'नमी', 'mr': 'ओलावा'},
    'weather_risk_signal': {
      'en': 'Weather risk',
      'hi': 'मौसम जोखिम',
      'mr': 'हवामान जोखीम',
    },
    'disease_probability': {
      'en': '{disease}: {risk}',
      'hi': '{disease}: {risk}',
      'mr': '{disease}: {risk}',
    },
    'no_signal_data': {
      'en': 'Signal data missing',
      'hi': 'संकेत डेटा नहीं है',
      'mr': 'संकेत डेटा नाही',
    },
    'no_signal_data_detail': {
      'en':
          'The map has a risk location, but NDVI/moisture details were not returned.',
      'hi':
          'मैप में जोखिम स्थान है, लेकिन वनस्पति सूचकांक/नमी विवरण नहीं मिला।',
      'mr':
          'नकाशात जोखीम ठिकाण आहे, पण वनस्पती निर्देशांक/ओलावा तपशील मिळाला नाही.',
    },
    'diagnose': {'en': 'Diagnose', 'hi': 'जांचें', 'mr': 'तपासा'},
    'open_diagnose_flow': {
      'en': 'Open diagnose flow',
      'hi': 'जांच प्रक्रिया खोलें',
      'mr': 'तपासणी प्रक्रिया उघडा',
    },
    'water_level': {'en': 'Water level', 'hi': 'जल स्तर', 'mr': 'पाणी पातळी'},
    'vegetation_index': {
      'en': 'Vegetation index',
      'hi': 'वनस्पति सूचकांक',
      'mr': 'वनस्पती निर्देशांक',
    },
    'water_index': {
      'en': 'Water index',
      'hi': 'जल सूचकांक',
      'mr': 'पाणी निर्देशांक',
    },
    'crop_health': {
      'en': 'Crop health',
      'hi': 'फसल स्वास्थ्य',
      'mr': 'पीक आरोग्य',
    },
    'canopy_ground_structure': {
      'en': 'Canopy & ground structure',
      'hi': 'कैनोपी और जमीन संरचना',
      'mr': 'कॅनोपी आणि जमीन रचना',
    },
    'crop_trend': {'en': 'Crop trend', 'hi': 'फसल रुझान', 'mr': 'पीक कल'},
    'waiting_for_data': {
      'en': 'waiting for data',
      'hi': 'डेटा की प्रतीक्षा',
      'mr': 'डेटाची प्रतीक्षा',
    },
    'no_data': {'en': 'No data', 'hi': 'डेटा नहीं', 'mr': 'डेटा नाही'},
    'ndvi_history': {
      'en': 'NDVI History',
      'hi': 'वनस्पति सूचकांक इतिहास',
      'mr': 'वनस्पती निर्देशांक इतिहास',
    },
    'satellite_index_graphs': {
      'en': 'Satellite index graphs',
      'hi': 'सैटेलाइट इंडेक्स ग्राफ',
      'mr': 'उपग्रह इंडेक्स ग्राफ',
    },
    'soil_health_card': {
      'en': 'Soil Health',
      'hi': 'मृदा स्वास्थ्य',
      'mr': 'माती आरोग्य',
    },
    'soil_health_subtitle': {
      'en': 'pH, NPK & Moisture',
      'hi': 'pH, NPK और नमी',
      'mr': 'pH, NPK आणि ओलावा',
    },
    'weather_impact': {
      'en': 'Weather Impact',
      'hi': 'मौसम प्रभाव',
      'mr': 'हवामान परिणाम',
    },
    'humidity_rainfall_logs': {
      'en': 'Humidity & rainfall logs',
      'hi': 'आर्द्रता और बारिश रिकॉर्ड',
      'mr': 'आर्द्रता आणि पाऊस नोंदी',
    },
    'yield_prognosis': {
      'en': 'Yield Prognosis',
      'hi': 'उपज अनुमान',
      'mr': 'उत्पन्न अंदाज',
    },
    'expected_harvest_index': {
      'en': 'Expected harvest index',
      'hi': 'अपेक्षित कटाई सूचकांक',
      'mr': 'अपेक्षित कापणी निर्देशांक',
    },
    'farm_insight': {
      'en': 'Farm Insight',
      'hi': 'खेत जानकारी',
      'mr': 'शेत माहिती',
    },
    'stage_sowing': {'en': 'Sowing', 'hi': 'बुवाई', 'mr': 'पेरणी'},
    'stage_establishment': {
      'en': 'Establishment',
      'hi': 'स्थापना',
      'mr': 'स्थापना',
    },
    'stage_vegetative': {
      'en': 'Vegetative',
      'hi': 'वनस्पतिक',
      'mr': 'वाढ अवस्था',
    },
    'stage_flowering': {'en': 'Flowering', 'hi': 'फूल अवस्था', 'mr': 'फुलोरा'},
    'stage_grain_filling': {
      'en': 'Grain filling',
      'hi': 'दाना भरना',
      'mr': 'दाणा भरणे',
    },
    'stage_maturity': {'en': 'Maturity', 'hi': 'परिपक्वता', 'mr': 'परिपक्वता'},
    'area': {'en': 'Area', 'hi': 'क्षेत्रफल', 'mr': 'क्षेत्रफळ'},
    'satellite_field_map': {
      'en': 'Satellite and field map',
      'hi': 'सैटेलाइट और खेत मानचित्र',
      'mr': 'उपग्रह आणि शेत नकाशा',
    },
    'growth': {'en': 'Growth', 'hi': 'वृद्धि', 'mr': 'वाढ'},
    'day_stage': {
      'en': 'Day {day} • Stage {stage}',
      'hi': 'दिन {day} • अवस्था {stage}',
      'mr': 'दिवस {day} • अवस्था {stage}',
    },
    'crop_cycle_timeline': {
      'en': 'Crop-cycle timeline',
      'hi': 'फसल चक्र टाइमलाइन',
      'mr': 'पीक चक्र टाइमलाइन',
    },
    'crop_lifecycle_guidance': {
      'en': 'Crop lifecycle guidance',
      'hi': 'फसल जीवनचक्र सलाह',
      'mr': 'पीक जीवनचक्र मार्गदर्शन',
    },
    'active_now': {'en': 'Active now', 'hi': 'अभी सक्रिय', 'mr': 'आता सक्रिय'},
    'completed': {'en': 'Completed', 'hi': 'पूरा', 'mr': 'पूर्ण'},
    'upcoming_day_range': {
      'en': 'Upcoming ({start}-{end} day)',
      'hi': 'आगामी ({start}-{end} दिन)',
      'mr': 'पुढील ({start}-{end} दिवस)',
    },
    'last_update': {
      'en': 'Last update',
      'hi': 'अंतिम अपडेट',
      'mr': 'शेवटचा अपडेट',
    },
    'status_note': {
      'en': 'Status note',
      'hi': 'स्थिति नोट',
      'mr': 'स्थिती नोंद',
    },
    'not_updated': {
      'en': 'Not updated',
      'hi': 'अपडेट नहीं',
      'mr': 'अपडेट नाही',
    },
    'detailed_analysis_diagnostics': {
      'en': 'Detailed Analysis & Diagnostics',
      'hi': 'विस्तृत विश्लेषण और जांच',
      'mr': 'सविस्तर विश्लेषण आणि तपासणी',
    },
    'recent_harvest_history': {
      'en': 'Recent harvest history',
      'hi': 'हाल की कटाई इतिहास',
      'mr': 'अलीकडील कापणी इतिहास',
    },
    'latest_field_notes': {
      'en': 'Latest field notes',
      'hi': 'नवीनतम खेत नोट्स',
      'mr': 'नवीनतम शेत नोंदी',
    },
    'ndvi_analysis_title': {
      'en': '{farm} • NDVI Analysis',
      'hi': '{farm} • वनस्पति सूचकांक विश्लेषण',
      'mr': '{farm} • वनस्पती निर्देशांक विश्लेषण',
    },
    'ndvi_health_index_trend': {
      'en': 'NDVI Health Index Trend',
      'hi': 'वनस्पति स्वास्थ्य सूचक रुझान',
      'mr': 'वनस्पती आरोग्य निर्देशांक कल',
    },
    'satellite_overpasses': {
      'en': 'Satellite Overpasses',
      'hi': 'सैटेलाइट पास',
      'mr': 'उपग्रह पास',
    },
    'weather_hazards_outlook': {
      'en': 'Weather Hazards Outlook',
      'hi': 'मौसम जोखिम दृष्टिकोण',
      'mr': 'हवामान धोका अंदाज',
    },
    'est_harvest_window': {
      'en': 'Est. Harvest Window',
      'hi': 'अनुमानित कटाई समय',
      'mr': 'अंदाजे कापणी वेळ',
    },
    'farm_questionnaire_details': {
      'en': 'Farm questionnaire details',
      'hi': 'खेत प्रश्नावली विवरण',
      'mr': 'शेत प्रश्नावली तपशील',
    },
    'harvest_history': {
      'en': 'Harvest history',
      'hi': 'कटाई इतिहास',
      'mr': 'कापणी इतिहास',
    },
    'weather_index_trend': {
      'en': 'Weather + index trend',
      'hi': 'मौसम + इंडेक्स रुझान',
      'mr': 'हवामान + निर्देशांक कल',
    },
    'select_farm': {
      'en': 'Select a farm',
      'hi': 'खेत चुनें',
      'mr': 'शेत निवडा',
    },
    'farm_count_history_message': {
      'en':
          'Showing {count} farm{plural} for this farmer. Tap a farm to open its crop history, disease records, harvests, and remote index timeline.',
      'hi':
          'इस किसान के लिए {count} खेत दिख रहे हैं। फसल इतिहास, रोग रिकॉर्ड, कटाई और रिमोट इंडेक्स टाइमलाइन खोलने के लिए खेत पर टैप करें।',
      'mr':
          'या शेतकऱ्यासाठी {count} शेत दाखवत आहोत. पीक इतिहास, रोग नोंदी, कापणी आणि रिमोट इंडेक्स टाइमलाइन उघडण्यासाठी शेतावर टॅप करा.',
    },
    'live': {'en': 'Live', 'hi': 'लाइव', 'mr': 'लाईव्ह'},
    'refresh': {'en': 'Refresh', 'hi': 'रीफ़्रेश करें', 'mr': 'रीफ्रेश करा'},
    'not_available': {
      'en': 'Not available',
      'hi': 'उपलब्ध नहीं',
      'mr': 'उपलब्ध नाही',
    },
    'high': {'en': 'High', 'hi': 'उच्च', 'mr': 'जास्त'},
    'map_marked_farm': {
      'en': 'Map marked farm',
      'hi': 'मैप पर चिह्नित खेत',
      'mr': 'नकाशावर चिन्हांकित शेत',
    },
    'cycle_summary_day': {
      'en': 'Cycle summary • day {day}',
      'hi': 'चक्र सारांश • दिन {day}',
      'mr': 'चक्र सारांश • दिवस {day}',
    },
    'stage': {'en': 'Stage', 'hi': 'अवस्था', 'mr': 'अवस्था'},
    'pending': {'en': 'Pending', 'hi': 'लंबित', 'mr': 'बाकी'},
    'failed': {'en': 'Failed', 'hi': 'विफल', 'mr': 'अयशस्वी'},
    'paused': {'en': 'Paused', 'hi': 'रुका हुआ', 'mr': 'थांबलेले'},
    'updated': {'en': 'Updated', 'hi': 'अपडेट हुआ', 'mr': 'अपडेट झाले'},
    'health_value': {
      'en': 'Health {value}',
      'hi': 'स्वास्थ्य {value}',
      'mr': 'आरोग्य {value}',
    },
    'previous_value': {
      'en': 'Previous {value}',
      'hi': 'पिछला {value}',
      'mr': 'मागील {value}',
    },
    'previous_crop_value': {
      'en': 'Previous crop: {value}',
      'hi': 'पिछली फसल: {value}',
      'mr': 'मागील पीक: {value}',
    },
    'soil_value': {
      'en': 'Soil: {value}',
      'hi': 'मिट्टी: {value}',
      'mr': 'माती: {value}',
    },
    'land_value': {
      'en': 'Land: {value}',
      'hi': 'जमीन: {value}',
      'mr': 'जमीन: {value}',
    },
    'seed_value': {
      'en': 'Seed: {value}',
      'hi': 'बीज: {value}',
      'mr': 'बियाणे: {value}',
    },
    'use_value': {
      'en': 'Use: {value}',
      'hi': 'उपयोग: {value}',
      'mr': 'वापर: {value}',
    },
    'active_now_range': {
      'en': 'Active now • {start}-{end}',
      'hi': 'अभी सक्रिय • {start}-{end}',
      'mr': 'आता सक्रिय • {start}-{end}',
    },
    'starts_at_day': {
      'en': 'Starts at day {day}',
      'hi': 'दिन {day} से शुरू',
      'mr': 'दिवस {day} पासून सुरू',
    },
    'current_status_value': {
      'en': 'Current status: {value}',
      'hi': 'वर्तमान स्थिति: {value}',
      'mr': 'सध्याची स्थिती: {value}',
    },
    'last_update_value': {
      'en': 'Last update: {value}',
      'hi': 'शेवटचा अपडेट: {value}',
      'mr': 'शेवटचा अपडेट: {value}',
    },
    'no_harvest_history': {
      'en': 'No harvest history yet',
      'hi': 'अभी कटाई इतिहास नहीं',
      'mr': 'अजून कापणी इतिहास नाही',
    },
    'selected_farm_harvest_empty_detail': {
      'en':
          'When grading and bagging are completed, harvest lots for this selected farm will appear in the timeline.',
      'hi':
          'ग्रेडिंग और बैगिंग पूरी होने पर इस चुने गए खेत के कटाई लॉट टाइमलाइन में दिखेंगे।',
      'mr':
          'ग्रेडिंग आणि बॅगिंग पूर्ण झाल्यावर या निवडलेल्या शेताचे कापणी लॉट टाइमलाइनमध्ये दिसतील.',
    },
    'no_field_notes': {
      'en': 'No field notes yet',
      'hi': 'अभी खेत नोट्स नहीं',
      'mr': 'अजून शेत नोंदी नाहीत',
    },
    'survey_count': {
      'en': '{count} survey',
      'hi': '{count} सर्वे',
      'mr': '{count} सर्वे',
    },
    'survey_count_one': {
      'en': '{count} survey',
      'hi': '{count} सर्वे',
      'mr': '{count} सर्वे',
    },
    'survey_count_many': {
      'en': '{count} surveys',
      'hi': '{count} सर्वे',
      'mr': '{count} सर्वे',
    },
    'farmer_baseline_surveys': {
      'en': 'Farmer Baseline Surveys',
      'hi': 'किसान बेसलाइन सर्वे',
      'mr': 'शेतकरी बेसलाइन सर्वे',
    },
    'baseline_survey': {
      'en': 'Baseline Survey',
      'hi': 'बेसलाइन सर्वे',
      'mr': 'बेसलाइन सर्वे',
    },
    'use_classic_form': {
      'en': 'Use classic form',
      'hi': 'क्लासिक फॉर्म उपयोग करें',
      'mr': 'क्लासिक फॉर्म वापरा',
    },
    'use_chat_form': {
      'en': 'Use chat form',
      'hi': 'चैट फॉर्म उपयोग करें',
      'mr': 'चॅट फॉर्म वापरा',
    },
    'language_english': {'en': 'English', 'hi': 'English', 'mr': 'English'},
    'language_hindi': {'en': 'हिन्दी', 'hi': 'हिन्दी', 'mr': 'हिन्दी'},
    'language_marathi': {'en': 'मराठी', 'hi': 'मराठी', 'mr': 'मराठी'},
    'by_label': {'en': 'by', 'hi': 'द्वारा', 'mr': 'द्वारे'},
    'no_surveys_found': {
      'en': 'No surveys found',
      'hi': 'कोई सर्वे नहीं मिला',
      'mr': 'कोणतेही सर्वे सापडले नाहीत',
    },
    'farmer_survey_records_here': {
      'en': 'Farmer survey records will appear here.',
      'hi': 'किसान सर्वे रिकॉर्ड यहाँ दिखेंगे।',
      'mr': 'शेतकरी सर्वे नोंदी येथे दिसतील.',
    },
    'offline_maps': {
      'en': 'Offline Maps',
      'hi': 'ऑफलाइन मैप',
      'mr': 'ऑफलाइन नकाशे',
    },
    'view_diagnostics': {
      'en': 'View Diagnostics',
      'hi': 'डायग्नोस्टिक्स देखें',
      'mr': 'डायग्नोस्टिक्स पहा',
    },
    'new_survey': {'en': 'New Survey', 'hi': 'नया सर्वे', 'mr': 'नवीन सर्वे'},
    'resume_saved_survey': {
      'en': 'Resume saved survey',
      'hi': 'सहेजा हुआ सर्वे फिर शुरू करें',
      'mr': 'जतन केलेला सर्वे पुन्हा सुरू करा',
    },
    'start_chat_survey': {
      'en': 'Start chat survey',
      'hi': 'चैट सर्वे शुरू करें',
      'mr': 'चॅट सर्वे सुरू करा',
    },
    'continue_new_survey': {
      'en': 'Continue / New Survey',
      'hi': 'जारी रखें / नया सर्वे',
      'mr': 'सुरू ठेवा / नवीन सर्वे',
    },
    'syncing_offline_surveys': {
      'en': 'Syncing offline surveys...',
      'hi': 'ऑफ़लाइन सर्वे सिंक हो रहे हैं...',
      'mr': 'ऑफलाइन सर्वे सिंक होत आहेत...',
    },
    'pending_sync': {
      'en': '{count} survey pending sync',
      'hi': '{count} सर्वे सिंक बाकी',
      'mr': '{count} सर्वे सिंक बाकी',
    },
    'pending_sync_one': {
      'en': '{count} survey pending sync',
      'hi': '{count} सर्वे सिंक बाकी',
      'mr': '{count} सर्वे सिंक बाकी',
    },
    'pending_sync_many': {
      'en': '{count} surveys pending sync',
      'hi': '{count} सर्वे सिंक बाकी',
      'mr': '{count} सर्वे सिंक बाकी',
    },
    'pending_sync_status': {
      'en': 'Pending sync',
      'hi': 'सिंक बाकी',
      'mr': 'सिंक बाकी',
    },
    'retry_sync': {
      'en': 'Retry sync',
      'hi': 'सिंक फिर प्रयास करें',
      'mr': 'सिंक पुन्हा करा',
    },
    'unfinished_survey': {
      'en': 'Unfinished survey',
      'hi': 'अधूरा सर्वे',
      'mr': 'अपूर्ण सर्वे',
    },
    'continue_from_last_saved_page': {
      'en': 'Continue from the last saved page',
      'hi': 'आख़िरी सहेजे गए पेज से जारी रखें',
      'mr': 'शेवटच्या जतन केलेल्या पानापासून सुरू ठेवा',
    },
    'sync_failed': {
      'en': 'Sync failed',
      'hi': 'सिंक विफल',
      'mr': 'सिंक अयशस्वी',
    },
    'syncing': {'en': 'Syncing', 'hi': 'सिंक हो रहा है', 'mr': 'सिंक होत आहे'},
    'saved_offline': {
      'en': 'Saved offline',
      'hi': 'ऑफ़लाइन सेव',
      'mr': 'ऑफलाइन जतन',
    },
    'survey_actions': {
      'en': 'Survey actions',
      'hi': 'सर्वे क्रियाएँ',
      'mr': 'सर्वे क्रिया',
    },
    'delete_survey': {
      'en': 'Delete Survey',
      'hi': 'सर्वे हटाएँ',
      'mr': 'सर्वे हटवा',
    },
    'delete_survey_prompt': {
      'en':
          'Delete survey for "{name}" from the remote database and Google Sheet? This cannot be undone.',
      'hi':
          '"{name}" के सर्वे को रिमोट डेटाबेस और Google Sheet से हटाएँ? इसे वापस नहीं लाया जा सकता।',
      'mr':
          '"{name}" चा सर्वे रिमोट डेटाबेस आणि Google Sheet मधून हटवायचा? हे परत आणता येणार नाही.',
    },
    'cancel': {'en': 'Cancel', 'hi': 'रद्द करें', 'mr': 'रद्द करा'},
    'delete': {'en': 'Delete', 'hi': 'हटाएँ', 'mr': 'हटवा'},
    'home_title': {'en': 'Home', 'hi': 'होम', 'mr': 'होम'},
    'harvest_qr': {
      'en': 'Harvest QR',
      'hi': 'कापणी क्यूआर',
      'mr': 'कापणी क्यूआर',
    },
    'harvest_trace_sticker': {
      'en': 'Harvest Trace Sticker',
      'hi': 'हार्वेस्ट ट्रेस स्टिकर',
      'mr': 'कापणी ट्रेस स्टिकर',
    },
    'harvest_trace': {
      'en': 'Harvest Trace',
      'hi': 'कटाई ट्रेस',
      'mr': 'कापणी ट्रेस',
    },
    'lot_details': {'en': 'Lot Details', 'hi': 'लॉट विवरण', 'mr': 'लॉट तपशील'},
    'farm_source': {'en': 'Farm Source', 'hi': 'खेत स्रोत', 'mr': 'शेत स्रोत'},
    'trace_quantity_bags': {
      'en': '{total} kg ({bags} bags x {bagSize} kg)',
      'hi': '{total} किलो ({bags} बोरी x {bagSize} किलो)',
      'mr': '{total} किलो ({bags} पोती x {bagSize} किलो)',
    },
    'percent_value': {'en': '{value}%', 'hi': '{value}%', 'mr': '{value}%'},
    'trace_verified_at': {
      'en': 'Trace verified at {value}',
      'hi': 'ट्रेस {value} पर सत्यापित',
      'mr': 'ट्रेस {value} येथे पडताळले',
    },
    'invalid_trace_code': {
      'en': 'Invalid trace code',
      'hi': 'ट्रेस कोड मान्य नहीं',
      'mr': 'ट्रेस कोड वैध नाही',
    },
    'scan_valid_harvest_qr': {
      'en': 'Scan a valid Kalsubai Farms harvest QR sticker.',
      'hi': 'मान्य Kalsubai Farms कटाई QR स्टिकर स्कैन करें।',
      'mr': 'वैध Kalsubai Farms कापणी QR स्टिकर स्कॅन करा.',
    },
    'sticker_use': {
      'en': 'Sticker Use',
      'hi': 'स्टिकर उपयोग',
      'mr': 'स्टिकर वापर',
    },
    'harvest_sticker_desc': {
      'en':
          'Download this card and print it as a bag sticker. The QR opens a public harvest trace card with batch, farm, grade and bag details.',
      'hi':
          'इस कार्ड को डाउनलोड करें और बैग स्टिकर के रूप में प्रिंट करें। क्यूआर बैच, खेत, ग्रेड और बोरी विवरण वाला सार्वजनिक कापणी ट्रेस कार्ड खोलता है।',
      'mr':
          'हे कार्ड डाउनलोड करा आणि पोत्याच्या स्टिकरप्रमाणे प्रिंट करा. क्यूआर बॅच, शेत, ग्रेड आणि पोती तपशील असलेले सार्वजनिक कापणी ट्रेस कार्ड उघडतो.',
    },
    'qr_locked': {
      'en': 'QR locked',
      'hi': 'क्यूआर लॉक है',
      'mr': 'क्यूआर लॉक आहे',
    },
    'harvest_sticker_ready': {
      'en': 'Harvest sticker ready',
      'hi': 'हार्वेस्ट स्टिकर तैयार',
      'mr': 'कापणी स्टिकर तयार',
    },
    'download_failed': {
      'en': 'Download failed',
      'hi': 'डाउनलोड विफल',
      'mr': 'डाउनलोड अयशस्वी',
    },
    'offline_field_maps': {
      'en': 'Offline Field Maps',
      'hi': 'ऑफलाइन खेत मैप',
      'mr': 'ऑफलाइन शेत नकाशे',
    },
    'stored_field_maps': {
      'en': 'Stored Field Maps',
      'hi': 'सहेजे गए खेत मैप',
      'mr': 'जतन केलेले शेत नकाशे',
    },
    'offline_tile_source': {
      'en': 'offline tile source',
      'hi': 'ऑफलाइन टाइल स्रोत',
      'mr': 'ऑफलाइन टाइल स्रोत',
    },
    'stored_offline_region': {
      'en': 'Stored offline region',
      'hi': 'सहेजा गया ऑफलाइन क्षेत्र',
      'mr': 'जतन केलेला ऑफलाइन भाग',
    },
    'could_not_load_place': {
      'en': 'Could not load that place.',
      'hi': 'वह जगह लोड नहीं हो सकी।',
      'mr': 'ते ठिकाण लोड करता आले नाही.',
    },
    'offline_map_deleted': {
      'en': 'Deleted {region} offline map',
      'hi': '{region} ऑफलाइन मैप हटाया गया',
      'mr': '{region} ऑफलाइन नकाशा हटवला',
    },
    'maptiler_key_required': {
      'en':
          'Set MAPTILER_API_KEY to use MapTiler field imagery and place search.',
      'hi': 'MapTiler खेत इमेजरी और जगह खोज के लिए MAPTILER_API_KEY सेट करें।',
      'mr': 'MapTiler शेत प्रतिमा आणि ठिकाण शोधासाठी MAPTILER_API_KEY सेट करा.',
    },
    'offline_tile_template_required': {
      'en':
          'Set OFFLINE_TILE_URL_TEMPLATE to your licensed custom tile endpoint if you are not using MapTiler.',
      'hi':
          'यदि MapTiler उपयोग नहीं कर रहे हैं, तो अपने लाइसेंस वाले कस्टम टाइल endpoint के लिए OFFLINE_TILE_URL_TEMPLATE सेट करें।',
      'mr':
          'MapTiler वापरत नसल्यास तुमच्या परवानाधारक कस्टम टाइल endpoint साठी OFFLINE_TILE_URL_TEMPLATE सेट करा.',
    },
    'offline_downloads_unavailable': {
      'en':
          'Offline map downloads are not available in this build because local tile storage is disabled here. Use the Android/iOS app build for field offline downloads.',
      'hi':
          'इस build में local tile storage बंद होने के कारण offline map download उपलब्ध नहीं है। Field offline download के लिए Android/iOS app build उपयोग करें।',
      'mr':
          'या build मध्ये local tile storage बंद असल्याने offline map download उपलब्ध नाही. Field offline download साठी Android/iOS app build वापरा.',
    },
    'offline_imagery_not_configured': {
      'en':
          'Offline field imagery is not configured. Set MAPTILER_API_KEY or OFFLINE_TILE_URL_TEMPLATE in .env, android/local.properties, environment variables, or --dart-define.',
      'hi':
          'Offline field imagery configured नहीं है। .env, android/local.properties, environment variables, या --dart-define में MAPTILER_API_KEY या OFFLINE_TILE_URL_TEMPLATE सेट करें।',
      'mr':
          'Offline field imagery configured नाही. .env, android/local.properties, environment variables, किंवा --dart-define मध्ये MAPTILER_API_KEY किंवा OFFLINE_TILE_URL_TEMPLATE सेट करा.',
    },
    'search_village_field_area': {
      'en': 'Search village or field area',
      'hi': 'गांव या खेत क्षेत्र खोजें',
      'mr': 'गाव किंवा शेत क्षेत्र शोधा',
    },
    'radius_km': {
      'en': 'Radius km',
      'hi': 'त्रिज्या किमी',
      'mr': 'त्रिज्या किमी',
    },
    'best_detail_km': {
      'en': 'Best detail: 1-3 km',
      'hi': 'सर्वश्रेष्ठ विवरण: 1-3 किमी',
      'mr': 'चांगला तपशील: 1-3 किमी',
    },
    'download_field_map': {
      'en': 'Download Field Map',
      'hi': 'खेत मैप डाउनलोड करें',
      'mr': 'शेत नकाशा डाउनलोड करा',
    },
    'downloading': {
      'en': 'Downloading',
      'hi': 'डाउनलोड हो रहा है',
      'mr': 'डाउनलोड होत आहे',
    },
    'offline_tiles_progress': {
      'en': '{downloaded}/{total} tiles from {source}',
      'hi': '{source} से {downloaded}/{total} टाइल',
      'mr': '{source} मधून {downloaded}/{total} टाइल',
    },
    'offline_map_download_hint': {
      'en':
          'Downloads the same field-detail area you will use for marking. Keep radius at 1-3 km for faster offline loading and sharper boundaries.',
      'hi':
          'मार्किंग के लिए उपयोग होने वाला वही field-detail क्षेत्र डाउनलोड करता है। तेज offline loading और साफ boundaries के लिए radius 1-3 km रखें।',
      'mr':
          'मार्किंगसाठी वापरणार तोच field-detail भाग डाउनलोड करतो. जलद offline loading आणि स्पष्ट boundaries साठी radius 1-3 km ठेवा.',
    },
    'lat_lng_value': {
      'en': '{lat}, {lng}',
      'hi': '{lat}, {lng}',
      'mr': '{lat}, {lng}',
    },
    'offline_region_detail': {
      'en':
          '{radius} km radius, field-detail center zoom {minZoom}-{maxZoom}, {downloaded}/{total} tiles, {size} MB',
      'hi':
          '{radius} किमी त्रिज्या, field-detail center zoom {minZoom}-{maxZoom}, {downloaded}/{total} टाइल, {size} MB',
      'mr':
          '{radius} किमी त्रिज्या, field-detail center zoom {minZoom}-{maxZoom}, {downloaded}/{total} टाइल, {size} MB',
    },
    'downloaded_maps': {
      'en': 'Downloaded maps',
      'hi': 'डाउनलोड किए गए मैप',
      'mr': 'डाउनलोड केलेले नकाशे',
    },
    'no_downloaded_field_maps_available': {
      'en': 'No complete downloaded field maps are available yet.',
      'hi': 'अभी कोई पूरा डाउनलोड किया गया खेत मैप उपलब्ध नहीं है।',
      'mr': 'अजून पूर्ण डाउनलोड केलेला शेत नकाशा उपलब्ध नाही.',
    },
    'no_downloaded_map_regions': {
      'en': 'No downloaded map regions are available for drawing.',
      'hi': 'बनाने के लिए कोई डाउनलोड किया गया मैप क्षेत्र उपलब्ध नहीं है।',
      'mr': 'रेखाटण्यासाठी डाउनलोड केलेला नकाशा भाग उपलब्ध नाही.',
    },
    'select_downloaded_field_map': {
      'en': 'Select downloaded field map',
      'hi': 'डाउनलोड किया गया खेत मैप चुनें',
      'mr': 'डाउनलोड केलेला शेत नकाशा निवडा',
    },
    'select_downloaded_map': {
      'en': 'Select downloaded map',
      'hi': 'डाउनलोड किया गया मैप चुनें',
      'mr': 'डाउनलोड केलेला नकाशा निवडा',
    },
    'downloaded_map_selected': {
      'en': 'Downloaded map selected',
      'hi': 'डाउनलोड किया गया मैप चुना गया',
      'mr': 'डाउनलोड केलेला नकाशा निवडला',
    },
    'loaded_offline_boundary_map': {
      'en': 'Loaded {region} for offline boundary marking.',
      'hi': 'ऑफलाइन boundary marking के लिए {region} लोड हुआ।',
      'mr': 'ऑफलाइन boundary marking साठी {region} लोड झाला.',
    },
    'centered_on_draw_boundary': {
      'en': 'Centered on {region}. Switch to Draw and mark the farm boundary.',
      'hi': '{region} पर केंद्रित हुआ। Draw पर जाएं और खेत सीमा चिह्नित करें।',
      'mr':
          '{region} वर मध्यभागी आणले. Draw वर जा आणि शेत सीमा चिन्हांकित करा.',
    },
    'downloaded_region_summary': {
      'en':
          '{radius} km · zoom {minZoom}-{maxZoom} · {downloaded}/{total} tiles',
      'hi':
          '{radius} किमी · zoom {minZoom}-{maxZoom} · {downloaded}/{total} टाइल',
      'mr':
          '{radius} किमी · zoom {minZoom}-{maxZoom} · {downloaded}/{total} टाइल',
    },
    'downloaded_region_status_summary': {
      'en':
          '{status} · {radius} km · zoom {minZoom}-{maxZoom} · {downloaded}/{total} tiles',
      'hi':
          '{status} · {radius} किमी · zoom {minZoom}-{maxZoom} · {downloaded}/{total} टाइल',
      'mr':
          '{status} · {radius} किमी · zoom {minZoom}-{maxZoom} · {downloaded}/{total} टाइल',
    },
    'draw_farm_boundary': {
      'en': 'Draw farm boundary',
      'hi': 'खेत सीमा बनाएं',
      'mr': 'शेत सीमा रेखाटा',
    },
    'draw_your_farm': {
      'en': 'Draw Your Farm',
      'hi': 'अपना खेत बनाएं',
      'mr': 'तुमचे शेत रेखाटा',
    },
    'draw_at_least_three_points': {
      'en': 'Draw at least 3 points to define your farm boundary.',
      'hi': 'खेत सीमा तय करने के लिए कम से कम 3 बिंदु बनाएं।',
      'mr': 'शेत सीमा ठरवण्यासाठी किमान 3 बिंदू रेखाटा.',
    },
    'name_your_farm': {
      'en': 'Name your farm',
      'hi': 'अपने खेत का नाम दें',
      'mr': 'तुमच्या शेताला नाव द्या',
    },
    'farm_name': {'en': 'Farm name', 'hi': 'खेत का नाम', 'mr': 'शेताचे नाव'},
    'my_farm': {'en': 'My Farm', 'hi': 'मेरा खेत', 'mr': 'माझे शेत'},
    'undo_last_point': {
      'en': 'Undo last point',
      'hi': 'आखिरी बिंदु हटाएं',
      'mr': 'शेवटचा बिंदू मागे घ्या',
    },
    'save': {'en': 'Save', 'hi': 'सेव करें', 'mr': 'जतन करा'},
    'tap_map_add_boundary_points': {
      'en': 'Tap the map to add boundary points',
      'hi': 'सीमा बिंदु जोड़ने के लिए मैप पर टैप करें',
      'mr': 'सीमा बिंदू जोडण्यासाठी नकाशावर टॅप करा',
    },
    'points_added': {
      'en': '{count} point{plural} added',
      'hi': '{count} बिंदु जोड़े गए',
      'mr': '{count} बिंदू जोडले',
    },
    'points_added_save_when_done': {
      'en': '{count} point{plural} added · Tap "Save" when done',
      'hi': '{count} बिंदु जोड़े गए · पूरा होने पर "Save" टैप करें',
      'mr': '{count} बिंदू जोडले · पूर्ण झाल्यावर "Save" टॅप करा',
    },
    'points_added_add_more': {
      'en': '{count} point{plural} added · Add {remaining} more',
      'hi': '{count} बिंदु जोड़े गए · {remaining} और जोड़ें',
      'mr': '{count} बिंदू जोडले · आणखी {remaining} जोडा',
    },
    're_center': {
      'en': 'Re-center',
      'hi': 'फिर केंद्रित करें',
      'mr': 'पुन्हा मध्यभागी आणा',
    },
    'tap_corners_boundary': {
      'en': 'Tap corners to build the farm boundary.',
      'hi': 'खेत सीमा बनाने के लिए कोनों पर टैप करें।',
      'mr': 'शेत सीमा तयार करण्यासाठी कोपऱ्यांवर टॅप करा.',
    },
    'add_second_boundary_point': {
      'en': 'Add a second point to create the first edge.',
      'hi': 'पहली रेखा बनाने के लिए दूसरा बिंदु जोड़ें।',
      'mr': 'पहिली रेषा तयार करण्यासाठी दुसरा बिंदू जोडा.',
    },
    'add_third_boundary_point': {
      'en': 'Add a third point to close the polygon.',
      'hi': 'पॉलीगॉन बंद करने के लिए तीसरा बिंदु जोड़ें।',
      'mr': 'पॉलीगॉन बंद करण्यासाठी तिसरा बिंदू जोडा.',
    },
    'drag_points_confirm_boundary': {
      'en': 'Drag points to refine the boundary, then confirm.',
      'hi': 'सीमा सुधारने के लिए बिंदु खींचें, फिर पुष्टि करें।',
      'mr': 'सीमा अचूक करण्यासाठी बिंदू ओढा, नंतर पुष्टी करा.',
    },
    'offline_map_tap_boundary': {
      'en': 'Offline map\nTap points to mark boundary',
      'hi': 'ऑफलाइन मैप\nसीमा चिन्हित करने के लिए बिंदु टैप करें',
      'mr': 'ऑफलाइन नकाशा\nसीमा चिन्हांकित करण्यासाठी बिंदू टॅप करा',
    },
    'offline_map_tap_draw_farm': {
      'en': 'Offline map\nTap points to draw farm',
      'hi': 'ऑफलाइन मैप\nखेत बनाने के लिए बिंदु टैप करें',
      'mr': 'ऑफलाइन नकाशा\nशेत रेखाटण्यासाठी बिंदू टॅप करा',
    },
    'offline_map_pan_draw': {
      'en': 'Offline map\nPan to your farm and draw',
      'hi': 'ऑफलाइन मैप\nअपने खेत पर पैन करें और बनाएं',
      'mr': 'ऑफलाइन नकाशा\nतुमच्या शेताकडे पॅन करा आणि रेखाटा',
    },
    'hectare_value': {
      'en': '{value} ha',
      'hi': '{value} हेक्टेयर',
      'mr': '{value} हेक्टर',
    },
    'points_more_to_confirm': {
      'en': 'Add {count} more point{plural} to confirm',
      'hi': 'पुष्टि के लिए {count} और बिंदु जोड़ें',
      'mr': 'पुष्टीसाठी आणखी {count} बिंदू जोडा',
    },
    'undo': {'en': 'Undo', 'hi': 'पूर्ववत करें', 'mr': 'मागे घ्या'},
    'redraw': {'en': 'Redraw', 'hi': 'फिर बनाएं', 'mr': 'पुन्हा रेखाटा'},
    'confirm': {'en': 'Confirm', 'hi': 'पुष्टि करें', 'mr': 'पुष्टी करा'},
    'draw_boundary': {
      'en': 'Draw boundary',
      'hi': 'सीमा बनाएं',
      'mr': 'सीमा रेखाटा',
    },
    'add_three_boundary_points': {
      'en': 'Add at least 3 boundary points',
      'hi': 'कम से कम 3 सीमा बिंदु जोड़ें',
      'mr': 'किमान 3 सीमा बिंदू जोडा',
    },
    'pan': {'en': 'Pan', 'hi': 'पैन', 'mr': 'पॅन'},
    'draw': {'en': 'Draw', 'hi': 'बनाएं', 'mr': 'रेखाटा'},
    'pan_field_then_draw': {
      'en': 'Pan to the field, then Draw: tap corners or drag the boundary',
      'hi': 'खेत तक पैन करें, फिर Draw: कोनों पर टैप करें या सीमा खींचें',
      'mr': 'शेतापर्यंत पॅन करा, मग Draw: कोपऱ्यांवर टॅप करा किंवा सीमा ओढा',
    },
    'clear': {'en': 'Clear', 'hi': 'साफ करें', 'mr': 'साफ करा'},
    'done': {'en': 'Done', 'hi': 'हो गया', 'mr': 'पूर्ण'},
    'zoom_in': {'en': 'Zoom in', 'hi': 'ज़ूम इन', 'mr': 'झूम इन'},
    'zoom_out': {'en': 'Zoom out', 'hi': 'ज़ूम आउट', 'mr': 'झूम आउट'},
    'zoom_range_short': {
      'en': 'Z{minZoom}-{maxZoom}',
      'hi': 'Z{minZoom}-{maxZoom}',
      'mr': 'Z{minZoom}-{maxZoom}',
    },
    'no_downloaded_field_maps': {
      'en': 'No downloaded field maps yet',
      'hi': 'अभी कोई खेत मैप डाउनलोड नहीं है',
      'mr': 'अजून कोणतेही शेत नकाशे डाउनलोड नाहीत',
    },
    'no_downloaded_field_maps_detail': {
      'en':
          'Search a village or field area while online, then download a small field-detail map and use that same download while marking offline.',
      'hi':
          'Online रहते हुए गांव या खेत क्षेत्र खोजें, फिर छोटा field-detail map डाउनलोड करें और offline marking में वही डाउनलोड उपयोग करें।',
      'mr':
          'Online असताना गाव किंवा शेत क्षेत्र शोधा, नंतर छोटा field-detail map डाउनलोड करा आणि offline marking करताना तोच डाउनलोड वापरा.',
    },
    'resume': {'en': 'Resume', 'hi': 'फिर शुरू करें', 'mr': 'पुन्हा सुरू करा'},
    'update': {'en': 'Update', 'hi': 'अपडेट करें', 'mr': 'अपडेट करा'},
    'could_not_export_sticker': {
      'en': 'Could not export the sticker image.',
      'hi': 'स्टिकर छवि निर्यात नहीं हो सकी।',
      'mr': 'स्टिकर प्रतिमा निर्यात करता आली नाही.',
    },
    'preparing': {
      'en': 'Preparing',
      'hi': 'तैयार हो रहा है',
      'mr': 'तैयार होत आहे',
    },
    'download_sticker': {
      'en': 'Download sticker',
      'hi': 'स्टिकर डाउनलोड करें',
      'mr': 'स्टिकर डाउनलोड करा',
    },
    'scan_harvest_qr': {
      'en': 'Scan harvest QR',
      'hi': 'कापणी क्यूआर स्कैन करें',
      'mr': 'कापणी क्यूआर स्कॅन करा',
    },
    'saved_to': {
      'en': 'Saved {path}',
      'hi': '{path} में सेव',
      'mr': '{path} मध्ये जतन',
    },
    'complete_grading': {
      'en': 'Complete grain grading',
      'hi': 'अनाज ग्रेडिंग पूरी करें',
      'mr': 'धान्य ग्रेडिंग पूर्ण करा',
    },
    'complete_farmer_profile': {
      'en': 'Complete farmer profile',
      'hi': 'किसान प्रोफ़ाइल पूरी करें',
      'mr': 'शेतकरी प्रोफाइल पूर्ण करा',
    },
    'select_saved_farm': {
      'en': 'Select a saved farm',
      'hi': 'सहेजा हुआ खेत चुनें',
      'mr': 'जतन केलेले शेत निवडा',
    },
    'add_batch_id': {
      'en': 'Add batch ID',
      'hi': 'बैच पहचान क्रमांक जोड़ें',
      'mr': 'बॅच ओळख क्रमांक जोडा',
    },
    'add_bag_details': {
      'en': 'Add bag details',
      'hi': 'बोरी विवरण जोड़ें',
      'mr': 'पोती तपशील जोडा',
    },
    'confirm_moisture': {
      'en': 'Confirm moisture',
      'hi': 'नमी की पुष्टि करें',
      'mr': 'ओलावा निश्चित करा',
    },
    'complete_grade_result': {
      'en': 'Complete grade result',
      'hi': 'ग्रेड परिणाम पूरा करें',
      'mr': 'ग्रेड परिणाम पूर्ण करा',
    },
    'wait_for_fpo_review_approval': {
      'en': 'Wait for FPO review approval',
      'hi': 'किसान उत्पादक संस्था समीक्षा की मंज़ूरी का इंतज़ार करें',
      'mr': 'शेतकरी उत्पादक संस्था पुनरावलोकन मंजुरीची वाट पाहा',
    },
    'kg_unit': {'en': 'kg', 'hi': 'किलो', 'mr': 'किलो'},
    'qtl_unit': {'en': 'qtl', 'hi': 'क्विंटल', 'mr': 'क्विंटल'},
    'km_unit': {'en': 'km', 'hi': 'किमी', 'mr': 'किमी'},
    'currency_symbol': {'en': 'Rs', 'hi': '₹', 'mr': '₹'},
    'batch': {'en': 'Batch', 'hi': 'बैच', 'mr': 'बॅच'},
    'analysis_id': {
      'en': 'Analysis ID',
      'hi': 'विश्लेषण पहचान क्रमांक',
      'mr': 'विश्लेषण ओळख क्रमांक',
    },
    'crop': {'en': 'Crop', 'hi': 'फसल', 'mr': 'पीक'},
    'product': {'en': 'Product', 'hi': 'उत्पाद', 'mr': 'उत्पादन'},
    'farm': {'en': 'Farm', 'hi': 'खेत', 'mr': 'शेत'},
    'farm_id': {
      'en': 'Farm ID',
      'hi': 'खेत पहचान क्रमांक',
      'mr': 'शेत ओळख क्रमांक',
    },
    'village': {'en': 'Village', 'hi': 'गाँव', 'mr': 'गाव'},
    'farmer': {'en': 'Farmer', 'hi': 'किसान', 'mr': 'शेतकरी'},
    'farmer_id': {
      'en': 'Farmer ID',
      'hi': 'किसान पहचान क्रमांक',
      'mr': 'शेतकरी ओळख क्रमांक',
    },
    'grade': {'en': 'Grade', 'hi': 'ग्रेड', 'mr': 'ग्रेड'},
    'score': {'en': 'Score', 'hi': 'स्कोर', 'mr': 'स्कोअर'},
    'standards': {'en': 'Standards', 'hi': 'मानक', 'mr': 'मानके'},
    'grader': {'en': 'Grader', 'hi': 'ग्रेडर', 'mr': 'ग्रेडर'},
    'moisture': {'en': 'Moisture', 'hi': 'नमी', 'mr': 'ओलावा'},
    'location': {'en': 'Location', 'hi': 'स्थान', 'mr': 'ठिकाण'},
    'harvest_yield': {
      'en': 'Harvest Yield',
      'hi': 'कटाई उपज',
      'mr': 'कापणी उत्पादन',
    },
    'rating': {'en': 'Rating', 'hi': 'रेटिंग', 'mr': 'रेटिंग'},
    'bag_size': {'en': 'Bag Size', 'hi': 'बोरी आकार', 'mr': 'पोती आकार'},
    'bags_label': {'en': 'Bags', 'hi': 'बोरी', 'mr': 'पोती'},
    'total': {'en': 'Total', 'hi': 'कुल', 'mr': 'एकूण'},
    'microservice': {
      'en': 'Microservice',
      'hi': 'माइक्रोसर्विस',
      'mr': 'मायक्रोसर्व्हिस',
    },
    'review_pending': {'en': 'Pending', 'hi': 'लंबित', 'mr': 'बाकी'},
    'apmc_market_name_akole': {
      'en': 'Akole APMC',
      'hi': 'अकोले मंडी',
      'mr': 'अकोले बाजार समिती',
    },
    'apmc_market_name_sangamner': {
      'en': 'Sangamner APMC',
      'hi': 'संगमनेर मंडी',
      'mr': 'संगमनेर बाजार समिती',
    },
    'apmc_market_name_nashik': {
      'en': 'Nashik APMC',
      'hi': 'नासिक मंडी',
      'mr': 'नाशिक बाजार समिती',
    },
    'apmc_market_name_pune': {
      'en': 'Pune Market Yard',
      'hi': 'पुणे मार्केट यार्ड',
      'mr': 'पुणे मार्केट यार्ड',
    },
    'apmc_market_name_rahuri': {
      'en': 'Rahuri APMC',
      'hi': 'राहुरी मंडी',
      'mr': 'राहुरी बाजार समिती',
    },
    'remote_index_pending': {
      'en': 'Remote index data pending',
      'hi': 'रिमोट इंडेक्स डेटा लंबित',
      'mr': 'रिमोट इंडेक्स डेटा बाकी',
    },
    'search_lot_hint': {
      'en': 'Search lot id, crop, variety, grade',
      'hi': 'लॉट पहचान क्रमांक, फसल, किस्म, ग्रेड खोजें',
      'mr': 'लॉट ओळख क्रमांक, पीक, वाण, ग्रेड शोधा',
    },
    'create_listing': {
      'en': 'Create listing',
      'hi': 'लिस्टिंग बनाएं',
      'mr': 'लिस्टिंग तयार करा',
    },
    'demand_trend': {
      'en': 'Demand trend',
      'hi': 'मांग रुझान',
      'mr': 'मागणी कल',
    },
    'apply_now': {
      'en': 'Apply Now',
      'hi': 'अभी आवेदन करें',
      'mr': 'आता अर्ज करा',
    },
    'search_schemes_hint': {
      'en': 'Search schemes, subsidies, and programs',
      'hi': 'योजनाएँ, सब्सिडी और कार्यक्रम खोजें',
      'mr': 'योजना, अनुदान आणि कार्यक्रम शोधा',
    },
    'farm_details': {
      'en': 'Farm Details',
      'hi': 'खेत विवरण',
      'mr': 'शेत तपशील',
    },
    'review_farm_crop_health': {
      'en': 'Review farm and crop health',
      'hi': 'खेत और फसल स्वास्थ्य देखें',
      'mr': 'शेत आणि पीक आरोग्य पहा',
    },
    'help_support_center': {
      'en': 'Help and support center',
      'hi': 'मदद और सहायता केंद्र',
      'mr': 'मदत आणि सहाय्य केंद्र',
    },
    'news_advisories': {
      'en': 'News & Advisories',
      'hi': 'समाचार और सलाह',
      'mr': 'बातम्या आणि सूचना',
    },
    'farm_impact_value': {
      'en': 'Farm impact: {value}',
      'hi': 'खेत प्रभाव: {value}',
      'mr': 'शेत परिणाम: {value}',
    },
    'government_schemes': {
      'en': 'Government Schemes',
      'hi': 'सरकारी योजनाएँ',
      'mr': 'सरकारी योजना',
    },
    'farm_documents': {
      'en': 'Farm documents',
      'hi': 'खेत दस्तावेज़',
      'mr': 'शेत कागदपत्रे',
    },
    'farmer_qr': {
      'en': 'Farmer QR',
      'hi': 'किसान क्यूआर',
      'mr': 'शेतकरी क्यूआर',
    },
    'farm_profile_active': {
      'en': 'Farm profile active',
      'hi': 'खेत प्रोफ़ाइल सक्रिय',
      'mr': 'शेत प्रोफाइल सक्रिय',
    },
    'max_label': {'en': 'Max', 'hi': 'अधिकतम', 'mr': 'कमाल'},
    'min_label': {'en': 'Min', 'hi': 'न्यूनतम', 'mr': 'किमान'},
    'aqi': {'en': 'AQI', 'hi': 'AQI', 'mr': 'AQI'},
    'saturday_short': {'en': 'Sat', 'hi': 'शनि', 'mr': 'शनि'},
    'weather_humid': {'en': 'Humid', 'hi': 'आर्द्र', 'mr': 'दमट'},
    'weather_dry': {'en': 'Dry', 'hi': 'सूखा', 'mr': 'कोरडे'},
    'seven_day_forecast': {
      'en': '7-Day Weather Forecast',
      'hi': '7 दिन का मौसम पूर्वानुमान',
      'mr': '7 दिवसांचा हवामान अंदाज',
    },
    'agro_watch_signals': {
      'en': 'Agro-watch signals',
      'hi': 'कृषि निगरानी संकेत',
      'mr': 'कृषी निरीक्षण संकेत',
    },
    'farmer_field_tips': {
      'en': 'Farmer field tips',
      'hi': 'किसान खेत सुझाव',
      'mr': 'शेतकरी शेत टिप्स',
    },
    'local_weather': {
      'en': 'Local weather',
      'hi': 'स्थानीय मौसम',
      'mr': 'स्थानिक हवामान',
    },
    'weather_panel': {
      'en': 'weather panel',
      'hi': 'मौसम पैनल',
      'mr': 'हवामान पॅनेल',
    },
    'weather_recommendation_scope': {
      'en':
          'Weather recommendations are scoped to the active farm selected on the farmer home page.',
      'hi': 'मौसम सुझाव किसान होम पेज पर चुने गए सक्रिय खेत के अनुसार हैं।',
      'mr': 'हवामान सूचना शेतकरी होम पेजवर निवडलेल्या सक्रिय शेतानुसार आहेत.',
    },
    'today_glance': {
      'en': 'Today at a glance',
      'hi': 'आज का सारांश',
      'mr': 'आजचा सारांश',
    },
    'evening': {'en': 'Evening', 'hi': 'शाम', 'mr': 'संध्याकाळ'},
    'low': {'en': 'Low', 'hi': 'कम', 'mr': 'कमी'},
    'moderate': {'en': 'Moderate', 'hi': 'मध्यम', 'mr': 'मध्यम'},
    'loading': {'en': 'Loading', 'hi': 'लोड हो रहा है', 'mr': 'लोड होत आहे'},
    'improving': {'en': 'Improving', 'hi': 'सुधार', 'mr': 'सुधारत आहे'},
    'declining': {'en': 'Declining', 'hi': 'घटता', 'mr': 'घटत आहे'},
    'strong': {'en': 'Strong', 'hi': 'मजबूत', 'mr': 'मजबूत'},
    'fair': {'en': 'Fair', 'hi': 'सामान्य', 'mr': 'सामान्य'},
    'sparse': {'en': 'Sparse', 'hi': 'कम घना', 'mr': 'विरळ'},
    'healthy': {'en': 'Healthy', 'hi': 'स्वस्थ', 'mr': 'निरोगी'},
    'stressed': {'en': 'Stressed', 'hi': 'तनावग्रस्त', 'mr': 'तणावग्रस्त'},
    'surface_heat': {
      'en': 'Surface Heat',
      'hi': 'सतह ताप',
      'mr': 'पृष्ठभाग उष्णता',
    },
    'canopy': {'en': 'Canopy', 'hi': 'कैनोपी', 'mr': 'कॅनोपी'},
    'current_conditions': {
      'en': 'Current Conditions',
      'hi': 'वर्तमान स्थिति',
      'mr': 'सध्याची स्थिती',
    },
    'clear_and_warm': {
      'en': 'Clear and Warm',
      'hi': 'साफ़ और गर्म',
      'mr': 'स्वच्छ आणि उबदार',
    },
    'weather_current_details': {
      'en':
          'Humidity: 45% • UV Index: 8 (Very High)\nVisibility: 7 km • Pressure: 1012 hPa',
      'hi':
          'आर्द्रता: 45% • UV सूचकांक: 8 (बहुत अधिक)\nदृश्यता: 7 km • दबाव: 1012 hPa',
      'mr':
          'आर्द्रता: 45% • UV निर्देशांक: 8 (खूप जास्त)\nदृश्यता: 7 km • दाब: 1012 hPa',
    },
    'soil_temp': {
      'en': 'Soil Temp',
      'hi': 'मिट्टी तापमान',
      'mr': 'माती तापमान',
    },
    'solar_rad': {
      'en': 'Solar Rad',
      'hi': 'सौर विकिरण',
      'mr': 'सौर किरणोत्सर्ग',
    },
    'disease_risk': {'en': 'Disease risk', 'hi': 'रोग जोखिम', 'mr': 'रोग धोका'},
    'crop_stage': {'en': 'Crop stage', 'hi': 'फसल अवस्था', 'mr': 'पीक अवस्था'},
    'light_irrigation_sunset': {
      'en': 'Light irrigation after sunset',
      'hi': 'सूर्यास्त के बाद हल्की सिंचाई',
      'mr': 'सूर्यास्तानंतर हलके सिंचन',
    },
    'soil_profile_moisture_dip': {
      'en': 'Soil profile suggests top 10cm moisture dip.',
      'hi': 'मिट्टी प्रोफ़ाइल ऊपर के 10cm में नमी घटने का संकेत देती है।',
      'mr': 'माती प्रोफाइल वरच्या 10cm मध्ये ओलावा घट दाखवते.',
    },
    'monitor_leaf_spot_evening': {
      'en': 'Monitor leaf spot by evening',
      'hi': 'शाम तक पत्ती धब्बे देखें',
      'mr': 'संध्याकाळपर्यंत पानांवरील डाग तपासा',
    },
    'humidity_above_70': {
      'en': 'Humidity above 70% after 2-3 days.',
      'hi': '2-3 दिनों के बाद आर्द्रता 70% से ऊपर।',
      'mr': '2-3 दिवसांनंतर आर्द्रता 70% पेक्षा जास्त.',
    },
    'hold_watering_window': {
      'en': 'Hold watering window',
      'hi': 'पानी देने का समय रोकें',
      'mr': 'पाणी देण्याची वेळ थांबवा',
    },
    'grain_filling_avoid_stress': {
      'en': 'Field is in grain-filling window, avoid water stress.',
      'hi': 'खेत दाना भरने की अवस्था में है, पानी तनाव से बचाएँ।',
      'mr': 'शेत दाणा भरण्याच्या अवस्थेत आहे, पाण्याचा ताण टाळा.',
    },
    'good': {'en': 'Good', 'hi': 'अच्छा', 'mr': 'चांगले'},
    'watch': {'en': 'Watch', 'hi': 'नज़र रखें', 'mr': 'लक्ष ठेवा'},
    'field_tip_cover_harvest': {
      'en': 'Cover harvested produce if rain alert crosses 35%.',
      'hi': 'बारिश चेतावनी 35% से ऊपर हो तो कटाई उत्पाद ढकें।',
      'mr': 'पाऊस इशारा 35% पेक्षा जास्त असल्यास कापलेला माल झाका.',
    },
    'field_tip_shift_spray': {
      'en': 'Shift heavy spray work to morning or late evening.',
      'hi': 'भारी छिड़काव सुबह या देर शाम करें।',
      'mr': 'जड फवारणी सकाळी किंवा उशिरा संध्याकाळी करा.',
    },
    'field_tip_low_volume_irrigation': {
      'en': 'Keep irrigation low-volume and frequent during warm dry spell.',
      'hi': 'गर्म सूखे समय में कम मात्रा और बार-बार सिंचाई रखें।',
      'mr': 'उबदार कोरड्या काळात कमी प्रमाणात व वारंवार सिंचन करा.',
    },

    // ── Weather ──
    'weather_forecast': {
      'en': 'Weather Forecast',
      'hi': 'मौसम पूर्वानुमान',
      'mr': 'हवामान अंदाज',
    },
    'weather': {'en': 'Weather', 'hi': 'मौसम', 'mr': 'हवामान'},
    'live_weather_location_required': {
      'en':
          'This farm needs a saved boundary or GPS location before live weather can be shown accurately.',
      'hi':
          'लाइव मौसम सही दिखाने के लिए इस खेत की सीमा या GPS स्थान सेव होना जरूरी है।',
      'mr':
          'थेट हवामान अचूक दाखवण्यासाठी या शेताची सीमा किंवा GPS ठिकाण सेव्ह असणे आवश्यक आहे.',
    },
    'live_weather_refreshing': {
      'en':
          'Live weather is refreshing for this farm. Pull down or tap refresh to try again.',
      'hi':
          'इस खेत का लाइव मौसम रीफ्रेश हो रहा है। फिर कोशिश करने के लिए नीचे खींचें या रीफ्रेश दबाएँ।',
      'mr':
          'या शेताचे थेट हवामान रीफ्रेश होत आहे. पुन्हा प्रयत्न करण्यासाठी खाली खेचा किंवा रीफ्रेश दाबा.',
    },
    'live_weather_unavailable': {
      'en': 'Live weather is not available.',
      'hi': 'लाइव मौसम उपलब्ध नहीं है।',
      'mr': 'थेट हवामान उपलब्ध नाही.',
    },
    'water_stress': {
      'en': 'Water stress',
      'hi': 'पानी तनाव',
      'mr': 'पाण्याचा ताण',
    },
    'next_24_hours': {
      'en': 'Next 24 hours',
      'hi': 'अगले 24 घंटे',
      'mr': 'पुढील 24 तास',
    },
    'rain_amount_value': {
      'en': '{amount} rain',
      'hi': '{amount} बारिश',
      'mr': '{amount} पाऊस',
    },
    'farm_weather_advice': {
      'en': 'Farm weather advice',
      'hi': 'खेत मौसम सलाह',
      'mr': 'शेत हवामान सल्ला',
    },
    'scout_selected_crop_forecast': {
      'en': 'Scout the selected crop using the latest forecast.',
      'hi': 'नवीनतम पूर्वानुमान के अनुसार चुनी गई फसल की जांच करें।',
      'mr': 'नवीन अंदाजानुसार निवडलेल्या पिकाची तपासणी करा.',
    },
    'weather_rec_irrigate_cool': {
      'en': 'Irrigate in a cool window and inspect dry patches.',
      'hi': 'ठंडे समय में सिंचाई करें और सूखे पैच देखें।',
      'mr': 'थंड्या वेळेत सिंचन करा आणि कोरडे पट्टे तपासा.',
    },
    'weather_rec_monitor_moisture': {
      'en': 'Monitor soil moisture and prepare irrigation if rain misses.',
      'hi': 'मिट्टी की नमी देखें और बारिश न हो तो सिंचाई तैयार रखें।',
      'mr': 'मातीचा ओलावा पाहा आणि पाऊस चुकल्यास सिंचन तयार ठेवा.',
    },
    'weather_rec_controlled': {
      'en': 'Water stress is currently controlled.',
      'hi': 'अभी पानी तनाव नियंत्रण में है।',
      'mr': 'सध्या पाण्याचा ताण नियंत्रणात आहे.',
    },
    'weather_rec_check_root_zone': {
      'en': 'Check soil moisture and irrigate if the root zone is dry.',
      'hi': 'मिट्टी की नमी जांचें और जड़ क्षेत्र सूखा हो तो सिंचाई करें।',
      'mr': 'मातीचा ओलावा तपासा आणि मुळांचा भाग कोरडा असल्यास सिंचन करा.',
    },
    'weather_rec_monitor_before_irrigation': {
      'en': 'Monitor soil moisture before the next irrigation decision.',
      'hi': 'अगले सिंचाई निर्णय से पहले मिट्टी की नमी देखें।',
      'mr': 'पुढील सिंचन निर्णयापूर्वी मातीचा ओलावा तपासा.',
    },
    'weather_rec_low_observation': {
      'en': 'Water stress is low; continue normal field observation.',
      'hi': 'पानी तनाव कम है; सामान्य खेत निरीक्षण जारी रखें।',
      'mr': 'पाण्याचा ताण कमी आहे; नियमित शेत निरीक्षण सुरू ठेवा.',
    },
    'weather_summary_supportive': {
      'en': 'Weather is supportive for current crop growth.',
      'hi': 'मौसम वर्तमान फसल बढ़वार के लिए सहायक है।',
      'mr': 'हवामान सध्याच्या पीक वाढीसाठी अनुकूल आहे.',
    },
    'weather_summary_attention': {
      'en': 'Weather needs scouting attention this week.',
      'hi': 'इस सप्ताह मौसम के कारण खेत जांच पर ध्यान दें।',
      'mr': 'या आठवड्यात हवामानामुळे शेत तपासणीवर लक्ष द्या.',
    },
    'weather_summary_stress_elevated': {
      'en': 'Weather stress is elevated; prioritize field inspection.',
      'hi': 'मौसम तनाव अधिक है; खेत निरीक्षण को प्राथमिकता दें।',
      'mr': 'हवामान ताण वाढला आहे; शेत तपासणीला प्राधान्य द्या.',
    },
    'weather_summary_wet_disease': {
      'en': 'Wet weather can raise disease risk. Scout leaves and panicles.',
      'hi':
          'गीला मौसम रोग जोखिम बढ़ा सकता है। पत्तियों और बालियों की जांच करें।',
      'mr': 'ओले हवामान रोग धोका वाढवू शकते. पाने आणि कणसे तपासा.',
    },
    'weather_summary_heat_dry': {
      'en': 'Heat and dry weather can stress the crop. Check moisture.',
      'hi': 'गर्मी और सूखा मौसम फसल पर तनाव डाल सकता है। नमी जांचें।',
      'mr': 'उष्ण आणि कोरडे हवामान पिकावर ताण आणू शकते. ओलावा तपासा.',
    },
    'weather_summary_manageable': {
      'en': 'Weather is manageable. Continue routine crop scouting.',
      'hi': 'मौसम संभालने योग्य है। नियमित फसल जांच जारी रखें।',
      'mr': 'हवामान नियंत्रणात आहे. नियमित पीक तपासणी सुरू ठेवा.',
    },
    'weather_next_check_midday': {
      'en': 'Check water stress before midday and irrigate if soil is dry.',
      'hi': 'दोपहर से पहले पानी तनाव देखें और मिट्टी सूखी हो तो सिंचाई करें।',
      'mr': 'दुपारपूर्वी पाण्याचा ताण तपासा आणि माती कोरडी असल्यास सिंचन करा.',
    },
    'weather_next_scout_round': {
      'en': 'Scout the crop during the next field round.',
      'hi': 'अगले खेत चक्कर में फसल की जांच करें।',
      'mr': 'पुढील शेत फेरीत पिकाची तपासणी करा.',
    },
    'weather_sync_needed': {
      'en': 'Weather sync needed',
      'hi': 'मौसम सिंक जरूरी',
      'mr': 'हवामान सिंक आवश्यक',
    },
    'live_weather_failed_fallback': {
      'en':
          'Live weather failed. Showing the last saved disease/weather context.',
      'hi': 'लाइव मौसम नहीं मिला। आखिरी सेव रोग/मौसम संदर्भ दिखाया जा रहा है।',
      'mr':
          'थेट हवामान मिळाले नाही. शेवटचा सेव्ह केलेला रोग/हवामान संदर्भ दाखवत आहे.',
    },
    'loading_live_farm_weather': {
      'en': 'Loading live farm weather...',
      'hi': 'लाइव खेत मौसम लोड हो रहा है...',
      'mr': 'थेट शेत हवामान लोड होत आहे...',
    },
    'hourly_temp_trend': {
      'en': 'Hourly Temperature Trend',
      'hi': 'घंटेवार तापमान रुझान',
      'mr': 'तासावार तापमान कल',
    },
    'hourly_temp_sub': {
      'en': 'Expected daily variations in temperature over the next 12 hours.',
      'hi': 'अगले 12 घंटों में तापमान में अपेक्षित बदलाव।',
      'mr': 'पुढील 12 तासांत तापमानातील अपेक्षित बदल.',
    },
    'condition': {'en': 'Condition', 'hi': 'स्थिति', 'mr': 'स्थिती'},
    'wind': {'en': 'Wind', 'hi': 'हवा', 'mr': 'वारा'},
    'rain_prob': {
      'en': 'Rain Prob.',
      'hi': 'वर्षा संभावना',
      'mr': 'पाऊस शक्यता',
    },
    'irrigation': {'en': 'Irrigation', 'hi': 'सिंचाई', 'mr': 'सिंचन'},
    'pest_risk': {'en': 'Pest risk', 'hi': 'कीट जोखिम', 'mr': 'कीड धोका'},
    'sync': {'en': 'Sync', 'hi': 'सिंक', 'mr': 'सिंक'},
    'ndvi': {'en': 'NDVI', 'hi': 'वनस्पति सूचकांक', 'mr': 'वनस्पती निर्देशांक'},
    'ndvi_explanation': {
      'en':
          'NDVI ranges from 0.0 to 1.0. Higher values (0.6 - 0.8) indicate healthy green vegetative growth.',
      'hi':
          'वनस्पति सूचकांक 0.0 से 1.0 तक होता है। अधिक मान (0.6 - 0.8) स्वस्थ हरी बढ़वार दिखाते हैं।',
      'mr':
          'वनस्पती निर्देशांक 0.0 ते 1.0 पर्यंत असतो. जास्त मूल्ये (0.6 - 0.8) निरोगी हिरवी वाढ दाखवतात.',
    },
    'predicted_yield': {
      'en': 'Predicted Yield',
      'hi': 'अनुमानित उपज',
      'mr': 'अंदाजित उत्पादन',
    },
    'tonnes_per_hectare': {
      'en': 't/ha',
      'hi': 'टन/हेक्टेयर',
      'mr': 'टन/हेक्टर',
    },
    'based_on_ndvi': {
      'en': 'Based on NDVI: {value}',
      'hi': 'वनस्पति सूचकांक के आधार पर: {value}',
      'mr': 'वनस्पती निर्देशांकावर आधारित: {value}',
    },
    'vegetation_index_history': {
      'en': 'Vegetation Index History',
      'hi': 'वनस्पति सूचकांक इतिहास',
      'mr': 'वनस्पती निर्देशांक इतिहास',
    },
    'evi': {
      'en': 'EVI',
      'hi': 'उन्नत वनस्पति सूचकांक',
      'mr': 'सुधारित वनस्पती निर्देशांक',
    },
    'recommendation': {'en': 'Recommendation', 'hi': 'सिफारिश', 'mr': 'शिफारस'},
    'ndvi_recommendation_good': {
      'en':
          'Crop health is excellent. Current NDVI levels indicate optimal canopy coverage. Maintain current irrigation and fertilisation practices.',
      'hi':
          'फसल स्वास्थ्य उत्कृष्ट है। वर्तमान वनस्पति सूचकांक अच्छी छतरी बढ़वार दिखाता है। मौजूदा सिंचाई और खाद प्रबंधन जारी रखें।',
      'mr':
          'पिकाचे आरोग्य उत्कृष्ट आहे. सध्याचा वनस्पती निर्देशांक चांगले आच्छादन दाखवतो. सध्याचे सिंचन आणि खत व्यवस्थापन सुरू ठेवा.',
    },
    'ndvi_recommendation_moderate': {
      'en':
          'Moderate crop health detected. Consider checking irrigation schedules and applying a balanced fertiliser. Monitor weekly for changes.',
      'hi':
          'फसल स्वास्थ्य मध्यम दिख रहा है। सिंचाई समय और संतुलित खाद की जांच करें। बदलाव के लिए हर सप्ताह निगरानी करें।',
      'mr':
          'पिकाचे आरोग्य मध्यम दिसत आहे. सिंचन वेळापत्रक आणि संतुलित खत तपासा. बदलांसाठी दर आठवड्याला निरीक्षण करा.',
    },
    'ndvi_recommendation_low': {
      'en':
          'Low vegetation index detected. Immediate field inspection recommended. Check for water stress, pest activity, or nutrient deficiency.',
      'hi':
          'वनस्पति सूचकांक कम दिख रहा है। तुरंत खेत निरीक्षण करें। पानी की कमी, कीट गतिविधि या पोषक तत्व की कमी जांचें।',
      'mr':
          'वनस्पती निर्देशांक कमी दिसत आहे. त्वरित शेत पाहणी करा. पाण्याचा ताण, कीड किंवा अन्नद्रव्य कमतरता तपासा.',
    },
    'bag_plan_action': {
      'en': 'Create bag plan and next action quickly',
      'hi': 'बैग योजना और अगली कार्रवाई जल्दी बनाएं',
      'mr': 'पोती नियोजन आणि पुढील कृती त्वरित करा',
    },
    'leaf_spot_moderate': {
      'en': 'Leaf spot moderate',
      'hi': 'पत्ती धब्बे मध्यम',
      'mr': 'पानावरील डाग मध्यम',
    },
    'grade_a_quality': {
      'en': 'Grade A quality',
      'hi': 'ग्रेड A गुणवत्ता',
      'mr': 'ग्रेड A गुणवत्ता',
    },
    'scout_zone_desc': {
      'en':
          'Satellite screening flags this spot as a possible disease patch. It is a pre-screen, not a confirmed diagnosis — walk there and check the plants before any treatment.',
      'hi':
          'सैटेलाइट स्क्रीनिंग इस स्थान को संभावित रोग क्षेत्र के रूप में चिन्हित करती है। यह एक पूर्व-स्क्रीन है, पुष्टि नहीं — उपचार से पहले वहां जाकर पौधों की जांच करें।',
      'mr':
          'उपग्रह स्क्रीनिंग या ठिकाणास संभाव्य रोग क्षेत्र म्हणून मार्क करते. हे प्राथमिक निरीक्षण आहे, पूर्ण निदान नाही — उपचार करण्यापूर्वी तेथे जाऊन रोपांची पाहणी करा.',
    },
    'crop_stress_desc': {
      'en':
          'This spot looks stressed by water or heat rather than disease. Walk there to check soil moisture and plant condition.',
      'hi':
          'यह स्थान रोग के बजाय पानी या गर्मी के तनाव से ग्रस्त लग रहा है। मिट्टी की नमी और पौधों की स्थिति जांचने के लिए वहां जाएं।',
      'mr':
          'हे ठिकाण रोगाऐवजी पाणी किंवा उष्णतेच्या ताणामुळे प्रभावित वाटत आहे. मातीचा ओलावा आणि रोपांची स्थिती तपासण्यासाठी तेथे जा.',
    },
    'field_center_dist': {
      'en': '≈ {dist} m from the field centre',
      'hi': '≈ खेत के केंद्र से {dist} मीटर',
      'mr': '≈ शेत केंद्रापासून {dist} मीटर',
    },
    'ai_guidance_spot': {
      'en': 'AI guidance for this spot',
      'hi': 'इस स्थान के लिए AI मार्गदर्शन',
      'mr': 'या ठिकाणासाठी AI मार्गदर्शन',
    },
    'asking_advisor': {
      'en': 'Asking the farm advisor...',
      'hi': 'खेत सलाहकार से पूछ रहे हैं...',
      'mr': 'शेत सल्लागाराला विचारत आहे...',
    },
    'confirm_photo_title': {
      'en': 'Confirm with a photo (optional)',
      'hi': 'फोटो के साथ पुष्टि करें (वैकल्पिक)',
      'mr': 'फोटोसह निश्चित करा (पर्यायी)',
    },
    'confirm_photo_desc': {
      'en':
          'When you reach the spot, photograph the affected leaves for an AI diagnosis with more specific guidance.',
      'hi':
          'जब आप उस स्थान पर पहुंचें, तो अधिक स्पष्ट मार्गदर्शन के लिए प्रभावित पत्तियों की फोटो लें।',
      'mr':
          'जेव्हा तुम्ही त्या ठिकाणी पोहचाल, तेव्हा अधिक स्पष्ट मार्गदर्शनासाठी प्रभावित पानांचा फोटो घ्या.',
    },
    'uploading_diagnosing': {
      'en': 'Uploading photo and diagnosing...',
      'hi': 'फोटो अपलोड और जांच चल रही है...',
      'mr': 'फोटो अपलोड आणि तपासणी चालू आहे...',
    },
    'not_screened_yet': {
      'en': 'Not screened yet',
      'hi': 'अभी जांच नहीं हुई',
      'mr': 'अजून तपासणी झालेली नाही',
    },
    'last_screen': {
      'en': 'Last screen: {date}',
      'hi': 'अंतिम जांच: {date}',
      'mr': 'शेवटची तपासणी: {date}',
    },
    'farm_refreshed': {
      'en': 'Farm refreshed',
      'hi': 'खेत रीफ्रेश हुआ',
      'mr': 'शेत रीफ्रेश झाले',
    },
    'disease_scan_saved': {
      'en': 'Disease scan saved',
      'hi': 'रोग स्कैन सेव हुआ',
      'mr': 'रोग स्कॅन जतन झाले',
    },
    'issue_cells_available': {
      'en': '{farm}: {count} issue {label} available.',
      'hi': '{farm}: {count} समस्या {label} उपलब्ध।',
      'mr': '{farm}: {count} समस्या {label} उपलब्ध.',
    },
    'cell': {'en': 'cell', 'hi': 'सेल', 'mr': 'सेल'},
    'cells': {'en': 'cells', 'hi': 'सेल', 'mr': 'सेल'},
    'advisor_refresh_failed_preserved': {
      'en': 'Advisor refresh failed, but disease scan is preserved.',
      'hi': 'सलाहकार रीफ्रेश विफल, लेकिन रोग स्कैन सुरक्षित है।',
      'mr': 'सल्लागार रीफ्रेश अयशस्वी, पण रोग स्कॅन सुरक्षित आहे.',
    },
    'status_updated': {
      'en': 'Status updated',
      'hi': 'स्थिति अपडेट हुई',
      'mr': 'स्थिती अपडेट झाली',
    },
    'status_saved_sync_pending': {
      'en':
          'Status saved for this farm. Refresh if the latest details do not appear.',
      'hi': 'इस खेत की स्थिति सेव हो गई। नई जानकारी न दिखे तो रीफ्रेश करें।',
      'mr': 'या शेताची स्थिती जतन झाली. नवीन माहिती दिसली नाही तर रीफ्रेश करा.',
    },
    'status_saved_sync_pending_body': {
      'en':
          'Could not save this farm status. Check the farmer login and internet, then try again.',
      'hi':
          'यह खेत स्थिति सेव नहीं हो सकी। किसान लॉगिन और इंटरनेट जांचकर फिर कोशिश करें।',
      'mr':
          'ही शेत स्थिती जतन झाली नाही. शेतकरी login आणि internet तपासून पुन्हा प्रयत्न करा.',
    },
    'submit_status': {
      'en': 'Submit status',
      'hi': 'स्थिति जमा करें',
      'mr': 'स्थिती सबमिट करा',
    },
    'stage_needs_field_photo': {
      'en': '{stage} needs a field photo. Add one before submitting status.',
      'hi':
          '{stage} के लिए खेत फोटो चाहिए। स्थिति जमा करने से पहले फोटो जोड़ें।',
      'mr': '{stage} साठी शेत फोटो हवा. स्थिती सबमिट करण्यापूर्वी फोटो जोडा.',
    },
    'write_farm_update_before_sending': {
      'en': 'Write your farm update before sending.',
      'hi': 'भेजने से पहले खेत अपडेट लिखें।',
      'mr': 'पाठवण्यापूर्वी शेत अपडेट लिहा.',
    },
    'status_note_saved_for_crop': {
      'en': 'Saved for {crop} {variety}. Add another note or submit status.',
      'hi':
          '{crop} {variety} के लिए सेव हुआ। दूसरी नोट जोड़ें या स्थिति जमा करें।',
      'mr':
          '{crop} {variety} साठी जतन झाले. दुसरी नोंद जोडा किंवा स्थिती सबमिट करा.',
    },
    'add_crop_status_before_submit': {
      'en': 'Add a crop status note before submitting.',
      'hi': 'जमा करने से पहले फसल स्थिति नोट जोड़ें।',
      'mr': 'सबमिट करण्यापूर्वी पीक स्थिती नोंद जोडा.',
    },
    'attach_photo_before_stage_submit': {
      'en': 'Attach photo before submitting for this stage.',
      'hi': 'इस अवस्था के लिए जमा करने से पहले फोटो जोड़ें।',
      'mr': 'या अवस्थेसाठी सबमिट करण्यापूर्वी फोटो जोडा.',
    },
    'stage_question_for_crop': {
      'en': 'For {crop} {variety}, {question}',
      'hi': '{crop} {variety} के लिए, {question}',
      'mr': '{crop} {variety} साठी, {question}',
    },
    'quick_growth_normal_for_crop': {
      'en': '{crop} {variety} growth looks normal',
      'hi': '{crop} {variety} की वृद्धि सामान्य दिख रही है',
      'mr': '{crop} {variety} वाढ सामान्य दिसत आहे',
    },
    'quick_irrigation_done_for_crop': {
      'en': 'Irrigation done for {crop} today',
      'hi': 'आज {crop} के लिए सिंचाई हुई',
      'mr': 'आज {crop} साठी सिंचन झाले',
    },
    'quick_reinspection_for_crop': {
      'en': 'Need re-inspection for {crop} field',
      'hi': '{crop} खेत की फिर जांच चाहिए',
      'mr': '{crop} शेताची पुन्हा तपासणी हवी',
    },
    'quick_unexpected_yellowing': {
      'en': 'Unexpected yellowing or spots seen',
      'hi': 'अनपेक्षित पीलापन या धब्बे दिखे',
      'mr': 'अनपेक्षित पिवळेपणा किंवा डाग दिसले',
    },
    'quick_check_disease_spots': {
      'en': 'Check {crop} {variety} disease spots',
      'hi': '{crop} {variety} रोग धब्बे जांचें',
      'mr': '{crop} {variety} रोग डाग तपासा',
    },
    'status_chat_hint': {
      'en': 'Type crop status, disease spot, water or growth note...',
      'hi': 'फसल स्थिति, रोग धब्बा, पानी या वृद्धि नोट लिखें...',
      'mr': 'पीक स्थिती, रोग डाग, पाणी किंवा वाढ नोंद लिहा...',
    },
    'attach_photo': {
      'en': 'Attach photo',
      'hi': 'फोटो जोड़ें',
      'mr': 'फोटो जोडा',
    },
    'status_reply_germination_healthy': {
      'en': 'Germination is healthy',
      'hi': 'अंकुरण स्वस्थ है',
      'mr': 'अंकुरण निरोगी आहे',
    },
    'status_reply_moisture_stress': {
      'en': 'Some moisture stress',
      'hi': 'थोड़ा नमी तनाव',
      'mr': 'थोडा ओलावा ताण',
    },
    'status_reply_need_irrigation_today': {
      'en': 'Need irrigation today',
      'hi': 'आज सिंचाई चाहिए',
      'mr': 'आज सिंचन हवे',
    },
    'status_reply_need_reinspection': {
      'en': 'Need re-inspection support',
      'hi': 'फिर जांच सहायता चाहिए',
      'mr': 'पुन्हा तपासणी मदत हवी',
    },
    'status_reply_patchy_stands': {
      'en': 'Patchy stands in corner',
      'hi': 'कोने में पौधे छिटपुट हैं',
      'mr': 'कोपऱ्यात उगवण विरळ आहे',
    },
    'status_reply_good_germination': {
      'en': 'Good germination overall',
      'hi': 'कुल मिलाकर अच्छा अंकुरण',
      'mr': 'एकूण अंकुरण चांगले',
    },
    'status_reply_need_replanting': {
      'en': 'Need replanting help',
      'hi': 'फिर रोपण सहायता चाहिए',
      'mr': 'पुन्हा लागवड मदत हवी',
    },
    'status_reply_irrigation_done': {
      'en': 'Irrigation done',
      'hi': 'सिंचाई हुई',
      'mr': 'सिंचन झाले',
    },
    'status_reply_growth_normal': {
      'en': 'Growth is normal',
      'hi': 'वृद्धि सामान्य है',
      'mr': 'वाढ सामान्य आहे',
    },
    'status_reply_weeds_observed': {
      'en': 'Some weeds observed',
      'hi': 'कुछ खरपतवार दिखे',
      'mr': 'काही तण दिसले',
    },
    'status_reply_leaf_pale': {
      'en': 'Leaf colour looks pale',
      'hi': 'पत्तों का रंग हल्का दिखता है',
      'mr': 'पानांचा रंग फिका दिसतो',
    },
    'status_reply_watering_done': {
      'en': 'Watering done',
      'hi': 'पानी दिया गया',
      'mr': 'पाणी दिले',
    },
    'status_reply_flowering_good': {
      'en': 'Flowering is good',
      'hi': 'फूल आना अच्छा है',
      'mr': 'फुलोरा चांगला आहे',
    },
    'status_reply_pollen_drop_seen': {
      'en': 'Pollen drop seen',
      'hi': 'पराग गिरना दिखा',
      'mr': 'पराग गळताना दिसला',
    },
    'status_reply_need_moisture_topup': {
      'en': 'Need moisture top-up',
      'hi': 'नमी बढ़ाने की जरूरत',
      'mr': 'ओलावा वाढवण्याची गरज',
    },
    'status_reply_insect_attack': {
      'en': 'Any insect attack appears',
      'hi': 'कीट हमला दिख रहा है',
      'mr': 'किडीचा प्रादुर्भाव दिसतो',
    },
    'status_reply_grains_filling': {
      'en': 'Grains are filling well',
      'hi': 'दाने अच्छे भर रहे हैं',
      'mr': 'दाणे चांगले भरत आहेत',
    },
    'status_reply_flower_drop_seen': {
      'en': 'Some flower drop seen',
      'hi': 'कुछ फूल गिरना दिखा',
      'mr': 'काही फुले गळताना दिसली',
    },
    'status_reply_low_moisture': {
      'en': 'Looks low moisture',
      'hi': 'नमी कम लग रही है',
      'mr': 'ओलावा कमी दिसतो',
    },
    'status_reply_need_support_recheck': {
      'en': 'Need support and re-check',
      'hi': 'सहायता और फिर जांच चाहिए',
      'mr': 'मदत आणि पुन्हा तपासणी हवी',
    },
    'status_reply_panicles_developed': {
      'en': 'Panicles are fully developed',
      'hi': 'बालियां पूरी विकसित हैं',
      'mr': 'कणसे पूर्ण विकसित आहेत',
    },
    'status_reply_grain_drying_normal': {
      'en': 'Grain drying is normal',
      'hi': 'दाना सूखना सामान्य है',
      'mr': 'धान्य वाळणे सामान्य आहे',
    },
    'status_reply_need_harvesting_support': {
      'en': 'Need harvesting support',
      'hi': 'कटाई सहायता चाहिए',
      'mr': 'कापणी मदत हवी',
    },
    'status_reply_check_moisture': {
      'en': 'Check moisture content',
      'hi': 'नमी मात्रा जांचें',
      'mr': 'ओलावा तपासा',
    },
    'farm_updated_summary': {
      'en': '{farm} updated: {summary}',
      'hi': '{farm} अपडेट हुआ: {summary}',
      'mr': '{farm} अपडेट झाले: {summary}',
    },
    'notification_pending': {
      'en': 'Notification pending',
      'hi': 'सूचना लंबित',
      'mr': 'सूचना बाकी',
    },
    'notification_service_unavailable': {
      'en':
          'Status saved for {farm}, notification service is temporarily unavailable.',
      'hi': '{farm} के लिए स्थिति सेव हुई, सूचना सेवा अभी उपलब्ध नहीं है।',
      'mr': '{farm} साठी स्थिती जतन केली, सूचना सेवा सध्या उपलब्ध नाही.',
    },
    'notification_panel': {
      'en': 'Notification panel',
      'hi': 'सूचना पैनल',
      'mr': 'सूचना पॅनेल',
    },
    'notification_panel_desc': {
      'en': 'Farm alerts and status updates for this farmer',
      'hi': 'इस किसान के खेत अलर्ट और स्थिति अपडेट',
      'mr': 'या शेतकऱ्याचे शेत अलर्ट आणि स्थिती अपडेट',
    },
    'new_notification': {
      'en': 'New notification',
      'hi': 'नई सूचना',
      'mr': 'नवीन सूचना',
    },
    'no_farmer_notifications': {
      'en': 'No notifications yet',
      'hi': 'अभी कोई सूचना नहीं',
      'mr': 'अजून सूचना नाहीत',
    },
    'no_farmer_notifications_desc': {
      'en': 'Farm updates, alerts, and status messages will appear here.',
      'hi': 'खेत अपडेट, अलर्ट और स्थिति संदेश यहां दिखेंगे।',
      'mr': 'शेत अपडेट, अलर्ट आणि स्थिती संदेश येथे दिसतील.',
    },
    'mark_read': {
      'en': 'Mark read',
      'hi': 'पढ़ा हुआ करें',
      'mr': 'वाचले म्हणून चिन्हांकित करा',
    },
    'notification_sync_failed': {
      'en': 'Could not refresh notifications. Try again.',
      'hi': 'सूचनाएँ रीफ्रेश नहीं हुईं। फिर कोशिश करें।',
      'mr': 'सूचना रीफ्रेश झाल्या नाहीत. पुन्हा प्रयत्न करा.',
    },
    'show_more_notifications': {
      'en': 'Show more notifications',
      'hi': 'और सूचनाएँ दिखाएँ',
      'mr': 'आणखी सूचना दाखवा',
    },
    'farm_status_notification_title': {
      'en': '{farm} status saved',
      'hi': '{farm} की स्थिति सेव हुई',
      'mr': '{farm} स्थिती जतन झाली',
    },
    'farm_status_notification_message': {
      'en': '{stage} update is saved.',
      'hi': '{stage} अपडेट सेव हुआ।',
      'mr': '{stage} अपडेट जतन झाले.',
    },
    'farm_added_notification_title': {
      'en': '{farm} added',
      'hi': '{farm} जोड़ा गया',
      'mr': '{farm} जोडले',
    },
    'farm_added_notification_message': {
      'en': '{farm} is saved and ready.',
      'hi': '{farm} सेव हो गया है और तैयार है।',
      'mr': '{farm} जतन झाले आहे आणि तयार आहे.',
    },
    'diagnose_farm': {
      'en': 'Diagnose {farm}',
      'hi': '{farm} की जांच करें',
      'mr': '{farm} ची तपासणी करा',
    },
    'zone_note_label': {
      'en': 'Zone note (e.g., leaf spot)',
      'hi': 'क्षेत्र नोट (जैसे: पत्ती धब्बा)',
      'mr': 'क्षेत्र नोंद (उदा: पानावरील डाग)',
    },
    'suspected_disease': {
      'en': 'suspected disease',
      'hi': 'संभावित रोग',
      'mr': 'संभाव्य रोग',
    },
    'marked_zones': {
      'en': 'Marked zones',
      'hi': 'चिन्हित क्षेत्र',
      'mr': 'मार्क केलेले भाग',
    },
    'no_disease_zone_title': {
      'en': 'No disease zone',
      'hi': 'कोई रोग क्षेत्र नहीं',
      'mr': 'कोणतेही रोग क्षेत्र नाही',
    },
    'add_disease_marker_before_save': {
      'en': 'Add at least one disease marker before saving.',
      'hi': 'सेव करने से पहले कम से कम एक रोग मार्कर जोड़ें।',
      'mr': 'जतन करण्यापूर्वी किमान एक रोग मार्कर जोडा.',
    },
    'diagnosis_saved': {
      'en': 'Diagnosis saved',
      'hi': 'जांच सेव हुई',
      'mr': 'तपासणी जतन झाली',
    },
    'disease_zones_updated': {
      'en': 'Disease zones updated on map for {farm}',
      'hi': '{farm} के लिए मैप पर रोग क्षेत्र अपडेट हुए',
      'mr': '{farm} साठी नकाशावर रोग क्षेत्र अपडेट झाले',
    },
    'selected_farm': {
      'en': 'Selected farm',
      'hi': 'चुना गया खेत',
      'mr': 'निवडलेले शेत',
    },
    'farm_condition': {
      'en': 'Farm condition',
      'hi': 'खेत की स्थिति',
      'mr': 'शेताची स्थिती',
    },
    'disease_detection': {
      'en': 'Disease detection',
      'hi': 'रोग पहचान',
      'mr': 'रोग ओळख',
    },
    'disease_detection_loading_desc': {
      'en':
          'Checking the latest disease scan and satellite risk cells for this selected farm.',
      'hi':
          'इस चुने गए खेत के लिए नवीनतम रोग स्कैन और सैटेलाइट जोखिम सेल जांचे जा रहे हैं।',
      'mr':
          'या निवडलेल्या शेतासाठी नवीन रोग स्कॅन आणि उपग्रह जोखीम सेल तपासत आहे.',
    },
    'disease_detection_missing_desc': {
      'en':
          'No disease scan is available yet. Open Diagnose to capture a photo or refresh field monitoring.',
      'hi':
          'अभी रोग स्कैन उपलब्ध नहीं है। फोटो लेने या खेत मॉनिटरिंग रीफ्रेश करने के लिए जांच खोलें।',
      'mr':
          'अजून रोग स्कॅन उपलब्ध नाही. फोटो घेण्यासाठी किंवा शेत निरीक्षण रीफ्रेश करण्यासाठी तपासा उघडा.',
    },
    'disease_detection_clear_desc': {
      'en':
          'No strong disease signal is detected in the latest synced scan. Continue normal scouting.',
      'hi':
          'नवीन सिंक स्कैन में मजबूत रोग संकेत नहीं मिला। सामान्य निरीक्षण जारी रखें।',
      'mr':
          'नवीन सिंक स्कॅनमध्ये ठळक रोग संकेत आढळला नाही. नियमित पाहणी सुरू ठेवा.',
    },
    'disease_detection_watch_desc': {
      'en':
          '{disease} signal is present at {risk}. Scout leaves and stems before spraying.',
      'hi':
          '{disease} संकेत {risk} पर है। छिड़काव से पहले पत्ते और तना जांचें।',
      'mr': '{disease} संकेत {risk} आहे. फवारणीपूर्वी पाने आणि खोड तपासा.',
    },
    'disease_detection_high_desc': {
      'en':
          '{disease} risk is {risk}. {cells} high-risk cells need photo confirmation.',
      'hi':
          '{disease} जोखिम {risk} है। {cells} उच्च जोखिम सेल को फोटो से पुष्टि चाहिए।',
      'mr':
          '{disease} धोका {risk} आहे. {cells} उच्च-जोखीम सेलसाठी फोटो पुष्टी हवी.',
    },
    'farm_condition_loading_desc': {
      'en':
          'Analysing the selected farm statistics from the latest synced records.',
      'hi':
          'नवीन सिंक किए गए रिकॉर्ड से चुने गए खेत के आंकड़े जांचे जा रहे हैं।',
      'mr':
          'नवीन सिंक झालेल्या नोंदींमधून निवडलेल्या शेताची आकडेवारी तपासत आहे.',
    },
    'farm_condition_good_desc': {
      'en':
          'Farm condition looks normal. Crop health, water signal, and disease risk are within a manageable range.',
      'hi':
          'खेत की स्थिति सामान्य दिख रही है। फसल स्वास्थ्य, पानी संकेत और रोग जोखिम संभालने योग्य हैं।',
      'mr':
          'शेताची स्थिती सामान्य दिसते. पीक आरोग्य, पाणी संकेत आणि रोग धोका नियंत्रणात आहेत.',
    },
    'farm_condition_watch_desc': {
      'en':
          'Some signals need attention. Check water, leaf colour, weed pressure, and marked risk spots this week.',
      'hi':
          'कुछ संकेतों पर ध्यान देना जरूरी है। इस सप्ताह पानी, पत्तों का रंग, खरपतवार और जोखिम वाले स्थान जांचें।',
      'mr':
          'काही संकेतांकडे लक्ष द्यावे लागेल. या आठवड्यात पाणी, पानांचा रंग, तण आणि धोक्याचे ठिकाण तपासा.',
    },
    'farm_condition_high_desc': {
      'en':
          'High stress is visible in the selected farm data. Inspect the risk area and record a photo diagnosis before spraying.',
      'hi':
          'चुने गए खेत के डेटा में अधिक तनाव दिख रहा है। छिड़काव से पहले जोखिम क्षेत्र देखें और फोटो जांच करें।',
      'mr':
          'निवडलेल्या शेताच्या डेटामध्ये जास्त ताण दिसतो. फवारणीपूर्वी धोक्याचे ठिकाण पाहा आणि फोटो तपासणी करा.',
    },
    'farm_action_good': {
      'en':
          'Maintain the current irrigation interval, continue weekly scouting, and keep farm records updated.',
      'hi':
          'मौजूदा सिंचाई अंतर बनाए रखें, साप्ताहिक निरीक्षण करें और खेत रिकॉर्ड अपडेट रखें।',
      'mr':
          'सध्याचे सिंचन अंतर ठेवा, आठवड्याला पाहणी करा आणि शेत नोंदी अपडेट ठेवा.',
    },
    'farm_action_watch': {
      'en':
          'Walk the field, compare weak patches with healthy rows, and refresh farm analysis after the next observation.',
      'hi':
          'खेत में चलकर कमजोर हिस्सों की स्वस्थ कतारों से तुलना करें और अगले निरीक्षण के बाद विश्लेषण रीफ्रेश करें।',
      'mr':
          'शेतात फेरफटका मारून कमजोर भागांची निरोगी ओळींशी तुलना करा आणि पुढील पाहणीनंतर विश्लेषण रीफ्रेश करा.',
    },
    'farm_action_water': {
      'en':
          'Check soil moisture near the root zone and irrigate lightly if the top soil is dry.',
      'hi':
          'जड़ क्षेत्र के पास मिट्टी की नमी जांचें और ऊपरी मिट्टी सूखी हो तो हल्की सिंचाई करें।',
      'mr':
          'मुळांच्या भागातील मातीची ओल तपासा आणि वरची माती कोरडी असल्यास हलके सिंचन करा.',
    },
    'farm_action_high': {
      'en':
          'Visit the marked risk spot, capture a clear leaf photo, and confirm the issue before chemical treatment.',
      'hi':
          'चिह्नित जोखिम स्थान पर जाएं, साफ पत्ती फोटो लें और रासायनिक उपचार से पहले समस्या पक्की करें।',
      'mr':
          'मार्क केलेल्या धोक्याच्या ठिकाणी जा, स्पष्ट पानाचा फोटो घ्या आणि रासायनिक उपचारापूर्वी समस्या निश्चित करा.',
    },
    'active_farm_context_desc': {
      'en':
          'Weather, market, news, schemes and history open with this active farm context.',
      'hi':
          'मौसम, बाजार, समाचार, योजनाएं और इतिहास इसी सक्रिय खेत संदर्भ में खुलेंगे।',
      'mr':
          'हवामान, बाजार, बातम्या, योजना आणि इतिहास या सक्रिय शेत संदर्भात उघडतील.',
    },
    'satellite_overview': {
      'en': 'Satellite Overview',
      'hi': 'सैटेलाइट सारांश',
      'mr': 'उपग्रह सारांश',
    },
    'no_satellite_data': {
      'en': 'No satellite index data available yet.',
      'hi': 'अभी कोई सैटेलाइट इंडेक्स डेटा उपलब्ध नहीं है।',
      'mr': 'अजून कोणताही उपग्रह इंडेक्स डेटा उपलब्ध नाही.',
    },
    'refreshing': {
      'en': 'Refreshing...',
      'hi': 'रीफ्रेश हो रहा है...',
      'mr': 'रीफ्रेश होत आहे...',
    },
    'refresh_farm': {
      'en': 'Refresh farm',
      'hi': 'खेत रीफ्रेश करें',
      'mr': 'शेत रीफ्रेश करा',
    },
    'refresh_risk': {
      'en': 'Refresh risk',
      'hi': 'जोखिम रीफ्रेश',
      'mr': 'धोका रीफ्रेश',
    },
    'next_actions': {
      'en': 'Next actions',
      'hi': 'अगली कार्रवाई',
      'mr': 'पुढील कृती',
    },
    'last_screen_value': {
      'en': 'Last screen: {value}',
      'hi': 'अंतिम जांच: {value}',
      'mr': 'शेवटची तपासणी: {value}',
    },
    'seven_days_range': {
      'en': 'Within {start}–{end} days',
      'hi': '{start}–{end} दिनों के भीतर',
      'mr': '{start}–{end} दिवसांत',
    },
    'bags_range': {
      'en': '{start}–{end} bags',
      'hi': '{start}–{end} बोरी',
      'mr': '{start}–{end} पोती',
    },
    'map_tap_guidance': {
      'en': 'Tap a spot on the map to see the issue and get guidance.',
      'hi':
          'समस्या देखने और मार्गदर्शन पाने के लिए मैप पर किसी स्थान को टैप करें।',
      'mr':
          'समस्या पाहण्यासाठी आणि मार्गदर्शन मिळवण्यासाठी नकाशावरील ठिकाणावर टॅप करा.',
    },
    'field_notes': {'en': 'Field notes', 'hi': 'खेत नोट्स', 'mr': 'शेत नोंदी'},
    'field_notes_desc': {
      'en':
          'Disease checks, status updates and farmer observations will sync into this history screen.',
      'hi':
          'रोग जांच, स्थिति अपडेट और किसान के अवलोकन इस इतिहास स्क्रीन में सिंक होंगे।',
      'mr':
          'रोग तपासणी, स्थिती अपडेट आणि शेतकऱ्याची निरीक्षणे या इतिहास स्क्रीनमध्ये सिंक होतील.',
    },
    'harvest_lots_sync_desc': {
      'en':
          'When grading and bagging are completed, harvest lots for this selected farm will appear in the timeline.',
      'hi':
          'ग्रेडिंग और बैगिंग पूरी होने पर, इस चुने हुए खेत के कटाई लॉट टाइमलाइन में दिखेंगे।',
      'mr':
          'ग्रेडिंग आणि बॅगिंग पूर्ण झाल्यावर, या निवडलेल्या शेताचे कापणी लॉट टाइमलाइनमध्ये दिसतील.',
    },
    'satellite_trend_desc': {
      'en':
          'Satellite NDVI, moisture and vegetation trend cards will appear after the remote farm feed returns data.',
      'hi':
          'रिमोट फार्म फीड से डेटा मिलने के बाद उपग्रह वनस्पति सूचकांक, नमी और वनस्पति रुझान कार्ड दिखेंगे।',
      'mr':
          'रिमोट फार्म फीडमधून डेटा मिळाल्यावर उपग्रह वनस्पती निर्देशांक, ओलावा आणि वनस्पती कल कार्ड दिसतील.',
    },
    'farm_overview': {
      'en': 'Farm Overview',
      'hi': 'खेत सारांश',
      'mr': 'शेत सारांश',
    },
    'details': {'en': 'Details', 'hi': 'विवरण', 'mr': 'तपशील'},
    'apmc_bulletin_title': {
      'en': 'APMC Market Bulletin',
      'hi': 'मंडी भाव बुलेटिन',
      'mr': 'बाजार समिती भाव बुलेटिन',
    },
    'apmc_bulletin_subtitle': {
      'en': 'Local mandi signals for today',
      'hi': 'आज के स्थानीय मंडी संकेत',
      'mr': 'आजचे स्थानिक बाजार समिती संकेत',
    },
    'apmc_bulletin_1': {
      'en': 'Finger millet demand is steady in nearby APMC markets.',
      'hi': 'पास की मंडियों में रागी की मांग स्थिर है।',
      'mr': 'जवळपासच्या बाजार समित्यांमध्ये नाचणीची मागणी स्थिर आहे.',
    },
    'apmc_bulletin_2': {
      'en': 'Grade and moisture checks improve selling price confidence.',
      'hi': 'ग्रेड और नमी की जांच से बिक्री मूल्य का भरोसा बढ़ता है।',
      'mr': 'ग्रेड आणि ओलावा तपासणीमुळे विक्री दराचा आत्मविश्वास वाढतो.',
    },
    'apmc_bulletin_3': {
      'en': 'Tap to open lot-wise APMC rates and listing options.',
      'hi': 'लॉट-वार मंडी भाव और लिस्टिंग विकल्प देखने के लिए टैप करें।',
      'mr': 'लॉट-नुसार बाजार समिती दर आणि लिस्टिंग पर्याय पाहण्यासाठी टॅप करा.',
    },
    'millet_field_tips': {
      'en':
          'Advisories are grouped for {farm} and should be checked with local FPO guidance before action.',
      'hi':
          'सलाह {farm} के लिए समूहीकृत है और कार्रवाई से पहले स्थानीय किसान उत्पादक संस्था मार्गदर्शन से जांचनी चाहिए।',
      'mr':
          'सूचना {farm} साठी एकत्रित केल्या आहेत आणि कृती करण्यापूर्वी स्थानिक शेतकरी उत्पादक संस्था मार्गदर्शनासह तपासल्या पाहिजेत।',
    },
    'no_important_alerts_desc': {
      'en': 'No important alerts found for this scan.',
      'hi': 'इस स्कैन के लिए कोई महत्वपूर्ण अलर्ट नहीं मिला।',
      'mr': 'या स्कॅनसाठी कोणतेही महत्त्वाचे अलर्ट सापडले नाहीत.',
    },
    'advisor_recommendation_missing': {
      'en':
          'Refresh updated map and cells, but advisory recommendations were not returned. Try again.',
      'hi':
          'मैप और सेल अपडेट हुए, लेकिन सलाहकार सुझाव नहीं मिले। फिर कोशिश करें।',
      'mr':
          'नकाशा आणि सेल अपडेट झाले, पण सल्लागार सूचना मिळाल्या नाहीत. पुन्हा प्रयत्न करा.',
    },
    'alert_refresh_retry_detail': {
      'en': 'Check the network and refresh again.',
      'hi': 'नेटवर्क जांचें और फिर रीफ्रेश करें।',
      'mr': 'नेटवर्क तपासा आणि पुन्हा रीफ्रेश करा.',
    },
    'local_farm_area': {
      'en': 'Local farm area',
      'hi': 'स्थानीय खेत क्षेत्र',
      'mr': 'स्थानिक शेत परिसर',
    },
    'farm_updates': {
      'en': '{farm} • farm updates',
      'hi': '{farm} • खेत अपडेट',
      'mr': '{farm} • शेत अपडेट',
    },
    'local_scheme_center': {
      'en': 'Local scheme center',
      'hi': 'स्थानीय योजना केंद्र',
      'mr': 'स्थानिक योजना केंद्र',
    },
    'local_scheme_center_farm': {
      'en': '{farm} • local scheme center',
      'hi': '{farm} • स्थानीय योजना केंद्र',
      'mr': '{farm} • स्थानिक योजना केंद्र',
    },
    'millet_advisor_title': {
      'en': 'Advisory for Millets',
      'hi': 'मिलेट्स के लिए सलाह',
      'mr': 'मिलेट्ससाठी सल्ला',
    },
    'phosphorus_advisory': {
      'en': '• Apply 20 kg/ha of phosphorus before upcoming rain shower.',
      'hi': '• आगामी बारिश से पहले 20 किलो/हेक्टेयर फास्फोरस डालें।',
      'mr': '• येणाऱ्या पावसापूर्वी २० किलो/हेक्टर स्फुरद टाका.',
    },
    'nitrogen_advisory': {
      'en': '• Top-dress with nitrogen during vegetative growth at day 35.',
      'hi': '• 35वें दिन वानस्पतिक वृद्धि के दौरान नाइट्रोजन का छिड़काव करें।',
      'mr': '• ३५ व्या दिवशी वाढीच्या अवस्थेत नत्राचा हप्ता द्या.',
    },
    'carbon_advisory': {
      'en':
          '• Organic carbon level is slightly low; add vermicompost or farmyard manure after current harvest.',
      'hi':
          '• जैविक कार्बन का स्तर थोड़ा कम है; वर्तमान कटाई के बाद वर्मीकम्पोस्ट या गोबर की खाद डालें।',
      'mr':
          '• सेंद्रिय कर्बाचे प्रमाण थोडे कमी आहे; कापणीनंतर गांडूळ खत किंवा शेणखत टाका.',
    },
    'pre_harvest_checklist': {
      'en': 'Pre-harvest Checklist',
      'hi': 'कटाई-पूर्व चेकलिस्ट',
      'mr': 'कापणी-पूर्व चेकलिस्ट',
    },
    'drying_yard_advisory': {
      'en': '• Arrange drying yards and ensure moisture is under 12%.',
      'hi':
          '• सुखाने के लिए जगह की व्यवस्था करें और सुनिश्चित करें कि नमी 12% से कम हो।',
      'mr':
          '• खळयाची व्यवस्था करा आणि ओलावा १२% पेक्षा कमी असल्याची खात्री करा.',
    },
    'bag_procurement_advisory': {
      'en': '• Procure 18 jute bags (50kg capacity) ahead of time.',
      'hi': '• समय से पहले 18 जूट की बोरियां (50 किलो क्षमता) प्राप्त करें।',
      'mr': '• वेळेपूर्वी १८ ज्यूट पोती (५० किलो क्षमता) मिळवा.',
    },
    'harvester_cleaning_advisory': {
      'en': '• Clean harvester blades to prevent contamination.',
      'hi': '• संदूषण रोकने के लिए हार्वेस्टर ब्लेड साफ़ करें।',
      'mr': '• भेसळ रोखण्यासाठी कापणी यंत्राची पाती स्वच्छ करा.',
    },
    'no_disease_zone': {
      'en': 'No disease zone',
      'hi': 'कोई रोग क्षेत्र नहीं',
      'mr': 'कोणतेही रोग क्षेत्र नाही',
    },
    'add_disease_marker_required': {
      'en': 'Add at least one disease marker before saving.',
      'hi': 'सेव करने से पहले कम से कम एक रोग मार्कर जोड़ें।',
      'mr': 'जतन करण्यापूर्वी किमान एक रोग मार्कर जोडा.',
    },
    'farm_refreshed_msg': {
      'en': 'Farm refreshed',
      'hi': 'खेत रीफ्रेश हुआ',
      'mr': 'शेत रीफ्रेश झाले',
    },
    'refreshing_dots': {
      'en': 'Refreshing...',
      'hi': 'रीफ्रेश हो रहा है...',
      'mr': 'रीफ्रेश होत आहे...',
    },
    'status_updated_msg': {
      'en': 'Status updated',
      'hi': 'स्थिति अपडेट हुई',
      'mr': 'स्थिती अपडेट झाली',
    },
    'scout_zone_title': {
      'en': 'Scout zone',
      'hi': 'निरीक्षण क्षेत्र',
      'mr': 'निरीक्षण क्षेत्र',
    },
    'crop_stress_title': {
      'en': 'Crop stress (water/heat)',
      'hi': 'फसल तनाव (पानी/गर्मी)',
      'mr': 'पीक ताण (पाणी/उष्णता)',
    },
    'possible_names': {
      'en': 'Possible {names}',
      'hi': 'संभावित {names}',
      'mr': 'संभाव्य {names}',
    },
    'brown_top': {'en': 'Brown Top', 'hi': 'ब्राउन टॉप', 'mr': 'ब्राउन टॉप'},
    'pragati': {'en': 'Pragati', 'hi': 'प्रगति', 'mr': 'प्रगती'},
    'general': {'en': 'General', 'hi': 'सामान्य', 'mr': 'सामान्य'},
    'farm_profile': {
      'en': 'Farm profile',
      'hi': 'खेत प्रोफ़ाइल',
      'mr': 'शेत प्रोफाइल',
    },
    'active': {'en': 'Active', 'hi': 'सक्रिय', 'mr': 'सक्रिय'},
    'medium': {'en': 'Medium', 'hi': 'मध्यम', 'mr': 'मध्यम'},
    'lot': {'en': 'Lot', 'hi': 'लॉट', 'mr': 'लॉट'},
    'not_rated': {'en': 'Not rated', 'hi': 'रेटिंग नहीं', 'mr': 'रेटिंग नाही'},
    'last_season': {
      'en': 'Last season',
      'hi': 'पिछला मौसम',
      'mr': 'मागील हंगाम',
    },
    'fpc_procurement': {
      'en': 'FPC procurement',
      'hi': 'किसान उत्पादक कंपनी खरीद',
      'mr': 'शेतकरी उत्पादक कंपनी खरेदी',
    },
    'profile_verified_for_fpc_procurement': {
      'en': 'Farmer profile verified for FPC procurement and grading.',
      'hi':
          'किसान प्रोफ़ाइल किसान उत्पादक कंपनी खरीद और ग्रेडिंग के लिए सत्यापित है।',
      'mr':
          'शेतकरी प्रोफाइल शेतकरी उत्पादक कंपनी खरेदी आणि ग्रेडिंगसाठी सत्यापित आहे.',
    },
    'update_after_fpc_grading': {
      'en': 'Update after FPC grading or procurement.',
      'hi': 'किसान उत्पादक कंपनी ग्रेडिंग या खरीद के बाद अपडेट करें।',
      'mr': 'शेतकरी उत्पादक कंपनी ग्रेडिंग किंवा खरेदीनंतर अपडेट करा.',
    },
    'yesterday': {'en': 'Yesterday', 'hi': 'कल', 'mr': 'काल'},
    'two_days_ago': {
      'en': '2 days ago',
      'hi': '2 दिन पहले',
      'mr': '2 दिवसांपूर्वी',
    },
    'storage': {'en': 'Storage', 'hi': 'भंडारण', 'mr': 'साठवण'},
    'acres_value': {
      'en': '{value} acres',
      'hi': '{value} एकड़',
      'mr': '{value} एकर',
    },
    'kg_value': {
      'en': '{value} kg',
      'hi': '{value} किलो',
      'mr': '{value} किलो',
    },
    'bags_size_value': {
      'en': '{count} × {size} kg',
      'hi': '{count} × {size} किलो',
      'mr': '{count} × {size} किलो',
    },
    'harvest_lot_label': {
      'en': '{batch} • {grade} • {qty} kg',
      'hi': '{batch} • {grade} • {qty} किलो',
      'mr': '{batch} • {grade} • {qty} किलो',
    },
    'harvest_lot_detail': {
      'en': '{crop} • {variety} • {grade} • {qty} kg',
      'hi': '{crop} • {variety} • {grade} • {qty} किलो',
      'mr': '{crop} • {variety} • {grade} • {qty} किलो',
    },
    'index_trend_delta': {
      'en': '{direction} {delta} since {date} ({value} prev)',
      'hi': '{date} से {direction} {delta} ({value} पिछला)',
      'mr': '{date} पासून {direction} {delta} ({value} मागील)',
    },
    'no_satellite_index_farm': {
      'en': 'No satellite index data available for this farm yet.',
      'hi': 'इस खेत के लिए अभी सैटेलाइट इंडेक्स डेटा उपलब्ध नहीं है।',
      'mr': 'या शेतासाठी अजून उपग्रह इंडेक्स डेटा उपलब्ध नाही.',
    },
    'no_remote_index_records': {
      'en': 'No records from remote index feed.',
      'hi': 'रिमोट इंडेक्स फीड से कोई रिकॉर्ड नहीं मिला।',
      'mr': 'रिमोट इंडेक्स फीडमधून कोणतेही रेकॉर्ड मिळाले नाहीत.',
    },
    'news_farm_title': {
      'en': 'News • {farm}',
      'hi': 'समाचार • {farm}',
      'mr': 'बातम्या • {farm}',
    },
    'schemes_farm_title': {
      'en': 'Schemes • {farm}',
      'hi': 'योजनाएँ • {farm}',
      'mr': 'योजना • {farm}',
    },
    'news_msp_title': {
      'en': 'Millet MSP updated for upcoming procurement cycle',
      'hi': 'आगामी खरीद चक्र के लिए मिलेट न्यूनतम समर्थन मूल्य अपडेट',
      'mr': 'आगामी खरेदी चक्रासाठी मिलेट किमान आधारभूत किंमत अपडेट',
    },
    'news_msp_summary': {
      'en': 'Farm support channels report improved rates in Maharashtra.',
      'hi': 'महाराष्ट्र में किसान सहायता चैनलों ने बेहतर दरों की सूचना दी।',
      'mr': 'महाराष्ट्रात शेतकरी सहाय्य वाहिन्यांनी सुधारित दर नोंदवले.',
    },
    'news_msp_impact': {
      'en': 'Check sale timing before creating new listings.',
      'hi': 'नई लिस्टिंग बनाने से पहले बिक्री समय जांचें।',
      'mr': 'नवीन लिस्टिंग तयार करण्यापूर्वी विक्रीची वेळ तपासा.',
    },
    'news_monsoon_title': {
      'en': 'Monsoon outlook: lighter showers expected',
      'hi': 'मानसून अनुमान: हल्की बारिश की संभावना',
      'mr': 'मान्सून अंदाज: हलक्या सरींची शक्यता',
    },
    'news_monsoon_summary': {
      'en':
          'Weather advisories suggest staggered irrigation in low-lying fields.',
      'hi': 'मौसम सलाह निचले खेतों में चरणबद्ध सिंचाई सुझाती है।',
      'mr': 'हवामान सूचना सखल शेतांमध्ये टप्प्याटप्प्याने सिंचन सुचवते.',
    },
    'news_monsoon_impact': {
      'en': 'Review irrigation window for active millet farms.',
      'hi': 'सक्रिय मिलेट खेतों के लिए सिंचाई समय देखें।',
      'mr': 'सक्रिय मिलेट शेतांसाठी सिंचन वेळ तपासा.',
    },
    'news_storage_title': {
      'en': 'Storage tips for short-season grains',
      'hi': 'कम अवधि वाले अनाज के लिए भंडारण सुझाव',
      'mr': 'कमी कालावधीच्या धान्यासाठी साठवण सूचना',
    },
    'news_storage_summary': {
      'en': 'Drying and bin ventilation reduced mold and pest risk.',
      'hi': 'सुखाने और भंडारण वेंटिलेशन से फफूंद और कीट जोखिम घटा।',
      'mr': 'वाळवण आणि कोठार वायुवीजनामुळे बुरशी व कीड धोका कमी झाला.',
    },
    'news_storage_impact': {
      'en': 'Useful for graded lots waiting for market listing.',
      'hi': 'बाजार लिस्टिंग की प्रतीक्षा कर रहे ग्रेडेड लॉट के लिए उपयोगी।',
      'mr': 'बाजार लिस्टिंगची वाट पाहणाऱ्या ग्रेडेड लॉटसाठी उपयुक्त.',
    },
    'scheme_pm_kisan_title': {
      'en': 'PM-KISAN Direct Support',
      'hi': 'PM-KISAN सीधी सहायता',
      'mr': 'PM-KISAN थेट मदत',
    },
    'scheme_pm_kisan_desc': {
      'en': 'Income support for farmers with crop-specific conditions.',
      'hi': 'फसल-विशिष्ट शर्तों के साथ किसानों के लिए आय सहायता।',
      'mr': 'पीक-विशिष्ट अटींसह शेतकऱ्यांसाठी उत्पन्न मदत.',
    },
    'scheme_pm_kisan_fit': {
      'en': 'Landholder records',
      'hi': 'भूमिधारक रिकॉर्ड',
      'mr': 'जमीनधारक नोंदी',
    },
    'scheme_processing_title': {
      'en': 'Millet Processing Grant',
      'hi': 'मिलेट प्रसंस्करण अनुदान',
      'mr': 'मिलेट प्रक्रिया अनुदान',
    },
    'scheme_processing_desc': {
      'en': 'Support for post-harvest processing units at district level.',
      'hi': 'जिला स्तर पर कटाई के बाद प्रसंस्करण इकाइयों के लिए सहायता।',
      'mr': 'जिल्हा स्तरावर कापणीनंतर प्रक्रिया युनिटसाठी मदत.',
    },
    'scheme_processing_fit': {
      'en': 'Grading and storage',
      'hi': 'ग्रेडिंग और भंडारण',
      'mr': 'ग्रेडिंग आणि साठवण',
    },
    'scheme_soil_title': {
      'en': 'Soil Health & Water Mission',
      'hi': 'मृदा स्वास्थ्य और जल मिशन',
      'mr': 'मृदा आरोग्य आणि जल मिशन',
    },
    'scheme_soil_desc': {
      'en': 'Free soil card and advisory updates linked with local officers.',
      'hi': 'स्थानीय अधिकारियों से जुड़े मुफ्त मृदा कार्ड और सलाह अपडेट।',
      'mr': 'स्थानिक अधिकाऱ्यांशी जोडलेले मोफत मृदा कार्ड आणि सूचना अपडेट.',
    },
    'scheme_soil_fit': {
      'en': 'Soil and water checks',
      'hi': 'मृदा और जल जांच',
      'mr': 'मृदा आणि पाणी तपासणी',
    },
    'apply': {'en': 'Apply', 'hi': 'आवेदन करें', 'mr': 'अर्ज करा'},
    'by_district_office': {
      'en': 'By district office',
      'hi': 'जिला कार्यालय द्वारा',
      'mr': 'जिल्हा कार्यालयाद्वारे',
    },
    'opening_application_for': {
      'en': 'Opening application form for {scheme}',
      'hi': '{scheme} के लिए आवेदन फॉर्म खुल रहा है',
      'mr': '{scheme} साठी अर्ज फॉर्म उघडत आहे',
    },
    'version_value': {
      'en': 'Version {version}',
      'hi': 'संस्करण {version}',
      'mr': 'आवृत्ती {version}',
    },
    'fpo_scan_farmer_qr_note': {
      'en': 'Only FPO / FPC login can scan this code to view farmer details.',
      'hi':
          'किसान विवरण देखने के लिए यह कोड केवल किसान उत्पादक संस्था / कंपनी लॉगिन से स्कैन हो सकता है।',
      'mr':
          'शेतकरी तपशील पाहण्यासाठी हा कोड फक्त शेतकरी उत्पादक संस्था / कंपनी लॉगिनने स्कॅन करता येतो.',
    },
    'open_farm_tab_switch': {
      'en': 'Open the Farm tab to switch farm.',
      'hi': 'खेत बदलने के लिए Farm टैब खोलें।',
      'mr': 'शेत बदलण्यासाठी Farm टॅब उघडा.',
    },
    'contact_field_coordinator_help': {
      'en': 'Contact your field coordinator for help.',
      'hi': 'मदद के लिए अपने फील्ड समन्वयक से संपर्क करें।',
      'mr': 'मदतीसाठी तुमच्या फील्ड समन्वयकाशी संपर्क साधा.',
    },
    'distance_from_field_center': {
      'en': '≈ {distance} m from the field centre',
      'hi': 'खेत केंद्र से लगभग {distance} मीटर',
      'mr': 'शेत केंद्रापासून अंदाजे {distance} मीटर',
    },
    'create_bag_plan_quickly': {
      'en': 'Create bag plan and next action quickly',
      'hi': 'बोरी योजना और अगली कार्रवाई जल्दी बनाएं',
      'mr': 'पोती योजना आणि पुढील कृती पटकन तयार करा',
    },
    'farm_sync_incomplete_retry': {
      'en':
          'Farm sync is incomplete for this farmer login. Please refresh farms after login and try again.',
      'hi':
          'इस किसान लॉगिन के लिए खेत सिंक अधूरा है। लॉगिन के बाद खेत रीफ्रेश करें और फिर कोशिश करें।',
      'mr':
          'या शेतकरी लॉगिनसाठी शेत सिंक अपूर्ण आहे. लॉगिननंतर शेते रीफ्रेश करा आणि पुन्हा प्रयत्न करा.',
    },
    'farmer_session_expired_refresh': {
      'en':
          'Your farmer session expired. Please login again and refresh alerts.',
      'hi':
          'आपका किसान सत्र समाप्त हो गया है। फिर लॉगिन करें और अलर्ट रीफ्रेश करें।',
      'mr':
          'तुमचे शेतकरी सत्र संपले आहे. पुन्हा लॉगिन करा आणि अलर्ट रीफ्रेश करा.',
    },
    'disease_screening_failed_retry': {
      'en':
          'Disease screening could not complete. Check farm sync and try again.',
      'hi': 'रोग जांच पूरी नहीं हो सकी। खेत सिंक जांचें और फिर कोशिश करें।',
      'mr':
          'रोग तपासणी पूर्ण झाली नाही. शेत सिंक तपासा आणि पुन्हा प्रयत्न करा.',
    },
    'alert_refresh_failed_retry': {
      'en': 'Alert refresh failed. Please try again.',
      'hi': 'अलर्ट रीफ्रेश विफल। कृपया फिर कोशिश करें।',
      'mr': 'अलर्ट रीफ्रेश अयशस्वी. कृपया पुन्हा प्रयत्न करा.',
    },
    'refresh_farm_weather_risk': {
      'en': 'Refresh farm to check rain, wetness and temperature risk.',
      'hi': 'बारिश, नमी और तापमान जोखिम जांचने के लिए खेत रीफ्रेश करें।',
      'mr': 'पाऊस, ओलावा आणि तापमान धोका तपासण्यासाठी शेत रीफ्रेश करा.',
    },
    'weather_heavy_rain_week': {
      'en':
          'Heavy rain in week {week} can waterlog young plants and cause damping-off. Check drainage in low spots of the field.',
      'hi':
          'सप्ताह {week} में तेज बारिश छोटे पौधों में जलभराव और damping-off कर सकती है। खेत के निचले हिस्सों में निकास जांचें।',
      'mr':
          'आठवडा {week} मध्ये जोरदार पाऊस लहान रोपांत पाणी साचणे आणि damping-off करू शकतो. शेतातील सखल भागात निचरा तपासा.',
    },
    'weather_low_rain_week': {
      'en':
          'Very little rain in week {week}; seedlings may need irrigation to establish.',
      'hi':
          'सप्ताह {week} में बहुत कम बारिश; पौधों को जमने के लिए सिंचाई चाहिए हो सकती है।',
      'mr':
          'आठवडा {week} मध्ये फार कमी पाऊस; रोपे स्थिर होण्यासाठी सिंचन लागेल.',
    },
    'weather_manageable_week': {
      'en':
          'Weather is manageable for the {stage} stage in week {week}. Keep checking for germination gaps.',
      'hi':
          'सप्ताह {week} में {stage} अवस्था के लिए मौसम संभालने योग्य है। अंकुरण अंतर जांचते रहें।',
      'mr':
          'आठवडा {week} मध्ये {stage} अवस्थेसाठी हवामान व्यवस्थापनीय आहे. उगवणीत अंतर तपासत रहा.',
    },
    'leaf_wetness_week': {
      'en':
          '{hours} h of leaf wetness in week {week} favours leaf spot and blast during {stage}. Scout the marked spots first.',
      'hi':
          'सप्ताह {week} में {hours} घंटे पत्ती नमी {stage} में पत्ती धब्बा और ब्लास्ट को बढ़ाती है। पहले चिन्हित स्थान देखें।',
      'mr':
          'आठवडा {week} मध्ये {hours} तास पानावरील ओलावा {stage} दरम्यान पानावरील डाग आणि ब्लास्ट वाढवतो. आधी चिन्हित ठिकाणे पाहा.',
    },
    'no_weather_trigger_week': {
      'en':
          'No strong weather trigger in week {week}. Continue weekly scouting during {stage}.',
      'hi':
          'सप्ताह {week} में बड़ा मौसम संकेत नहीं है। {stage} के दौरान साप्ताहिक निरीक्षण जारी रखें।',
      'mr':
          'आठवडा {week} मध्ये मोठा हवामान संकेत नाही. {stage} दरम्यान साप्ताहिक निरीक्षण सुरू ठेवा.',
    },
    'wet_weather_stage_risk': {
      'en':
          'Wet weather in week {week} is risky during {stage}; flowers and filling grain are sensitive to fungal spread and grain mould.',
      'hi':
          'सप्ताह {week} में गीला मौसम {stage} के दौरान जोखिम भरा है; फूल और भरते दाने फफूंद और grain mould के प्रति संवेदनशील हैं।',
      'mr':
          'आठवडा {week} मध्ये ओले हवामान {stage} दरम्यान धोकादायक आहे; फुले आणि भरत असलेले धान्य बुरशी व grain mould साठी संवेदनशील असते.',
    },
    'stable_weather_week': {
      'en':
          'Weather is stable in week {week} ({stage}). Watch for sudden rain before harvest decisions.',
      'hi':
          'सप्ताह {week} में मौसम स्थिर है ({stage})। कटाई निर्णय से पहले अचानक बारिश पर नजर रखें।',
      'mr':
          'आठवडा {week} मध्ये हवामान स्थिर आहे ({stage}). कापणी निर्णयापूर्वी अचानक पावसावर लक्ष ठेवा.',
    },
    'photo_diagnosis_failed': {
      'en': 'Photo diagnosis failed: {error}',
      'hi': 'फोटो जांच विफल: {error}',
      'mr': 'फोटो तपासणी अयशस्वी: {error}',
    },
    'week_after_sowing_stage': {
      'en': 'Week {week} after sowing • {stage}',
      'hi': 'बुवाई के बाद सप्ताह {week} • {stage}',
      'mr': 'पेरणीनंतर आठवडा {week} • {stage}',
    },
    'soil_health_farm_title': {
      'en': '{farm} • Soil Health',
      'hi': '{farm} • मृदा स्वास्थ्य',
      'mr': '{farm} • मृदा आरोग्य',
    },
    'weather_impact_farm_title': {
      'en': '{farm} • Weather Impact',
      'hi': '{farm} • मौसम प्रभाव',
      'mr': '{farm} • हवामान परिणाम',
    },
    'yield_prognosis_farm_title': {
      'en': '{farm} • Yield Prognosis',
      'hi': '{farm} • उपज अनुमान',
      'mr': '{farm} • उत्पादन अंदाज',
    },
    'microclimate_statistics': {
      'en': 'Microclimate Statistics',
      'hi': 'सूक्ष्म मौसम आंकड़े',
      'mr': 'सूक्ष्म हवामान आकडे',
    },
    'solar_radiation': {
      'en': 'Solar Radiation',
      'hi': 'सौर विकिरण',
      'mr': 'सौर किरणोत्सर्ग',
    },
    'daily_evapotranspiration': {
      'en': 'Daily Evapotranspiration',
      'hi': 'दैनिक वाष्पोत्सर्जन',
      'mr': 'दैनिक बाष्पोत्सर्जन',
    },
    'dew_point': {'en': 'Dew Point', 'hi': 'ओसांक', 'mr': 'दवबिंदू'},
    'relative_humidity': {
      'en': 'Relative Humidity',
      'hi': 'सापेक्ष आर्द्रता',
      'mr': 'सापेक्ष आर्द्रता',
    },
    'expected_yield_prognosis': {
      'en': 'Expected Yield Prognosis',
      'hi': 'अपेक्षित उपज अनुमान',
      'mr': 'अपेक्षित उत्पादन अंदाज',
    },
    'quality_grade_prediction': {
      'en': 'Quality Grade Prediction',
      'hi': 'गुणवत्ता ग्रेड अनुमान',
      'mr': 'गुणवत्ता ग्रेड अंदाज',
    },
    'fungal_disease_low_humidity': {
      'en': '• Fungal disease risk: Low (humidity remains under 70%)',
      'hi': '• फफूंद रोग जोखिम: कम (आर्द्रता 70% से कम है)',
      'mr': '• बुरशीजन्य रोग धोका: कमी (आर्द्रता 70% पेक्षा कमी आहे)',
    },
    'heat_stress_advisory': {
      'en':
          '• Heat Stress: Moderate (Top temps exceeding 31°C; ensure evening soil dampness)',
      'hi':
          '• गर्मी तनाव: मध्यम (ऊपरी तापमान 31°C से अधिक; शाम को मिट्टी में नमी रखें)',
      'mr':
          '• उष्णता ताण: मध्यम (तापमान 31°C पेक्षा जास्त; संध्याकाळी माती ओलसर ठेवा)',
    },
    'npk_soil_chemistry': {
      'en': 'NPK & Soil Chemistry',
      'hi': 'NPK और मृदा रसायन',
      'mr': 'NPK आणि मृदा रसायन',
    },
    'nitrogen_n': {
      'en': 'Nitrogen (N)',
      'hi': 'नाइट्रोजन (N)',
      'mr': 'नत्र (N)',
    },
    'phosphorus_p': {
      'en': 'Phosphorus (P)',
      'hi': 'फॉस्फोरस (P)',
      'mr': 'स्फुरद (P)',
    },
    'potassium_k': {
      'en': 'Potassium (K)',
      'hi': 'पोटैशियम (K)',
      'mr': 'पालाश (K)',
    },
    'organic_carbon': {
      'en': 'Organic Carbon',
      'hi': 'जैविक कार्बन',
      'mr': 'सेंद्रिय कर्ब',
    },
    'optimal_65_kg_ha': {
      'en': 'Optimal (65 kg/ha)',
      'hi': 'उत्तम (65 किलो/हेक्टर)',
      'mr': 'उत्तम (65 किलो/हेक्टर)',
    },
    'moderate_28_kg_ha': {
      'en': 'Moderate (28 kg/ha)',
      'hi': 'मध्यम (28 किलो/हेक्टर)',
      'mr': 'मध्यम (28 किलो/हेक्टर)',
    },
    'high_195_kg_ha': {
      'en': 'High (195 kg/ha)',
      'hi': 'अधिक (195 किलो/हेक्टर)',
      'mr': 'जास्त (195 किलो/हेक्टर)',
    },
    'moderate_055_percent': {
      'en': 'Moderate (0.55%)',
      'hi': 'मध्यम (0.55%)',
      'mr': 'मध्यम (0.55%)',
    },
    'soil_ph_value': {
      'en': 'Soil pH Value:',
      'hi': 'मृदा pH मान:',
      'mr': 'मृदा pH मूल्य:',
    },
    'soil_ph_ideal': {
      'en': '6.7 (Slightly Acidic • Ideal)',
      'hi': '6.7 (हल्का अम्लीय • आदर्श)',
      'mr': '6.7 (किंचित आम्लीय • आदर्श)',
    },
    'est_production': {
      'en': 'Est. Production',
      'hi': 'अनुमानित उत्पादन',
      'mr': 'अंदाजित उत्पादन',
    },
    'current_stage_projection': {
      'en': 'Current Stage Projection',
      'hi': 'वर्तमान अवस्था अनुमान',
      'mr': 'सध्याच्या अवस्थेचा अंदाज',
    },
    'on_track_percent': {
      'en': 'On Track (102%)',
      'hi': 'सही दिशा में (102%)',
      'mr': 'योग्य दिशेने (102%)',
    },
    'harvest_window_demo': {
      'en': 'July 15 - July 20',
      'hi': '15 जुलाई - 20 जुलाई',
      'mr': '15 जुलै - 20 जुलै',
    },
    'grade_a_high_density': {
      'en': 'A (High density grains)',
      'hi': 'A (उच्च घनत्व दाने)',
      'mr': 'A (जास्त घनतेचे धान्य)',
    },
    'cloud_percent': {
      'en': '{value}% Cloud',
      'hi': '{value}% बादल',
      'mr': '{value}% ढग',
    },
    'fpo_dashboard': {
      'en': 'FPO Dashboard',
      'hi': 'FPO डैशबोर्ड',
      'mr': 'FPO डॅशबोर्ड',
    },
    'admin_login': {
      'en': 'Admin login',
      'hi': 'एडमिन लॉगिन',
      'mr': 'अ‍ॅडमिन लॉगिन',
    },
    'sign_in_satellite_monitoring': {
      'en': 'Sign in to satellite monitoring',
      'hi': 'सैटेलाइट निगरानी में साइन इन करें',
      'mr': 'उपग्रह निरीक्षणात साइन इन करा',
    },
    'sign_in': {'en': 'Sign In', 'hi': 'साइन इन', 'mr': 'साइन इन'},
    'need_access': {
      'en': 'Need access?',
      'hi': 'एक्सेस चाहिए?',
      'mr': 'प्रवेश हवा आहे?',
    },
    'create_satellite_account': {
      'en': 'Create a satellite account',
      'hi': 'सैटेलाइट account बनाएं',
      'mr': 'उपग्रह account तयार करा',
    },
    'create_account': {
      'en': 'Create Account',
      'hi': 'account बनाएं',
      'mr': 'account तयार करा',
    },
    'setup_satellite_monitoring': {
      'en': 'Set up satellite monitoring access',
      'hi': 'सैटेलाइट निगरानी access सेट करें',
      'mr': 'उपग्रह निरीक्षण access सेट करा',
    },
    'already_registered': {
      'en': 'Already registered?',
      'hi': 'पहले से पंजीकृत?',
      'mr': 'आधीच नोंदणीकृत?',
    },
    'sign_in_to_account': {
      'en': 'Sign in to your account',
      'hi': 'अपने account में साइन इन करें',
      'mr': 'तुमच्या account मध्ये साइन इन करा',
    },
    'email_address': {
      'en': 'Email Address',
      'hi': 'ईमेल पता',
      'mr': 'ईमेल पत्ता',
    },
    'enter_registered_fpc_email': {
      'en': 'Enter registered FPC email',
      'hi': 'पंजीकृत FPC ईमेल दर्ज करें',
      'mr': 'नोंदणीकृत FPC ईमेल लिहा',
    },
    'enter_email_address': {
      'en': 'Enter email address',
      'hi': 'ईमेल पता दर्ज करें',
      'mr': 'ईमेल पत्ता लिहा',
    },
    'enter_valid_email': {
      'en': 'Enter a valid email',
      'hi': 'मान्य ईमेल दर्ज करें',
      'mr': 'वैध ईमेल लिहा',
    },
    'password': {'en': 'Password', 'hi': 'पासवर्ड', 'mr': 'पासवर्ड'},
    'enter_fpc_login_password': {
      'en': 'Enter FPC login password',
      'hi': 'FPC लॉगिन पासवर्ड दर्ज करें',
      'mr': 'FPC लॉगिन पासवर्ड लिहा',
    },
    'enter_password': {
      'en': 'Enter password',
      'hi': 'पासवर्ड दर्ज करें',
      'mr': 'पासवर्ड लिहा',
    },
    'create_password': {
      'en': 'Create password',
      'hi': 'पासवर्ड बनाएं',
      'mr': 'पासवर्ड तयार करा',
    },
    'confirm_password': {
      'en': 'Confirm Password',
      'hi': 'पासवर्ड पुष्टि करें',
      'mr': 'पासवर्ड पुष्टी करा',
    },
    'show_password': {
      'en': 'Show password',
      'hi': 'पासवर्ड दिखाएँ',
      'mr': 'पासवर्ड दाखवा',
    },
    'hide_password': {
      'en': 'Hide password',
      'hi': 'पासवर्ड छिपाएँ',
      'mr': 'पासवर्ड लपवा',
    },
    'password_min_six_chars': {
      'en': 'Password must be at least 6 characters',
      'hi': 'पासवर्ड कम से कम 6 अक्षर का होना चाहिए',
      'mr': 'पासवर्ड किमान 6 अक्षरांचा हवा',
    },
    'password_too_short': {
      'en': 'Password too short',
      'hi': 'पासवर्ड बहुत छोटा है',
      'mr': 'पासवर्ड खूप लहान आहे',
    },
    'at_least_six_chars': {
      'en': 'At least 6 characters',
      'hi': 'कम से कम 6 अक्षर',
      'mr': 'किमान 6 अक्षरे',
    },
    'passwords_do_not_match': {
      'en': 'Passwords do not match',
      'hi': 'पासवर्ड मेल नहीं खाते',
      'mr': 'पासवर्ड जुळत नाहीत',
    },
    'verifying': {
      'en': 'Verifying',
      'hi': 'सत्यापन हो रहा है',
      'mr': 'पडताळणी होत आहे',
    },
    'fpc_login': {'en': 'FPC Login', 'hi': 'FPC लॉगिन', 'mr': 'FPC लॉगिन'},
    'login_to_fpc_dashboard': {
      'en': 'Login to FPC Dashboard',
      'hi': 'FPC डैशबोर्ड में लॉगिन करें',
      'mr': 'FPC डॅशबोर्डमध्ये लॉगिन करा',
    },
    'fpc_login_desc': {
      'en':
          'Login with your registered FPC account to access farmer verification, procurement and field tools.',
      'hi':
          'किसान सत्यापन, खरीद और field tools के लिए अपने पंजीकृत FPC account से login करें।',
      'mr':
          'शेतकरी पडताळणी, खरेदी आणि field tools साठी तुमच्या नोंदणीकृत FPC account ने login करा.',
    },
    'fpc_login_info': {
      'en':
          'Use the email and password configured in Supabase for your FPC account.',
      'hi':
          'अपने FPC account के लिए Supabase में configured ईमेल और पासवर्ड उपयोग करें।',
      'mr':
          'तुमच्या FPC account साठी Supabase मध्ये configured ईमेल आणि पासवर्ड वापरा.',
    },
    'management': {'en': 'Management', 'hi': 'प्रबंधन', 'mr': 'व्यवस्थापन'},
    'farmers': {'en': 'Farmers', 'hi': 'किसान', 'mr': 'शेतकरी'},
    'fpo_farmers_subtitle': {
      'en': 'Scan QR and manage members',
      'hi': 'QR स्कैन करें और सदस्य प्रबंधित करें',
      'mr': 'QR स्कॅन करा आणि सदस्य व्यवस्थापित करा',
    },
    'procurement': {'en': 'Procurement', 'hi': 'खरीद', 'mr': 'खरेदी'},
    'fpo_procurement_subtitle': {
      'en': 'Review grain grading jobs',
      'hi': 'अनाज ग्रेडिंग कार्य समीक्षा करें',
      'mr': 'धान्य ग्रेडिंग कामे तपासा',
    },
    'fpo_grain_grading_subtitle': {
      'en': 'Grade FPC customer lots',
      'hi': 'FPC ग्राहक लॉट ग्रेड करें',
      'mr': 'FPC ग्राहक लॉट ग्रेड करा',
    },
    'receiver': {'en': 'Receiver', 'hi': 'रिसीवर', 'mr': 'स्वीकार केंद्र'},
    'fpo_receiver_subtitle': {
      'en': 'Scan harvest QR and save purchases',
      'hi': 'कटाई QR स्कैन करें और खरीद सेव करें',
      'mr': 'कापणी QR स्कॅन करा आणि खरेदी जतन करा',
    },
    'field_maps': {'en': 'Field Maps', 'hi': 'खेत मैप', 'mr': 'शेत नकाशे'},
    'offline_map_areas': {
      'en': 'Offline map areas',
      'hi': 'ऑफलाइन मैप क्षेत्र',
      'mr': 'ऑफलाइन नकाशा क्षेत्रे',
    },
    'diagnostics': {
      'en': 'Diagnostics',
      'hi': 'डायग्नोस्टिक्स',
      'mr': 'डायग्नोस्टिक्स',
    },
    'farm_diagnostics': {
      'en': 'Farm Diagnostics',
      'hi': 'खेत डायग्नोस्टिक्स',
      'mr': 'शेत डायग्नोस्टिक्स',
    },
    'farm_health_reports': {
      'en': 'Farm health reports',
      'hi': 'खेत स्वास्थ्य रिपोर्ट',
      'mr': 'शेत आरोग्य अहवाल',
    },
    'satellite_monitoring': {
      'en': 'Satellite Monitoring',
      'hi': 'सैटेलाइट निगरानी',
      'mr': 'उपग्रह निरीक्षण',
    },
    'dashboard': {'en': 'Dashboard', 'hi': 'डैशबोर्ड', 'mr': 'डॅशबोर्ड'},
    'advanced_monitoring': {
      'en': 'Advanced Monitoring',
      'hi': 'उन्नत निगरानी',
      'mr': 'प्रगत निरीक्षण',
    },
    'advanced': {'en': 'Advanced', 'hi': 'उन्नत', 'mr': 'प्रगत'},
    'algorithm_selection': {
      'en': 'Algorithm Selection',
      'hi': 'एल्गोरिदम चयन',
      'mr': 'अल्गोरिदम निवड',
    },
    'date_range': {
      'en': 'Date Range',
      'hi': 'तारीख सीमा',
      'mr': 'तारीख श्रेणी',
    },
    'start_date': {
      'en': 'Start Date',
      'hi': 'आरंभ तारीख',
      'mr': 'सुरुवातीची तारीख',
    },
    'end_date': {'en': 'End Date', 'hi': 'अंतिम तारीख', 'mr': 'शेवटची तारीख'},
    'analysing': {
      'en': 'Analysing...',
      'hi': 'विश्लेषण हो रहा है...',
      'mr': 'विश्लेषण होत आहे...',
    },
    'run_analysis': {
      'en': 'Run Analysis',
      'hi': 'विश्लेषण चलाएँ',
      'mr': 'विश्लेषण चालवा',
    },
    'no_farm': {'en': 'No farm', 'hi': 'कोई खेत नहीं', 'mr': 'शेत नाही'},
    'select_farm_first': {
      'en': 'Select a farm first',
      'hi': 'पहले खेत चुनें',
      'mr': 'आधी शेत निवडा',
    },
    'results': {'en': 'Results', 'hi': 'परिणाम', 'mr': 'निकाल'},
    'field_diagnostics': {
      'en': 'Field Diagnostics',
      'hi': 'खेत डायग्नोस्टिक्स',
      'mr': 'शेत डायग्नोस्टिक्स',
    },
    'signed_in_as': {
      'en': 'Signed in as',
      'hi': 'इनके रूप में साइन इन',
      'mr': 'या म्हणून साइन इन',
    },
    'close': {'en': 'Close', 'hi': 'बंद करें', 'mr': 'बंद करा'},
    'satellite_monitoring_subtitle': {
      'en': 'Use admin credentials for farm satellite tools',
      'hi': 'खेत सैटेलाइट टूल के लिए एडमिन लॉगिन उपयोग करें',
      'mr': 'शेत उपग्रह साधनांसाठी अ‍ॅडमिन लॉगिन वापरा',
    },
    'change_role': {
      'en': 'Change Role',
      'hi': 'भूमिका बदलें',
      'mr': 'भूमिका बदला',
    },
    'fpo_workspace': {
      'en': 'FPO / FPC workspace',
      'hi': 'FPO / FPC कार्यक्षेत्र',
      'mr': 'FPO / FPC कार्यक्षेत्र',
    },
    'alerts': {'en': 'Alerts', 'hi': 'अलर्ट', 'mr': 'अलर्ट'},
    'scan_farmer_qr': {
      'en': 'Scan Farmer QR',
      'hi': 'किसान QR स्कैन करें',
      'mr': 'शेतकरी QR स्कॅन करा',
    },
    'fpc_farmer_verification': {
      'en': 'FPC Farmer Verification',
      'hi': 'FPC किसान सत्यापन',
      'mr': 'FPC शेतकरी पडताळणी',
    },
    'fpc_farmer_verification_desc': {
      'en': 'Use this FPC login scanner for farmer passport/profile QR only.',
      'hi':
          'इस FPC लॉगिन स्कैनर का उपयोग केवल किसान पासपोर्ट/प्रोफाइल QR के लिए करें।',
      'mr': 'हा FPC लॉगिन स्कॅनर फक्त शेतकरी पासपोर्ट/प्रोफाइल QR साठी वापरा.',
    },
    'open_camera_scanner': {
      'en': 'Open camera scanner',
      'hi': 'कैमरा स्कैनर खोलें',
      'mr': 'कॅमेरा स्कॅनर उघडा',
    },
    'qr_payload': {'en': 'QR payload', 'hi': 'QR डेटा', 'mr': 'QR डेटा'},
    'paste_farmer_qr_payload': {
      'en': 'Paste farmer QR payload for verification',
      'hi': 'सत्यापन के लिए किसान QR डेटा पेस्ट करें',
      'mr': 'पडताळणीसाठी शेतकरी QR डेटा पेस्ट करा',
    },
    'invalid_farmer_qr': {
      'en': 'Invalid farmer QR.',
      'hi': 'किसान QR मान्य नहीं है।',
      'mr': 'शेतकरी QR वैध नाही.',
    },
    'farmer_qr_not_fpo_access': {
      'en': 'This QR is not for FPO / FPC access.',
      'hi': 'यह QR FPO / FPC access के लिए नहीं है।',
      'mr': 'हा QR FPO / FPC access साठी नाही.',
    },
    'farmer_qr_scan_failed': {
      'en': 'Scan failed. Use a valid Kalsubai Farms farmer QR.',
      'hi': 'स्कैन विफल हुआ। मान्य Kalsubai Farms किसान QR उपयोग करें।',
      'mr': 'स्कॅन अयशस्वी. वैध Kalsubai Farms शेतकरी QR वापरा.',
    },
    'verify_farmer': {
      'en': 'Verify farmer',
      'hi': 'किसान सत्यापित करें',
      'mr': 'शेतकरी पडताळा',
    },
    'scan_again': {
      'en': 'Scan again',
      'hi': 'फिर स्कैन करें',
      'mr': 'पुन्हा स्कॅन करा',
    },
    'yield': {'en': 'Yield', 'hi': 'उपज', 'mr': 'उत्पादन'},
    'phone': {'en': 'Phone', 'hi': 'फोन', 'mr': 'फोन'},
    'detail': {'en': 'Detail', 'hi': 'विवरण', 'mr': 'तपशील'},
    'season': {'en': 'Season', 'hi': 'मौसम', 'mr': 'हंगाम'},
    'current': {'en': 'Current', 'hi': 'वर्तमान', 'mr': 'सध्याचे'},
    'past_crop_production': {
      'en': 'Past Crop Production',
      'hi': 'पिछला फसल उत्पादन',
      'mr': 'मागील पीक उत्पादन',
    },
    'no_past_crop_production_qr': {
      'en': 'No past crop production captured in this QR.',
      'hi': 'इस QR में पिछला फसल उत्पादन उपलब्ध नहीं है।',
      'mr': 'या QR मध्ये मागील पीक उत्पादन उपलब्ध नाही.',
    },
    'selling_history': {
      'en': 'Selling History',
      'hi': 'बिक्री इतिहास',
      'mr': 'विक्री इतिहास',
    },
    'no_selling_history_qr': {
      'en': 'No selling history captured in this QR.',
      'hi': 'इस QR में बिक्री इतिहास उपलब्ध नहीं है।',
      'mr': 'या QR मध्ये विक्री इतिहास उपलब्ध नाही.',
    },
    'farmer_linked': {
      'en': 'Farmer linked',
      'hi': 'किसान लिंक हुआ',
      'mr': 'शेतकरी जोडला',
    },
    'farmer_profile_verified_fpo': {
      'en': 'Farmer profile is verified for FPO / FPC access.',
      'hi': 'किसान प्रोफाइल FPO / FPC एक्सेस के लिए सत्यापित है।',
      'mr': 'शेतकरी प्रोफाइल FPO / FPC प्रवेशासाठी पडताळले आहे.',
    },
    'add_to_fpc_records': {
      'en': 'Add to FPC records',
      'hi': 'FPC रिकॉर्ड में जोड़ें',
      'mr': 'FPC नोंदीत जोडा',
    },
    'grade_lot': {
      'en': 'Grade lot',
      'hi': 'लॉट ग्रेड करें',
      'mr': 'लॉट ग्रेड करा',
    },
    'fpc_customer': {
      'en': 'FPC customer',
      'hi': 'FPC ग्राहक',
      'mr': 'FPC ग्राहक',
    },
    'fpc_customer_farm': {
      'en': 'FPC customer farm',
      'hi': 'FPC ग्राहक खेत',
      'mr': 'FPC ग्राहक शेत',
    },
    'grading_review': {
      'en': 'Grading Review',
      'hi': 'ग्रेडिंग समीक्षा',
      'mr': 'ग्रेडिंग पुनरावलोकन',
    },
    'review_updated': {
      'en': 'Review updated',
      'hi': 'समीक्षा अपडेट हुई',
      'mr': 'पुनरावलोकन अपडेट झाले',
    },
    'review_failed': {
      'en': 'Review failed',
      'hi': 'समीक्षा विफल',
      'mr': 'पुनरावलोकन अयशस्वी',
    },
    'no_grading_jobs_need_review': {
      'en': 'No grading jobs need review.',
      'hi': 'कोई ग्रेडिंग कार्य समीक्षा के लिए नहीं है।',
      'mr': 'पुनरावलोकनासाठी ग्रेडिंग कामे नाहीत.',
    },
    'approved': {'en': 'Approved', 'hi': 'स्वीकृत', 'mr': 'मंजूर'},
    'recapture_requested': {
      'en': 'Recapture requested',
      'hi': 'फिर फोटो मांगा गया',
      'mr': 'पुन्हा फोटो मागितला',
    },
    'rejected': {'en': 'Rejected', 'hi': 'अस्वीकृत', 'mr': 'नाकारले'},
    'approve': {'en': 'Approve', 'hi': 'स्वीकृत करें', 'mr': 'मंजूर करा'},
    'request_recapture': {
      'en': 'Request recapture',
      'hi': 'फिर फोटो मांगें',
      'mr': 'पुन्हा फोटो मागा',
    },
    'reject': {'en': 'Reject', 'hi': 'अस्वीकृत करें', 'mr': 'नकारा'},
    'crop_variety_moisture': {
      'en': '{crop} {variety} • Moisture {moisture}',
      'hi': '{crop} {variety} • नमी {moisture}',
      'mr': '{crop} {variety} • ओलावा {moisture}',
    },
    'crop_variety_value': {
      'en': '{crop} - {variety}',
      'hi': '{crop} - {variety}',
      'mr': '{crop} - {variety}',
    },
    'risk': {'en': 'Risk', 'hi': 'जोखिम', 'mr': 'धोका'},
    'label_value': {
      'en': '{label}: {value}',
      'hi': '{label}: {value}',
      'mr': '{label}: {value}',
    },
    'fpc_receiver': {
      'en': 'FPC Receiver',
      'hi': 'FPC रिसीवर',
      'mr': 'FPC स्वीकार केंद्र',
    },
    'receive_harvest_lot': {
      'en': 'Receive Harvest Lot',
      'hi': 'कटाई लॉट प्राप्त करें',
      'mr': 'कापणी लॉट स्वीकारा',
    },
    'receive_harvest_lot_desc': {
      'en':
          'Scan a public harvest QR sticker. The received product is saved to the FPC remote ledger.',
      'hi':
          'सार्वजनिक कटाई QR स्टिकर स्कैन करें। प्राप्त उत्पाद FPC रिमोट लेजर में सेव होता है।',
      'mr':
          'सार्वजनिक कापणी QR स्टिकर स्कॅन करा. प्राप्त माल FPC रिमोट लेजरमध्ये जतन होतो.',
    },
    'scan_another_harvest_qr': {
      'en': 'Scan another harvest QR',
      'hi': 'दूसरा कटाई QR स्कैन करें',
      'mr': 'दुसरा कापणी QR स्कॅन करा',
    },
    'received_lot_saved': {
      'en': 'Received lot {batch} saved.',
      'hi': 'प्राप्त लॉट {batch} सेव हुआ।',
      'mr': 'प्राप्त लॉट {batch} जतन झाला.',
    },
    'received_products_ledger': {
      'en': 'Received Products Ledger',
      'hi': 'प्राप्त उत्पाद लेजर',
      'mr': 'प्राप्त माल लेजर',
    },
    'no_received_products': {
      'en':
          'No purchased product received yet. Scan harvest QR stickers to create accountability records.',
      'hi':
          'अभी कोई खरीदा उत्पाद प्राप्त नहीं हुआ। जवाबदेही रिकॉर्ड बनाने के लिए कटाई QR स्टिकर स्कैन करें।',
      'mr':
          'अजून खरेदी केलेला माल प्राप्त नाही. जबाबदारी नोंदींसाठी कापणी QR स्टिकर स्कॅन करा.',
    },
    'received_lot': {
      'en': 'Received lot',
      'hi': 'प्राप्त लॉट',
      'mr': 'प्राप्त लॉट',
    },
    'harvest_lot': {'en': 'Harvest lot', 'hi': 'कटाई लॉट', 'mr': 'कापणी लॉट'},
    'quantity': {'en': 'Quantity', 'hi': 'मात्रा', 'mr': 'प्रमाण'},
    'batch_id': {'en': 'Batch ID', 'hi': 'बैच ID', 'mr': 'बॅच ID'},
    'farmer_id_label': {'en': 'Farmer ID', 'hi': 'किसान ID', 'mr': 'शेतकरी ID'},
    'farm_id_label': {'en': 'Farm ID', 'hi': 'खेत ID', 'mr': 'शेत ID'},
    'moisture_source': {
      'en': 'Moisture source',
      'hi': 'नमी स्रोत',
      'mr': 'ओलावा स्रोत',
    },
    'review': {'en': 'Review', 'hi': 'समीक्षा', 'mr': 'पुनरावलोकन'},
    'trace_generated': {
      'en': 'Trace generated',
      'hi': 'ट्रेस बनाया गया',
      'mr': 'ट्रेस तयार झाले',
    },
    'price_per_kg': {'en': 'Price/kg', 'hi': 'कीमत/किलो', 'mr': 'दर/किलो'},
    'rating_1_5': {'en': 'Rating 1-5', 'hi': 'रेटिंग 1-5', 'mr': 'रेटिंग 1-5'},
    'receiver_notes': {
      'en': 'Receiver notes',
      'hi': 'रिसीवर नोट्स',
      'mr': 'स्वीकार नोंदी',
    },
    'saving': {'en': 'Saving', 'hi': 'सेव हो रहा है', 'mr': 'जतन होत आहे'},
    'save_received_product': {
      'en': 'Save received product',
      'hi': 'प्राप्त उत्पाद सेव करें',
      'mr': 'प्राप्त माल जतन करा',
    },
    'could_not_load_received_products': {
      'en': 'Could not load received product records.',
      'hi': 'प्राप्त उत्पाद रिकॉर्ड लोड नहीं हुए।',
      'mr': 'प्राप्त माल नोंदी लोड झाल्या नाहीत.',
    },
    'could_not_read_harvest_qr': {
      'en': 'Could not read this harvest QR.',
      'hi': 'यह कटाई QR पढ़ा नहीं गया।',
      'mr': 'हा कापणी QR वाचता आला नाही.',
    },
    'could_not_save_received_product': {
      'en': 'Could not save received product in remote database.',
      'hi': 'प्राप्त उत्पाद रिमोट डेटाबेस में सेव नहीं हुआ।',
      'mr': 'प्राप्त माल रिमोट डेटाबेसमध्ये जतन झाला नाही.',
    },
    'rs_value': {'en': 'Rs {value}', 'hi': 'Rs {value}', 'mr': 'Rs {value}'},
    'kg_value_plain': {
      'en': '{value} kg',
      'hi': '{value} किलो',
      'mr': '{value} किलो',
    },
    'kg_bags_value': {
      'en': '{value} kg bags',
      'hi': '{value} किलो बोरी',
      'mr': '{value} किलो पोती',
    },
    'bags_x_kg_value': {
      'en': '{count} bags x {size} kg',
      'hi': '{count} बोरी x {size} किलो',
      'mr': '{count} पोती x {size} किलो',
    },
    'score_out_of_100': {
      'en': '{score}/100',
      'hi': '{score}/100',
      'mr': '{score}/100',
    },
    'crop_quantity_total': {
      'en': '{crop} - {quantity} - {total}',
      'hi': '{crop} - {quantity} - {total}',
      'mr': '{crop} - {quantity} - {total}',
    },
  };
}
