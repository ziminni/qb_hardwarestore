import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies a release token and says so.
Future<void> copyReleaseToken(BuildContext context, String token) async {
  await Clipboard.setData(ClipboardData(text: token));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(const SnackBar(content: Text('Token copied.')));
}

/// The release token of an approved requisition.
///
/// The cashier types this token at Release materials, so the approver must be
/// able to read it and hand it to the foreman. It is a bearer credential
/// (whoever holds it can release the goods on credit, see `get_token` in the
/// requisition serializer), so it stays hidden until asked for; Copy works
/// either way.
class RequisitionTokenPanel extends StatefulWidget {
  const RequisitionTokenPanel({super.key, required this.token});

  final String token;

  @override
  State<RequisitionTokenPanel> createState() => _RequisitionTokenPanelState();
}

class _RequisitionTokenPanelState extends State<RequisitionTokenPanel> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final token = widget.token;
    final tail = token.length > 4 ? token.substring(token.length - 4) : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Release token',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _shown ? token : '•••••••• $tail',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _shown = !_shown),
                child: Text(_shown ? 'Hide' : 'Show'),
              ),
              OutlinedButton.icon(
                onPressed: () => copyReleaseToken(context, token),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy token'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Give this to the foreman. The cashier enters it at Release '
            'materials. Whoever has it can release the goods.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Shown right after an approval, so the token is handed over at once.
Future<void> showApprovedTokenDialog(
  BuildContext context, {
  required String reqNumber,
  required String token,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$reqNumber approved'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Give this release token to the foreman. The cashier enters it '
              'at Release materials. Whoever has it can release the goods, '
              'so share it only with them.',
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                token,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'It stays on the requisition, under Release token.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => copyReleaseToken(dialogContext, token),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy token'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
