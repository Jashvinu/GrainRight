import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/widgets/role_login_shell.dart';

void main() {
  for (final device in <({Size size, double textScale, String name})>[
    (size: const Size(320, 568), textScale: 1, name: 'compact phone'),
    (size: const Size(360, 640), textScale: 2, name: 'large text phone'),
    (size: const Size(800, 1280), textScale: 1, name: 'tablet'),
  ]) {
    testWidgets('role login shell is responsive on ${device.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = device.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: device.size,
              textScaler: TextScaler.linear(device.textScale),
            ),
            child: RoleLoginShell(
              title: 'Farmer producer company login',
              subtitle:
                  'Use your registered account to securely open the workspace.',
              languageCode: 'en',
              onLanguageChanged: (_) {},
              onBack: () {},
              info: const RoleLoginInfoStrip(
                icon: Icons.verified_user_outlined,
                text: 'Only approved team members can continue.',
              ),
              form: const Column(
                children: [
                  TextField(decoration: InputDecoration(labelText: 'Email')),
                  SizedBox(height: 14),
                  TextField(decoration: InputDecoration(labelText: 'Password')),
                ],
              ),
              action: RoleLoginButton(
                loading: false,
                onPressed: () {},
                label: 'Login to farmer producer company dashboard',
                loadingLabel: 'Verifying account',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dense role login keeps the same two-field flow compact', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: RoleLoginShell(
          dense: true,
          title: 'FPC Login',
          subtitle:
              'One secure login. The correct workspace opens automatically.',
          languageCode: 'en',
          onLanguageChanged: (_) {},
          onBack: () {},
          info: const RoleLoginInfoStrip(
            icon: Icons.verified_user_outlined,
            text: 'No role selection is needed.',
          ),
          form: const Column(
            children: [
              TextField(decoration: InputDecoration(labelText: 'Email')),
              SizedBox(height: 14),
              TextField(decoration: InputDecoration(labelText: 'Password')),
            ],
          ),
          action: RoleLoginButton(
            loading: false,
            onPressed: () {},
            label: 'Login to FPC Dashboard',
            loadingLabel: 'Verifying',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
