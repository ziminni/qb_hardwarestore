import 'package:client/core/config/api_config.dart';
import 'package:client/core/network/api_client.dart';
import 'package:flutter/material.dart';

/// Asks for this device's server address, saves it and re-points the API
/// client. Returns the address now in use, or null when cancelled.
Future<String?> changeServerAddress(BuildContext context) async {
  final typed = await showDialog<String>(
    context: context,
    builder: (context) => const ServerAddressDialog(),
  );
  if (typed == null || !context.mounted) return null;
  final url = await ApiConfig.save(typed.isEmpty ? null : typed);
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

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server address'),
      content: TextField(
        key: const ValueKey('server-address-field'),
        controller: _address,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: '192.168.8.105:8000',
          helperText: 'The computer running BuildPro, on this Wi-Fi.',
        ),
      ),
      actions: [
        if (ApiConfig.savedBaseUrl != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Use default'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _address.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
