// Smoke test for the app's unauthenticated entry path.
//
// Replaces Flutter's default counter template, which could never compile against
// this app: it imported `package:client/main.dart` and called `const MyApp()`,
// but `MyApp` lives in `package:client/app.dart` and requires an `auth` argument.
// That compile error blocked `flutter test` entirely.

import 'package:client/app.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('launching without a session lands on the login page', (
    WidgetTester tester,
  ) async {
    final auth = AuthViewmodel(AuthRepository(AuthService()));

    // Mirrors main.dart, which supplies AuthViewmodel above MyApp. LoginPage
    // reads it with Consumer<AuthViewmodel>.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MyApp(auth: auth),
      ),
    );
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
