@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3): a gallery of
/// the seven shared components rendered with the REAL fonts, written as PNGs
/// into the SDD folder so the layout can be looked at without the browser.
///
/// This file is opt in: it only runs when RUN_GOLDENS is passed, so the normal
/// suite never fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/shared/widgets/components_golden_test.dart
/// ```
void main() {
  // Opt in: the normal suite never compares goldens (a font or platform
  // difference must not fail CI). Pass --dart-define=RUN_GOLDENS=true to run.
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute target so the PNGs land in the SDD folder, not next to the test.
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
    // Icons: the test harness does not load the Material icon font, so every
    // Icon would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) {
      await _loadFontFile('MaterialIcons', icons);
    }
    // Peso sign: the bundled OpenSans and Cinzel have no U+20B1, so every
    // amount would be a box. The app relies on the platform font here; the
    // test has none, so a system font that does carry it stands in.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final entry in const [
    ('1440', Size(1440, 1200)),
    ('760', Size(760, 2000)),
  ]) {
    testWidgets('component gallery at ${entry.$1} px', (tester) async {
      await _pumpGallery(tester, entry.$2);
      await expectLater(
        find.byKey(galleryKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/f3_gallery_${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const galleryKey = ValueKey('ComponentGallery');

/// Stands in for the platform font the app itself falls back to for a glyph
/// the brand fonts do not have.
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

/// The running Flutter SDK, found from the environment or from the dart binary
/// that is executing this test.
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

Future<void> _pumpGallery(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        // Only the gallery: lets a peso sign fall back to the system font the
        // app itself uses, because the brand fonts stop at Latin.
        textTheme: AppTheme.lightTheme.textTheme.apply(
          fontFamilyFallback: const [_pesoFallbackFamily],
        ),
      ),
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: galleryKey,
            child: ColoredBox(
              color: AppColors.background,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _Gallery(width: size.width - 48),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.width});

  final double width;

  static const _rows = <_Product>[
    _Product(
      'Portland Cement 40 kg',
      'bag',
      120,
      285.00,
      'In stock',
      StatusTone.success,
    ),
    _Product(
      'Deformed Steel Bar 10 mm',
      'length',
      64,
      9000.00,
      'Low stock',
      StatusTone.warning,
    ),
    _Product(
      'Marine Plywood 3/4 in',
      'sheet',
      18,
      1480.50,
      'In stock',
      StatusTone.success,
    ),
    _Product(
      'Latex Paint White 4 L',
      'can',
      6,
      1234567.89,
      'In stock',
      StatusTone.success,
    ),
    _Product(
      'PVC Pipe 2 in x 3 m',
      'piece',
      0,
      320.00,
      'Out of stock',
      StatusTone.error,
    ),
    _Product(
      'Coco Lumber 2 x 3 x 10 ft',
      'piece',
      42,
      540.00,
      'On order',
      StatusTone.info,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: 'Search products',
          options: const [
            'All',
            'Cement',
            'Steel bars',
            'Plywood',
            'Paint',
            'Plumbing',
          ],
          selected: 'All',
          onSelected: (_) {},
        ),
        const SizedBox(height: 16),
        DataPanel<_Product>(
          columns: [
            DataPanelColumn<_Product>(
              label: 'Product',
              cell: (row) =>
                  Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            DataPanelColumn<_Product>(
              label: 'Unit',
              cell: (row) => Text(row.unit),
            ),
            DataPanelColumn<_Product>(
              label: 'Quantity',
              numeric: true,
              cell: (row) => Text(formatCount(row.qty)),
            ),
            DataPanelColumn<_Product>(
              label: 'Price',
              numeric: true,
              cell: (row) => Text(formatPeso(row.price)),
            ),
            DataPanelColumn<_Product>(
              label: 'Status',
              cell: (row) => StatusBadge(label: row.status, tone: row.tone),
            ),
          ],
          rows: _rows,
          emptyMessage: 'No products match this search.',
        ),
        const SizedBox(height: 16),
        const MetricGrid(
          children: [
            MetricTile(
              label: 'Today sales',
              value: '₱48,290.00',
              caption: '26 transactions',
              trend: '+8.4%',
            ),
            MetricTile(
              label: 'Receivables',
              value: '₱1,234,567.89',
              caption: '3 accounts overdue',
              trend: '-2.1%',
            ),
            MetricTile(
              label: 'Low stock',
              value: '12 items',
              caption: 'Needs a purchase order',
            ),
            MetricTile(label: 'Open shifts', value: '2'),
          ],
        ),
        const SizedBox(height: 16),
        const ErrorBanner(
          message:
              'Sales could not be loaded. Showing the last loaded records.',
          onRetry: _noop,
        ),
        const SizedBox(height: 16),
        const AppPanelBox(
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
            message: 'No products match this search.',
            actionLabel: 'Clear search',
            onAction: _noop,
          ),
        ),
      ],
    );
  }
}

/// A plain white box so the gallery shows the empty state the way a page will:
/// inside an AppPanel.
class AppPanelBox extends StatelessWidget {
  const AppPanelBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

void _noop() {}

class _Product {
  const _Product(
    this.name,
    this.unit,
    this.qty,
    this.price,
    this.status,
    this.tone,
  );

  final String name;
  final String unit;
  final int qty;
  final double price;
  final String status;
  final StatusTone tone;
}
