# Baseline Survey Form — Updated Flow, Translation, and Bug Fix Notes

## Purpose

This file updates the baseline survey form flow, translation labels, and app logic based on the screenshots and review notes.

The main goal is to make the form field-ready for English, Marathi, and Hindi users, while fixing missing conditional fields and duplicate crop sections.

---

## Change Summary

1. **Date of Birth selection issue**
   - The Date of Birth field must save the selected date from the date picker.
   - The selected date must be shown in the field after the user taps **OK**.
   - Future dates should not be allowed.

2. **Missing “Other” text fields**
   - Wherever the option **Other / इतर / अन्य** is selected, a text field must immediately appear below that question.
   - This must work consistently for all single-select and multi-select fields.

3. **Kharif crops and Other crops are duplicate**
   - Remove the separate **Other Crops** section/tab.
   - Keep one common **Kharif Crops** repeatable section.
   - Add **Other** as an option inside the **Kharif Crops → Crop name** field.
   - If **Other** is selected, show fields for **Other crop name** and **Other crop details**.

4. **Expand short forms**
   - Do not show short forms like **POP** in the form.
   - Show the full label: **Package of Practice**.
   - Use clear labels like **Rupees (₹)** and **centimetres (cm)** where needed.

5. **Marathi display issue**
   - Marathi is available as a language option, but some fields still display in English.
   - The app must load the full Marathi locale for all labels, options, buttons, section titles, helper text, and validation messages.
   - The language switch must update the complete form, not only the header or navigation buttons.

6. **Pest, Growth and Harvest conditional fields**
   - Under **Spray methods**, the **per acre** field is currently appearing for **Neem** and **Matka**, but not for **Jeevamrut** and **Pesticide**.
   - Add the same conditional field for **Jeevamrut per acre** and **Pesticide per acre**.

7. **Translation wording improved**
   - Some literal translations have been changed to farmer-friendly wording.
   - “Inorganic” is changed to **Chemical / रासायनिक / रासायनिक** because it is easier for farmers to understand.
   - “Organic fertilizer helps disease?” is changed to disease-control wording so it does not sound like fertilizer helps the disease grow.

---

# Updated English Form Flow

