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
  'farm_polygon','main_crop','main_crop_land_acre','annual_agri_income',
  'non_agri_income','total_annual_income','makes_food_products',
  'food_products_list','food_product_training_received',
  'food_product_training_source','repeat_kharif_crops',
  'repeat_main_crop_practices','repeat_main_crop_yearly',
  'repeat_other_crop_practices'
);
delete from public.form_sections
where title in (
  'Family Information','Income Sources','Land Holding','Forest Patta',
  'Farm Boundary','Main Crop','Kharif Crops','Main Crop Agronomy',
  'Main Crop 3-Year Production','Income & Food Products','Other Crop Agronomy'
);
insert into public.form_sections (id, title, icon_name, sort_order, is_active)
values
  (gen_random_uuid(), 'Family Information', 'person', 10, true),
  (gen_random_uuid(), 'Income Sources', 'payments', 20, true),
  (gen_random_uuid(), 'Land Holding', 'landscape', 30, true),
  (gen_random_uuid(), 'Forest Patta', 'forest', 40, true),
  (gen_random_uuid(), 'Farm Boundary', 'map', 50, true),
  (gen_random_uuid(), 'Main Crop', 'grass', 60, true),
  (gen_random_uuid(), 'Kharif Crops', 'eco', 70, true),
  (gen_random_uuid(), 'Main Crop Agronomy', 'agriculture', 80, true),
  (gen_random_uuid(), 'Main Crop 3-Year Production', 'bar_chart', 90, true),
  (gen_random_uuid(), 'Income & Food Products', 'currency_rupee', 110, true),
  (gen_random_uuid(), 'Other Crop Agronomy', 'agriculture', 120, true);
