import 'package:client/data/models/requisition.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:flutter/material.dart';

/// The material release counter — Phase 5's only **irreversible** screen (decision 09).
///
/// A store clerk takes a printed token from a foreman, checks it, and releases the materials. The
/// release FIFO-deducts real stock, writes a real `SalesTransaction`, and **always** leaves a
/// receivable because a construction firm pays later — so the receipt is shown, not just the success.
///
/// [viewmodel] is injectable so a test can observe what the screen sends; production passes nothing.
class MaterialReleasePage extends StatefulWidget {
  const MaterialReleasePage({super.key, this.viewmodel});

  final MaterialReleaseViewmodel? viewmodel;

  @override
  State<MaterialReleasePage> createState() => _MaterialReleasePageState();
}

class _MaterialReleasePageState extends State<MaterialReleasePage> {
  late final MaterialReleaseViewmodel _viewmodel =
      widget.viewmodel ?? MaterialReleaseViewmodel();
  late final bool _ownsViewmodel = widget.viewmodel == null;
  final _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    if (_ownsViewmodel) _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Release materials',
      subtitle: 'Verify a material token and release the stock it covers',
      selectedNavigationIndex: 2,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height - 132,
        child: AnimatedBuilder(
        animation: _viewmodel,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Verify the material token'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _token,
                      decoration: const InputDecoration(
                        labelText: 'Token',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _viewmodel.isBusy
                        ? null
                        : () => _viewmodel.verify(_token.text.trim()),
                    child: const Text('Verify'),
                  ),
                ],
              ),
              if (_viewmodel.isBusy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: LinearProgressIndicator(),
                ),
              if (_viewmodel.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _viewmodel.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_viewmodel.verification != null) ...[
                const SizedBox(height: 24),
                _VerificationCard(
                  verification: _viewmodel.verification!,
                  // The action appears only where the viewmodel would accept it: a released token
                  // cannot be released again, and the server would refuse the second press.
                  onRelease: _viewmodel.isReleased || _viewmodel.isBusy
                      ? null
                      : _viewmodel.release,
                ),
              ],
              if (_viewmodel.result != null) ...[
                const SizedBox(height: 24),
                _ReceiptCard(result: _viewmodel.result!),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.verification,
    required this.onRelease,
  });

  final TokenVerification verification;
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  verification.reqNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Chip(label: Text(verification.project)),
              ],
            ),
            const SizedBox(height: 8),
            // Who the materials are being released for — the same provenance rule as the queue.
            Text('For ${verification.customer}'),
            const SizedBox(height: 12),
            for (final item in verification.items)
              Text(
                '${item.remaining} of ${item.quantity} × ${item.variantName} remaining',
              ),
            if (onRelease != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRelease,
                child: const Text('Release materials'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.result});

  final ReleaseResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Released',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Sale ${result.transactionNo}'),
            Text('Total ₱${result.grandTotal.toStringAsFixed(2)}'),
            // A construction firm pays later, so this is the number the clerk must say out loud.
            Text('Balance due ₱${result.balanceDue.toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}
