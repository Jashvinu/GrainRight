import 'package:flutter/material.dart';

import 'farmer_login_screen.dart';

class StakeholderLoginScreen extends StatelessWidget {
  const StakeholderLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FarmerLoginScreen(
      titleKey: 'stakeholder_login',
      subtitleKey: 'stakeholder_login_subtitle',
      loginNoteKey: 'stakeholder_login_note',
      continueLabelKey: 'stakeholder_continue',
      nextRoute: '/stakeholder',
    );
  }
}
