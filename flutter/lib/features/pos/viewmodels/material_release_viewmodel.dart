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

  Future<void> verify(String token) async {
    isBusy = true;
    error = null;
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

    error = null;
    isBusy = true;
    notifyListeners();
    try {
      result = await _repository.release(token);
    } on RequisitionServiceException catch (failure) {
      error = failure.message;
      notifyListeners();
      return false;
    } finally {
      isBusy = false;
    }
    notifyListeners();
    return true;
  }
}
