import 'package:client/core/format/format.dart';
import 'package:client/data/models/bodega.dart';

/// What the checker says about one arrived item (owner 2026-11-18).
enum ItemCondition {
  complete('Complete'),
  damaged('Damaged'),
  missing('Missing');

  const ItemCondition(this.label);
  final String label;
}

/// The checker's answer for one delivery line, before it is sent.
///
/// The quantity is optional: left empty, Damaged and Missing mean the WHOLE
/// line; typed, they mean that many of it, and the rest arrived good.
class ItemReport {
  ItemReport(this.line);

  final BodegaDeliveryLine line;
  ItemCondition condition = ItemCondition.complete;
  String qtyText = '';
  String remarks = '';

  /// The photo taken on this phone and not yet uploaded, if any.
  List<int>? photoBytes;

  /// A photo already on the server (taken earlier, then the screen reopened).
  bool get hasPhoto => photoBytes != null || line.photoUrl.isNotEmpty;

  /// `(good, damaged)` for the server, or the sentence saying what is wrong.
  ({double good, double damaged})? verdict(void Function(String) onError) {
    final delivered = line.deliveredQty;
    if (condition == ItemCondition.complete) {
      return (good: delivered, damaged: 0);
    }
    final text = qtyText.trim().replaceAll(',', '');
    double affected = delivered;
    if (text.isNotEmpty) {
      final parsed = double.tryParse(text);
      if (parsed == null || parsed <= 0) {
        onError('${line.label}: "$qtyText" is not a quantity.');
        return null;
      }
      if (parsed > delivered + 1e-9) {
        onError(
          '${line.label}: only ${formatQuantity(delivered)} ${line.unit} '
          'arrived.',
        );
        return null;
      }
      if (line.isWhole && parsed != parsed.roundToDouble()) {
        onError('${line.label} is counted in whole ${line.unit}.');
        return null;
      }
      affected = parsed;
    }
    return switch (condition) {
      ItemCondition.damaged => (good: delivered - affected, damaged: affected),
      // Missing pieces are neither good nor damaged: the server writes off
      // what is left (delivered - good - damaged) as never arrived.
      _ => (good: delivered - affected, damaged: 0),
    };
  }
}

/// The whole delivery's report: every line answered and photographed.
class ArrivalReport {
  ArrivalReport(BodegaDelivery delivery)
    : deliveryId = delivery.id,
      items = [for (final line in delivery.lines) ItemReport(line)];

  final int deliveryId;
  final List<ItemReport> items;

  /// Lines still without a photo, in order.
  List<ItemReport> get missingPhotos => [
    for (final item in items)
      if (!item.hasPhoto) item,
  ];

  /// The confirmation to send, or null with [onError] told why.
  BodegaDeliveryConfirmation? confirmation(void Function(String) onError) {
    final unphotographed = missingPhotos;
    if (unphotographed.isNotEmpty) {
      onError('Take a photo of ${unphotographed.first.line.label}.');
      return null;
    }
    final lines =
        <({int lineId, double good, double damaged, String remarks})>[];
    for (final item in items) {
      final verdict = item.verdict(onError);
      if (verdict == null) return null;
      lines.add((
        lineId: item.line.id,
        good: verdict.good,
        damaged: verdict.damaged,
        remarks: item.remarks.trim(),
      ));
    }
    return BodegaDeliveryConfirmation(lines: lines);
  }
}
