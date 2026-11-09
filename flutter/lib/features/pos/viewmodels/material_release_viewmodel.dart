import 'package:flutter/foundation.dart';

import '../../../data/models/requisition.dart';
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
      _eligibleLines.any((line) => line.outstanding > 0);

  /// Why the confirm press is not offered, in the clerk's words. Null when it is.
  ///
  /// A pressed button that can only fail is a server error at the counter, so the reason
  /// replaces the button. The two cases are different instructions: an empty shelf means
  /// "come back after a delivery", a finished token means "this paper is done". The
  /// fallback is conservative on purpose: an unanswered line still counts as owed.
  String? get confirmBlockedReason {
    if (verification == null || hasReleasable) return null;
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

  Future<void> verify(String token) async {
    isBusy = true;
    error = null;
    needsOpenShift = false;
    verification = null;
    result = null;
    notifyListeners();
    try {
      verification = await _repository.verifyToken(token);
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
    if (token == null || result != null) return false;
    // Decision 05: nothing releasable writes nothing at all on the server, so the press
    // is refused HERE, where the clerk can still be told why.
    if (!hasReleasable) return false;

    error = null;
    needsOpenShift = false;
    isBusy = true;
    notifyListeners();
    try {
      result = await _repository.release(token);
    } on RequisitionServiceException catch (failure) {
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
    notifyListeners();
  }
}
