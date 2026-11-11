@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

/// Owner review material for Task 10a (phase 1d): the stock adjustment dialog in
/// the shared family, with the System quantity to New quantity boxes, the worded
/// difference badge and the real fonts.
///
/// The plan's acceptance pair is the wide capture and the narrow one at 1.3x
/// text, where clipping shows first; 1100 is the third width the plan lists.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_adjust_stock_golden_test.dart
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
  });

  for (final (width, scale) in const [
    (1440.0, 1.0),
    (1100.0, 1.0),
    (760.0, 1.3),
  ]) {
    testWidgets('adjust stock at ${width.toInt()} px, text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const _AdjustHost(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The adjusted quantity is typed into the field, so the new-quantity box
      // and the difference badge show a real change rather than no change.
      await tester.enterText(find.byType(TextFormField).first, '1250');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
          Uri.file(
            '${goldenDir.path}/f3_adjust_stock_${width.toInt()}_'
            '${scale.toStringAsFixed(1).replaceAll('.', '_')}.png',
          ),
        ),
      );
    }, skip: !enabled);
  }
}

const goldenKey = ValueKey('AdjustStockGolden');

class _AdjustHost extends StatefulWidget {
  const _AdjustHost();

  @override
  State<_AdjustHost> createState() => _AdjustHostState();
}

class _AdjustHostState extends State<_AdjustHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final item = product(
        id: 1,
        name: 'Portland Cement 40 kg bag, type 1P',
        variants: [
          variant(
            id: 11,
            productId: 1,
            name: '40 kg bag',
            baseUomCode: 'BAG',
            baseUomId: 3,
          ),
        ],
      );
      showDialog<void>(
        context: context,
        builder: (_) => InventoryAdjustStockDialog(
          product: item,
          variant: item.variants.first,
          currentStock: 1200,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: AppColors.background);
  }
}

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
