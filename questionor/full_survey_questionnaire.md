# GrainRight Full Survey Questionnaire

Generated on: 2026-06-05

This document lists every survey question and option found in the project form configuration and repeat-group UI.

Sources cross-checked:
- `lib/config/offline_form_seed.dart`
- `lib/controllers/form_controller.dart`
- `lib/controllers/chat_survey_controller.dart`
- `lib/widgets/chat/repeat_group_prompt.dart`
- `lib/widgets/dynamic_field.dart`
- `lib/widgets/dynamic_step.dart`
- `lib/services/form_config_service.dart`
- Supabase migrations under `supabase/migrations`

Notes:
- Boolean questions use `Yes / No`.
- Numeric land questions use acre inputs unless stated otherwise.
- Currency questions use rupees.
- Repeat groups are stored in child tables and are rendered as multi-field question blocks.
- Disease and repeat-group options are partly enforced by runtime fallback code, so they are included even if an older remote form configuration is incomplete.

## 1. Family Information

1. Farmer Name
   - Type: Text
   - Required in offline seed: Yes

2. Village
   - Type: Text
   - Required in offline seed: Yes

3. Gram Panchayat
   - Type: Text
   - Required in offline seed: Yes

4. Taluka
   - Type: Text
   - Required in offline seed: Yes

5. District
   - Type: Text
   - Required in offline seed: Yes

6. Mobile No.
   - Type: Mobile number
   - Validation: 10 digits

7. Aadhaar No.
   - Type: Aadhaar number
   - Hint: `XXXX XXXX XXXX`
   - Validation: 12 digits

8. Date of Birth
   - Type: Date
   - Validation: minimum `1930-01-01`, maximum today

9. Education
   - Type: Dropdown
   - Options: Illiterate, Primary, Secondary, Graduate

10. Gender
    - Type: Dropdown
    - Options: Male, Female, Other

11. Category
    - Type: Dropdown
    - Options: General, SC, ST, OBC

## 2. Income Sources / Land Farming

12. Income sources
    - Type: Multi-select
    - Options: Farming, Private Job, Government Job, Business, Other
    - Required in offline seed: Yes

13. Other income source
    - Type: Text
    - Condition: shown when `Income sources` includes `Other`
    - Source note: present in migration `20260514182150_survey_form_i18n_other_fields.sql`; not present in the offline seed.

14. Farming type
    - Type: Multi-select
    - Options: Rainfed, Irrigated, Other
    - Required in offline seed: Yes

15. Other farming type
    - Type: Text
    - Condition: shown when `Farming type` includes `Other`
    - Source note: present in migration `20260514182150_survey_form_i18n_other_fields.sql`; not present in the offline seed.

16. Owns farmland?
    - Type: Yes / No
    - Required in offline seed: Yes

17. Total land area
    - Type: Acre
    - Suffix: acre
    - Required in offline seed: Yes

18. Irrigated land
    - Type: Acre
    - Suffix: acre

19. Dry land
    - Type: Acre
    - Suffix: acre

20. Fallow land
    - Type: Acre
    - Suffix: acre

21. Leased land
    - Type: Acre
    - Suffix: acre

22. Rain-based area
    - Type: Acre
    - Suffix: acre

## 3. Forest Patta

23. Has forest patta?
    - Type: Yes / No
    - Required in offline seed: Yes

24. Forest patta area
    - Type: Acre
    - Suffix: acre
    - Condition: shown when `Has forest patta?` is Yes

25. Applied for forest patta?
    - Type: Yes / No
    - Condition: shown when `Has forest patta?` is No

## 4. Farm Boundary

26. Farm Boundary Polygon
    - Type: Map polygon drawing
    - Offline label: `Farm Boundary Polygon (optional)`
    - Hint: Draw if time permits; submission is allowed without it.

## 5. Main Crop

27. Main crop
    - Type: Dropdown
    - Options: Paddy (Rice), Nachani (Ragi), Bajra, Other
    - Stored values: `paddy`, `nachani`, `bajra`, `other`
    - Required in offline seed: Yes

28. Other crop name
    - Type: Text
    - Condition: shown when `Main crop` is Other

29. Other crop details
    - Type: Text
    - Hint: Variety, local name, or field notes
    - Condition: shown when `Main crop` is Other

30. Land under main crop
    - Type: Acre
    - Suffix: acre