with sections as (
  select id, title from public.form_sections
)
insert into public.form_fields (
  id, section_id, field_key, label, label_hi, label_mr, input_type,
  sort_order, is_required, validation, visibility_rule, auto_calc_formula,
  dropdown_options_key, hint_text, suffix_text, crop_role, repeat_group
)
values
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'farmer_name', 'Farmer Name', 'किसान का नाम', 'शेतकऱ्याचे नाव', 'text', 10, true, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'village', 'Village', 'गांव', 'गाव', 'text', 20, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'gram_panchayat', 'Gram Panchayat', 'ग्राम पंचायत', 'ग्रामपंचायत', 'text', 30, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'taluka', 'Taluka', 'तालुका', 'तालुका', 'text', 40, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'district', 'District', 'जिला', 'जिल्हा', 'text', 50, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'mobile_number', 'Mobile No.', 'मोबाइल नंबर', 'मोबाईल क्र.', 'mobile', 60, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'aadhaar_number', 'Aadhaar No.', 'आधार नंबर', 'आधार क्र.', 'aadhar', 70, false, '{}'::jsonb, null, null, null, 'XXXX XXXX XXXX', null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'date_of_birth', 'Date of Birth', 'जन्म तिथि', 'जन्म तारीख', 'date', 80, false, '{"date_max":"today"}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'education', 'Education', 'शिक्षा', 'शिक्षण', 'dropdown', 90, false, '{}'::jsonb, null, null, 'education_v2', null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'gender', 'Gender', 'लिंग', 'लिंग', 'dropdown', 100, false, '{}'::jsonb, null, null, 'gender_v2', null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Family Information'), 'category', 'Category', 'वर्ग', 'वर्ग', 'dropdown', 110, false, '{}'::jsonb, null, null, 'category_v2', null, null, null, null),

  (gen_random_uuid(), (select id from sections where title='Income Sources'), 'income_sources', 'Income sources', 'आय के स्रोत', 'उत्पन्नाचे स्रोत', 'multiselect', 10, false, '{}'::jsonb, null, null, 'income_sources_v2', null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income Sources'), 'farming_type', 'Farming type', 'खेती का प्रकार', 'शेतीचा प्रकार', 'multiselect', 20, false, '{}'::jsonb, null, null, 'farming_type_v2', null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income Sources'), 'owns_farmland', 'Owns farmland?', 'क्या खेत की जमीन है?', 'स्वतःची शेतजमीन आहे का?', 'boolean', 30, false, '{}'::jsonb, null, null, null, null, null, null, null),

  (gen_random_uuid(), (select id from sections where title='Land Holding'), 'total_land_area_acre', 'Total land area', 'कुल जमीन', 'एकूण जमीन', 'acre', 10, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land Holding'), 'irrigated_land_acre', 'Irrigated land', 'सिंचित जमीन', 'सिंचित जमीन', 'acre', 20, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land Holding'), 'dry_land_acre', 'Dry land', 'सूखी जमीन', 'कोरडवाहू जमीन', 'acre', 30, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land Holding'), 'fallow_land_acre', 'Fallow land', 'परती जमीन', 'पडीत जमीन', 'acre', 40, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land Holding'), 'leased_land_acre', 'Leased land', 'पट्टे की जमीन', 'भाडेपट्ट्याची जमीन', 'acre', 50, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Land Holding'), 'rain_based_area_acre', 'Rain-based area', 'वर्षा आधारित क्षेत्र', 'पावसावर आधारित क्षेत्र', 'acre', 60, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),

  (gen_random_uuid(), (select id from sections where title='Forest Patta'), 'has_forest_patta', 'Has forest patta?', 'क्या वन पट्टा है?', 'वन पट्टा आहे का?', 'boolean', 10, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Forest Patta'), 'forest_patta_acre', 'Forest patta area', 'वन पट्टा क्षेत्र', 'वन पट्टा क्षेत्र', 'acre', 20, false, '{}'::jsonb, '{"depends_on":"has_forest_patta","operator":"equals","value":true}'::jsonb, null, null, null, 'acre', null, null),
  (gen_random_uuid(), (select id from sections where title='Forest Patta'), 'applied_for_forest_patta', 'Applied for forest patta?', 'क्या वन पट्टा के लिए आवेदन किया?', 'वन पट्ट्यासाठी अर्ज केला आहे का?', 'boolean', 30, false, '{}'::jsonb, '{"depends_on":"has_forest_patta","operator":"equals","value":false}'::jsonb, null, null, null, null, null, null),

  (gen_random_uuid(), (select id from sections where title='Farm Boundary'), 'farm_polygon', 'Farm Boundary Polygon', 'खेत की सीमा', 'शेताची सीमा', 'polygon_pencil', 10, false, '{}'::jsonb, null, null, null, null, null, null, null),

  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'main_crop', 'Main crop', 'मुख्य फसल', 'मुख्य पीक', 'dropdown', 10, false, '{}'::jsonb, null, null, 'main_crop_v2', null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Main Crop'), 'main_crop_land_acre', 'Land under main crop', 'मुख्य फसल का क्षेत्र', 'मुख्य पिकाखालील जमीन', 'acre', 20, false, '{}'::jsonb, null, null, null, null, 'acre', null, null),

  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'annual_agri_income', 'Annual agricultural income', 'वार्षिक कृषि आय', 'वार्षिक कृषी उत्पन्न', 'currency', 10, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'non_agri_income', 'Non-agricultural income', 'गैर-कृषि आय', 'बिगर-कृषी उत्पन्न', 'currency', 20, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'total_annual_income', 'Total annual income', 'कुल वार्षिक आय', 'एकूण वार्षिक उत्पन्न', 'auto_calc', 30, false, '{}'::jsonb, null, '{"operation":"sum","operands":["annual_agri_income","non_agri_income"]}'::jsonb, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'makes_food_products', 'Makes food products?', 'क्या खाद्य उत्पाद बनाते हैं?', 'खाद्य उत्पाद बनवता का?', 'boolean', 40, false, '{}'::jsonb, null, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'food_products_list', 'Food products list', 'खाद्य उत्पादों की सूची', 'खाद्य उत्पादनांची यादी', 'text', 50, false, '{}'::jsonb, '{"depends_on":"makes_food_products","operator":"equals","value":true}'::jsonb, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'food_product_training_received', 'Food product training received?', 'क्या खाद्य उत्पाद प्रशिक्षण मिला?', 'खाद्य उत्पादनाचे प्रशिक्षण मिळाले का?', 'boolean', 60, false, '{}'::jsonb, '{"depends_on":"makes_food_products","operator":"equals","value":true}'::jsonb, null, null, null, null, null, null),
  (gen_random_uuid(), (select id from sections where title='Income & Food Products'), 'food_product_training_source', 'Food product training source', 'प्रशिक्षण स्रोत', 'प्रशिक्षण स्रोत', 'text', 70, false, '{}'::jsonb, '{"depends_on":"food_product_training_received","operator":"equals","value":true}'::jsonb, null, null, null, null, null, null);
