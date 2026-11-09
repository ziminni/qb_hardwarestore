import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:flutter/foundation.dart';

/// What one review attempt did, from the dialog's point of view.
enum ReviewOutcome {
  /// The server stored the decision.
  saved,

  /// Nothing was stored and the request can still be answered.
  refused,

  /// The write may have landed and the state could not be reloaded.
  blocked,
}

/// The result of one Accept or Decline attempt.
class ReviewResult {
  const ReviewResult(this.outcome, {this.message});

  final ReviewOutcome outcome;

  /// Copy for the reviewer, when there is anything to say.
  final String? message;
}

/// Owns the "Requests from projects" queue: one selected status, the rows the
/// server sent for it, the sidebar's waiting count, and every review attempt in
/// flight (Phase 1b, decisions 09, 10 and 13).
///
/// Screen-scoped and provided by its own page rather than registered globally,
/// matching the receivables and POS screens: a viewmodel that lives as long as
/// one screen should not outlive it.
///
/// Nothing here edits a quantity, a price or a status by hand. Accept and
/// Decline are WRITES whose answer is the server's, so:
///  * a landed decision is shown from the returned row, then refreshed,
///  * a saved decision whose refresh failed says so instead of reading as a
///    failed decision somebody would repeat,
///  * a write with an unknown outcome (timeout) or a stale one (409) reloads the
///    authoritative detail BEFORE offering the buttons again, and stays blocked
///    with an explicit retry when that reload also fails.
class ProjectRequestsViewmodel extends ChangeNotifier {
  ProjectRequestsViewmodel({
    RequisitionRepository? repository,
    RequisitionStatus initialStatus = RequisitionStatus.waiting,
  }) : _repository = repository ?? RequisitionRepository(),
       _status = initialStatus;

  /// What the dialog says when the decision landed but the list did not reload.
  static const String savedButStaleCopy =
      'The decision was saved, but the list could not be refreshed. '
      'Check the queue before answering again.';

  /// What the dialog says when neither the write nor the reload answered.
  static const String blockedCopy =
      'The decision may or may not have been saved. Retry refresh before '
      'trying again.';

  static const String _busyCopy = 'This request is still being saved.';

  final RequisitionRepository _repository;

  RequisitionStatus _status;
  RequisitionStatus get status => _status;

  List<Requisition> _requests = const [];
  List<Requisition> get requests => List.unmodifiable(_requests);

  bool _isLoading = false;

  /// True while a list read runs. The first build is inside one, so the queue
  /// shows its spinner rather than an empty-state claim.
  bool get isLoading => _isLoading;

  String? _loadError;

  /// Why the last list read failed. The rows it already had are kept.
  String? get loadError => _loadError;

  int? _waitingCount;

  /// How many requests are waiting for the store, or null when no read has
  /// confirmed one. Null is drawn as NO badge: a failed read is not a zero.
  int? get waitingCount => _waitingCount;

  /// The last authoritative state of a request the reviewer has open.
  final Map<int, Requisition> _details = {};

  Requisition? detailFor(int id) => _details[id];

  final Set<int> _submitting = {};
  final Set<int> _blocked = {};
  final Map<int, String> _reviewMessages = {};

  /// The number of the newest list read. A read that resolves after a newer
  /// one has started is dropped: it can only describe a status, a count or an
  /// error the screen has already left behind, and it could put a row that was
  /// answered a moment ago back to WAITING.
  int _listGeneration = 0;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Notifies, unless the screen that owns this viewmodel is already gone.
  ///
  /// Every read and every decision finishes asynchronously, and the reviewer
  /// can close the screen in between.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool isSubmitting(int id) => _submitting.contains(id);

  /// True when the decision may have landed and the detail could not be
  /// reloaded: both actions stay off until [retryRefresh] succeeds.
  bool isBlocked(int id) => _blocked.contains(id);

  String? reviewMessage(int id) => _reviewMessages[id];

  /// Reads the selected status, then the sidebar's waiting count.
  ///
  /// The count is a SEPARATE read on purpose: a failed badge read must not fail
  /// the queue behind it, and it must not be answered with a made-up zero.
  Future<void> load() async {
    await _readList(spinner: true);
  }

  /// Switches the status filter and loads that status oldest-first.
  Future<void> selectStatus(RequisitionStatus status) async {
    if (status == _status) return;
    _status = status;
    _notify();
    await load();
  }

  /// Answers every line (decision 10) and returns what happened.
  Future<ReviewResult> accept(
    int id,
    List<RequisitionLineDecision> decisions,
  ) => _review(id, () => _repository.accept(id, decisions));

  /// Declines the WHOLE request (decision 09).
  Future<ReviewResult> decline(int id, String reason) =>
      _review(id, () => _repository.decline(id, reason));