```text
Baseline Survey Form
├── Language
│   ├── English
│   ├── Hindi
│   └── Marathi
├── Family Information
│   ├── Farmer Name [required]
│   ├── Village [required]
│   ├── Gram Panchayat [required]
│   ├── Taluka [required]
│   ├── District [required]
│   ├── Mobile Number [10 digits]
│   ├── Aadhaar Number [12 digits]
│   ├── Date of Birth
│   │   └── Date picker must save the selected date after tapping OK.
│   ├── Education
│   │   ├── Illiterate
│   │   ├── Primary
│   │   ├── Secondary
│   │   └── Graduate
│   ├── Gender
│   │   ├── Male
│   │   ├── Female
│   │   └── Other
│   └── Social Category
│       ├── General
│       ├── Scheduled Caste
│       ├── Scheduled Tribe
│       └── Other Backward Class
├── Land / Farming
│   ├── Income sources [required, multi-select]
│   │   ├── Farming
│   │   ├── Business
│   │   ├── Government job
│   │   ├── Private job
│   │   └── Other
│   │       └── If selected: Please specify other income source
│   ├── Farming type [required, multi-select]
│   │   ├── Rainfed
│   │   ├── Irrigated
│   │   └── Other
│   │       └── If selected: Please specify other farming type
│   ├── Owns farmland? [required, yes/no]
│   ├── Total land area [required, acre]
│   ├── Irrigated land [acre]
│   ├── Dry / unirrigated land [acre]
│   ├── Fallow land [acre]
│   ├── Leased land [acre]
│   └── Rainfed area [acre]
├── Forest Patta
│   ├── Has forest patta? [required, yes/no]
│   ├── If yes: Forest patta area [acre]
│   └── If no: Applied for forest patta? [yes/no]
├── Farm Boundary
│   └── Farm boundary drawing [optional]
│       └── Draw the farm boundary if time permits. The survey can still be submitted without it.
├── Main Crop
│   ├── Main crop [required]
│   │   ├── Paddy / Rice
│   │   ├── Nachani / Ragi
│   │   └── Bajra / Pearl millet
│   └── Land under main crop [acre]
├── Kharif Crops
│   └── Crops taken in Kharif season [up to 4 rows]
│       ├── Crop name
│       │   ├── Paddy / Rice
│       │   ├── Nachani / Ragi
│       │   ├── Bajra / Pearl millet
│       │   └── Other
│       │       ├── If selected: Other crop name
│       │       └── If selected: Other crop details
│       ├── Cultivated area [acre]
│       ├── Variety
│       ├── Production quantity
│       └── Average estimated cost [Rupees ₹]
├── Main Crop Agronomy
│   └── Main crop practices
│       ├── Location and training
│       │   ├── Where is the main crop grown?
│       │   │   ├── Own land
│       │   │   ├── Forest patta
│       │   │   ├── Leased land
│       │   │   └── Other
│       │   │       └── If selected: Please specify other land type
│       │   ├── Same land every year? [yes/no]
│       │   ├── Land topology
│       │   │   ├── Flat
│       │   │   ├── Sloped
│       │   │   ├── Terraced
│       │   │   ├── Hilly
│       │   │   └── Other
│       │   │       └── If selected: Please specify other topology
│       │   ├── Seed sources [multi-select]
│       │   │   ├── Own saved
│       │   │   ├── Local market
│       │   │   ├── Government source
│       │   │   ├── Neighbour
│       │   │   ├── Co-operative society
│       │   │   └── Other
│       │   │       └── If selected: Please specify other seed source
│       │   ├── Package of Practice training received? [yes/no]
│       │   ├── If yes: Training source
│       │   └── Farming method
│       │       ├── Organic
│       │       ├── Chemical
│       │       ├── Mixed
│       │       └── Natural
│       ├── Seed and land preparation
│       │   ├── Treats seeds? [yes/no]
│       │   ├── If yes: Seed treatment materials [multi-select]
│       │   │   ├── Cow dung
│       │   │   ├── Cow urine
│       │   │   ├── Neem
│       │   │   ├── Jeevamrut
│       │   │   ├── Chemical
│       │   │   └── Other
│       │   │       └── If selected: Please specify other material
│       │   ├── Seedling / sowing method
│       │   │   ├── Direct sowing
│       │   │   ├── Nursery transplanting
│       │   │   ├── Broadcasting
│       │   │   └── Other
│       │   │       └── If selected: Please specify other method
│       │   ├── Seedlings ready after [days]
│       │   ├── Difference noticed
│       │   ├── Tractor days
│       │   ├── Tractor cost [Rupees ₹]
│       │   ├── Bullock days
│       │   ├── Bullock cost [Rupees ₹]
│       │   └── Land prepared by hand? [yes/no]
│       ├── Sowing / transplanting and crop care
│       │   ├── Sowing / transplanting method
│       │   │   ├── By hand
│       │   │   ├── Machine
│       │   │   ├── Direct sowing
│       │   │   └── Other
│       │   │       └── If selected: Please specify other method
│       │   ├── Dip seedlings in Jeevamrut? [yes/no]
│       │   ├── Plant spacing [centimetres cm]
│       │   ├── Transplanting days
│       │   ├── Needs transplanting labour? [yes/no]
│       │   ├── If yes: Number of labourers
│       │   ├── If yes: Daily wage [Rupees ₹]
│       │   ├── Does weeding? [yes/no]
│       │   └── If yes: Weeding after [days]
│       └── Pest, Growth and Harvest
│           ├── Sprays for pest control? [yes/no]
│           ├── If yes: Spray methods [multi-select]
│           │   ├── Neem
│           │   │   └── If selected: Neem quantity per acre
│           │   ├── Matka
│           │   │   └── If selected: Matka quantity per acre
│           │   ├── Jeevamrut
│           │   │   └── If selected: Jeevamrut quantity per acre
│           │   ├── Pesticide
│           │   │   └── If selected: Pesticide quantity per acre
│           │   └── Other
│           │       └── If selected: Please specify other spray details
│           ├── Does organic fertilizer help in disease control? [yes/no]
│           ├── Planting to flowering [days]
│           ├── Uses fertilizer? [yes/no]
│           ├── If yes: Fertilizer names
│           ├── If yes: Quantity per acre
│           ├── Pest problem during flowering? [yes/no]
│           ├── If yes: Pest type
│           ├── If yes: Sprays used
│           ├── Maturity [days]
│           ├── Monitors crop? [yes/no]
│           ├── If yes: Monitoring methods [multi-select]
│           │   ├── Daily field walk
│           │   ├── Photos
│           │   ├── Notes
│           │   ├── Mobile app
│           │   └── Other
│           │       └── If selected: Please specify other monitoring method
│           ├── Harvest method
│           │   ├── By hand
│           │   ├── Machine
│           │   └── Mixed
│           ├── Harvest labour type
│           │   ├── Family
│           │   ├── Hired labour
│           │   └── Mixed
│           ├── Harvest daily wage [Rupees ₹]
│           ├── Number of harvest labourers
│           ├── Harvest days
│           ├── Ready to eat/sell after [days]
│           ├── Sells this crop? [yes/no]
│           └── If yes: When sold
│               ├── Immediately after harvest
│               ├── Within 3 months
│               ├── Within 6 months
│               └── Held for a better price
├── Main Crop 3-Year Production
│   └── Main crop production history [2023, 2024, 2025]
│       ├── Area [acre]
│       ├── Total production
│       ├── Home consumption
│       ├── Quantity sold
│       ├── Sold where
│       └── Selling price [Rupees ₹]
└── Income and Food Products
    ├── Annual agricultural income [Rupees ₹]
    ├── Non-agricultural income [Rupees ₹]
    ├── Total annual income [auto-calculated]
    ├── Makes food products? [yes/no]
    ├── If yes: Food products list
    ├── If yes: Food product making training received? [yes/no]
    └── If training received: Training source
```

