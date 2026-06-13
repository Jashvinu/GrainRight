import 'package:get/get.dart';

/// Shared locale-aware strings for the core farmer-facing shell screens
/// (entry/role select, farmer login). Mirrors [GradingStrings] so the
/// Marathi/Hindi-first audience sees regional text immediately, instead of the
/// Marathi-only legacy `AppTranslations`. See docs/10_uiux_flow_audit.md §3.1.
class UiStrings {
  UiStrings._();

  static String _lang() {
    final code = Get.locale?.languageCode ?? 'en';
    return (code == 'mr' || code == 'hi') ? code : 'en';
  }

  static String t(String key) {
    final row = _data[key];
    if (row == null) return key;
    return row[_lang()] ?? row['en'] ?? key;
  }

  static const Map<String, Map<String, String>> _data = {
    // ── Role selection (main login) ──
    'welcome': {'en': 'Welcome!', 'hi': 'स्वागत है!', 'mr': 'स्वागत आहे!'},
    'choose_continue': {
      'en': 'Choose how you want to continue',
      'hi': 'आगे कैसे बढ़ना है चुनें',
      'mr': 'पुढे कसे जायचे ते निवडा',
    },
    'role_farmer': {'en': 'Farmer', 'hi': 'किसान', 'mr': 'शेतकरी'},
    'role_farmer_sub': {'en': 'Login with mobile', 'hi': 'मोबाइल से लॉगिन', 'mr': 'मोबाइलने लॉगिन'},
    'role_fpo': {'en': 'FPO / FPC', 'hi': 'FPO / FPC', 'mr': 'FPO / FPC'},
    'role_fpo_sub': {
      'en': 'Login with FPC details',
      'hi': 'FPC जानकारी से लॉगिन',
      'mr': 'FPC माहितीने लॉगिन',
    },
    'role_admin': {'en': 'Admin', 'hi': 'एडमिन', 'mr': 'अ‍ॅडमिन'},
    'role_admin_sub': {
      'en': 'System administration',
      'hi': 'सिस्टम प्रशासन',
      'mr': 'सिस्टम प्रशासन',
    },
    'guest': {'en': 'Continue as Guest', 'hi': 'मेहमान के रूप में जारी रखें', 'mr': 'पाहुणा म्हणून सुरू ठेवा'},
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
    'farmer_login': {'en': 'Farmer Login', 'hi': 'किसान लॉगिन', 'mr': 'शेतकरी लॉगिन'},
    'mobile_number': {'en': 'Mobile Number', 'hi': 'मोबाइल नंबर', 'mr': 'मोबाइल नंबर'},
    'enter_mobile': {'en': 'Enter mobile number', 'hi': 'मोबाइल नंबर लिखें', 'mr': 'मोबाइल नंबर लिहा'},
    'continue_': {'en': 'Continue', 'hi': 'आगे बढ़ें', 'mr': 'पुढे चला'},
    'please_wait': {'en': 'Please wait', 'hi': 'कृपया रुकें', 'mr': 'कृपया थांबा'},
    'secure_private': {'en': 'Secure & Private', 'hi': 'सुरक्षित और निजी', 'mr': 'सुरक्षित आणि खाजगी'},
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

    // ── Profile ──
    'detailed_profile': {'en': 'Detailed Profile', 'hi': 'विस्तृत प्रोफ़ाइल', 'mr': 'सविस्तर प्रोफाइल'},
    'detailed_farmer_profile': {
      'en': 'Detailed Farmer Profile',
      'hi': 'विस्तृत किसान प्रोफ़ाइल',
      'mr': 'सविस्तर शेतकरी प्रोफाइल',
    },
    'verified_farmer': {'en': 'Verified Farmer', 'hi': 'सत्यापित किसान', 'mr': 'पडताळलेला शेतकरी'},
    'farmer_identity_qr': {'en': 'Farmer Identity QR', 'hi': 'किसान पहचान QR', 'mr': 'शेतकरी ओळख QR'},
    'personal_information': {'en': 'Personal Information', 'hi': 'व्यक्तिगत जानकारी', 'mr': 'वैयक्तिक माहिती'},
    'farmer_id': {'en': 'Farmer ID', 'hi': 'किसान ID', 'mr': 'शेतकरी ID'},
    'phone_number': {'en': 'Phone Number', 'hi': 'फ़ोन नंबर', 'mr': 'फोन नंबर'},
    'location': {'en': 'Location', 'hi': 'स्थान', 'mr': 'ठिकाण'},
    'gender': {'en': 'Gender', 'hi': 'लिंग', 'mr': 'लिंग'},
    'male': {'en': 'Male', 'hi': 'पुरुष', 'mr': 'पुरुष'},
    'age': {'en': 'Age', 'hi': 'उम्र', 'mr': 'वय'},
    'years': {'en': 'years', 'hi': 'वर्ष', 'mr': 'वर्षे'},
    'farm_statistics': {'en': 'Farm Statistics', 'hi': 'खेत आँकड़े', 'mr': 'शेत आकडेवारी'},
    'primary_farm': {'en': 'Primary Farm', 'hi': 'मुख्य खेत', 'mr': 'मुख्य शेत'},
    'total_area': {'en': 'Total Area', 'hi': 'कुल क्षेत्र', 'mr': 'एकूण क्षेत्र'},
    'current_crop': {'en': 'Current Crop', 'hi': 'वर्तमान फसल', 'mr': 'सध्याचे पीक'},
    'soil_health': {'en': 'Soil Health', 'hi': 'मृदा स्वास्थ्य', 'mr': 'माती आरोग्य'},
    'excellent': {'en': 'Excellent', 'hi': 'उत्कृष्ट', 'mr': 'उत्कृष्ट'},
    'rewards_achievements': {
      'en': 'Rewards & Achievements',
      'hi': 'पुरस्कार और उपलब्धियाँ',
      'mr': 'बक्षिसे आणि यश',
    },
    'top_harvester': {'en': 'Top Harvester', 'hi': 'शीर्ष कटाईकर्ता', 'mr': 'अव्वल कापणीदार'},
    'organic_pro': {'en': 'Organic Pro', 'hi': 'ऑर्गेनिक प्रो', 'mr': 'सेंद्रिय प्रो'},
    'early_adopter': {'en': 'Early Adopter', 'hi': 'अर्ली अडॉप्टर', 'mr': 'लवकर स्वीकारणारा'},
    'settings_support': {'en': 'Settings & Support', 'hi': 'सेटिंग्स और सहायता', 'mr': 'सेटिंग्ज आणि मदत'},
    'trusted_profile': {'en': 'Trusted Profile', 'hi': 'विश्वसनीय प्रोफ़ाइल', 'mr': 'विश्वासार्ह प्रोफाइल'},
    'account_settings': {'en': 'Account Settings', 'hi': 'खाता सेटिंग्स', 'mr': 'खाते सेटिंग्ज'},
    'help_support': {'en': 'Help & Support', 'hi': 'मदद और सहायता', 'mr': 'मदत आणि सहाय्य'},
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

    // ── Weather ──
    'weather_forecast': {'en': 'Weather Forecast', 'hi': 'मौसम पूर्वानुमान', 'mr': 'हवामान अंदाज'},
    'weather': {'en': 'Weather', 'hi': 'मौसम', 'mr': 'हवामान'},
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
    'rain_prob': {'en': 'Rain Prob.', 'hi': 'वर्षा संभावना', 'mr': 'पाऊस शक्यता'},
    'irrigation': {'en': 'Irrigation', 'hi': 'सिंचाई', 'mr': 'सिंचन'},
    'pest_risk': {'en': 'Pest risk', 'hi': 'कीट जोखिम', 'mr': 'कीड धोका'},
    'sync': {'en': 'Sync', 'hi': 'सिंक', 'mr': 'सिंक'},
  };
}
