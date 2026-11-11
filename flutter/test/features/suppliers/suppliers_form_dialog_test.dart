// Phase 1d Task 10b (decisions 16-17): the supplier form joins the shared
// dialog family.
//
// What must stay exactly as it was: the field labels the page's test finds
// ("Company Name"), the validation sentence, the returned `Supplier`, and both
// footer actions. What changes: the frame (hexagon header, a guidance note) and
// the HCI acceptance every redesigned dialog owes the plan: keyboard order
// follows the fields, Esc closes and focus comes back to the opener, and
// nothing clips at 1.3x text in a 760 px window with the REAL fonts.

import 'dart:io';

import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/suppliers_form_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

const _guidance = 'Purchase orders and Receiving only offer active suppliers.';

void main() {
  setUpAll(_loadAppFonts);

  /// Opens the form the way the Suppliers page does, from a button that owns its
  /// focus, and hands back everything the assertions look at.
  Future<({FocusNode opener, Supplier? Function() saved})> open(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    double scale = 1.0,
    Supplier? supplier,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);
    Supplier? saved;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Focus(
              focusNode: opener,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<Supplier>(
                    context: context,
                    builder: (_) => SuppliersFormDialog(supplier: supplier),
                  ).then((value) => saved = value),
                  child: const Text('Add supplier'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    opener.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add supplier'));
    await tester.pumpAndSettle();
    return (opener: opener, saved: () => saved);
  }

  /// The label of the field that currently holds the keyboard, or the dialog's
  /// close button, so a Tab order can be written down.
  String focused(WidgetTester tester) {
    for (final label in const [
      'Company Name',
      'Contact Person',
      'Phone',
      'Email',
      'Address',
    ]) {
      final field = find.descendant(
        of: find.widgetWithText(TextFormField, label),
        matching: find.byType(EditableText),
      );
      if (field.evaluate().isEmpty) continue;
      if (tester.widget<EditableText>(field).focusNode.hasFocus) return label;
    }
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null &&
        context.findAncestorWidgetOfExactType<IconButton>() != null) {
      return 'close';
    }
    return 'nothing';
  }

  testWidgets('the form is the shared shell: hexagon header and guidance', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    final title = tester.widget<Text>(find.text('Add Supplier'));
    expect(title.style?.fontFamily, 'Cinzel');
    expect(
      title.style!.fontSize!,
      greaterThanOrEqualTo(18),
      reason: 'Cinzel below 18 px is the one thing the look rules forbid',
    );
    expect(find.byType(HexIconBadge), findsOneWidget);
    expect(find.text('SUPPLIER DETAILS'), findsOneWidget);
    expect(find.text(_guidance), findsOneWidget);

    // The fields the Suppliers page's own test drives, unchanged.
    for (final label in const [
      'Company Name',
      'Contact Person',
      'Phone',
      'Email',
      'Address',
    ]) {
      expect(find.widgetWithText(TextFormField, label), findsOneWidget);
    }
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save Supplier'), findsOneWidget);
  });

  testWidgets('the keyboard runs from the header down the fields in order', (
    tester,
  ) async {
    await open(tester);

    // The dialog frame takes the keyboard on open, so Esc works before anything
    // is touched; Tab then runs close, then the fields in reading order.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused(tester), 'close');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused(tester), 'Company Name');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused(tester), 'Contact Person');
  });

  testWidgets('Esc closes and focus returns to the button that opened it', (
    tester,
  ) async {
    final host = await open(tester);
    expect(find.byType(AppDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(
      host.opener.hasPrimaryFocus,
      isTrue,
      reason: 'a keyboard user must land back on the button they pressed',
    );
  });

  testWidgets('validation and the returned supplier are unchanged', (
    tester,
  ) async {
    final host = await open(tester);

    await tester.tap(find.text('Save Supplier'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the company name.'), findsOneWidget);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(host.saved(), isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Company Name'),
      'Tagbilaran Hardware',
    );
    await tester.tap(find.text('Save Supplier'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(host.saved()?.companyName, 'Tagbilaran Hardware');
    expect(host.saved()?.isActive, isTrue);
  });

  testWidgets('an edited supplier keeps its id and its active flag', (
    tester,
  ) async {
    const existing = Supplier(
      id: 7,
      companyName: 'Bohol Cement Traders',
      contactPerson: 'Rina Lim',
      phone: '0917 000 1111',
      email: 'orders@boholcement.ph',
      address: 'Tagbilaran City',
      isActive: false,
    );
    final host = await open(tester, supplier: existing);

    expect(find.text('Edit Supplier'), findsOneWidget);
    final phone = find.widgetWithText(TextFormField, 'Phone');
    expect(
      tester.widget<TextField>(find.byType(TextField).first),
      isNotNull,
      reason: 'sanity: the dialog is a form of plain fields',
    );
    expect(
      find.descendant(of: phone, matching: find.text('0917 000 1111')),
      findsOneWidget,
    );

    await tester.tap(find.text('Save Supplier'));
    await tester.pumpAndSettle();

    expect(host.saved()?.id, 7);
    expect(host.saved()?.isActive, isFalse);
    expect(host.saved()?.contactPerson, 'Rina Lim');
  });

  testWidgets('at 760 px and 1.3x text nothing clips and every action is '
      'reachable', (tester) async {
    await open(tester, size: const Size(760, 900), scale: 1.3);

    expect(tester.takeException(), isNull);
    for (final label in const [
      'Company Name',
      'Contact Person',
      'Phone',
      'Email',
      'Address',
    ]) {
      expect(find.widgetWithText(TextFormField, label), findsOneWidget);
    }
    expect(find.text('Save Supplier').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text(_guidance), findsOneWidget);
    final rect = tester.getRect(find.byType(AppDialog));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(760));
  });
}