---

# Updated Marathi Form Flow

```text
मूलभूत सर्वेक्षण फॉर्म
├── भाषा
│   ├── English
│   ├── हिंदी
│   └── मराठी
├── कौटुंबिक माहिती
│   ├── शेतकऱ्याचे नाव [आवश्यक]
│   ├── गाव [आवश्यक]
│   ├── ग्रामपंचायत [आवश्यक]
│   ├── तालुका [आवश्यक]
│   ├── जिल्हा [आवश्यक]
│   ├── मोबाईल क्रमांक [10 अंक]
│   ├── आधार क्रमांक [12 अंक]
│   ├── जन्म तारीख
│   │   └── तारीख निवडल्यानंतर OK दाबल्यावर तारीख जतन झाली पाहिजे.
│   ├── शिक्षण
│   │   ├── निरक्षर
│   │   ├── प्राथमिक
│   │   ├── माध्यमिक
│   │   └── पदवीधर
│   ├── लिंग
│   │   ├── पुरुष
│   │   ├── स्त्री
│   │   └── इतर
│   └── सामाजिक प्रवर्ग
│       ├── सामान्य
│       ├── अनुसूचित जाती
│       ├── अनुसूचित जमाती
│       └── इतर मागास वर्ग
├── जमीन / शेती
│   ├── उत्पन्नाचे स्रोत [आवश्यक, अनेक निवड]
│   │   ├── शेती
│   │   ├── व्यवसाय
│   │   ├── सरकारी नोकरी
│   │   ├── खाजगी नोकरी
│   │   └── इतर
│   │       └── निवडल्यास: इतर उत्पन्न स्रोत नमूद करा
│   ├── शेतीचा प्रकार [आवश्यक, अनेक निवड]
│   │   ├── पावसावर आधारित
│   │   ├── सिंचित
│   │   └── इतर
│   │       └── निवडल्यास: इतर शेती प्रकार नमूद करा
│   ├── स्वतःची शेतजमीन आहे का? [आवश्यक, होय/नाही]
│   ├── एकूण जमीन क्षेत्र [आवश्यक, एकर]
│   ├── सिंचित जमीन [एकर]
│   ├── कोरडवाहू / असिंचित जमीन [एकर]
│   ├── पडीत जमीन [एकर]
│   ├── भाडेपट्ट्याची जमीन [एकर]
│   └── पावसावर आधारित क्षेत्र [एकर]
├── वन हक्क पट्टा
│   ├── वन हक्क पट्टा आहे का? [आवश्यक, होय/नाही]
│   ├── होय असल्यास: वन हक्क पट्ट्याचे क्षेत्र [एकर]
│   └── नाही असल्यास: वन हक्क पट्ट्यासाठी अर्ज केला आहे का? [होय/नाही]
├── शेताची सीमा
│   └── शेताची सीमा रेखाटणे [ऐच्छिक]
│       └── वेळ असल्यास शेताची सीमा रेखाटा. सीमा न रेखाटताही सर्वेक्षण सबमिट करता येईल.
├── मुख्य पीक
│   ├── मुख्य पीक [आवश्यक]
│   │   ├── भात
│   │   ├── नाचणी
│   │   └── बाजरी
│   └── मुख्य पिकाखालील जमीन [एकर]
├── खरीप पिके
│   └── खरीप हंगामातील पिके [जास्तीत जास्त 4 नोंदी]
│       ├── पिकाचे नाव
│       │   ├── भात
│       │   ├── नाचणी
│       │   ├── बाजरी
│       │   └── इतर
│       │       ├── निवडल्यास: इतर पिकाचे नाव
│       │       └── निवडल्यास: इतर पिकाचा तपशील
│       ├── लागवड क्षेत्र [एकर]
│       ├── वाण
│       ├── उत्पादन प्रमाण
│       └── सरासरी अंदाजित खर्च [रुपये ₹]
├── मुख्य पिकाच्या कृषी पद्धती
│   └── मुख्य पीक पद्धती
│       ├── ठिकाण आणि प्रशिक्षण
│       │   ├── मुख्य पीक कोणत्या जमिनीवर घेतले?
│       │   │   ├── स्वतःची जमीन
│       │   │   ├── वन हक्क पट्टा
│       │   │   ├── भाडेपट्ट्याची जमीन
│       │   │   └── इतर
│       │   │       └── निवडल्यास: इतर जमीन प्रकार नमूद करा
│       │   ├── दरवर्षी तीच जमीन वापरता का? [होय/नाही]
│       │   ├── जमिनीची रचना
│       │   │   ├── सपाट
│       │   │   ├── उताराची
│       │   │   ├── पायऱ्यांची
│       │   │   ├── डोंगराळ
│       │   │   └── इतर
│       │   │       └── निवडल्यास: इतर रचना नमूद करा
│       │   ├── बियाण्याचे स्रोत [अनेक निवड]
│       │   │   ├── स्वतः साठवलेले
│       │   │   ├── स्थानिक बाजार
│       │   │   ├── शासकीय स्रोत
│       │   │   ├── शेजारी
│       │   │   ├── सहकारी संस्था
│       │   │   └── इतर
│       │   │       └── निवडल्यास: इतर बियाणे स्रोत नमूद करा
│       │   ├── Package of Practice म्हणजे शिफारस केलेल्या पीक पद्धतीचे प्रशिक्षण मिळाले आहे का? [होय/नाही]
│       │   ├── होय असल्यास: प्रशिक्षण स्रोत
│       │   └── शेती पद्धत
│       │       ├── सेंद्रिय
│       │       ├── रासायनिक
│       │       ├── मिश्र
│       │       └── नैसर्गिक
│       ├── बियाणे आणि जमीन तयारी
│       │   ├── बियाण्यांवर प्रक्रिया करता का? [होय/नाही]
│       │   ├── होय असल्यास: बीज प्रक्रिया साहित्य [अनेक निवड]
│       │   │   ├── शेण
│       │   │   ├── गोमूत्र
│       │   │   ├── कडुनिंब
│       │   │   ├── जीवामृत
│       │   │   ├── रासायनिक
│       │   │   └── इतर
│       │   │       └── निवडल्यास: इतर साहित्य नमूद करा
│       │   ├── रोप / पेरणी पद्धत
│       │   │   ├── थेट पेरणी
│       │   │   ├── रोपवाटिकेतून पुनर्लागवड
│       │   │   ├── फेकून पेरणी
│       │   │   └── इतर
│       │   │       └── निवडल्यास: इतर पद्धत नमूद करा
│       │   ├── रोपे तयार होण्यास लागणारे दिवस
│       │   ├── जाणवलेला फरक
│       │   ├── ट्रॅक्टर दिवस
│       │   ├── ट्रॅक्टर खर्च [रुपये ₹]
│       │   ├── बैल दिवस
│       │   ├── बैल खर्च [रुपये ₹]
│       │   └── जमीन हाताने तयार केली का? [होय/नाही]
│       ├── पेरणी / पुनर्लागवड आणि पीक काळजी
│       │   ├── पेरणी / पुनर्लागवड पद्धत
│       │   │   ├── हाताने
│       │   │   ├── यंत्राने
│       │   │   ├── थेट पेरणी
│       │   │   └── इतर
│       │   │       └── निवडल्यास: इतर पद्धत नमूद करा
│       │   ├── रोपे जीवामृतात बुडवता का? [होय/नाही]
│       │   ├── रोपांमधील अंतर [सेंटीमीटर cm]
│       │   ├── पुनर्लागवडीचे दिवस
│       │   ├── पुनर्लागवडीसाठी मजूर लागतात का? [होय/नाही]
│       │   ├── होय असल्यास: मजुरांची संख्या
│       │   ├── होय असल्यास: रोजंदारी [रुपये ₹]
│       │   ├── खुरपणी करता का? [होय/नाही]
│       │   └── होय असल्यास: खुरपणी किती दिवसांनी
│       └── कीड, वाढ आणि कापणी
│           ├── कीड नियंत्रणासाठी फवारणी करता का? [होय/नाही]
│           ├── होय असल्यास: फवारणी पद्धती [अनेक निवड]
│           │   ├── कडुनिंब
│           │   │   └── निवडल्यास: कडुनिंब प्रमाण प्रति एकर
│           │   ├── मटका
│           │   │   └── निवडल्यास: मटका प्रमाण प्रति एकर
│           │   ├── जीवामृत
│           │   │   └── निवडल्यास: जीवामृत प्रमाण प्रति एकर
│           │   ├── कीटकनाशक
│           │   │   └── निवडल्यास: कीटकनाशक प्रमाण प्रति एकर
│           │   └── इतर
│           │       └── निवडल्यास: इतर फवारणी तपशील नमूद करा
│           ├── सेंद्रिय खतामुळे रोग नियंत्रणास मदत होते का? [होय/नाही]
│           ├── लागवडीपासून फुलोऱ्यापर्यंत दिवस
│           ├── खत वापरता का? [होय/नाही]
│           ├── होय असल्यास: खतांची नावे
│           ├── होय असल्यास: प्रति एकर प्रमाण
│           ├── फुलोऱ्याच्या वेळी किडीची समस्या येते का? [होय/नाही]
│           ├── होय असल्यास: किडीचा प्रकार
│           ├── होय असल्यास: वापरलेली फवारणी
│           ├── परिपक्वता दिवस
│           ├── पिकावर लक्ष ठेवता का? [होय/नाही]
│           ├── होय असल्यास: देखरेख पद्धती [अनेक निवड]
│           │   ├── रोज शेतफेरी
│           │   ├── फोटो
│           │   ├── नोंदी
│           │   ├── मोबाईल अॅप
│           │   └── इतर
│           │       └── निवडल्यास: इतर देखरेख पद्धत नमूद करा
│           ├── कापणी पद्धत
│           │   ├── हाताने
│           │   ├── यंत्राने
│           │   └── मिश्र
│           ├── कापणी मजूर प्रकार
│           │   ├── कुटुंब
│           │   ├── भाड्याने मजूर
│           │   └── मिश्र
│           ├── कापणी रोजंदारी [रुपये ₹]
│           ├── कापणी मजुरांची संख्या
│           ├── कापणी दिवस
│           ├── खाण्यास/विक्रीस तयार होण्यास लागणारे दिवस
│           ├── हे पीक विकता का? [होय/नाही]
│           └── होय असल्यास: कधी विकले
│               ├── कापणीनंतर लगेच
│               ├── 3 महिन्यांच्या आत
│               ├── 6 महिन्यांच्या आत
│               └── चांगल्या किमतीसाठी ठेवले
├── मुख्य पिकाचे 3 वर्षांचे उत्पादन
│   └── मुख्य पीक उत्पादन इतिहास [2023, 2024, 2025]
│       ├── क्षेत्र [एकर]
│       ├── एकूण उत्पादन
│       ├── घरगुती वापर
│       ├── विकलेले प्रमाण
│       ├── कुठे विकले
│       └── विक्री किंमत [रुपये ₹]
└── उत्पन्न आणि खाद्य उत्पादने
    ├── वार्षिक कृषी उत्पन्न [रुपये ₹]
    ├── बिगर-कृषी उत्पन्न [रुपये ₹]
    ├── एकूण वार्षिक उत्पन्न [स्वयं-गणना]
    ├── खाद्य उत्पादने बनवता का? [होय/नाही]
    ├── होय असल्यास: खाद्य उत्पादनांची यादी
    ├── होय असल्यास: खाद्य उत्पादने बनवण्याचे प्रशिक्षण मिळाले आहे का? [होय/नाही]
    └── प्रशिक्षण मिळाले असल्यास: प्रशिक्षण स्रोत
```

