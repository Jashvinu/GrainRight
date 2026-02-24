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
            text: 'wrk',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: 'Farm',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.green,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
