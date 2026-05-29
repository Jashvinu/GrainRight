update public.form_fields
set label_mr = 'पडीत जमीन', updated_at = now()
where field_key = 'fallow_land_acre';
update public.dropdown_options as target
set label_mr = source.label_mr
from (
  values
    ('disease_name_common', 'Blast', 'करपा'),
    ('disease_name_common', 'Leaf blast', 'पानावरील करपा'),
    ('disease_name_common', 'Neck blast', 'मान करपा'),
    ('disease_name_common', 'Finger blast', 'कणसावरील करपा'),
    ('disease_name_common', 'Brown spot', 'तपकिरी ठिपका'),
    ('disease_name_common', 'Sheath blight', 'खोडावरील करपा'),
    ('disease_name_common', 'Bacterial leaf blight', 'जीवाणूजन्य पान करपा'),
    ('disease_name_common', 'Bacterial leaf streak', 'जीवाणूजन्य पान रेषा'),
    ('disease_name_common', 'False smut', 'खोटा काणी रोग'),
    ('disease_name_common', 'Tungro', 'टुंग्रो रोग'),
    ('disease_name_common', 'Downy mildew', 'केवडा रोग'),
    ('disease_name_common', 'Green ear disease', 'हिरवा कणीस रोग'),
    ('disease_name_common', 'Ergot', 'अरगट रोग'),
    ('disease_name_common', 'Smut', 'काणी रोग'),
    ('disease_name_common', 'Rust', 'तांबेरा रोग'),
    ('disease_name_common', 'Grain mold', 'दाणा बुरशी'),
    ('disease_name_common', 'Foot rot', 'खोड कुज'),
    ('disease_name_common', 'Seedling blight', 'रोप करपा'),

    ('crop_variety_bajra', 'Dhanshakti', 'धनशक्ती'),
    ('crop_variety_bajra', 'ICTP 8203', 'आयसीटीपी ८२०३'),
    ('crop_variety_bajra', 'Phule Adishakti', 'फुले आदिशक्ती'),
    ('crop_variety_bajra', 'Phule Mahashakti', 'फुले महाशक्ती'),
    ('crop_variety_bajra', 'Pusa Composite 612', 'पुसा कॉम्पोझिट ६१२'),
    ('crop_variety_bajra', 'ICMV 221', 'आयसीएमव्ही २२१'),
    ('crop_variety_bajra', 'ICMV 155', 'आयसीएमव्ही १५५'),
    ('crop_variety_bajra', 'AIMP 92901 Samrudhi', 'एआयएमपी ९२९०१ समृद्धी'),

    ('crop_variety_nachani', 'GPU 28', 'जीपीयू २८'),
    ('crop_variety_nachani', 'GPU 67', 'जीपीयू ६७'),
    ('crop_variety_nachani', 'GPU 66', 'जीपीयू ६६'),
    ('crop_variety_nachani', 'VL Mandua', 'व्हीएल मांडुआ'),
    ('crop_variety_nachani', 'Dapoli 1', 'दापोली १'),
    ('crop_variety_nachani', 'Phule Nachani', 'फुले नाचणी'),
    ('crop_variety_nachani', 'MR 6', 'एमआर ६'),

    ('crop_variety_paddy', 'Indrayani', 'इंद्रायणी'),
    ('crop_variety_paddy', 'Ambemohar', 'आंबेमोहोर'),
    ('crop_variety_paddy', 'Phule Maval', 'फुले मावळ'),
    ('crop_variety_paddy', 'Phule Samruddhi', 'फुले समृद्धी'),
    ('crop_variety_paddy', 'Jaya', 'जया'),
    ('crop_variety_paddy', 'Kolam', 'कोलम'),
    ('crop_variety_paddy', 'HMT', 'एचएमटी'),
    ('crop_variety_paddy', 'Sona Masuri', 'सोना मसुरी')
) as source(option_key, value, label_mr)
where target.option_key = source.option_key
  and target.value = source.value;
