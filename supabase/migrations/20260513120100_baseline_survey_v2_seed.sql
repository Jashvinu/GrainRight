delete from public.dropdown_options
where option_key in (
  'education_v2','gender_v2','category_v2','income_sources_v2',
  'farming_type_v2','main_crop_v2'
);

delete from public.form_fields
where field_key in (
  'language','farmer_name','village','gram_panchayat','taluka','district',
  'mobile_number','aadhaar_number','date_of_birth','education','gender',
  'category','income_sources','farming_type','owns_farmland',
  'total_land_area_acre','irrigated_land_acre','dry_land_acre',
  'fallow_land_acre','leased_land_acre','rain_based_area_acre',
  'has_forest_patta','forest_patta_acre','applied_for_forest_patta',
  'farm_polygon','main_crop','main_crop_other','main_crop_land_acre',
  'other_crop_land_acre','other_crop_details','annual_agri_income',
  'non_agri_income','total_annual_income','makes_food_products',
  'food_products_list','food_product_training_received',
  'food_product_training_source','repeat_kharif_crops','repeat_other_crops',
  'repeat_main_crop_practices','repeat_main_crop_yearly',
  'repeat_other_crop_practices'
);

delete from public.form_sections
where title in (
  'Family Information','Land / Farming','Forest Patta','Farm Boundary',
  'Main Crop','Kharif Crops','Other Crops','Main Crop Agronomy',
  'Main Crop 3-Year Production','Income & Food Products',
  'Other Crop Agronomy'
);

insert into public.form_sections (id, title, icon_name, sort_order, is_active)
values
  (gen_random_uuid(), 'Family Information', 'person', 10, true),
  (gen_random_uuid(), 'Land / Farming', 'landscape', 20, true),
  (gen_random_uuid(), 'Forest Patta', 'forest', 30, true),
  (gen_random_uuid(), 'Farm Boundary', 'map', 40, true),
  (gen_random_uuid(), 'Main Crop', 'grass', 50, true),
  (gen_random_uuid(), 'Kharif Crops', 'eco', 60, true),
  (gen_random_uuid(), 'Other Crops', 'eco', 65, true),
  (gen_random_uuid(), 'Main Crop Agronomy', 'agriculture', 70, true),
  (gen_random_uuid(), 'Other Crop Agronomy', 'agriculture', 75, true),
  (gen_random_uuid(), 'Main Crop 3-Year Production', 'bar_chart', 80, true),
  (gen_random_uuid(), 'Income & Food Products', 'currency_rupee', 90, true);