---

# Updated Hindi Form Flow

```text
बेसलाइन सर्वे फॉर्म
├── भाषा
│   ├── English
│   ├── हिंदी
│   └── मराठी
├── पारिवारिक जानकारी
│   ├── किसान का नाम [आवश्यक]
│   ├── गांव [आवश्यक]
│   ├── ग्राम पंचायत [आवश्यक]
│   ├── तालुका [आवश्यक]
│   ├── जिला [आवश्यक]
│   ├── मोबाइल नंबर [10 अंक]
│   ├── आधार नंबर [12 अंक]
│   ├── जन्म तिथि
│   │   └── तारीख चुनने के बाद OK दबाने पर तारीख सेव होनी चाहिए।
│   ├── शिक्षा
│   │   ├── निरक्षर
│   │   ├── प्राथमिक
│   │   ├── माध्यमिक
│   │   └── स्नातक
│   ├── लिंग
│   │   ├── पुरुष
│   │   ├── महिला
│   │   └── अन्य
│   └── सामाजिक वर्ग
│       ├── सामान्य
│       ├── अनुसूचित जाति
│       ├── अनुसूचित जनजाति
│       └── अन्य पिछड़ा वर्ग
├── भूमि / खेती
│   ├── आय के स्रोत [आवश्यक, बहु-चयन]
│   │   ├── खेती
│   │   ├── व्यवसाय
│   │   ├── सरकारी नौकरी
│   │   ├── निजी नौकरी
│   │   └── अन्य
│   │       └── चुनने पर: अन्य आय स्रोत लिखें
│   ├── खेती का प्रकार [आवश्यक, बहु-चयन]
│   │   ├── वर्षा आधारित
│   │   ├── सिंचित
│   │   └── अन्य
│   │       └── चुनने पर: अन्य खेती प्रकार लिखें
│   ├── क्या आपके पास अपनी खेत जमीन है? [आवश्यक, हां/नहीं]
│   ├── कुल जमीन क्षेत्र [आवश्यक, एकड़]
│   ├── सिंचित जमीन [एकड़]
│   ├── सूखी / असिंचित जमीन [एकड़]
│   ├── परती जमीन [एकड़]
│   ├── पट्टे की जमीन [एकड़]
│   └── वर्षा आधारित क्षेत्र [एकड़]
├── वन अधिकार पट्टा
│   ├── क्या वन अधिकार पट्टा है? [आवश्यक, हां/नहीं]
│   ├── हां हो तो: वन अधिकार पट्टा क्षेत्र [एकड़]
│   └── नहीं हो तो: क्या वन अधिकार पट्टा के लिए आवेदन किया है? [हां/नहीं]
├── खेत की सीमा
│   └── खेत की सीमा रेखांकित करना [वैकल्पिक]
│       └── समय हो तो खेत की सीमा बनाएं। सीमा बनाए बिना भी सर्वे जमा किया जा सकता है।
├── मुख्य फसल
│   ├── मुख्य फसल [आवश्यक]
│   │   ├── धान
│   │   ├── नाचनी / रागी
│   │   └── बाजरा
│   └── मुख्य फसल का क्षेत्र [एकड़]
├── खरीफ फसलें
│   └── खरीफ मौसम की फसलें [अधिकतम 4 पंक्तियां]
│       ├── फसल का नाम
│       │   ├── धान
│       │   ├── नाचनी / रागी
│       │   ├── बाजरा
│       │   └── अन्य
│       │       ├── चुनने पर: अन्य फसल का नाम
│       │       └── चुनने पर: अन्य फसल विवरण
│       ├── खेती का क्षेत्र [एकड़]
│       ├── किस्म
│       ├── उत्पादन मात्रा
│       └── औसत अनुमानित लागत [रुपये ₹]
├── मुख्य फसल की कृषि पद्धतियां
│   └── मुख्य फसल पद्धतियां
│       ├── स्थान और प्रशिक्षण
│       │   ├── मुख्य फसल किस जमीन पर उगाई गई?
│       │   │   ├── अपनी जमीन
│       │   │   ├── वन अधिकार पट्टा
│       │   │   ├── पट्टे की जमीन
│       │   │   └── अन्य
│       │   │       └── चुनने पर: अन्य जमीन प्रकार लिखें
│       │   ├── क्या हर साल वही जमीन इस्तेमाल करते हैं? [हां/नहीं]
│       │   ├── जमीन की बनावट
│       │   │   ├── समतल
│       │   │   ├── ढलान वाली
│       │   │   ├── सीढ़ीदार
│       │   │   ├── पहाड़ी
│       │   │   └── अन्य
│       │   │       └── चुनने पर: अन्य बनावट लिखें
│       │   ├── बीज के स्रोत [बहु-चयन]
│       │   │   ├── स्वयं सहेजा हुआ
│       │   │   ├── स्थानीय बाजार
│       │   │   ├── सरकारी स्रोत
│       │   │   ├── पड़ोसी
│       │   │   ├── सहकारी संस्था
│       │   │   └── अन्य
│       │   │       └── चुनने पर: अन्य बीज स्रोत लिखें
│       │   ├── क्या Package of Practice यानी अनुशंसित खेती पद्धति का प्रशिक्षण मिला है? [हां/नहीं]
│       │   ├── हां हो तो: प्रशिक्षण स्रोत
│       │   └── खेती पद्धति
│       │       ├── जैविक
│       │       ├── रासायनिक
│       │       ├── मिश्रित
│       │       └── प्राकृतिक
│       ├── बीज और जमीन की तैयारी
│       │   ├── क्या बीज उपचार करते हैं? [हां/नहीं]
│       │   ├── हां हो तो: बीज उपचार सामग्री [बहु-चयन]
│       │   │   ├── गोबर
│       │   │   ├── गोमूत्र
│       │   │   ├── नीम
│       │   │   ├── जीवामृत
│       │   │   ├── रासायनिक
│       │   │   └── अन्य
│       │   │       └── चुनने पर: अन्य सामग्री लिखें
│       │   ├── पौध / बुवाई विधि
│       │   │   ├── सीधी बुवाई
│       │   │   ├── नर्सरी से रोपाई
│       │   │   ├── छिटकवां बुवाई
│       │   │   └── अन्य
│       │   │       └── चुनने पर: अन्य विधि लिखें
│       │   ├── पौध तैयार होने में लगने वाले दिन
│       │   ├── देखा गया अंतर
│       │   ├── ट्रैक्टर दिन
│       │   ├── ट्रैक्टर लागत [रुपये ₹]
│       │   ├── बैल दिन
│       │   ├── बैल लागत [रुपये ₹]
│       │   └── क्या जमीन हाथ से तैयार की? [हां/नहीं]
│       ├── बुवाई / रोपाई और फसल देखभाल
│       │   ├── बुवाई / रोपाई विधि
│       │   │   ├── हाथ से
│       │   │   ├── मशीन से
│       │   │   ├── सीधी बुवाई
│       │   │   └── अन्य
│       │   │       └── चुनने पर: अन्य विधि लिखें
│       │   ├── क्या पौधों को जीवामृत में डुबोते हैं? [हां/नहीं]
│       │   ├── पौधों की दूरी [सेंटीमीटर cm]
│       │   ├── रोपाई दिन
│       │   ├── क्या रोपाई के लिए मजदूर चाहिए? [हां/नहीं]
│       │   ├── हां हो तो: मजदूरों की संख्या
│       │   ├── हां हो तो: दैनिक मजदूरी [रुपये ₹]
│       │   ├── क्या निराई करते हैं? [हां/नहीं]
│       │   └── हां हो तो: निराई कितने दिन बाद
│       └── कीट, वृद्धि और कटाई
│           ├── क्या कीट नियंत्रण के लिए छिड़काव करते हैं? [हां/नहीं]
│           ├── हां हो तो: छिड़काव पद्धतियां [बहु-चयन]
│           │   ├── नीम
│           │   │   └── चुनने पर: नीम मात्रा प्रति एकड़
│           │   ├── मटका
│           │   │   └── चुनने पर: मटका मात्रा प्रति एकड़
│           │   ├── जीवामृत
│           │   │   └── चुनने पर: जीवामृत मात्रा प्रति एकड़
│           │   ├── कीटनाशक
│           │   │   └── चुनने पर: कीटनाशक मात्रा प्रति एकड़
│           │   └── अन्य
│           │       └── चुनने पर: अन्य छिड़काव विवरण लिखें
│           ├── क्या जैविक खाद रोग नियंत्रण में मदद करती है? [हां/नहीं]
│           ├── रोपण से फूल आने तक दिन
│           ├── क्या उर्वरक उपयोग करते हैं? [हां/नहीं]
│           ├── हां हो तो: उर्वरक नाम
│           ├── हां हो तो: प्रति एकड़ मात्रा
│           ├── फूल आने के समय कीट समस्या होती है? [हां/नहीं]
│           ├── हां हो तो: कीट प्रकार
│           ├── हां हो तो: उपयोग किए गए छिड़काव
│           ├── परिपक्वता दिन
│           ├── क्या फसल की निगरानी करते हैं? [हां/नहीं]
│           ├── हां हो तो: निगरानी पद्धतियां [बहु-चयन]
│           │   ├── रोज खेत निरीक्षण
│           │   ├── फोटो
│           │   ├── नोट्स
│           │   ├── मोबाइल ऐप
│           │   └── अन्य
│           │       └── चुनने पर: अन्य निगरानी पद्धति लिखें
│           ├── कटाई विधि
│           │   ├── हाथ से
│           │   ├── मशीन से
│           │   └── मिश्रित
│           ├── कटाई मजदूर प्रकार
│           │   ├── परिवार
│           │   ├── किराए के मजदूर
│           │   └── मिश्रित
│           ├── कटाई दैनिक मजदूरी [रुपये ₹]
│           ├── कटाई मजदूरों की संख्या
│           ├── कटाई दिन
│           ├── खाने/बेचने के लिए तैयार होने में लगने वाले दिन
│           ├── क्या यह फसल बेचते हैं? [हां/नहीं]
│           └── हां हो तो: कब बेचा
│               ├── कटाई के तुरंत बाद
│               ├── 3 महीनों के भीतर
│               ├── 6 महीनों के भीतर
│               └── बेहतर कीमत के लिए रखा
├── मुख्य फसल का 3-वर्षीय उत्पादन
│   └── मुख्य फसल उत्पादन इतिहास [2023, 2024, 2025]
│       ├── क्षेत्र [एकड़]
│       ├── कुल उत्पादन
│       ├── घरेलू उपयोग
│       ├── बेची गई मात्रा
│       ├── कहां बेचा
│       └── बिक्री मूल्य [रुपये ₹]
└── आय और खाद्य उत्पाद
    ├── वार्षिक कृषि आय [रुपये ₹]
    ├── गैर-कृषि आय [रुपये ₹]
    ├── कुल वार्षिक आय [स्वतः गणना]
    ├── क्या खाद्य उत्पाद बनाते हैं? [हां/नहीं]
    ├── हां हो तो: खाद्य उत्पादों की सूची
    ├── हां हो तो: क्या खाद्य उत्पाद बनाने का प्रशिक्षण मिला है? [हां/नहीं]
    └── प्रशिक्षण मिला हो तो: प्रशिक्षण स्रोत
```

