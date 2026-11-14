import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One request, and — while it is WAITING — the store's answer to it.
///
/// Answering happens HERE rather than on the list because it needs the lines:
/// each one is Available or Not available, and a Not-available line carries the
/// reason the project will read (decisions 09 and 10). Nothing on this screen
/// touches stock, money or the CPMS token: accepting reserves nothing and books
/// nothing.
class ProjectRequestReviewDialog extends StatefulWidget {
  const ProjectRequestReviewDialog({
    super.key,
    required this.viewmodel,
    required this.requisition,
  });

  static const String acceptCopy =
      'Accepting does not reserve stock. Amount owed is recorded when '
      'materials are released.';

  /// Decision 14: an unknown expected amount is never shown as ₱0.00.
  static const String unavailableAmountCopy = 'Expected amount unavailable';
  static const String notOwedCopy = 'Expected amount, not yet owed';

  /// A closed request's open quantities are abandoned, and the debt lives on the
  /// ledger. Saying so here stops "Closed" from reading as "settled".
  static const String closedCopy =
      'Anything not released stays closed. The actual balance is on '
      'Receivables.';

  final ProjectRequestsViewmodel viewmodel;
  final Requisition requisition;

  @override
  State<ProjectRequestReviewDialog> createState() =>
      _ProjectRequestReviewDialogState();
}