with sections as (
  select id, title from public.form_sections
)
insert into public.form_fields (
  id, section_id, field_key, label, label_hi, label_mr, input_type,
  sort_order, is_required, validation, visibility_rule, auto_calc_formula,
  dropdown_options_key, hint_text, hint_text_hi, hint_text_mr, suffix_text,
  crop_role, repeat_group
)
values
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'farmer_name', 'Farmer Name', 'किसान का नाम', 'शेतकऱ्याचे नाव', 'text', 10, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'village', 'Village', 'गांव', 'गाव', 'text', 20, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'gram_panchayat', 'Gram Panchayat', 'ग्राम पंचायत', 'ग्रामपंचायत', 'text', 30, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'taluka', 'Taluka', 'तालुका', 'तालुका', 'text', 40, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'district', 'District', 'जिला', 'जिल्हा', 'text', 50, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'mobile_number', 'Mobile No.', 'मोबाइल नंबर', 'मोबाईल क्र.', 'mobile', 60, false, '{"regex":"^[0-9]{10}$","regex_message":"Enter a 10 digit mobile number"}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'aadhaar_number', 'Aadhaar No.', 'आधार नंबर', 'आधार क्र.', 'aadhar', 70, false, '{"regex":"^[0-9]{12}$","regex_message":"Enter a 12 digit Aadhaar number"}'::jsonb, null, null, null, 'XXXX XXXX XXXX', 'XXXX XXXX XXXX', 'XXXX XXXX XXXX', null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'date_of_birth', 'Date of Birth', 'जन्म तिथि', 'जन्म तारीख', 'date', 80, false, '{"date_max":"today"}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'education', 'Education', 'शिक्षा', 'शिक्षण', 'dropdown', 90, false, '{}'::jsonb, null, null, 'education_v2', null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'gender', 'Gender', 'लिंग', 'लिंग', 'dropdown', 100, false, '{}'::jsonb, null, null, 'gender_v2', null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'category', 'Category', 'वर्ग', 'वर्ग', 'dropdown', 110, false, '{}'::jsonb, null, null, 'category_v2', null, null, null, null, null, null),

  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'income_sources', 'Income sources', 'आय के स्रोत', 'उत्पन्नाचे स्रोत', 'multiselect', 10, true, '{}'::jsonb, null, null, 'income_sources_v2', null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'farming_type', 'Farming type', 'खेती का प्रकार', 'शेतीचा प्रकार', 'multiselect', 20, true, '{}'::jsonb, null, null, 'farming_type_v2', null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'owns_farmland', 'Owns farmland?', 'क्या खेत की जमीन है?', 'स्वतःची शेतजमीन आहे का?', 'boolean', 30, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'total_land_area_acre', 'Total land area', 'कुल जमीन', 'एकूण जमीन', 'acre', 40, true, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'irrigated_land_acre', 'Irrigated land', 'सिंचित जमीन', 'सिंचित जमीन', 'acre', 50, false, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'dry_land_acre', 'Dry land', 'सूखी जमीन', 'कोरडवाहू जमीन', 'acre', 60, false, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'fallow_land_acre', 'Fallow land', 'परती जमीन', 'पडीत जमीन', 'acre', 70, false, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'leased_land_acre', 'Leased land', 'पट्टे की जमीन', 'भाडेपट्ट्याची जमीन', 'acre', 80, false, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land / Farming'), 'rain_based_area_acre', 'Rain-based area', 'वर्षा आधारित क्षेत्र', 'पावसावर आधारित क्षेत्र', 'acre', 90, false, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),

  (gen_random_uuid(), (select id from sections where title='Forest Patta'), 'has_forest_patta', 'Has forest patta?', 'क्या वन पट्टा है?', 'वन पट्टा आहे का?', 'boolean', 10, true, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Forest Patta'), 'forest_patta_acre', 'Forest patta area', 'वन पट्टा क्षेत्र', 'वन पट्टा क्षेत्र', 'acre', 20, false, '{}'::jsonb, '{"depends_on":"has_forest_patta","operator":"equals","value":true}'::jsonb, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Forest Patta'), 'applied_for_forest_patta', 'Applied for forest patta?', 'क्या वन पट्टा के लिए आवेदन किया?', 'वन पट्ट्यासाठी अर्ज केला आहे का?', 'boolean', 30, false, '{}'::jsonb, '{"depends_on":"has_forest_patta","operator":"equals","value":false}'::jsonb, null, null, null, null, null, null, null, null),

  (gen_random_uuid(), (select id from sections where title='Farm Boundary'), 'farm_polygon', 'Farm Boundary Polygon (optional)', 'खेत की सीमा (वैकल्पिक)', 'शेताची सीमा (ऐच्छिक)', 'polygon_pencil', 10, false, '{}'::jsonb, null, null, null, 'Draw if time permits; submission is allowed without it.', 'समय हो तो बनाएं; इसके बिना भी जमा कर सकते हैं।', 'वेळ असल्यास रेखाटा; याशिवायही सबमिट करता येईल.', null, null, null),

  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'main_crop', 'Main crop', 'मुख्य फसल', 'मुख्य पीक', 'dropdown', 10, true, '{}'::jsonb, null, null, 'main_crop_v2', null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'main_crop_other', 'Other crop name', 'अन्य फसल का नाम', 'इतर पिकाचे नाव', 'text', 20, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"equals","value":"other"}'::jsonb, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'other_crop_details', 'Other crop details', 'अन्य फसल विवरण', 'इतर पिकाचा तपशील', 'text', 30, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"equals","value":"other"}'::jsonb, null, null, 'Variety, local name, or field notes', 'किस्म, स्थानीय नाम या नोट्स', 'जात, स्थानिक नाव किंवा नोंदी', null, null, null),
  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'main_crop_land_acre', 'Land under main crop', 'मुख्य फसल का क्षेत्र', 'मुख्य पिकाखालील जमीन', 'acre', 40, false, '{}'::jsonb, null, null, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'other_crop_land_acre', 'Land under other crop', 'अन्य फसल का क्षेत्र', 'इतर पिकाखालील जमीन', 'acre', 50, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"contains_any","value":["bajra","other"]}'::jsonb, null, null, null, null, null, 'acre', null, null),

  (gen_random_uuid(), (select id from sections where title='Kharif Crops'), 'repeat_kharif_crops', 'Crops taken in Kharif season', 'खरीफ मौसम की फसलें', 'खरीप हंगामातील पिके', 'text', 10, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"contains_any","value":["paddy","nachani"]}'::jsonb, null, null, 'Add each crop with area, variety, production, and estimated cost.', 'प्रत्येक फसल का क्षेत्र, किस्म, उत्पादन और अनुमानित लागत जोड़ें।', 'प्रत्येक पिकाचे क्षेत्र, जात, उत्पादन आणि अंदाजित खर्च जोडा.', null, null, 'kharif_crops'),
  (gen_random_uuid(), (select id from sections where title='Other Crops'), 'repeat_other_crops', 'Other crops taken', 'ली गई अन्य फसलें', 'घेतलेली इतर पिके', 'text', 10, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"contains_any","value":["bajra","other"]}'::jsonb, null, null, 'Add other crop rows with area, variety, production, and estimated cost.', 'अन्य फसल की पंक्तियां क्षेत्र, किस्म, उत्पादन और लागत सहित जोड़ें।', 'इतर पिकांच्या नोंदी क्षेत्र, जात, उत्पादन आणि खर्चासह जोडा.', null, null, 'other_crops'),
  (gen_random_uuid(), (select id from sections where title='Main Crop Agronomy'), 'repeat_main_crop_practices', 'Rice/Ragi main crop agronomy practices', 'धान/रागी मुख्य फसल की कृषि पद्धतियां', 'भात/नाचणी मुख्य पिकाच्या कृषी पद्धती', 'text', 10, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"contains_any","value":["paddy","nachani"]}'::jsonb, null, null, 'Seed, nursery, land preparation, transplanting, pest, fertilizer, monitoring, and harvest details.', 'बीज, नर्सरी, भूमि तैयारी, रोपाई, कीट, उर्वरक, निगरानी और कटाई विवरण।', 'बियाणे, रोपवाटिका, जमीन तयारी, लागवड, कीड, खत, पाहणी आणि कापणी तपशील.', null, 'main', 'crop_practices'),
  (gen_random_uuid(), (select id from sections where title='Main Crop 3-Year Production'), 'repeat_main_crop_yearly', 'Main crop production for last 3 years', 'पिछले 3 वर्षों का मुख्य फसल उत्पादन', 'मागील 3 वर्षांचे मुख्य पिक उत्पादन', 'text', 10, false, '{}'::jsonb, null, null, null, 'Production history for 2023, 2024, and 2025.', '2023, 2024 और 2025 का उत्पादन इतिहास।', '2023, 2024 आणि 2025 चा उत्पादन इतिहास.', null, null, 'main_crop_yearly'),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'annual_agri_income', 'Annual agricultural income', 'वार्षिक कृषि आय', 'वार्षिक कृषी उत्पन्न', 'currency', 10, false, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'non_agri_income', 'Non-agricultural income', 'गैर-कृषि आय', 'बिगर-कृषी उत्पन्न', 'currency', 20, false, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'total_annual_income', 'Total annual income', 'कुल वार्षिक आय', 'एकूण वार्षिक उत्पन्न', 'auto_calc', 30, false, '{}'::jsonb, null, '{"operation":"sum","operands":["annual_agri_income","non_agri_income"]}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'makes_food_products', 'Makes food products?', 'क्या खाद्य उत्पाद बनाते हैं?', 'खाद्य उत्पाद बनवता का?', 'boolean', 40, false, '{}'::jsonb, null, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'food_products_list', 'Food products list', 'खाद्य उत्पादों की सूची', 'खाद्य उत्पादनांची यादी', 'text', 50, false, '{}'::jsonb, '{"depends_on":"makes_food_products","operator":"equals","value":true}'::jsonb, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'food_product_training_received', 'Food product training received?', 'क्या खाद्य उत्पाद प्रशिक्षण मिला?', 'खाद्य उत्पादनाचे प्रशिक्षण मिळाले का?', 'boolean', 60, false, '{}'::jsonb, '{"depends_on":"makes_food_products","operator":"equals","value":true}'::jsonb, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'food_product_training_source', 'Food product training source', 'प्रशिक्षण स्रोत', 'प्रशिक्षण स्रोत', 'text', 70, false, '{}'::jsonb, '{"depends_on":"food_product_training_received","operator":"equals","value":true}'::jsonb, null, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Other Crop Agronomy'), 'repeat_other_crop_practices', 'Bajra/other crop agronomy practices', 'बाजरा/अन्य फसल कृषि पद्धतियां', 'बाजरी/इतर पिकाच्या कृषी पद्धती', 'text', 10, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"contains_any","value":["bajra","other"]}'::jsonb, null, null, 'Fill seed, land preparation, pest, fertilizer, monitoring, harvest, and selling details.', 'बीज, भूमि तैयारी, कीट, उर्वरक, निगरानी, कटाई और बिक्री विवरण भरें।', 'बियाणे, जमीन तयारी, कीड, खत, पाहणी, कापणी आणि विक्री तपशील भरा.', null, 'other', 'crop_practices');