---

# Screenshot-Based Translation Fixes

These labels were visible in the screenshots and should display as follows when Marathi is selected.

| English label | Marathi label | Hindi label |
|---|---|---|
| New Survey | नवीन सर्वेक्षण | नया सर्वेक्षण |
| Main Crop Agronomy | मुख्य पिकाच्या कृषी पद्धती | मुख्य फसल की कृषि पद्धतियां |
| Other Crop Agronomy | इतर पिकाच्या कृषी पद्धती | अन्य फसल की कृषि पद्धतियां |
| Own land | स्वतःची जमीन | अपनी जमीन |
| Forest patta | वन हक्क पट्टा | वन अधिकार पट्टा |
| Leased land | भाडेपट्ट्याची जमीन | पट्टे की जमीन |
| Other | इतर | अन्य |
| Same land every year? | दरवर्षी तीच जमीन वापरता का? | क्या हर साल वही जमीन इस्तेमाल करते हैं? |
| Yes | होय | हां |
| No | नाही | नहीं |
| Land topology | जमिनीची रचना | जमीन की बनावट |
| Flat | सपाट | समतल |
| Sloped | उताराची | ढलान वाली |
| Terraced | पायऱ्यांची | सीढ़ीदार |
| Hilly | डोंगराळ | पहाड़ी |
| Seed sources | बियाण्याचे स्रोत | बीज के स्रोत |
| Own saved | स्वतः साठवलेले | स्वयं सहेजा हुआ |
| Local market | स्थानिक बाजार | स्थानीय बाजार |
| Government | शासकीय स्रोत | सरकारी स्रोत |
| Neighbour | शेजारी | पड़ोसी |
| Back | मागे | पीछे |
| Continue | पुढे | आगे |
| Select date | तारीख निवडा | तारीख चुनें |
| Cancel | रद्द करा | रद्द करें |
| OK | ठीक आहे | ठीक है |

