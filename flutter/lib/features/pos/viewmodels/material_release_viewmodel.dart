import 'package:client/core/sync/app_sync_bus.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/requisition.dart';
import '../../../data/models/pos_transaction.dart' show PosReceipt;
import '../../../data/repositories/requisition_repository.dart';
import '../../../data/services/requisition_service.dart';

/// The material release counter — Phase 5's only **irreversible** action (decision 09).
///
/// Releasing a token FIFO-deducts real stock, writes a real `SalesTransaction` and always creates a
/// receivable, because a construction firm pays later. So the guards live here, below the widget:
///
/// * Nothing is released before a token is verified. The server's `release` calls `verify_token`
///   first, but a clerk must not be able to press the button at all without one — otherwise a
///   mis-press surfaces as a server error rather than as an instruction.
/// * A released token cannot be released twice. The second press must send **nothing**; the server
///   would refuse it, and a refusal here would look like a bug at the counter.
class MaterialReleaseViewmodel extends ChangeNotifier {
  MaterialReleaseViewmodel({RequisitionRepository? repository})
    : _repository = repository ?? RequisitionRepository();

  final RequisitionRepository _repository;

  bool isBusy = false;

  /// The server's own wording, which names the reason ("Token has already been used.").
  String? error;

  TokenVerification? verification;
  ReleaseResult? result;

  bool get hasVerified => verification != null;
  bool get isReleased => result != null;

  /// The lines this scan can hand over (decision 05).
  Iterable<VerifiedRequisitionItem> get releasableLines =>
      (verification?.items ?? const <VerifiedRequisitionItem>[]).where(
        (line) => line.isReleasable,
      );

  /// The lines the store agreed to serve.
  ///
  /// Decision 13: a line the store answered Not available is never handed over, so it
  /// is not one of the lines this request promises. An absent/null answer is NOT a
  /// refusal — the line may still be collected — so it stays in.
  Iterable<VerifiedRequisitionItem> get _eligibleLines =>
      (verification?.items ?? const <VerifiedRequisitionItem>[]).where(
        (line) => line.available != false,
      );

  /// True when anything can leave the store on this scan.
  bool get hasReleasable => releasableLines.isNotEmpty;

  int get releasableLineCount => releasableLines.length;

  /// The lines this scan is about: refused lines are not promised, so they are not
  /// counted (decision 13).
  int get totalLineCount => _eligibleLines.length;

  /// True when the release will leave lines open on this token.
  ///
  /// Read per line rather than from the request's status, because a SHORT line keeps its
  /// remainder: the token stays valid and the project comes back for it. A Not available
  /// line is not one of them: nobody will ever hand it over (decision 13).
  bool get leavesLinesOpen =>
      _eligibleLines.any((line) => outstandingAfter(line) > 0);

  /// The cashier's Give now per line id (2026-11-27 design). Starts at each line's
  /// releasable on every verify; a line that cannot go out has none.
  Map<int, double> _giveNow = const {};

  /// What this line hands over on the next release. 0 for a line that cannot go.
  double giveNow(int itemId) => _giveNow[itemId] ?? 0;

  VerifiedRequisitionItem? _line(int itemId) {
    for (final line in releasableLines) {
      if (line.id == itemId) return line;
    }
    return null;
  }

  /// Sets a line's Give now, clamped to `0 … releasable`. A whole unit (a bag) is
  /// floored to a whole number; a measured one keeps at most 2 decimals, the server's
  /// own limit, so what the screen shows is exactly what is sent.
  void setGiveNow(int itemId, double amount) {
    final line = _line(itemId);
    if (line == null || isBusy || result != null) return;
    var value = amount.isNaN ? 0.0 : amount;
    if (value < 0) value = 0;
    if (value > line.releasable) value = line.releasable;
    value = line.isWhole
        ? (value + 1e-9).floorToDouble()
        : ((value * 100) + 1e-6).floorToDouble() / 100;
    _giveNow = {..._giveNow, itemId: value};
    notifyListeners();
  }

  /// True when the cashier moved this line away from what can go out.
  bool giveNowChanged(int itemId) {
    final line = _line(itemId);
    return line != null && (giveNow(itemId) - line.releasable).abs() > 1e-9;
  }

  /// What stays owed on this line after the release, with the chosen amount.
  double outstandingAfter(VerifiedRequisitionItem line) {
    if (line.available == false) return 0;
    final left = line.remaining - giveNow(line.id);
    return left > 0 ? left : 0;
  }

  /// The lines that hand something over with the current amounts.
  Iterable<VerifiedRequisitionItem> get givingLines =>
      releasableLines.where((line) => giveNow(line.id) > 0);

  /// Price × Give now, summed: the screen's estimate. The receipt shows the server's.
  double get todayTotal => releasableLines.fold(
    0.0,
    (sum, line) => sum + line.unitPrice * giveNow(line.id),
  );

  /// What this release hands over, line by line, for the summary.
  List<({String name, double qty, String unit})> get givingToday => [
    for (final line in givingLines)
      (name: line.variantName, qty: giveNow(line.id), unit: line.unit),
  ];

  /// What a later visit still has to collect, after this release.
  List<({String name, double qty, String unit})> get stillOpenAfter => [
    for (final line in _eligibleLines)
      if (outstandingAfter(line) > 0)
        (name: line.variantName, qty: outstandingAfter(line), unit: line.unit),
  ];