31. Land under other crop
    - Type: Acre
    - Suffix: acre
    - Condition: shown when `Main crop` is Bajra or Other

## 6. Kharif Crops Repeat Group

Question block: Crops taken in Kharif season / Kharif crops

Repeat behavior:
- Up to 4 crop rows can be added.
- Crop 1 is prefilled from `Main crop` and `Land under main crop` when available.
- Each crop row contains the questions below.

32. Crop name
    - Type: Dropdown when crop options are available
    - Options: Paddy (Rice), Nachani (Ragi), Bajra, Other

33. Other crop name
    - Type: Text
    - Condition: shown when crop name is Other

34. Other crop details
    - Type: Text
    - Condition: shown when crop name is Other

35. Cultivated area
    - Type: Number
    - Unit: acre

36. Variety
    - Type: Dropdown for known crop names; otherwise text
    - Bajra options: Dhanshakti, ICTP 8203, Phule Adishakti, Phule Mahashakti, Pusa Composite 612, ICMV 221, ICMV 155, AIMP 92901 Samrudhi, Other
    - Nachani/Ragi options: GPU 28, GPU 67, GPU 66, VL Mandua, Dapoli 1, Phule Nachani, MR 6, Other
    - Paddy/Rice options: Indrayani, Ambemohar, Phule Maval, Phule Samruddhi, Jaya, Kolam, HMT, Sona Masuri, Other

37. Other variety
    - Type: Text
    - Condition: shown when `Variety` is Other

38. Production quantity
    - Type: Number with unit
    - Unit options: qt, kg, ton
    - Default unit: qt

39. Average estimated cost
    - Type: Number
    - Unit: Rupees

## 7. Crop Agronomy Repeat Groups

The app captures two agronomy practice blocks:
- Rice/Ragi crop practices
- Bajra/Other crop practices

The chat/classic UI can label these as:
- Main Crop Agronomy - Rice/Ragi crop practices
- Main Crop Agronomy - Bajra/Other crop practices
- Other Crop Agronomy - Rice/Ragi crop practices
- Other Crop Agronomy - Bajra/Other crop practices

The selected first Kharif crop determines which crop-practice group is treated as the primary/main slot. Each agronomy block contains the same questions below, except `Seedling ready (days)` is only collected for the Rice/Ragi role.

### 7.1 Location and Training

40. Grown on
    - Type: Single select
    - Options: Own land, Forest patta, Leased land, Other

41. Other details
    - Type: Text
    - Condition: shown when `Grown on` is Other

42. Same land every year?
    - Type: Yes / No

43. Land topology
    - Type: Single select
    - Options: Flat, Sloped, Terraced, Hilly, Other

44. Other details
    - Type: Text
    - Condition: shown when `Land topology` is Other

45. Seed sources
    - Type: Multi-select
    - Options: Own saved, Local market, Government source, Neighbour, Co-op society, Other

46. Other source details
    - Type: Text
    - Condition: shown when `Seed sources` includes Other

47. Package of Practice training received?
    - Type: Yes / No

48. Training source
    - Type: Text
    - Condition: shown when `Package of Practice training received?` is Yes

49. Farming method
    - Type: Single select
    - Options: Organic, Chemical, Mixed, Traditional

### 7.2 Seed and Land Preparation

50. Treats seeds?
    - Type: Yes / No

51. Seed treatment materials
    - Type: Multi-select
    - Options: Cow dung, Cow urine, Neem, Jeevamrut, Chemical, Other
    - Condition: shown when `Treats seeds?` is Yes

52. Other details
    - Type: Text
    - Condition: shown when `Seed treatment materials` includes Other

53. Seedling method
    - Type: Single select
    - Options: Direct sowing, Nursery transplant, Broadcasting, Other

54. Other details
    - Type: Text
    - Condition: shown when `Seedling method` is Other

55. Seedling ready
    - Type: Number
    - Unit: days
    - Condition: collected for Rice/Ragi crop-practice role only

56. Tractor days
    - Type: Number

57. Tractor cost
    - Type: Number
    - Unit: Rupees

58. Bullock days
    - Type: Number

59. Bullock cost
    - Type: Number
    - Unit: Rupees

60. Land prepared by hand?
    - Type: Yes / No

### 7.3 Transplanting and Crop Care

61. Transplant method
    - Type: Single select
    - Options: By hand, Machine, Direct seed, Other

62. Other details
    - Type: Text
    - Condition: shown when `Transplant method` is Other

