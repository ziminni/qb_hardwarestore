import 'package:client/core/config/api_config.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/bodega/mobile/bodega_history_screen.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_widgets.dart';
import 'package:client/features/bodega/mobile/bodega_stock_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Profile: who is signed in (with a picture), the Bodega's read-only lists,
/// this phone's settings, and log out.
class BodegaProfileTab extends StatelessWidget {
  const BodegaProfileTab({super.key, this.takePhoto});

  final PhotoTaker? takePhoto;

  Future<void> _changePicture(BuildContext context, AuthViewmodel auth) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (auth.user?.avatarUrl.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: const Text('Remove picture'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    String? error;
    if (choice == 'remove') {
      error = await auth.setAvatar(null);
    } else {
      final taken = await (takePhoto ?? takePhotoWithCamera)(
        fromGallery: choice == 'gallery',
      );
      if (taken == null) return;
      error = await auth.setAvatar(taken.bytes, filename: taken.name);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Profile picture updated.')),
    );
  }

  Future<void> _serverAddress(BuildContext context) async {
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => const _ServerAddressDialog(),
    );
    if (saved == null || !context.mounted) return;
    final url = await ApiConfig.save(saved.isEmpty ? null : saved);
    ApiClient.instance.setBaseUrl(url);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('This phone now talks to $url')));
  }

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();
    final user = auth.user;
    final name = user?.fullName ?? '';
    final initials = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final avatar = user?.avatarUrl ?? '';
    return ListView(
      key: const ValueKey('bodega-profile'),
      padding: const EdgeInsets.only(top: 20, bottom: 24),
      children: [
        Center(
          child: GestureDetector(
            key: const ValueKey('profile-avatar'),
            onTap: () => _changePicture(context, auth),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.brandBlack,
                  foregroundImage: avatar.isEmpty
                      ? null
                      : NetworkImage(mediaUrl(avatar)),
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: const TextStyle(
                      color: AppColors.brandGold,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.brandGold,
                    child: Icon(
                      Icons.photo_camera,
                      size: 17,
                      color: AppColors.brandBlack,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name.isEmpty ? 'Bodega Checker' : name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        Text(
          user?.roleLabel ?? 'Bodega Checker',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.brandGoldText),
        ),
        if ((user?.username ?? '').isNotEmpty)
          Text(
            '@${user!.username}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        const SectionHeader(title: 'Bodega'),
        MobileCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.warehouse_outlined),
                title: const Text('Bodega stock'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const BodegaStockScreen()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Release history'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, const BodegaHistoryScreen()),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Settings'),
        MobileCard(
          child: ListTile(
            key: const ValueKey('server-address'),
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Server address'),
            subtitle: Text(ApiConfig.baseUrl),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _serverAddress(context),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            key: const ValueKey('log-out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: auth.isLoading ? null : auth.logout,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ),
      ],
    );
  }
}

class _ServerAddressDialog extends StatefulWidget {
  const _ServerAddressDialog();

  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
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
