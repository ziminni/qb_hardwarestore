// Phase 9 F3 (decision 21 §3): the transfers screen's data.
//
// Pinned here:
//   * the slip list and the shelf list are read on load, and only ACTIVE shelves
//     are offered as a transfer's ends;
//   * a failed slip read and a failed shelf read are two different facts;
//   * recording posts ONCE — a second click while the first is on the wire is
//     refused by the viewmodel, not by the server;
//   * a refusal is the server's own sentence and leaves the list untouched;
//   * a recorded slip goes to the top of the list the reader sees.

import 'dart:async';

import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/repositories/stock_transfer_repository.dart';
import 'package:client/data/services/stock_transfer_service.dart';
import 'package:client/features/transfers/viewmodels/transfers_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

StockTransfer transfer({
  int id = 1,
  String number = 'TR-20261113-0001',
  String from = 'Store',
  String to = 'Bodega',
  String remarks = '',
  List<StockTransferLine>? lines,
}) => StockTransfer(
  id: id,
  number: number,
  fromLocationId: 1,
  fromLocationName: from,
  toLocationId: 2,
  toLocationName: to,
  userId: 7,
  userName: 'Ana Lopez',
  remarks: remarks,
  createdAt: DateTime(2026, 11, 13, 9, 15),
  lines:
      lines ??
      const [
        StockTransferLine(
          id: 11,
          variantUomId: 4,
          variantId: 8,
          variantName: '20A 1-pole',
          productName: 'Circuit Breaker',
          unit: 'BAG',
          qty: 2,
          baseQty: 24,
          moves: [],
        ),
      ],
);

class _FakeStockTransferRepository extends StockTransferRepository {
  _FakeStockTransferRepository({List<StockTransfer> transfers = const []})
    : _transfers = [...transfers];

  List<StockTransfer> _transfers;

  final List<StockTransferRequest> posted = [];

  /// Set to refuse the READ like the API would (a 403/500 message).
  String? readError;

  /// Set to refuse the WRITE like the API would — the server's own sentence.
  String? writeError;

  /// Held to keep the write on the wire, so a second click can be attempted.
  Completer<void>? gate;

  @override
  Future<List<StockTransfer>> fetchAll() async {
    final error = readError;
    if (error != null) throw StockTransferServiceException(error);
    return [..._transfers];
  }

  @override
  Future<StockTransfer> create(StockTransferRequest request) async {
    final held = gate;
    if (held != null) await held.future;
    posted.add(request);
    final error = writeError;
    if (error != null) throw StockTransferServiceException(error);
    final recorded = transfer(
      id: 100 + posted.length,
      number: 'TR-20261113-000${posted.length}',
      remarks: request.remarks,
    );
    _transfers = [recorded, ..._transfers];
    return recorded;
  }
}

TransfersViewmodel _state({
  FakeStorageLocationRepository? shelves,
  _FakeStockTransferRepository? transfers,
}) => TransfersViewmodel(
  repository: transfers ?? _FakeStockTransferRepository(),
  locations:
      shelves ??
      FakeStorageLocationRepository(
        locations: const [
          StorageLocation(id: 1, name: 'Store'),
          StorageLocation(id: 2, name: 'Bodega'),
          StorageLocation(id: 3, name: 'Yard', isActive: false),
        ],
      ),
);

