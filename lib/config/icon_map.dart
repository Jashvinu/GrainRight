import 'package:flutter/material.dart';

const Map<String, IconData> kIconMap = {
  'person_outline': Icons.person_outline,
  'landscape_outlined': Icons.landscape_outlined,
  'grass_outlined': Icons.grass_outlined,
  'science_outlined': Icons.science_outlined,
  'bar_chart_outlined': Icons.bar_chart_outlined,
  'inventory_2_outlined': Icons.inventory_2_outlined,
  'currency_rupee_outlined': Icons.currency_rupee_outlined,
  'info_outline': Icons.info_outline,
  'agriculture': Icons.agriculture,
  'water_drop_outlined': Icons.water_drop_outlined,
  'home_outlined': Icons.home_outlined,
  'shopping_cart_outlined': Icons.shopping_cart_outlined,
  'assessment_outlined': Icons.assessment_outlined,
  'eco_outlined': Icons.eco_outlined,
  'local_shipping_outlined': Icons.local_shipping_outlined,
};

IconData resolveIcon(String name) => kIconMap[name] ?? Icons.info_outline;
