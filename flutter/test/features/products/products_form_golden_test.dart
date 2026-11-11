@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner review material for Task 8 (phase 1d): the redesigned Add product
/// dialog, rendered with the REAL fonts, captured as PNGs.
///
/// Four captures, the two widths the plan names and both text scales, each with
/// one extra selling unit filled in ("Bag = 40 kg at ₱270") so the live helper
/// is part of the picture.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/products/products_form_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');
  final goldenDir = Directory(
    '${Directory.current.path}/../.superpowers/sdd/ui-refresh/goldens',
  );

  setUpAll(() async {
    goldenDir.createSync(recursive: true);
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
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    // The brand fonts stop at Latin, so the peso sign would be a box.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final (width, scale) in const [
    (1440.0, 1.0),
    (1440.0, 1.3),
    (760.0, 1.0),
    (760.0, 1.3),
  ]) {
    testWidgets('add product at ${width.toInt()} px, text scale $scale', (
      tester,
    ) async {
      // Tall enough that the WHOLE form fits at both scales: the owner reviews
      // the three steps together, not a scroll position. 2500 px is what 1.3x
      // text needs before step 3's location field and its "Saved on this device
      // only" helper fall below the fold (the dialog caps at 0.9 x height).
      tester.view.physicalSize = Size(width, 2500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme.copyWith(
              // Only the golden: lets the peso sign fall back to the system font
              // the app itself uses.
              textTheme: AppTheme.lightTheme.textTheme.apply(
                fontFamilyFallback: const [_pesoFallbackFamily],
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const _FormHost(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // One extra selling unit: Bag = 40 kg at ₱270, so the helper reads
      // "1 BAG = 40 KG · ₱6.75 per KG".
      await _tapKey(tester, const ValueKey('add-unit-row'));
      await _tapKey(tester, const ValueKey('row-unit-0'));
      await tester.tap(find.text('Bag (BAG)').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('row-factor-0')), '40');
      await tester.enterText(find.byKey(const ValueKey('row-price-0')), '270');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      // Back to the top of the form: the capture is the dialog as it opens.
      await tester.ensureVisible(find.text('Basic information'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
          Uri.file(
            '${goldenDir.path}/f3_add_product_${width.toInt()}_'
            '${scale.toStringAsFixed(1).replaceAll('.', '_')}.png',
          ),
        ),
      );
    }, skip: !enabled);
  }
}

const goldenKey = ValueKey('AddProductGolden');

/// The page behind the dialog: a button that opens it, so the capture is a real
/// dialog route on its scrim rather than a floating widget.
class _FormHost extends StatefulWidget {
  const _FormHost();

  @override
  State<_FormHost> createState() => _FormHostState();
}

class _FormHostState extends State<_FormHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        builder: (_) => const ProductsFormDialog(
          categories: [Category(id: 1, name: 'Cement')],
          brands: [Brand(id: 1, name: 'Holcim')],
          units: [
            UnitOfMeasure(id: 1, code: 'KG', name: 'Kilogram'),
            UnitOfMeasure(id: 2, code: 'BAG', name: 'Bag', isWhole: true),
            UnitOfMeasure(id: 3, code: 'BOX', name: 'Box', isWhole: true),
          ],
          products: [],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: AppColors.background);
  }
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Stands in for the platform font the app itself falls back to for a glyph the
/// brand fonts do not have.
const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFontFile(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

String? _flutterSdkFile(String relativePath) {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      '$root/$relativePath',
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 6; depth++) {
    candidates.add('${dir.path}/$relativePath');
    dir = dir.parent;
  }
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
