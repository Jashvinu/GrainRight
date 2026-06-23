import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/theme.dart';
import '../config/ui_strings.dart';

const double appHeaderToolbarHeight = 66;
const double appBackButtonLeadingWidth = 64;
const double appHeaderButtonSize = 44;

Widget? appBackButtonLeading(BuildContext context, {VoidCallback? onPressed}) {
  if (onPressed == null && !Navigator.of(context).canPop()) {
    return null;
  }
  return _AppHeaderLeading(child: AppBackButton(onPressed: onPressed));
}

Widget appMenuButtonLeading(BuildContext context, {VoidCallback? onPressed}) {
  return _AppHeaderLeading(
    child: AppMenuButton(
      onPressed: onPressed ?? () => Scaffold.maybeOf(context)?.openDrawer(),
    ),
  );
}

class _AppHeaderLeading extends StatelessWidget {
  final Widget child;

  const _AppHeaderLeading({required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: child,
    );
  }
}

class AppHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final double size;

  const AppHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.backgroundColor = Colors.white,
    this.foregroundColor = AppTheme.greenDark,
    this.borderColor = const Color(0xFFE5E7EB),
    this.size = appHeaderButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: foregroundColor,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final double size;

  const AppBackButton({
    super.key,
    this.onPressed,
    this.backgroundColor = Colors.white,
    this.foregroundColor = AppTheme.greenDark,
    this.borderColor = const Color(0xFFE5E7EB),
    this.size = appHeaderButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    return AppHeaderIconButton(
      tooltip: UiStrings.t('back'),
      onPressed: onPressed ?? () => Get.back(),
      icon: Icons.arrow_back_rounded,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      borderColor: borderColor,
      size: size,
    );
  }
}

class AppMenuButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const AppMenuButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppHeaderIconButton(
      tooltip: UiStrings.t('menu'),
      onPressed: onPressed,
      icon: Icons.menu_rounded,
    );
  }
}