63. Dip in Jeevamrut?
    - Type: Yes / No

64. Plant spacing
    - Type: Number
    - Unit: centimetres cm

65. Transplant days
    - Type: Number

66. Needs transplant labour?
    - Type: Yes / No

67. How many labourers
    - Type: Number
    - Condition: shown when `Needs transplant labour?` is Yes

68. Daily wage
    - Type: Number
    - Unit: Rupees
    - Condition: shown when `Needs transplant labour?` is Yes

69. Does weeding?
    - Type: Yes / No

70. Weeding after
    - Type: Number
    - Unit: days
    - Condition: shown when `Does weeding?` is Yes

### 7.4 Pest, Growth, Harvest

71. Sprays for pest?
    - Type: Yes / No

72. Spray methods
    - Type: Multi-select
    - Options: Neem, Matka, Jeevamrut, Pesticide, Other
    - Condition: shown when `Sprays for pest?` is Yes

73. Matka per acre
    - Type: Number with unit
    - Unit options: ml, kg
    - Condition: shown when `Spray methods` includes Matka

74. Neem per acre
    - Type: Number with unit
    - Unit options: ml, kg
    - Condition: shown when `Spray methods` includes Neem

75. Jeevamrut per acre
    - Type: Number with unit
    - Unit options: ml, kg
    - Condition: shown when `Spray methods` includes Jeevamrut

76. Pesticide per acre
    - Type: Number with unit
    - Unit options: ml, kg
    - Condition: shown when `Spray methods` includes Pesticide

77. Other spray details
    - Type: Text
    - Condition: shown when `Spray methods` includes Other

78. Does organic fertilizer help in disease control?
    - Type: Yes / No

79. Planting to flowering
    - Type: Number
    - Unit: days

80. Uses fertilizer?
    - Type: Yes / No

81. Fertilizer names
    - Type: Text
    - Condition: shown when `Uses fertilizer?` is Yes

82. Quantity per acre
    - Type: Number
    - Condition: shown when `Uses fertilizer?` is Yes

83. Flowering pest problem?
    - Type: Yes / No

84. Pest type
    - Type: Text
    - Condition: shown when `Flowering pest problem?` is Yes

85. Sprays used
    - Type: Text
    - Condition: shown when `Flowering pest problem?` is Yes

86. Maturity
    - Type: Number
    - Unit: days

87. Monitors crop?
    - Type: Yes / No

88. Monitoring methods
    - Type: Multi-select
    - Options: Daily walk, Photos, Notes, Mobile app, Other
    - Condition: shown when `Monitors crop?` is Yes

89. Other details
    - Type: Text
    - Condition: shown when `Monitoring methods` includes Other

90. Harvest method
    - Type: Single select
    - Options: By hand, Machine, Mixed

91. Harvest labour type
    - Type: Single select
    - Options: Family, Hired, Mixed

92. Harvest daily wage
    - Type: Number
    - Unit: Rupees

93. Harvest labourers
    - Type: Number

94. Harvest days
    - Type: Number

95. Ready to eat/sell
    - Type: Number
    - Unit: days

96. Sells this crop?
    - Type: Yes / No

97. When sold
    - Type: Single select
    - Options: Right after harvest, Within 3 months, Within 6 months, Hold for better price
    - Condition: shown when `Sells this crop?` is Yes

## 8. Main Crop 3-Year Production Repeat Group

Question block: Main crop production for last 3 years / Main crop production history

Repeat behavior:
- Fixed year rows: 2023, 2024, 2025.
- Each year row contains the questions below.

98. Area
    - Type: Number
    - Unit: acre

99. Total production
    - Type: Number with unit
    - Unit options: qt, kg, ton
    - Default unit: qt

100. Yield
     - Type: Number with unit
     - Label in UI: Yield (average per acre)
     - Unit options: qt, kg, ton
     - Default unit: qt

101. Home consumption
     - Type: Number with unit
     - Unit options: qt, kg, ton
     - Default unit: qt

102. Quantity sold
     - Type: Number with unit
     - Unit options: qt, kg, ton
     - Default unit: qt

103. Sold where
     - Type: Multi-select
     - Options: Local market, FPC, APMC/Mandi, Trader, SHG/Co-op, Processing unit, Direct consumer, Other

104. Other selling place
     - Type: Text
     - Condition: shown when `Sold where` includes Other