with sections as (
  select id, title from public.form_sections
)
insert into public.form_fields (
  id, section_id, field_key, label, label_hi, label_mr, input_type,
  sort_order, is_required, validation, visibility_rule, auto_calc_formula,
  dropdown_options_key, hint_text, suffix_text, crop_role, repeat_group
)
values
  (gen_random_uuid(), (select id from sections where title='Kharif Crops'), 'repeat_kharif_crops', 'Crops taken in Kharif season', 'खरीफ मौसम की फसलें', 'खरीप हंगामातील पिके', 'text', 10, false, '{}'::jsonb, null, null, null, 'Add each crop with area, variety, production, and estimated cost.', null, null, 'kharif_crops'),
  (gen_random_uuid(), (select id from sections where title='Main Crop Agronomy'), 'repeat_main_crop_practices', 'Main crop agronomy practices', 'मुख्य फसल की कृषि पद्धतियां', 'मुख्य पिकाच्या कृषी पद्धती', 'text', 10, false, '{}'::jsonb, null, null, null, 'Seed, nursery, land preparation, transplanting, pest, fertilizer, monitoring, and harvest details.', null, 'main', 'crop_practices'),
  (gen_random_uuid(), (select id from sections where title='Main Crop 3-Year Production'), 'repeat_main_crop_yearly', 'Main crop production for last 3 years', 'पिछले 3 वर्षों का मुख्य फसल उत्पादन', 'मागील 3 वर्षांचे मुख्य पिक उत्पादन', 'text', 10, false, '{}'::jsonb, null, null, null, 'Production history for 2023, 2024, and 2025.', null, null, 'main_crop_yearly'),
  (gen_random_uuid(), (select id from sections where title='Other Crop Agronomy'), 'repeat_other_crop_practices', 'Other crop agronomy practices', 'अन्य फसल की कृषि पद्धतियां', 'इतर पिकाच्या कृषी पद्धती', 'text', 10, false, '{}'::jsonb, '{"depends_on":"main_crop","operator":"contains_any","value":["bajra","other"]}'::jsonb, null, null, 'Fill only when other crop practices need to be captured.', null, 'other', 'crop_practices');
insert into public.dropdown_options (id, option_key, value, label_hi, label_mr, sort_order, is_active)
values
  (gen_random_uuid(), 'education_v2', 'illiterate', 'निरक्षर', 'निरक्षर', 10, true),
  (gen_random_uuid(), 'education_v2', 'primary', 'प्राथमिक', 'प्राथमिक', 20, true),
  (gen_random_uuid(), 'education_v2', 'secondary', 'माध्यमिक', 'माध्यमिक', 30, true),
  (gen_random_uuid(), 'education_v2', 'graduate', 'स्नातक', 'पदवीधर', 40, true),
  (gen_random_uuid(), 'gender_v2', 'male', 'पुरुष', 'पुरुष', 10, true),
  (gen_random_uuid(), 'gender_v2', 'female', 'महिला', 'स्त्री', 20, true),
  (gen_random_uuid(), 'gender_v2', 'other', 'अन्य', 'इतर', 30, true),
  (gen_random_uuid(), 'category_v2', 'general', 'सामान्य', 'सामान्य', 10, true),
  (gen_random_uuid(), 'category_v2', 'sc', 'अनुसूचित जाति', 'अनुसूचित जाती', 20, true),
  (gen_random_uuid(), 'category_v2', 'st', 'अनुसूचित जनजाति', 'अनुसूचित जमाती', 30, true),
  (gen_random_uuid(), 'category_v2', 'obc', 'ओबीसी', 'ओबीसी', 40, true),
  (gen_random_uuid(), 'income_sources_v2', 'farming', 'खेती', 'शेती', 10, true),
  (gen_random_uuid(), 'income_sources_v2', 'business', 'व्यवसाय', 'व्यवसाय', 20, true),
  (gen_random_uuid(), 'income_sources_v2', 'govt_job', 'सरकारी नौकरी', 'सरकारी नोकरी', 30, true),
  (gen_random_uuid(), 'income_sources_v2', 'private_job', 'निजी नौकरी', 'खाजगी नोकरी', 40, true),
  (gen_random_uuid(), 'income_sources_v2', 'other', 'अन्य', 'इतर', 50, true),
  (gen_random_uuid(), 'farming_type_v2', 'rainfed', 'वर्षा आधारित', 'पावसावर आधारित', 10, true),
  (gen_random_uuid(), 'farming_type_v2', 'irrigated', 'सिंचित', 'सिंचित', 20, true),
  (gen_random_uuid(), 'farming_type_v2', 'other', 'अन्य', 'इतर', 30, true),
  (gen_random_uuid(), 'main_crop_v2', 'paddy', 'धान', 'भात', 10, true),
  (gen_random_uuid(), 'main_crop_v2', 'nachani', 'नाचनी', 'नाचणी', 20, true),
  (gen_random_uuid(), 'main_crop_v2', 'bajra', 'बाजरा', 'बाजरी', 30, true),
  (gen_random_uuid(), 'main_crop_v2', 'other', 'अन्य', 'इतर', 40, true);