  /// Tries the authoritative detail read again for a blocked request.
  Future<bool> retryRefresh(int id) async {
    if (!_blocked.contains(id)) return true;
    final detail = await _reloadDetail(id);
    if (detail == null) {
      _notify();
      return false;
    }
    _blocked.remove(id);
    _reviewMessages[id] = 'Showing the request as the server holds it.';
    _notify();
    return true;
  }

  Future<ReviewResult> _review(
    int id,
    Future<Requisition> Function() write,
  ) async {
    if (_submitting.contains(id) || _blocked.contains(id)) {
      return const ReviewResult(ReviewOutcome.refused, message: _busyCopy);
    }
    _submitting.add(id);
    _reviewMessages.remove(id);
    _notify();

    try {
      final updated = await write();
      _details[id] = updated;
      _replaceRow(updated);
      _notify();

      final refreshed = await _readList();
      if (!refreshed) {
        _reviewMessages[id] = savedButStaleCopy;
        return const ReviewResult(
          ReviewOutcome.saved,
          message: savedButStaleCopy,
        );
      }
      _reviewMessages.remove(id);
      return const ReviewResult(ReviewOutcome.saved);
    } on RequisitionServiceException catch (error) {
      // A 400 is an ANSWER: nothing was stored, and the reviewer can fix the
      // form. Timeouts and the stale-decision 409 are the opposite: only the
      // server knows the current state.
      if (!error.outcomeUnknown && error.code != 'REQUEST_ALREADY_REVIEWED') {
        _reviewMessages[id] = error.message;
        return ReviewResult(ReviewOutcome.refused, message: error.message);
      }

      // The list first, then the DETAIL: the detail is the newest read, so a
      // list page built a moment earlier cannot put a just-answered row back to
      // WAITING and invite a second decision.
      await _readList();
      final detail = await _reloadDetail(id);
      if (detail == null) {
        _blocked.add(id);
        _reviewMessages[id] = blockedCopy;
        return const ReviewResult(ReviewOutcome.blocked, message: blockedCopy);
      }
      _reviewMessages[id] = error.message;
      return ReviewResult(ReviewOutcome.refused, message: error.message);
    } catch (_) {
      _reviewMessages[id] = 'The decision could not be sent. Try again.';
      return const ReviewResult(
        ReviewOutcome.refused,
        message: 'The decision could not be sent. Try again.',
      );
    } finally {
      _submitting.remove(id);
      _notify();
    }
  }

  /// Replaces one row in the loaded list, keeping its position.
  void _replaceRow(Requisition updated) {
    final index = _requests.indexWhere((row) => row.id == updated.id);
    if (index < 0) return;
    final rows = [..._requests];
    rows[index] = updated;
    _requests = rows;
  }

  /// Reloads the selected status and the count.
  ///
  /// Only the NEWEST read may write what it got back. An older read that
  /// resolves late is dropped, so a slow WAITING page cannot repaint the screen
  /// the reviewer has already filtered away from. Returns false only when this
  /// read failed and it was still the newest: a superseded read is not a
  /// failure to report, because the read that replaced it reports for itself.
  Future<bool> _readList({bool spinner = false}) async {
    final generation = ++_listGeneration;
    final status = _status;
    if (spinner) {
      _isLoading = true;
      _loadError = null;
      _notify();
    }

    var ok = true;
    try {
      final rows = await _repository.fetchRequisitions(status: status.apiValue);
      if (generation != _listGeneration) return true;
      _requests = rows;
      for (final row in rows) {
        _details[row.id] = row;
      }
      _loadError = null;
    } on RequisitionServiceException catch (error) {
      if (generation != _listGeneration) return true;
      ok = false;
      if (spinner) _loadError = error.message;
    } catch (_) {
      if (generation != _listGeneration) return true;
      ok = false;
      if (spinner) _loadError = 'The requests could not be loaded.';
    }

    await _readWaitingCount(generation);

    // Only the NEWEST read may end the spinner: an older read finishing while a
    // newer one is still in flight would otherwise switch it off early, and the
    // newer read's own rows or error would then land without a repaint.
    if (generation == _listGeneration && _isLoading) {
      _isLoading = false;
      _notify();
    }
    return ok;
  }

  Future<void> _readWaitingCount(int generation) async {
    try {
      final count = await _repository.waitingCount();
      if (generation == _listGeneration) _waitingCount = count;
    } catch (_) {
      // No badge beats a false 0: this leaves the last confirmed count alone.
    }
  }

  Future<Requisition?> _reloadDetail(int id) async {
    try {
      final detail = await _repository.fetchRequisition(id);
      _details[id] = detail;
      _replaceRow(detail);
      return detail;
    } catch (_) {
      return null;
    }
  }
}
