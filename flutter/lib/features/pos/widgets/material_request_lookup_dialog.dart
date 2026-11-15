import 'package:client/data/models/requisition.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// A cashier can choose an accepted/open request without carrying its token slip.
class MaterialRequestLookupDialog extends StatefulWidget {
  const MaterialRequestLookupDialog({super.key, required this.viewmodel});

  final MaterialReleaseViewmodel viewmodel;

  @override
  State<MaterialRequestLookupDialog> createState() =>
      _MaterialRequestLookupDialogState();
}

class _MaterialRequestLookupDialogState
    extends State<MaterialRequestLookupDialog> {
  late Future<List<Requisition>> _requests = widget.viewmodel
      .fetchReleaseQueue();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find accepted request'),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('release.requestSearch'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Request number, project or customer',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Requisition>>(
                future: _requests,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return ErrorBanner(
                      message: '${snapshot.error}',
                      onRetry: () => setState(() {
                        _requests = widget.viewmodel.fetchReleaseQueue();
                      }),
                    );
                  }
                  final all = snapshot.data ?? const <Requisition>[];
                  final matches = all
                      .where(
                        (request) =>
                            '${request.reqNumber} ${request.projectName} ${request.projectCustomerName}'
                                .toLowerCase()
                                .contains(_search),
                      )
                      .toList(growable: false);
                  if (matches.isEmpty) {
                    return Center(
                      child: Text(
                        all.isEmpty
                            ? 'No accepted requests waiting for release.'
                            : 'No requests match your search.',
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final request = matches[index];
                      return ListTile(
                        title: Text(request.reqNumber),
                        subtitle: Text(
                          '${request.projectName}\n${request.projectCustomerName}'
                          '${request.rawStatus == 'PARTIAL' ? '\nPartially released — remaining items only' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, request.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
