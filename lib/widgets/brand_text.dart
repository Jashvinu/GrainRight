import 'package:flutter/material.dart';
import '../config/theme.dart';

class BrandText extends StatelessWidget {
  final double fontSize;

  const BrandText({super.key, this.fontSize = 28});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Kalsubai',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
              letterSpacing: 0,
            ),
          ),
          TextSpan(
            text: ' Farms',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.green,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