void main() {
  test('load reads the slips and the shelves', () async {
    final state = _state(
      transfers: _FakeStockTransferRepository(
        transfers: [transfer(id: 1), transfer(id: 2, number: 'TR-20261113-0002')],
      ),
    );

    await state.load();

    expect(state.isLoading, isFalse);
    expect(state.loadError, isNull);
    expect(state.transfers.map((row) => row.number), [
      'TR-20261113-0001',
      'TR-20261113-0002',
    ]);
    expect(state.locations, hasLength(3), reason: 'the Admin sees them all');
    expect(state.activeLocations.map((row) => row.name), ['Store', 'Bodega']);
    expect(
      state.locationError,
      isNull,
      reason: 'a shelf read that answered is not an error',
    );
  });

  test('a failed slip read says so and keeps the shelves usable', () async {
    final transfers = _FakeStockTransferRepository()..readError = 'Forbidden.';
    final state = _state(transfers: transfers);

    await state.load();

    expect(state.loadError, 'Forbidden.');
    expect(state.isLoading, isFalse);
    expect(state.activeLocations, hasLength(2));
  });

  test('a failed SHELF read is its own fact, not a missing slip list', () async {
    final shelves = FakeStorageLocationRepository()
      ..readError = 'The storage locations could not be read.';
    final state = _state(
      shelves: shelves,
      transfers: _FakeStockTransferRepository(transfers: [transfer()]),
    );

    await state.load();

    expect(state.transfers, hasLength(1));
    expect(state.loadError, isNull);
    expect(
      state.locationError,
      'The storage locations could not be read.',
      reason:
          'a screen that cannot name the shelves must not offer an empty picker',
    );
    expect(state.activeLocations, isEmpty);
  });

  test('record posts once and puts the numbered slip on top', () async {
    final transfers = _FakeStockTransferRepository(transfers: [transfer()]);
    final state = _state(transfers: transfers);
    await state.load();

    final outcome = await state.record(
      const StockTransferRequest(
        fromLocationId: 1,
        toLocationId: 2,
        remarks: 'Shelf refill',
        lines: [(variantUomId: 4, qty: 2)],
      ),
    );

    expect(outcome.recorded?.number, 'TR-20261113-0001');
    expect(outcome.refusal, isNull);
    expect(transfers.posted, hasLength(1));
    expect(transfers.posted.single.lines.single.variantUomId, 4);
    expect(state.transfers.first.number, 'TR-20261113-0001');
    expect(
      state.transfers,
      hasLength(2),
      reason: 'the new slip joins the ones already read',
    );
    expect(state.actionError, isNull);
    expect(state.isRecording, isFalse);
  });

  test('a second click while the first is on the wire posts nothing', () async {
    final transfers = _FakeStockTransferRepository()..gate = Completer<void>();
    final state = _state(transfers: transfers);
    await state.load();

    final first = state.record(
      const StockTransferRequest(
        fromLocationId: 1,
        toLocationId: 2,
        lines: [(variantUomId: 4, qty: 2)],
      ),
    );
    final second = await state.record(
      const StockTransferRequest(
        fromLocationId: 1,
        toLocationId: 2,
        lines: [(variantUomId: 4, qty: 3)],
      ),
    );

    expect(state.isRecording, isTrue);
    expect(second.recorded, isNull);
    expect(second.refusal, contains('Still recording'));

    transfers.gate!.complete();
    await first;

    expect(
      transfers.posted,
      hasLength(1),
      reason: 'one click, one transfer — a second would move the stock twice',
    );
    expect(state.isRecording, isFalse);
  });

  test('a refusal is the server sentence and changes nothing', () async {
    final transfers = _FakeStockTransferRepository(transfers: [transfer()])
      ..writeError =
          'Not enough Portland cement at Store: 3.00 BAG short of the 5 BAG '
          'this line moves.';
    final state = _state(transfers: transfers);
    await state.load();

    final outcome = await state.record(
      const StockTransferRequest(
        fromLocationId: 1,
        toLocationId: 2,
        lines: [(variantUomId: 4, qty: 5)],
      ),
    );

    expect(outcome.recorded, isNull);
    expect(outcome.refusal, contains('3.00 BAG short'));
    expect(state.actionError, contains('3.00 BAG short'));
    expect(state.transfers, hasLength(1), reason: 'a refusal writes nothing');
    expect(state.isRecording, isFalse);
  });

  test('clearActionError drops the banner', () async {
    final transfers = _FakeStockTransferRepository()..writeError = 'Refused.';
    final state = _state(transfers: transfers);
    await state.load();
    await state.record(
      const StockTransferRequest(
        fromLocationId: 1,
        toLocationId: 2,
        lines: [(variantUomId: 4, qty: 1)],
      ),
    );

    state.clearActionError();

    expect(state.actionError, isNull);
  });
}