105. Selling price
     - Type: Number
     - Unit: Rupees

## 9. Disease

106. Any Disease Observed?
     - Type: Yes / No

107. Crop affected / Affected Crop
     - Type: Dropdown
     - Options: dynamic list from selected main crop and Kharif crop rows, plus Bajra, Nachani (Ragi), Paddy (Rice), Other
     - Condition: shown when `Any Disease Observed?` is Yes

108. Other crop affected
     - Type: Text
     - Condition: shown when `Crop affected` is Other

109. Disease Name
     - Type: Dropdown
     - Options: Blast, Leaf blast, Neck blast, Finger blast, Brown spot, Sheath blight, Bacterial leaf blight, Bacterial leaf streak, False smut, Tungro, Downy mildew, Green ear disease, Ergot, Smut, Rust, Grain mold, Foot rot, Seedling blight, Other
     - Condition: shown when `Any Disease Observed?` is Yes

110. Other disease name
     - Type: Text
     - Hint: Write name if not listed
     - Condition: shown when `Disease Name` is Other

111. Disease Severity
     - Type: Dropdown
     - Options: Mild, Moderate, Severe
     - Condition: shown when `Any Disease Observed?` is Yes

112. Symptoms Observed
     - Type: Textarea
     - Hint: Write key symptoms
     - Condition: shown when `Any Disease Observed?` is Yes

113. Treatment Taken
     - Type: Textarea
     - Hint: Fungicide, biocontrol, etc.
     - Condition: shown when `Any Disease Observed?` is Yes

## 10. Income and Food Products

114. Annual agricultural income
     - Type: Currency

115. Non-agricultural income
     - Type: Currency

116. Total cost of cultivation
     - Type: Currency

117. Total annual income
     - Type: Auto-calculated
     - Formula: `Annual agricultural income + Non-agricultural income - Total cost of cultivation`

118. Makes food products?
     - Type: Yes / No

119. Food products list
     - Type: Text
     - Condition: shown when `Makes food products?` is Yes

120. Food product training received?
     - Type: Yes / No
     - Condition: shown when `Makes food products?` is Yes

121. Food product training source
     - Type: Text
     - Condition: shown when `Food product training received?` is Yes

## Option Keys Cross-Check

- `education_v2`: Illiterate, Primary, Secondary, Graduate
- `gender_v2`: Male, Female, Other
- `category_v2`: General, SC, ST, OBC
- `income_sources_v2`: Farming, Private Job, Government Job, Business, Other
- `farming_type_v2`: Rainfed, Irrigated, Other
- `main_crop_v2`: Paddy (Rice), Nachani (Ragi), Bajra, Other
- `disease_severity`: Mild, Moderate, Severe
- `disease_name_common`: Blast, Leaf blast, Neck blast, Finger blast, Brown spot, Sheath blight, Bacterial leaf blight, Bacterial leaf streak, False smut, Tungro, Downy mildew, Green ear disease, Ergot, Smut, Rust, Grain mold, Foot rot, Seedling blight, Other
- `affected_crop_fallback`: Bajra, Nachani (Ragi), Paddy (Rice), Other
- `crop_variety_bajra`: Dhanshakti, ICTP 8203, Phule Adishakti, Phule Mahashakti, Pusa Composite 612, ICMV 221, ICMV 155, AIMP 92901 Samrudhi, Other
- `crop_variety_nachani`: GPU 28, GPU 67, GPU 66, VL Mandua, Dapoli 1, Phule Nachani, MR 6, Other
- `crop_variety_paddy`: Indrayani, Ambemohar, Phule Maval, Phule Samruddhi, Jaya, Kolam, HMT, Sona Masuri, Other

## Source Differences Noted

1. The offline seed groups income and land fields under `Land / Farming`, while the baseline SQL seed separates them into `Income Sources` and `Land Holding`.
2. The offline seed includes `main_crop_other`, `other_crop_details`, and `other_crop_land_acre`; older SQL seed content only had `main_crop` and `main_crop_land_acre`, but the database/export schema includes the other-crop columns.
3. Later migrations and controller fallback expand Disease fields and options beyond the initial baseline.
4. `income_sources_other` and `farming_type_other` are present in a migration, but not in the offline seed. They are included above so they are not missed if the remote form configuration contains them.
5. `Other Crops` as a standalone section is removed by `FormConfigService`; the active crop-entry UI uses the Kharif crops repeat group instead.
