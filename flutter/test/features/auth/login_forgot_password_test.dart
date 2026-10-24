// Phase 3 Task 0 (U) — the login screen's "Forgot password?" was
// `TextButton(onPressed: () {}, ...)`: a link that swallowed the tap.
//
// There is no self-service reset in this system — `POST /auth/login/` is the
// only credential endpoint and password changes happen in the Django admin or
// User Management. So the control becomes an honest instruction: ask a System
// Administrator to reset it. A dialog is better than a mailto: that no server
// answers.

import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: const MaterialApp(home: LoginPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('"Forgot password?" explains who can reset it', (tester) async {
    await _pump(tester);

    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.textContaining('System Administrator'),
      findsOneWidget,
      reason: 'the only actor who can reset a password must be named',
    );
    expect(
      find.textContaining('reset'),
      findsWidgets,
      reason: 'the dialog must say what to ask for, not only who to ask',
    );
  });

  testWidgets('the dialog closes and leaves the form usable', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);

    // The fields still work: this is a dialog, not a blocking screen.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Enter your username or email'),
      'admin',
    );
    expect(find.text('admin'), findsOneWidget);
  });
}