  /// Why the confirm press is not offered, in the clerk's words. Null when it is.
  ///
  /// A pressed button that can only fail is a server error at the counter, so the reason
  /// replaces the button. The two cases are different instructions: an empty shelf means
  /// "come back after a delivery", a finished token means "this paper is done". The
  /// fallback is conservative on purpose: an unanswered line still counts as owed.
  String? get confirmBlockedReason {
    if (verification == null) return null;
    if (hasReleasable) {
      return givingLines.isEmpty ? 'Set at least one Give now above 0.' : null;
    }
    final eligible = _eligibleLines;
    if (eligible.isNotEmpty &&
        eligible.every((line) => line.availability == LineAvailability.done)) {
      return 'Everything on this request was already released.';
    }
    return 'Nothing on this request is in stock right now. The token stays valid.';
  }

  /// Lines a later scan still has to hand over, from the server's own release answer.
  int get openLineCount => result?.openLineCount ?? 0;

  /// True when the last RELEASE was refused with `NO_OPEN_SHIFT`.
  ///
  /// Decision 03 (Phase 3): a release is recorded against the cashier's open
  /// shift, so `release_materials` refuses without one. That is a RULE with a
  /// next step the screen can offer — the Shifts tab — where every other
  /// refusal (a spent token, a bad code) is not.
  ///
  /// Driven by the CODE, never by the prose: a connection error whose text
  /// happened to mention a shift must not put a pointless detour on screen.
  bool needsOpenShift = false;

  Future<List<Requisition>> fetchReleaseQueue() =>
      _repository.fetchReleaseQueue();

  /// Accepted requests waiting at the counter, shown on the page itself so the
  /// cashier picks one instead of hunting for a token slip.
  List<Requisition> queue = const [];

  /// Why the queue could not be read; the last rows stay on screen.
  String? queueError;

  /// True until the first queue read answers.
  bool queueLoading = true;

  bool _queueReadInFlight = false;

  /// Reads the queue. Overlapping reads are dropped, so a timer tick and a
  /// manual refresh never race each other.
  Future<void> loadQueue() async {
    if (_queueReadInFlight) return;
    _queueReadInFlight = true;
    try {
      queue = await _repository.fetchReleaseQueue();
      queueError = null;
    } on RequisitionServiceException catch (failure) {
      queueError = failure.message;
    } catch (_) {
      queueError = 'The accepted requests could not be loaded.';
    } finally {
      _queueReadInFlight = false;
      queueLoading = false;
      notifyListeners();
    }
  }

  Future<PosReceipt> fetchReceipt() =>
      _repository.fetchReleaseReceipt(result!.transactionId);

  Future<void> verify(String token) =>
      _verify(() => _repository.verifyToken(token));

  Future<void> verifyRequest(int id) =>
      _verify(() => _repository.verifyRequest(id));

  Future<void> _verify(Future<TokenVerification> Function() lookup) async {
    if (isBusy) return;
    isBusy = true;
    error = null;
    needsOpenShift = false;
    verification = null;
    result = null;
    notifyListeners();
    try {
      verification = await lookup();
      _giveNow = {
        for (final line in releasableLines) line.id: line.releasable,
      };
    } on RequisitionServiceException catch (failure) {
      error = failure.message;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// Returns true only if the server accepted the release.
  Future<bool> release() async {
    final token = verification?.token;
    if (isBusy || token == null || result != null) return false;
    // Decision 05: nothing releasable writes nothing at all on the server, so the press
    // is refused HERE, where the clerk can still be told why.
    if (!hasReleasable || givingLines.isEmpty) return false;

    error = null;
    needsOpenShift = false;
    isBusy = true;
    notifyListeners();
    try {
      result = await _repository.release(
        token,
        quantities: {
          for (final line in releasableLines) line.id: giveNow(line.id),
        },
      );
    } on RequisitionServiceException catch (failure) {
      if (failure.code == 'RELEASE_QTY_TOO_HIGH') {
        // Stock moved since the screen loaded: reload the request so the limits are
        // the shelf's current ones, then say why the press did nothing.
        final requisitionId = verification?.requisitionId;
        isBusy = false;
        if (requisitionId != null) await verifyRequest(requisitionId);
        error =
            'Stock changed since this request was opened. The amounts were '
            'updated — check them and release again.';
        notifyListeners();
        return false;
      }
      error = failure.message;
      // Only this refusal has an action attached; every other one is read and
      // reported, so a Retry of the same press is the honest next step.
      needsOpenShift = failure.code == 'NO_OPEN_SHIFT';
      notifyListeners();
      return false;
    } finally {
      isBusy = false;
    }
    notifyListeners();
    // A fully released request leaves the queue; a partial one stays.
    loadQueue();
    AppSyncBus.instance.notifyMarkersChanged();
    return true;
  }

  /// Clears everything the last token put on screen, for the next customer.
  ///
  /// The guards above are what make a release safe; this is only the screen's
  /// "next token" reset, so it never runs mid-request.
  void reset() {
    if (isBusy) return;
    error = null;
    needsOpenShift = false;
    verification = null;
    result = null;
    _giveNow = const {};
    notifyListeners();
  }
}
