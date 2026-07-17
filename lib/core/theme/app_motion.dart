import 'package:flutter/animation.dart';

class AppMotion {
  const AppMotion._();

  static const Duration tap = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration page = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuart;
}
