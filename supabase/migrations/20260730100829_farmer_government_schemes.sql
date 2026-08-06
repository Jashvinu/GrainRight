create table public.government_schemes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (btrim(slug) <> ''),
  title jsonb not null check (jsonb_typeof(title) = 'object' and title ? 'en'),
  summary jsonb not null check (jsonb_typeof(summary) = 'object' and summary ? 'en'),
  fit_label jsonb not null default '{}'::jsonb
    check (jsonb_typeof(fit_label) = 'object'),
  level_label jsonb not null default '{}'::jsonb
    check (jsonb_typeof(level_label) = 'object'),
  status_label jsonb not null default '{}'::jsonb
    check (jsonb_typeof(status_label) = 'object'),
  benefit jsonb not null default '{}'::jsonb
    check (jsonb_typeof(benefit) = 'object'),
  eligibility jsonb not null default '{}'::jsonb
    check (jsonb_typeof(eligibility) = 'object'),
  documents jsonb not null default '{}'::jsonb
    check (jsonb_typeof(documents) = 'object'),
  application_steps jsonb not null default '{}'::jsonb
    check (jsonb_typeof(application_steps) = 'object'),
  state_code text not null default 'ALL'
    check (state_code in ('ALL', 'MH')),
  application_url text not null
    check (application_url ~ '^https://'),
  source_url text not null
    check (source_url ~ '^https://'),
  valid_from date,
  valid_until date,
  is_active boolean not null default true,
  priority integer not null default 100 check (priority >= 0),
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (valid_until is null or valid_from is null or valid_until >= valid_from)
);

comment on table public.government_schemes is
  'Curated farmer scheme feed. Client reloads it on every Schemes screen open and pull-to-refresh.';

create index government_schemes_active_priority_idx
  on public.government_schemes (is_active, priority, updated_at desc);

create trigger set_government_schemes_updated_at
before update on public.government_schemes
for each row execute function public.set_updated_at();

alter table public.government_schemes enable row level security;

revoke all on public.government_schemes from public, anon, authenticated;
grant select on public.government_schemes to anon, authenticated;
grant all on public.government_schemes to service_role;

create policy "farmers read current government schemes"
on public.government_schemes
for select
to anon, authenticated
using (
  is_active
  and (valid_from is null or valid_from <= current_date)
  and (valid_until is null or valid_until >= current_date)
);

