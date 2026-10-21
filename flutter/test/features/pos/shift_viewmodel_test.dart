import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shift behind the POS shell (Phase 4).
///
/// The rules that matter are the ones a widget cannot see: "no open shift" and
/// "could not ask" are DIFFERENT answers, and the till gate hangs off the
/// difference. If a failed request read as "no shift", a cashier who already has
/// one open would be shown the open-a-shift prompt and would either be refused
/// by the server or, worse, think their sales were not being recorded.
class _StubShifts extends ShiftService {
  int currentCalls = 0;
  int listCalls = 0;
  double? openedWith;
  int? closedId;
  double? closedWith;
  Object? failCurrent;
  Object? failOpen;
  Object? failClose;
  Object? failList;
  Shift? current;
  Shift? opened;
  Shift? closed;
  List<Shift> history = const [];

  @override
  Future<Shift?> fetchCurrent() async {
    currentCalls++;
    if (failCurrent != null) throw failCurrent!;
    return current;
  }

  @override
  Future<Shift> openShift(double openingFloat) async {
    openedWith = openingFloat;
    if (failOpen != null) throw failOpen!;
    return opened!;
  }

  @override
  Future<Shift> closeShift(int shiftId, double closingCount) async {
    closedId = shiftId;
    closedWith = closingCount;
    if (failClose != null) throw failClose!;
    return closed!;
  }

  @override
  Future<List<Shift>> fetchAll() async {
    listCalls++;
    if (failList != null) throw failList!;
    return history;
  }
}

Shift _shift({
  int id = 1,
  String status = Shift.openStatus,
  double openingFloat = 5000,
  double? closingCount,
  ZReading? zReading,
}) {
  return Shift(
    id: id,
    cashierName: 'Ana Cruz',
    status: status,
    openingFloat: openingFloat,
    closingCount: closingCount,
    openedAt: DateTime(2026, 10, 21, 8),
    closedAt: status == Shift.closedStatus ? DateTime(2026, 10, 21, 17) : null,
    notes: '',
    zReading: zReading,
  );
}

const _z = ZReading(
  transactionCount: 12,
  grossSales: 8400,
  cashSales: 4400,
  cardSales: 2500,
  gcashSales: 1500,
  expectedDrawer: 9400,
  variance: -50,
);

void main() {
  group('ShiftViewmodel.loadCurrent', () {
    test('an open shift from the server sets the current shift', () async {
      final service = _StubShifts()..current = _shift();
      final vm = ShiftViewmodel(service: service);

      await vm.loadCurrent();

      expect(vm.currentShift?.id, 1);
      expect(vm.hasOpenShift, isTrue);
      expect(vm.loadError, isNull);
      expect(vm.isLoading, isFalse);
    });

    test('no open shift is not an error and does not open the gate', () async {
      final service = _StubShifts();
      final vm = ShiftViewmodel(service: service);

      await vm.loadCurrent();

      expect(vm.currentShift, isNull);
      expect(vm.hasOpenShift, isFalse);
      expect(
        vm.loadError,
        isNull,
        reason: 'a 404 means "no shift", which is the normal start of a day',
      );
    });

    test('a failed load is an error, NOT an empty answer', () async {
      final service = _StubShifts()
        ..failCurrent = const ShiftServiceException('Cannot connect.');
      final vm = ShiftViewmodel(service: service);

      await vm.loadCurrent();

      expect(vm.loadError, 'Cannot connect.');
      expect(
        vm.hasOpenShift,
        isFalse,
        reason:
            'the gate must show the failure and offer a retry, not silently '
            'claim the cashier has no shift',
      );
    });
  });

  group('ShiftViewmodel.openShift', () {
    test('opens with the counted float and becomes the current shift', () async {
      final service = _StubShifts()..opened = _shift(openingFloat: 5000);
      final vm = ShiftViewmodel(service: service);

      final opened = await vm.openShift(5000);

      expect(service.openedWith, 5000);
      expect(opened?.id, 1);
      expect(vm.currentShift?.id, 1);
      expect(vm.hasOpenShift, isTrue);
      expect(vm.actionError, isNull);
    });

    test('a refused open leaves the cashier with no shift and a message', () async {
      final service = _StubShifts()
        ..failOpen = const ShiftServiceException(
          'You already have an open shift. Close it first.',
        );
      final vm = ShiftViewmodel(service: service);

      final opened = await vm.openShift(5000);

      expect(opened, isNull);
      expect(vm.currentShift, isNull);
      expect(vm.hasOpenShift, isFalse);
      expect(
        vm.actionError,
        'You already have an open shift. Close it first.',
        reason: 'the server detail is what tells the cashier what to do next',
      );
    });
  });

  group('ShiftViewmodel.closeShift', () {
    test('closes the current shift and returns the Z-reading', () async {
      final service = _StubShifts()
        ..current = _shift()
        ..closed = _shift(
          status: Shift.closedStatus,
          closingCount: 9350,
          zReading: _z,
        );
      final vm = ShiftViewmodel(service: service);
      await vm.loadCurrent();

      final closed = await vm.closeShift(9350);

      expect(service.closedId, 1, reason: 'the id comes from the open shift');
      expect(service.closedWith, 9350);
      expect(closed?.zReading?.variance, -50);
      expect(closed?.zReading?.transactionCount, 12);
      expect(
        vm.currentShift,
        isNull,
        reason: 'a closed shift is nobody\'s open shift; the till must gate',
      );
      expect(vm.hasOpenShift, isFalse);
      expect(vm.actionError, isNull);
    });

    test('a failed close keeps the shift open on screen', () async {
      final service = _StubShifts()
        ..current = _shift()
        ..failClose = const ShiftServiceException('Cannot connect.');
      final vm = ShiftViewmodel(service: service);
      await vm.loadCurrent();

      final closed = await vm.closeShift(9350);

      expect(closed, isNull);
      expect(
        vm.currentShift?.id,
        1,
        reason:
            'clearing it would tell the cashier their shift ended while the '
            'server still has it open, and the next sale would post into it',
      );
      expect(vm.actionError, 'Cannot connect.');
    });

    test('close with no current shift does nothing', () async {
      final service = _StubShifts()..closed = _shift();
      final vm = ShiftViewmodel(service: service);

      final closed = await vm.closeShift(100);

      expect(closed, isNull);
      expect(service.closedId, isNull);
    });
  });

  group('ShiftViewmodel history', () {
    test('loads the shift list for the management page', () async {
      final service = _StubShifts()
        ..history = [
          _shift(id: 2, status: Shift.closedStatus, closingCount: 9350, zReading: _z),
          _shift(),
        ];
      final vm = ShiftViewmodel(service: service);

      await vm.loadHistory();

      expect(vm.history.length, 2);
      expect(vm.history.first.zReading?.expectedDrawer, 9400);
      expect(vm.loadError, isNull);
    });

    test('a failed history load is reported, not shown as an empty table', () async {
      final service = _StubShifts()
        ..failList = const ShiftServiceException('Cannot connect.');
      final vm = ShiftViewmodel(service: service);

      await vm.loadHistory();

      expect(vm.loadError, 'Cannot connect.');
    });
  });
}
