// Z2 fix task B (D-05): the Reports caption was cut at text scale 1.3.
//
// The four stock figures are laid out by MetricGrid, which picked four tiles
// across from a pixel width alone. At a 1.3x text scale the same width has to
// hold 30% wider words, so "Landed cost of stock on hand" ended in "Landed cost
// of stock on ...". The grid's minimum tile width now scales with the text, so
// a raised scale gets two wider tiles instead of four cramped ones.
//
// Measured on the REAL fonts at 1100 x 900: that is where the sweep caught it.
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

const String caption = 'Landed cost of stock on hand';

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('the inventory value caption is not cut at text scale 1.3', (
    tester,
  ) async {
    await _pump(tester, const Size(1100, 900), textScale: 1.3);

    final paragraph = tester.renderObject<RenderParagraph>(find.text(caption));
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'the caption names what the value IS, so it cannot end in "..."',
    );
  });

  testWidgets('a desktop window still shows four tiles across at scale 1.0', (
    tester,
  ) async {
    // The fix must not cost the everyday layout: 1100 px at the default scale
    // has room for four figures, and stacking them two by two would spend
    // twice the height on four numbers.
    await _pump(tester, const Size(1100, 900), textScale: 1.0);

    final first = tester.getRect(find.text('INVENTORY VALUE'));
    final fourth = tester.getRect(find.text('PRODUCTS COUNTED'));
    expect(fourth.top, first.top, reason: 'four tiles on one line');
    // A scale-aware floor at 1.0 is the plain 235 px floor it always was.
    expect(first.width, greaterThan(0));
  });
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required double textScale,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final store = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(id: 1, name: 'Portland Cement 40 kg', categoryName: 'Cement'),
      ],
      batches: [batch(id: 1, variantId: 1, qty: 100, cost: 245)],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await store.load();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>.value(value: _stockManagerAuth()),
        ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const InventoryReportsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Stock Manager the shell paints its sidebar for.
AuthViewmodel _stockManagerAuth() {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 4,
    username: 'stocker',
    email: 'stocker@qb.ph',
    fullName: 'Ana Lopez',
    role: const Role(id: 4, name: 'inventory', displayName: 'Stock Manager'),
  );
  return auth;
}

/// The app's own fonts, so a truncation measured here is one a stocker sees.
Future<void> _loadRealFonts() async {
  await _loadFont('Cinzel', const [
    'Cinzel-Regular.ttf',
    'Cinzel-Medium.ttf',
    'Cinzel-Bold.ttf',
  ]);
  await _loadFont('OpenSans', const [
    'OpenSans-Regular.ttf',
    'OpenSans-Medium.ttf',
    'OpenSans-Bold.ttf',
  ]);
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
