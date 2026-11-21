import 'package:client/core/config/api_config.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:client/features/bodega/views/bodega_pages.dart';
import 'package:client/features/bodega/widgets/receipt_scanner.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// Takes one photo and answers its bytes, or null when the person cancels.
typedef PhotoTaker =
    Future<({List<int> bytes, String name})?> Function({bool fromGallery});

/// The default [PhotoTaker]: the phone's camera (or gallery), shrunk to a
/// size that uploads quickly and stays well under the server's 5 MB.
Future<({List<int> bytes, String name})?> takePhotoWithCamera({
  bool fromGallery = false,
}) async {
  final picked = await ImagePicker().pickImage(
    source: fromGallery ? ImageSource.gallery : ImageSource.camera,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
  );
  if (picked == null) return null;
  return (bytes: await picked.readAsBytes(), name: picked.name);
}

/// A photo URL the phone can load: rewrites any `/media/...` URL onto the
/// active [ApiConfig.baseUrl] so proxy-rewritten `http://` or internal hosts
/// always load through the phone's configured HTTPS tunnel or LAN address.
String mediaUrl(String url) {
  if (url.isEmpty) return url;
  if (url.contains('://')) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.path.startsWith('/media/')) {
      return '${ApiConfig.baseUrl}${parsed.path}';
    }
    return url;
  }
  return '${ApiConfig.baseUrl}$url';
}

/// Optional gateway header required when fetching `/media/*` through the
/// Cloudflare tunnel (`tunnel/nginx.conf.template`).
Map<String, String>? mediaHeaders() {
  final key = ApiConfig.gatewayKey.trim();
  return key.isEmpty ? null : {'X-QB-Gateway-Key': key};
}

/// A small red count on an icon; nothing when [count] is 0.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: AppColors.error,
      child: child,
    );
  }
}

/// A heading with an optional "See all" on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ],
      ),
    );
  }
}

/// A white rounded card, the phone app's one surface.
class MobileCard extends StatelessWidget {
  const MobileCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Muted centred text for an empty list.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
}

/// Finds [receipt]'s claim and opens it full screen, or says why not.
Future<void> openClaim(
  BuildContext context,
  BodegaViewmodel viewmodel,
  String receipt,
) async {
  final found = await viewmodel.lookup(receipt);
  if (!context.mounted) return;
  if (!found || viewmodel.claim == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(viewmodel.actionError ?? 'Receipt not found.')),
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider<BodegaViewmodel>.value(
        value: viewmodel,
        child: const ClaimScreen(),
      ),
    ),
  );
  viewmodel.closeClaim();
}

/// The Scan button: the camera, then the receipt's claim.
Future<void> scanAndOpenClaim(
  BuildContext context,
  BodegaViewmodel viewmodel,
  ReceiptScanner? scanner,
) async {
  // No camera: the scanner's typed fallback on its own.
  final value = scanner == null && !cameraScanAvailable
      ? await _typeOrNumber(context)
      : await (scanner ?? scanReceiptWithCamera)(context);
  if (value == null || !context.mounted) return;
  await openClaim(context, viewmodel, value);
}

Future<String?> _typeOrNumber(BuildContext context) {
  final number = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Type the OR number'),
      content: TextField(
        controller: number,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
        decoration: const InputDecoration(hintText: 'OR-20261118-0001'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, number.text.trim()),
          child: const Text('Find'),
        ),
      ],
    ),
  );
}

/// One receipt's claim and its release form, full screen.
class ClaimScreen extends StatelessWidget {
  const ClaimScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final claim = context.watch<BodegaViewmodel>().claim;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.brandBlack,
        foregroundColor: AppColors.brandWhite,
        title: Text(
          claim == null
              ? 'Receipt'
              : claim.orNumber.isNotEmpty
              ? claim.orNumber
              : claim.transactionNo,
        ),
      ),
      body: claim == null
          ? const EmptyNote('This receipt is closed.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                BodegaClaimCard(key: ValueKey(claim.saleId), claim: claim),
              ],
            ),
    );
  }
}

/// Receipts waiting for pick-up, newest sale first (or oldest, when asked).
List<BodegaClaim> sortedClaims(
  List<BodegaClaim> claims, {
  bool oldestFirst = false,
}) {
  final sorted = [...claims]
    ..sort((a, b) {
      final at = a.soldAt ?? DateTime(0), bt = b.soldAt ?? DateTime(0);
      return oldestFirst ? at.compareTo(bt) : bt.compareTo(at);
    });
  return sorted;
}