insert into public.government_schemes (
  slug,
  title,
  summary,
  fit_label,
  level_label,
  status_label,
  benefit,
  eligibility,
  documents,
  application_steps,
  state_code,
  application_url,
  source_url,
  priority
)
values
(
  'pm-kisan',
  jsonb_build_object(
    'en', 'Pradhan Mantri Kisan Samman Nidhi (PM-KISAN)',
    'hi', 'प्रधानमंत्री किसान सम्मान निधि (PM-KISAN)',
    'mr', 'प्रधानमंत्री किसान सन्मान निधी (PM-KISAN)'
  ),
  jsonb_build_object(
    'en', 'Central income support for eligible landholding farmer families.',
    'hi', 'पात्र भूमिधारक किसान परिवारों के लिए केंद्रीय आय सहायता।',
    'mr', 'पात्र जमीनधारक शेतकरी कुटुंबांसाठी केंद्राची उत्पन्न मदत.'
  ),
  jsonb_build_object(
    'en', 'Landholding farmer families',
    'hi', 'भूमिधारक किसान परिवार',
    'mr', 'जमीनधारक शेतकरी कुटुंबे'
  ),
  jsonb_build_object('en', 'Central', 'hi', 'केंद्रीय', 'mr', 'केंद्रीय'),
  jsonb_build_object('en', 'Applications open', 'hi', 'आवेदन खुले हैं', 'mr', 'अर्ज सुरू आहेत'),
  jsonb_build_object(
    'en', 'Eligible families receive ₹6,000 per year in three equal instalments through direct benefit transfer.',
    'hi', 'पात्र परिवारों को प्रत्यक्ष लाभ अंतरण से तीन समान किस्तों में प्रति वर्ष ₹6,000 मिलते हैं।',
    'mr', 'पात्र कुटुंबांना थेट लाभ हस्तांतरणाद्वारे तीन समान हप्त्यांत दरवर्षी ₹6,000 मिळतात.'
  ),
  jsonb_build_object(
    'en', 'The family must hold cultivable land in its name and must not fall under the scheme exclusion categories.',
    'hi', 'परिवार के नाम खेती योग्य भूमि होनी चाहिए और वह योजना की बहिष्करण श्रेणियों में नहीं होना चाहिए।',
    'mr', 'कुटुंबाच्या नावावर लागवडीयोग्य जमीन असावी आणि ते योजनेच्या अपात्र श्रेणीत नसावे.'
  ),
  jsonb_build_object(
    'en', jsonb_build_array('Aadhaar card', 'Aadhaar-linked mobile number', 'Land record', 'Bank passbook'),
    'hi', jsonb_build_array('आधार कार्ड', 'आधार से जुड़ा मोबाइल नंबर', 'भूमि रिकॉर्ड', 'बैंक पासबुक'),
    'mr', jsonb_build_array('आधार कार्ड', 'आधारशी जोडलेला मोबाईल क्रमांक', 'जमीन नोंद', 'बँक पासबुक')
  ),
  jsonb_build_object(
    'en', jsonb_build_array('Open the official farmer registration form.', 'Verify Aadhaar and mobile number.', 'Add land and bank details.', 'Review and submit the application.'),
    'hi', jsonb_build_array('आधिकारिक किसान पंजीकरण फॉर्म खोलें।', 'आधार और मोबाइल नंबर सत्यापित करें।', 'भूमि और बैंक विवरण भरें।', 'जाँच कर आवेदन जमा करें।'),
    'mr', jsonb_build_array('अधिकृत शेतकरी नोंदणी अर्ज उघडा.', 'आधार आणि मोबाईल क्रमांक पडताळा.', 'जमीन आणि बँक तपशील भरा.', 'तपासून अर्ज सादर करा.')
  ),
  'ALL',
  'https://www.pmkisan.gov.in/RegistrationFormupdated.aspx',
  'https://www.myscheme.gov.in/schemes/pm-kisan',
  10
),
(
  'pmfby',
  jsonb_build_object(
    'en', 'Pradhan Mantri Fasal Bima Yojana (PMFBY)',
    'hi', 'प्रधानमंत्री फसल बीमा योजना (PMFBY)',
    'mr', 'प्रधानमंत्री पीक विमा योजना (PMFBY)'
  ),
  jsonb_build_object(
    'en', 'Crop insurance for notified crops against specified natural risks and crop loss.',
    'hi', 'अधिसूचित फसलों के लिए निर्धारित प्राकृतिक जोखिमों और फसल नुकसान के विरुद्ध बीमा।',
    'mr', 'अधिसूचित पिकांसाठी ठराविक नैसर्गिक धोके आणि पीक नुकसानीविरुद्ध विमा.'
  ),
  jsonb_build_object(
    'en', 'Notified crops and seasons',
    'hi', 'अधिसूचित फसलें और मौसम',
    'mr', 'अधिसूचित पिके आणि हंगाम'
  ),
  jsonb_build_object('en', 'Central', 'hi', 'केंद्रीय', 'mr', 'केंद्रीय'),
  jsonb_build_object('en', 'Check current season', 'hi', 'वर्तमान मौसम जाँचें', 'mr', 'चालू हंगाम तपासा'),
  jsonb_build_object(
    'en', 'Provides insurance protection for eligible notified crops. Premium, crop availability, and cut-off dates depend on the current state notification.',
    'hi', 'पात्र अधिसूचित फसलों के लिए बीमा सुरक्षा देता है। प्रीमियम, उपलब्ध फसल और अंतिम तिथि वर्तमान राज्य अधिसूचना पर निर्भर हैं।',
    'mr', 'पात्र अधिसूचित पिकांना विमा संरक्षण मिळते. हप्ता, उपलब्ध पीक आणि अंतिम तारीख चालू राज्य अधिसूचनेवर अवलंबून असते.'
  ),
  jsonb_build_object(
    'en', 'The farmer, crop, land, and season must be covered by the current notification for the selected location.',
    'hi', 'चयनित स्थान की वर्तमान अधिसूचना में किसान, फसल, भूमि और मौसम शामिल होना चाहिए।',
    'mr', 'निवडलेल्या ठिकाणाच्या चालू अधिसूचनेत शेतकरी, पीक, जमीन आणि हंगाम समाविष्ट असणे आवश्यक आहे.'
  ),
  jsonb_build_object(
    'en', jsonb_build_array('Farmer identity', 'Land record', 'Crop and sowing details', 'Bank account details'),
    'hi', jsonb_build_array('किसान पहचान', 'भूमि रिकॉर्ड', 'फसल और बुवाई विवरण', 'बैंक खाता विवरण'),
    'mr', jsonb_build_array('शेतकरी ओळख', 'जमीन नोंद', 'पीक आणि पेरणी तपशील', 'बँक खाते तपशील')
  ),
  jsonb_build_object(
    'en', jsonb_build_array('Open the official Farmer Corner.', 'Register or sign in with the farmer mobile number.', 'Select the notified crop and season.', 'Complete the form and pay the applicable farmer premium.'),
    'hi', jsonb_build_array('आधिकारिक किसान कॉर्नर खोलें।', 'किसान मोबाइल नंबर से पंजीकरण या लॉगिन करें।', 'अधिसूचित फसल और मौसम चुनें।', 'फॉर्म पूरा कर लागू किसान प्रीमियम भरें।'),
    'mr', jsonb_build_array('अधिकृत Farmer Corner उघडा.', 'शेतकरी मोबाईल क्रमांकाने नोंदणी किंवा लॉगिन करा.', 'अधिसूचित पीक आणि हंगाम निवडा.', 'अर्ज पूर्ण करून लागू शेतकरी विमा हप्ता भरा.')
  ),
  'ALL',
  'https://pmfby.gov.in/farmerRegistration',
  'https://pmfby.gov.in/',
  20
),
(
  'mahadbt-farmer',
  jsonb_build_object(
    'en', 'MahaDBT Agriculture Schemes',
    'hi', 'महाDBT कृषि योजनाएँ',
    'mr', 'महाDBT कृषी योजना'
  ),
  jsonb_build_object(
    'en', 'Maharashtra''s farmer portal for agriculture components, subsidies, and application tracking.',
    'hi', 'कृषि घटकों, सब्सिडी और आवेदन ट्रैकिंग के लिए महाराष्ट्र का किसान पोर्टल।',
    'mr', 'कृषी घटक, अनुदाने आणि अर्ज स्थितीसाठी महाराष्ट्राचे शेतकरी पोर्टल.'
  ),
  jsonb_build_object(
    'en', 'Maharashtra Farmer ID',
    'hi', 'महाराष्ट्र किसान आईडी',
    'mr', 'महाराष्ट्र शेतकरी आयडी'
  ),
  jsonb_build_object('en', 'Maharashtra', 'hi', 'महाराष्ट्र', 'mr', 'महाराष्ट्र'),
  jsonb_build_object('en', 'Portal open', 'hi', 'पोर्टल खुला है', 'mr', 'पोर्टल सुरू आहे'),
  jsonb_build_object(
    'en', 'One application portal for eligible agriculture scheme components. Benefits and selection rules vary by component.',
    'hi', 'पात्र कृषि योजना घटकों के लिए एक आवेदन पोर्टल। लाभ और चयन नियम घटक के अनुसार बदलते हैं।',
    'mr', 'पात्र कृषी योजना घटकांसाठी एकच अर्ज पोर्टल. लाभ आणि निवड नियम घटकानुसार बदलतात.'
  ),
  jsonb_build_object(
    'en', 'A Maharashtra Farmer ID is required. Component eligibility is calculated from the farmer profile, land, crop, and scheme rules.',
    'hi', 'महाराष्ट्र किसान आईडी आवश्यक है। घटक पात्रता किसान प्रोफ़ाइल, भूमि, फसल और योजना नियमों से तय होती है।',
    'mr', 'महाराष्ट्र शेतकरी आयडी आवश्यक आहे. घटक पात्रता शेतकरी प्रोफाइल, जमीन, पीक आणि योजना नियमांवर ठरते.'
  ),
  jsonb_build_object(
    'en', jsonb_build_array('Farmer ID', 'Aadhaar-linked mobile number', 'Land and crop records', 'Bank account details', 'Component-specific documents'),
    'hi', jsonb_build_array('किसान आईडी', 'आधार से जुड़ा मोबाइल नंबर', 'भूमि और फसल रिकॉर्ड', 'बैंक खाता विवरण', 'घटक-विशिष्ट दस्तावेज'),
    'mr', jsonb_build_array('शेतकरी आयडी', 'आधारशी जोडलेला मोबाईल क्रमांक', 'जमीन आणि पीक नोंदी', 'बँक खाते तपशील', 'घटकानुसार आवश्यक कागदपत्रे')
  ),
  jsonb_build_object(
    'en', jsonb_build_array('Open the official MahaDBT Farmer login.', 'Sign in with Farmer ID and OTP.', 'Complete the farmer, land, and crop profile.', 'Choose an eligible component and submit its documents.'),
    'hi', jsonb_build_array('आधिकारिक महाDBT किसान लॉगिन खोलें।', 'किसान आईडी और OTP से लॉगिन करें।', 'किसान, भूमि और फसल प्रोफ़ाइल पूरी करें।', 'पात्र घटक चुनकर उसके दस्तावेज जमा करें।'),
    'mr', jsonb_build_array('अधिकृत महाDBT शेतकरी लॉगिन उघडा.', 'शेतकरी आयडी आणि OTP ने लॉगिन करा.', 'शेतकरी, जमीन आणि पीक प्रोफाइल पूर्ण करा.', 'पात्र घटक निवडून त्याची कागदपत्रे सादर करा.')
  ),
  'MH',
  'https://mahadbt.maharashtra.gov.in/Farmer/AgriLogin/AgriLogin',
  'https://mahadbt.maharashtra.gov.in/Home/LandingPage',
  30
);