Note: The **Other Crop Agronomy** tab should be removed if it is only duplicating the same agronomy questions. If retained for a later version, it must also be fully translated.

---

# Conditional Logic Checklist

## Date of Birth

- Field key: `date_of_birth`
- Type: Date picker
- Required: optional, unless the final survey rules require it
- Validation:
  - Must save selected date after tapping **OK**.
  - Must display selected date in the field.
  - Future dates are not allowed.
  - Recommended display format: `DD-MM-YYYY`.

## Other fields

Whenever **Other / इतर / अन्य** is selected, show a text field immediately below the same question.

Apply this to:

- Income sources
- Farming type
- Kharif crop name
- Land grown on
- Land topology
- Seed sources
- Seed treatment materials
- Seedling / sowing method
- Sowing / transplanting method
- Spray methods
- Monitoring methods

Suggested field naming:

```text
income_sources_other
farming_type_other
kharif_crop_other_name
kharif_crop_other_details
grown_on_other
land_topology_other
seed_source_other
seed_treatment_other
seedling_method_other
sowing_transplant_method_other
spray_method_other
monitoring_method_other
```

## Crop flow

- Remove separate **Other Crops** section.
- Remove duplicate **Other Crop Agronomy** section unless there is a clear separate use case.
- Use one **Kharif Crops** section with up to 4 rows.
- The crop name field inside each Kharif row must include:
  - Paddy / Rice
  - Nachani / Ragi
  - Bajra / Pearl millet
  - Other
