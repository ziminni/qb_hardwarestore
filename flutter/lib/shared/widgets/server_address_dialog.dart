import 'package:client/core/config/api_config.dart';
import 'package:client/core/network/api_client.dart';
import 'package:flutter/material.dart';

/// Asks for this device's server address and optional tunnel gateway key,
/// saves them and re-points the API client. Returns the address now in use,
/// or null when cancelled.
Future<String?> changeServerAddress(BuildContext context) async {
  final result = await showDialog<({String url, String gatewayKey})>(
    context: context,
    builder: (context) => const ServerAddressDialog(),
  );
  if (result == null || !context.mounted) return null;
  final url = await ApiConfig.save(result.url.isEmpty ? null : result.url);
  await ApiConfig.saveGatewayKey(
    result.gatewayKey.isEmpty ? null : result.gatewayKey,
  );
  ApiClient.instance.setBaseUrl(url);
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('This phone now talks to $url')));
  }
  return url;
}

class ServerAddressDialog extends StatefulWidget {
  const ServerAddressDialog({super.key});

  @override
  State<ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<ServerAddressDialog> {
  late final _address = TextEditingController(
    text: ApiConfig.savedBaseUrl ?? ApiConfig.baseUrl,
  );
  late final _gatewayKey = TextEditingController(
    text: ApiConfig.savedGatewayKey ?? '',
  );

  @override
  void dispose() {
    _address.dispose();
    _gatewayKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('server-address-field'),
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Server URL or LAN IP',
              hintText: 'https://pos-api.yourdomain.com',
              helperText:
                  'Use your online tunnel URL (faraway Bodega) or local LAN IP.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('server-gateway-key-field'),
            controller: _gatewayKey,
            decoration: const InputDecoration(
              labelText: 'Gateway key (for online tunnel)',
              hintText: 'Optional — leave blank on local Wi-Fi',
              helperText: 'Matches QB_GATEWAY_KEY from the POS tunnel setup.',
            ),
          ),
        ],
      ),
      actions: [
        if (ApiConfig.savedBaseUrl != null || ApiConfig.savedGatewayKey != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (url: '', gatewayKey: '')),
            child: const Text('Use default'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            url: _address.text.trim(),
            gatewayKey: _gatewayKey.text.trim(),
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
