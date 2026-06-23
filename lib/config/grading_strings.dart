import 'package:get/get.dart';

import 'locale_text.dart';

/// Self-contained, locale-aware strings for the AI grain-grading flow.
///
/// The legacy `AppTranslations.translate()` resolves Marathi-only (Hindi always
/// falls back to English), so the grading flow ships its own en/hi/mr table to
/// honour the Marathi/Hindi-first, minimal-text audience without touching the
/// survey i18n other screens depend on. See docs/10_uiux_flow_audit.md §3.1.
class GradingStrings {
  GradingStrings._();

  static String _lang() {
    final code = Get.locale?.languageCode ?? 'en';
    return (code == 'mr' || code == 'hi') ? code : 'en';
  }

  /// Look up a key for the active locale, falling back to English then the key.
  static String t(String key) {
    final row = _data[key];
    if (row == null) return key;
    return LocaleText.digits(row[_lang()] ?? row['en'] ?? key);
  }

  static const Map<String, Map<String, String>> _data = {
    'title': {'en': 'Grain Grading', 'hi': 'अनाज ग्रेडिंग', 'mr': 'धान्य ग्रेडिंग'},
    'step_setup': {'en': 'Batch', 'hi': 'बैच', 'mr': 'बॅच'},
    'step_crop': {'en': 'Crop', 'hi': 'फसल', 'mr': 'पीक'},
    'step_grain': {'en': 'Grain photo', 'hi': 'अनाज फोटो', 'mr': 'धान्य फोटो'},
    'step_moisture': {'en': 'Moisture', 'hi': 'नमी', 'mr': 'ओलावा'},
    'step_result': {'en': 'Result', 'hi': 'परिणाम', 'mr': 'निकाल'},

    'choose_crop': {'en': 'Choose your crop', 'hi': 'अपनी फसल चुनें', 'mr': 'तुमचे पीक निवडा'},
    'setup_batch': {
      'en': 'Farm and batch details',
      'hi': 'खेत और बैच विवरण',
      'mr': 'शेत आणि बॅच तपशील',
    },
    'choose_variety': {'en': 'Choose variety', 'hi': 'किस्म चुनें', 'mr': 'वाण निवडा'},
    'next': {'en': 'Next', 'hi': 'आगे', 'mr': 'पुढे'},
    'back': {'en': 'Back', 'hi': 'पीछे', 'mr': 'मागे'},

    'take_grain_photo': {
      'en': 'Photograph the grain',
      'hi': 'अनाज की फोटो लें',
      'mr': 'धान्याचा फोटो घ्या',
    },
    'grain_hint': {
      'en': 'Spread grain on a plain surface in good light.',
      'hi': 'साफ़ सतह पर अच्छी रोशनी में अनाज फैलाएँ।',
      'mr': 'स्वच्छ पृष्ठभागावर चांगल्या प्रकाशात धान्य पसरवा.',
    },
    'take_moisture_photo': {
      'en': 'Photograph the moisture meter',
      'hi': 'नमी मीटर की फोटो लें',
      'mr': 'ओलावा मीटरचा फोटो घ्या',
    },
    'moisture_hint': {
      'en': 'Point the camera at the number on the meter.',
      'hi': 'कैमरा मीटर के नंबर पर रखें।',
      'mr': 'कॅमेरा मीटरवरील आकड्यावर धरा.',
    },
    'camera': {'en': 'Camera', 'hi': 'कैमरा', 'mr': 'कॅमेरा'},
    'gallery': {'en': 'Gallery', 'hi': 'गैलरी', 'mr': 'गॅलरी'},
    'retake': {'en': 'Retake', 'hi': 'फिर लें', 'mr': 'पुन्हा घ्या'},
    'enter_moisture': {
      'en': 'Or type moisture %',
      'hi': 'या नमी % लिखें',
      'mr': 'किंवा ओलावा % लिहा',
    },
    'moisture_percent': {'en': 'Moisture %', 'hi': 'नमी %', 'mr': 'ओलावा %'},

    'check_grade': {'en': 'Check grade', 'hi': 'ग्रेड जाँचें', 'mr': 'ग्रेड तपासा'},
    'read_moisture': {'en': 'Read moisture', 'hi': 'नमी पढ़ें', 'mr': 'ओलावा वाचा'},
    'checking': {'en': 'Checking…', 'hi': 'जाँच हो रही है…', 'mr': 'तपासत आहे…'},
    'checking_hint': {
      'en': 'Reading your photos and grading rules.',
      'hi': 'आपकी फोटो और नियम पढ़े जा रहे हैं।',
      'mr': 'तुमचे फोटो आणि नियम वाचत आहोत.',
    },

    'grade_label': {'en': 'Grade', 'hi': 'ग्रेड', 'mr': 'ग्रेड'},
    'confidence': {'en': 'Confidence', 'hi': 'विश्वास', 'mr': 'खात्री'},
    'moisture_label': {'en': 'Moisture', 'hi': 'नमी', 'mr': 'ओलावा'},
    'needs_human_check': {
      'en': 'Needs a human check',
      'hi': 'मनुष्य जाँच ज़रूरी',
      'mr': 'माणसाची तपासणी हवी',
    },
    'why': {'en': 'Why this grade', 'hi': 'यह ग्रेड क्यों', 'mr': 'हा ग्रेड का'},
    'looks_wrong': {'en': 'Looks wrong?', 'hi': 'ग़लत लगता है?', 'mr': 'चुकीचे वाटते?'},
    'generate_qr': {
      'en': 'Make Harvest QR',
      'hi': 'कापणी क्यूआर बनाएँ',
      'mr': 'कापणी क्यूआर बनवा',
    },
    'grade_again': {'en': 'Grade again', 'hi': 'फिर ग्रेड करें', 'mr': 'पुन्हा ग्रेड करा'},

    'risk_low': {'en': 'Safe to store', 'hi': 'भंडारण सुरक्षित', 'mr': 'साठवण सुरक्षित'},
    'risk_moderate': {'en': 'Dry a little', 'hi': 'थोड़ा सुखाएँ', 'mr': 'थोडे वाळवा'},
    'risk_high': {'en': 'Too wet — dry it', 'hi': 'बहुत गीला — सुखाएँ', 'mr': 'खूप ओले — वाळवा'},
    'risk_critical': {'en': 'Do not store yet', 'hi': 'अभी भंडारण न करें', 'mr': 'अजून साठवू नका'},

    'offline_title': {'en': 'Connect to grade', 'hi': 'ग्रेडिंग हेतु कनेक्ट करें', 'mr': 'ग्रेडिंगसाठी कनेक्ट करा'},
    'offline_body': {
      'en': 'Grain grading needs the internet. Connect and try again.',
      'hi': 'ग्रेडिंग के लिए इंटरनेट चाहिए। कनेक्ट करके फिर कोशिश करें।',
      'mr': 'ग्रेडिंगसाठी इंटरनेट हवे. कनेक्ट करून पुन्हा प्रयत्न करा.',
    },
    'not_configured': {
      'en': 'Grading service is not set up yet.',
      'hi': 'ग्रेडिंग सेवा अभी सेट नहीं है।',
      'mr': 'ग्रेडिंग सेवा अजून सेट नाही.',
    },
    'retry': {'en': 'Try again', 'hi': 'फिर कोशिश करें', 'mr': 'पुन्हा प्रयत्न करा'},
    'error_generic': {
      'en': 'Something went wrong. Try again.',
      'hi': 'कुछ ग़लत हुआ। फिर कोशिश करें।',
      'mr': 'काहीतरी चुकले. पुन्हा प्रयत्न करा.',
    },

    'feedback_title': {'en': 'What is the right grade?', 'hi': 'सही ग्रेड क्या है?', 'mr': 'योग्य ग्रेड कोणता?'},
    'feedback_thanks': {'en': 'Thanks — saved', 'hi': 'धन्यवाद — सहेजा गया', 'mr': 'धन्यवाद — जतन केले'},
    'submit': {'en': 'Send', 'hi': 'भेजें', 'mr': 'पाठवा'},
    'fpc_title': {
      'en': 'FPC Grain Grading',
      'hi': 'किसान उत्पादक कंपनी अनाज ग्रेडिंग',
      'mr': 'शेतकरी उत्पादक कंपनी धान्य ग्रेडिंग',
    },
    'farmer': {'en': 'Farmer', 'hi': 'किसान', 'mr': 'शेतकरी'},
    'farm_name': {'en': 'Farm name', 'hi': 'खेत का नाम', 'mr': 'शेताचे नाव'},
    'location': {'en': 'Location', 'hi': 'स्थान', 'mr': 'ठिकाण'},
    'batch_id': {
      'en': 'Batch ID',
      'hi': 'बैच पहचान क्रमांक',
      'mr': 'बॅच ओळख क्रमांक',
    },
    'fpo_approval_required': {
      'en': 'FPO approval is required before QR generation.',
      'hi': 'क्यूआर बनाने से पहले किसान उत्पादक संस्था की मंज़ूरी जरूरी है।',
      'mr': 'क्यूआर तयार करण्यापूर्वी शेतकरी उत्पादक संस्थेची मंजुरी आवश्यक आहे.',
    },
    'complete_qr_details_first': {
      'en': 'Complete farmer, farm, batch, bag, and grading details first.',
      'hi': 'पहले किसान, खेत, बैच, बोरी और ग्रेडिंग विवरण पूरा करें।',
      'mr': 'प्रथम शेतकरी, शेत, बॅच, पोते आणि ग्रेडिंग तपशील पूर्ण करा.',
    },
    'fpc_customer_lot': {
      'en': 'FPC customer lot',
      'hi': 'किसान उत्पादक कंपनी ग्राहक लॉट',
      'mr': 'शेतकरी उत्पादक कंपनी ग्राहक लॉट',
    },
    'farmer_farm_lot': {
      'en': 'Farmer farm lot',
      'hi': 'किसान खेत लॉट',
      'mr': 'शेतकरी शेत लॉट',
    },
    'generate_public_trace_qr': {
      'en': 'Generate public trace QR',
      'hi': 'सार्वजनिक ट्रेस क्यूआर बनाएं',
      'mr': 'सार्वजनिक ट्रेस क्यूआर तयार करा',
    },
    'ai_grading': {
      'en': 'AI grading',
      'hi': 'एआई ग्रेडिंग',
      'mr': 'एआय ग्रेडिंग',
    },
    'generated_automatically': {
      'en': 'Generated automatically',
      'hi': 'अपने आप बना',
      'mr': 'आपोआप तयार',
    },
    'bag_kg': {'en': 'Bag kg', 'hi': 'बोरी kg', 'mr': 'पोते kg'},
    'bags': {'en': 'Bags', 'hi': 'बोरी', 'mr': 'पोती'},
    'finger_millet_ragi': {
      'en': 'Finger Millet (Ragi)',
      'hi': 'रागी',
      'mr': 'नाचणी',
    },
    'local': {'en': 'Local', 'hi': 'स्थानीय', 'mr': 'स्थानिक'},
    'farmer_name_unavailable': {
      'en': 'Farmer name unavailable',
      'hi': 'किसान का नाम उपलब्ध नहीं',
      'mr': 'शेतकऱ्याचे नाव उपलब्ध नाही',
    },
    'no_farm_selected': {
      'en': 'No farm selected',
      'hi': 'कोई खेत चुना नहीं',
      'mr': 'शेत निवडले नाही',
    },
    'location_unavailable': {
      'en': 'Location unavailable',
      'hi': 'स्थान उपलब्ध नहीं',
      'mr': 'ठिकाण उपलब्ध नाही',
    },
    'cloud_score': {'en': 'Cloud score', 'hi': 'क्लाउड स्कोर', 'mr': 'क्लाउड स्कोअर'},
    'score_grade': {'en': 'Score grade', 'hi': 'स्कोर ग्रेड', 'mr': 'स्कोअर ग्रेड'},
    'model_suggested': {
      'en': 'Model suggested',
      'hi': 'मॉडल सुझाव',
      'mr': 'मॉडेल सूचना',
    },
    'grain_score': {'en': 'Grain score', 'hi': 'अनाज स्कोर', 'mr': 'धान्य स्कोअर'},
    'moisture_score': {'en': 'Moisture score', 'hi': 'नमी स्कोर', 'mr': 'ओलावा स्कोअर'},
    'broken_grain': {'en': 'Broken grain', 'hi': 'टूटा अनाज', 'mr': 'तुटलेले धान्य'},
    'foreign_matter': {'en': 'Foreign matter', 'hi': 'बाहरी पदार्थ', 'mr': 'परकीय घटक'},
    'damaged_grain': {'en': 'Damaged grain', 'hi': 'क्षतिग्रस्त अनाज', 'mr': 'नुकसान झालेले धान्य'},
    'uniformity': {'en': 'Uniformity', 'hi': 'एकरूपता', 'mr': 'एकसारखेपणा'},
    'cloud_model_analysis': {
      'en': 'Cloud Model Analysis',
      'hi': 'क्लाउड मॉडल विश्लेषण',
      'mr': 'क्लाउड मॉडेल विश्लेषण',
    },
  };
}