- If **Other** is selected:
  - Show **Other crop name**.
  - Show **Other crop details**.

## Package of Practice

- Do not display `POP`.
- Display full label:
  - English: **Package of Practice training received?**
  - Marathi: **Package of Practice म्हणजे शिफारस केलेल्या पीक पद्धतीचे प्रशिक्षण मिळाले आहे का?**
  - Hindi: **क्या Package of Practice यानी अनुशंसित खेती पद्धति का प्रशिक्षण मिला है?**

## Pest, Growth and Harvest

When **Sprays for pest control?** is **Yes**, show **Spray methods**.

For every selected spray method, show the related per-acre field:

| Selected option | Field to show |
|---|---|
| Neem | Neem quantity per acre |
| Matka | Matka quantity per acre |
| Jeevamrut | Jeevamrut quantity per acre |
| Pesticide | Pesticide quantity per acre |
| Other | Other spray details |

This fixes the issue where **Jeevamrut** and **Pesticide** were not showing the per-acre field.

## Marathi language display

- Selecting Marathi must update the entire form to Marathi.
- Section titles, question labels, option chips, helper text, button labels, validation messages, and date picker labels must all use the Marathi translation file.
- Do not leave English labels inside Marathi mode.
- If a translation key is missing, mark it as a bug rather than silently falling back to English.