insert into public.dropdown_options (id, option_key, value, label, label_hi, label_mr, sort_order, is_active)
values
  (gen_random_uuid(), 'education_v2', 'illiterate', 'Illiterate', 'निरक्षर', 'निरक्षर', 10, true),
  (gen_random_uuid(), 'education_v2', 'primary', 'Primary', 'प्राथमिक', 'प्राथमिक', 20, true),
  (gen_random_uuid(), 'education_v2', 'secondary', 'Secondary', 'माध्यमिक', 'माध्यमिक', 30, true),
  (gen_random_uuid(), 'education_v2', 'graduate', 'Graduate', 'स्नातक', 'पदवीधर', 40, true),
  (gen_random_uuid(), 'gender_v2', 'male', 'Male', 'पुरुष', 'पुरुष', 10, true),
  (gen_random_uuid(), 'gender_v2', 'female', 'Female', 'महिला', 'स्त्री', 20, true),
  (gen_random_uuid(), 'gender_v2', 'other', 'Other', 'अन्य', 'इतर', 30, true),
  (gen_random_uuid(), 'category_v2', 'general', 'General', 'सामान्य', 'सामान्य', 10, true),
  (gen_random_uuid(), 'category_v2', 'sc', 'SC', 'अनुसूचित जाति', 'अनुसूचित जाती', 20, true),
  (gen_random_uuid(), 'category_v2', 'st', 'ST', 'अनुसूचित जनजाति', 'अनुसूचित जमाती', 30, true),
  (gen_random_uuid(), 'category_v2', 'obc', 'OBC', 'ओबीसी', 'ओबीसी', 40, true),
  (gen_random_uuid(), 'income_sources_v2', 'farming', 'Farming', 'खेती', 'शेती', 10, true),
  (gen_random_uuid(), 'income_sources_v2', 'business', 'Business', 'व्यवसाय', 'व्यवसाय', 20, true),
  (gen_random_uuid(), 'income_sources_v2', 'govt_job', 'Government job', 'सरकारी नौकरी', 'सरकारी नोकरी', 30, true),
  (gen_random_uuid(), 'income_sources_v2', 'private_job', 'Private job', 'निजी नौकरी', 'खाजगी नोकरी', 40, true),
  (gen_random_uuid(), 'income_sources_v2', 'other', 'Other', 'अन्य', 'इतर', 50, true),
  (gen_random_uuid(), 'farming_type_v2', 'rainfed', 'Rainfed', 'वर्षा आधारित', 'पावसावर आधारित', 10, true),
  (gen_random_uuid(), 'farming_type_v2', 'irrigated', 'Irrigated', 'सिंचित', 'सिंचित', 20, true),
  (gen_random_uuid(), 'farming_type_v2', 'other', 'Other', 'अन्य', 'इतर', 30, true),
  (gen_random_uuid(), 'main_crop_v2', 'paddy', 'Paddy (Rice)', 'धान', 'भात', 10, true),
  (gen_random_uuid(), 'main_crop_v2', 'nachani', 'Nachani (Ragi)', 'नाचनी', 'नाचणी', 20, true),
  (gen_random_uuid(), 'main_crop_v2', 'bajra', 'Bajra', 'बाजरा', 'बाजरी', 30, true),
  (gen_random_uuid(), 'main_crop_v2', 'other', 'Other', 'अन्य', 'इतर', 40, true);