class _ProjectRequestReviewDialogState
    extends State<ProjectRequestReviewDialog> {
  /// Each line's answer: true Available, false Not available, null unanswered.
  final Map<int, bool?> _answers = {};

  /// Why the store will not serve a line, as typed.
  final Map<int, TextEditingController> _reasons = {};

  final TextEditingController _declineReason = TextEditingController();

  String? _error;

  @override
  void initState() {
    super.initState();
    for (final line in widget.requisition.items) {
      _answers[line.id] = line.available;
      _reasons[line.id] = TextEditingController(text: line.declineReason);
    }
  }

  @override
  void dispose() {
    for (final controller in _reasons.values) {
      controller.dispose();
    }
    _declineReason.dispose();
    super.dispose();
  }

  Requisition get _request =>
      widget.viewmodel.detailFor(widget.requisition.id) ?? widget.requisition;

  void _answer(int lineId, bool available) {
    setState(() {
      _answers[lineId] = available;
      _error = null;
    });
  }

  Future<void> _accept() async {
    final request = _request;
    final items = request.items;

    if (items.any((line) => _answers[line.id] == null)) {
      setState(() => _error = 'Answer every line before accepting.');
      return;
    }
    final excluded = [
      for (final line in items)
        if (_answers[line.id] == false) line,
    ];
    if (excluded.length == items.length) {
      setState(() {
        _error =
            'At least one line must be available. Decline the whole request '
            'instead.';
      });
      return;
    }
    if (excluded.any((line) => _reasonFor(line.id).isEmpty)) {
      setState(() {
        _error = 'Give a reason for each line the store will not serve.';
      });
      return;
    }

    final confirmed = await _confirm(
      title: 'Accept this request?',
      confirmKey: const Key('confirm-accept'),
      confirmLabel: 'Yes, accept',
      excluded: excluded,
    );
    if (confirmed != true || !mounted) return;

    final result = await widget.viewmodel.accept(request.id, [
      for (final line in items)
        RequisitionLineDecision(
          lineId: line.id,
          available: _answers[line.id]!,
          declineReason: _answers[line.id]! ? '' : _reasonFor(line.id),
        ),
    ]);
    if (!mounted) return;
    if (result.outcome == ReviewOutcome.saved) {
      Navigator.of(context).pop(result.message ?? 'Request accepted.');
      return;
    }
    setState(() => _error = result.message);
  }

  Future<void> _decline() async {
    final request = _request;
    final reason = _declineReason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Give a reason for declining the request.');
      return;
    }

    final confirmed = await _confirm(
      title: 'Decline this request?',
      confirmKey: const Key('confirm-decline'),
      confirmLabel: 'Yes, decline',
      excluded: const [],
    );
    if (confirmed != true || !mounted) return;

    final result = await widget.viewmodel.decline(request.id, reason);
    if (!mounted) return;
    if (result.outcome == ReviewOutcome.saved) {
      Navigator.of(context).pop(result.message ?? 'Request declined.');
      return;
    }
    setState(() => _error = result.message);
  }

  String _reasonFor(int lineId) => (_reasons[lineId]?.text ?? '').trim();

  /// The explicit confirmation: it names the request and the project, and the
  /// lines the store is refusing, so nobody presses through without reading it.
  Future<bool?> _confirm({
    required String title,
    required Key confirmKey,
    required String confirmLabel,
    required List<RequisitionItem> excluded,
  }) {
    final request = _request;
    final refused = excluded.isEmpty
        ? 'none'
        : excluded.map(_lineName).join(', ');
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(
          '${request.reqNumber} for ${request.projectName}.\n'
          'Lines marked Not available: $refused.\n\n'
          '${ProjectRequestReviewDialog.acceptCopy}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  static String _lineName(RequisitionItem line) =>
      line.productName.isEmpty ? line.variantName : line.productName;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ProjectRequestsViewmodel>();
    final request = _request;
    final reviewable = request.status == RequisitionStatus.waiting;
    final submitting = viewmodel.isSubmitting(request.id);
    final blocked = viewmodel.isBlocked(request.id);
    final message = _error ?? viewmodel.reviewMessage(request.id);

    return AlertDialog(
      title: Text(request.reqNumber),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge(
                label: request.status.label,
                tone: statusToneFor(request.status),
              ),
              const SizedBox(height: AppSpacing.md),
              _fact('Project', request.projectName),
              _fact('Contractor', request.projectCustomerName),
              _fact('Requested by', request.requestedByName),
              _fact('Received', _received(request)),
              _fact('CPMS request id', request.cpmsRequestId ?? '—'),
              // CPMS's approver stays THEIR name (decision 09): the store's
              // review never replaces who approved it in the project system.
              _fact(
                'CPMS approver',
                request.approverName ?? 'No approver sent',
              ),
              if (request.notes.trim().isNotEmpty)
                _fact('Notes', request.notes),
              if (request.declineReason.trim().isNotEmpty)
                _fact('Decline reason', request.declineReason),
              if (_showsAmount(request.status)) _amount(request),
              if (request.status == RequisitionStatus.closed)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    ProjectRequestReviewDialog.closedCopy,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const Divider(height: AppSpacing.lg),
              const Text(
                'Lines',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final line in request.items)
                _line(
                  line,
                  reviewable: reviewable,
                  canEdit: !submitting && !blocked,
                ),
              if (reviewable) ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  ProjectRequestReviewDialog.acceptCopy,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('decline-reason'),
                  controller: _declineReason,
                  enabled: !submitting && !blocked,
                  decoration: const InputDecoration(
                    labelText: 'Decline reason',
                    hintText: 'Why can the store not serve this request?',
                    isDense: true,
                  ),
                ),
              ],
              if (message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.errorTint,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.errorText,
                    ),
                  ),
                ),
              ],
              if (blocked)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('retry-refresh'),
                    onPressed: () => viewmodel.retryRefresh(request.id),
                    child: const Text('Retry refresh'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: reviewable
          ? [
              TextButton(
                key: const Key('decline-request'),
                onPressed: submitting || blocked ? null : _decline,
                child: const Text('Decline request'),
              ),
              FilledButton(
                key: const Key('accept-request'),
                onPressed: submitting || blocked ? null : _accept,
                child: const Text('Accept request'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
    );
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  /// Decision 14: WAITING and DECLINED have no expected figure at all; a
  /// reviewed request shows one, or says it is unknown. Never ₱0.00.
  static bool _showsAmount(RequisitionStatus status) => switch (status) {
    RequisitionStatus.accepted ||
    RequisitionStatus.partial ||
    RequisitionStatus.released ||
    RequisitionStatus.closed => true,
    _ => false,
  };

  Widget _amount(Requisition request) {
    final amount = request.expectedAmount;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            amount == null
                ? ProjectRequestReviewDialog.unavailableAmountCopy
                : formatPeso(amount),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (amount != null)
            const Text(
              ProjectRequestReviewDialog.notOwedCopy,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _line(
    RequisitionItem line, {
    required bool reviewable,
    required bool canEdit,
  }) {
    final answer = _answers[line.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _lineName(line),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            [line.variantName, line.unit].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            'Qty ${formatQuantity(line.quantity)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (reviewable) ...[
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  key: ValueKey('line-${line.id}-available'),
                  label: const Text('Available'),
                  selected: answer == true,
                  onSelected: canEdit ? (_) => _answer(line.id, true) : null,
                ),
                ChoiceChip(
                  key: ValueKey('line-${line.id}-not-available'),
                  label: const Text('Not available'),
                  selected: answer == false,
                  onSelected: canEdit ? (_) => _answer(line.id, false) : null,
                ),
              ],
            ),
            if (answer == false)
              TextField(
                key: ValueKey('line-${line.id}-reason'),
                controller: _reasons[line.id],
                enabled: canEdit,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why can the store not serve this line?',
                  isDense: true,
                ),
              ),
          ] else if (answer != null) ...[
            StatusBadge(
              label: answer ? 'Available' : 'Not available',
              tone: answer ? StatusTone.success : StatusTone.error,
            ),
            if (!answer && line.declineReason.trim().isNotEmpty)
              Text(line.declineReason, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  static String _received(Requisition request) =>
      request.createdAt == null ? '—' : formatDate(request.createdAt!);
}

/// The queue's one status→tone map, shared with the list's badges so a row and
/// its dialog never disagree about how a status reads.
StatusTone statusToneFor(RequisitionStatus status) => switch (status) {
  RequisitionStatus.waiting => StatusTone.warning,
  RequisitionStatus.accepted => StatusTone.success,
  RequisitionStatus.declined => StatusTone.error,
  RequisitionStatus.partial => StatusTone.info,
  RequisitionStatus.released => StatusTone.success,
  RequisitionStatus.closed => StatusTone.neutral,
  RequisitionStatus.draft ||
  RequisitionStatus.submitted ||
  RequisitionStatus.approved ||
  RequisitionStatus.cancelled ||
  RequisitionStatus.rejected ||
  RequisitionStatus.unknown => StatusTone.neutral,
};