---

# Developer QA Checklist

- [ ] Date of Birth picker saves and displays selected date.
- [ ] Future date selection is blocked.
- [ ] Marathi mode translates all visible labels, including option chips.
- [ ] Hindi mode translates all visible labels, including option chips.
- [ ] Every **Other** selection opens a text field below the question.
- [ ] **Other** is removed from Main Crop if the updated flow is followed.
- [ ] **Other** is added under Kharif Crops → Crop name.
- [ ] Separate Other Crops section is removed.
- [ ] Duplicate Other Crop Agronomy tab is removed or fully translated if retained.
- [ ] `POP` is replaced with **Package of Practice** everywhere.
- [ ] Pesticide quantity per acre appears when Pesticide is selected.
- [ ] Jeevamrut quantity per acre appears when Jeevamrut is selected.
- [ ] Neem quantity per acre appears when Neem is selected.
- [ ] Matka quantity per acre appears when Matka is selected.
- [ ] Rupee fields show **Rupees (₹)** / **रुपये (₹)**.
- [ ] Distance fields show **centimetres (cm)** / **सेंटीमीटर (cm)**.
- [ ] Required field validation is translated in English, Marathi, and Hindi.

---

# Notes for Implementation

Use stable internal field keys in English and only translate the display labels. For example:

```text
field key: main_crop_agronomy.land_topology
English label: Land topology
Marathi label: जमिनीची रचना
Hindi label: जमीन की बनावट
```

This prevents data issues when the user changes language in the middle of the survey.

For multi-select options, save internal values like:

```text
neem
matka
jeevamrut
pesticide
other
```

Then translate only the visible label.

