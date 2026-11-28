import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ani_dash/core/constants/anidash_go.dart';
import 'package:ani_dash/features/settings/data/device_pairing_service.dart';
import 'package:ani_dash/shared/auth/providers/auth_notifier.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  final DevicePairingService _pairingService = DevicePairingService();
  bool _pairing = false;
  bool _loadingDevices = true;
  List<PairedDeviceRecord> _pairedDevices = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshDevices);
  }

  Future<void> _refreshDevices() async {
    if (mounted) {
      setState(() {
        _loadingDevices = true;
      });
    }
    final devices = await _pairingService.fetchPairedDevices(
      ref.read(authProvider),
    );
    if (!mounted) return;
    setState(() {
      _pairedDevices = devices;
      _loadingDevices = false;
    });
  }

  Future<void> _scanCode() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _PairingScannerScreen()),
    );
    if (value != null && mounted) await _confirmAndPair(value);
  }

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Enter pairing code'),
            content: TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'Code shown on AniDash Go',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty && mounted) {
      await _confirmAndPair(value);
    }
  }

  Future<void> _confirmAndPair(String input) async {
    if (DevicePairingService.parsePairingCode(input) == null) {
      _showMessage(
        'Invalid code',
        'Use the QR code or one-time code shown on the official AniDash Go website.',
      );
      return;
    }

    final scannedAt = DateTime.now();
    setState(() => _pairing = true);
    final inspection = await _pairingService.inspect(input);
    if (!mounted) return;
    setState(() => _pairing = false);
    if (!inspection.isSuccess) {
      _showMessage('Could not verify device', inspection.result.message);
      return;
    }
    final device = inspection.device!;

    final auth = ref.read(authProvider);
    final connected = <String>[
      if (auth.isAniListAuthenticated) 'AniList',
      if (auth.isMalAuthenticated) 'MyAnimeList',
    ];
    if (connected.isEmpty) {
      _showMessage(
        'Connect an account first',
        'Connect AniList or MyAnimeList in Account Settings, then scan the code again.',
      );
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: const Icon(Icons.devices_rounded),
            title: const Text('Connect this device?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('${device.browser} · ${device.operatingSystem}'),
                      if (device.location != null) Text(device.location!),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Connect ${connected.join(' and ')} to this AniDash Go browser? Only choose Yes for a code you requested yourself.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Yes, connect'),
              ),
            ],
          ),
    );
    if (approved != true || !mounted) {
      await _pairingService.deny(input);
      return;
    }

    setState(() => _pairing = true);
    final result = await _pairingService.approve(input: input, auth: auth);
    if (!mounted) return;
    setState(() => _pairing = false);
    if (result.isSuccess) {
      await _pairingService.rememberPairedDevice(
        device: device,
        scannedAt: scannedAt,
      );
      if (mounted) {
        await _refreshDevices();
      }
    }
    _showMessage(
      result.isSuccess ? 'Device connected' : 'Could not connect',
      result.message,
    );
  }

  Future<void> _removeDeviceRecord(PairedDeviceRecord device) async {
    final remove = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              device.isRemote ? 'Revoke this device?' : 'Remove device record?',
            ),
            content: Text(
              device.isRemote
                  ? '${device.name} will immediately lose access to your connected AniDash account.'
                  : 'This removes ${device.name} from this phone’s saved pairing history.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(device.isRemote ? 'Revoke' : 'Remove'),
              ),
            ],
          ),
    );
    if (remove != true) return;
    final removed = await _pairingService.revokePairedDevice(
      device,
      ref.read(authProvider),
    );
    if (!mounted) return;
    if (!removed) {
      _showMessage(
        'Could not revoke device',
        'AniDash Go could not revoke this browser. Check your connection and try again.',
      );
      return;
    }
    await _refreshDevices();
  }

  void _showMessage(String title, String message) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Devices'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.laptop_mac_rounded, size: 36, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  'Connect AniDash Go',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open AniDash Go on a PC or browser, choose Connect with AniDash, then scan its one-time QR code here.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pairing ? null : _scanCode,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Scan QR'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pairing ? null : _enterCode,
                        icon: const Icon(Icons.keyboard_rounded),
                        label: const Text('Enter code'),
                      ),
                    ),
                  ],
                ),
                if (_pairing) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Approving this browser securely…'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Paired devices',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                '${_pairedDevices.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                ),
              ),
              IconButton(
                tooltip: 'Refresh paired devices',
                onPressed: _loadingDevices ? null : _refreshDevices,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingDevices && _pairedDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pairedDevices.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.devices_other_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No browsers have been paired from this phone yet.',
                    ),
                  ),
                ],
              ),
            )
          else
            ..._pairedDevices.map(
              (device) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PairedDeviceCard(
                  device: device,
                  onRemove: () => _removeDeviceRecord(device),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'AniDash Go sessions last up to 30 days. Connected browsers, recent activity, and remote revocation are synchronized securely from AniDash Go.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Accounts available to sync',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          _AccountTile(
            name: 'AniList',
            username: auth.anilistUser?.name,
            connected: auth.isAniListAuthenticated,
          ),
          const SizedBox(height: 8),
          _AccountTile(
            name: 'MyAnimeList',
            username: auth.malUser?.name,
            connected: auth.isMalAuthenticated,
          ),
          const SizedBox(height: 24),
          Text('How pairing works', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          const _InfoRow(
            icon: Icons.looks_one_rounded,
            text: 'AniDash Go creates a short-lived, single-use pairing code.',
          ),
          const _InfoRow(
            icon: Icons.looks_two_rounded,
            text:
                'You scan it and confirm exactly which tracker accounts will connect.',
          ),
          const _InfoRow(
            icon: Icons.looks_3_rounded,
            text:
                'Watch progress and lists can then stay aligned through the same AniList or MyAnimeList account.',
          ),
          const SizedBox(height: 8),
          Text(
            'The QR code never contains your account password or tracker token. Local downloads, caches, and app-only settings do not sync to the website.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed:
                () => launchUrl(
                  Uri.parse(AniDashGo.websiteUrl),
                  mode: LaunchMode.externalApplication,
                ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open AniDash Go'),
          ),
        ],
      ),
    );
  }
}

class _PairedDeviceCard extends StatelessWidget {
  const _PairedDeviceCard({required this.device, required this.onRemove});

  final PairedDeviceRecord device;
  final VoidCallback onRemove;

  String _activeAge(DateTime connectedAt) {
    final elapsed = DateTime.now().difference(connectedAt);
    if (elapsed.inMinutes < 1) return 'Paired just now';
    if (elapsed.inHours < 1) return 'Paired for ${elapsed.inMinutes} min';
    if (elapsed.inDays < 1) return 'Paired for ${elapsed.inHours} hr';
    return 'Paired for ${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final formatter = DateFormat('dd MMM yyyy, h:mm a');
    final withinExpectedSession = DateTime.now().isBefore(
      device.expectedSessionExpiry,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                child: Icon(Icons.computer_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${device.browser} · ${device.operatingSystem}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Device options',
                onSelected: (_) => onRemove(),
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded),
                            SizedBox(width: 10),
                            Text('Remove / revoke'),
                          ],
                        ),
                      ),
                    ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(
                  withinExpectedSession
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  size: 17,
                ),
                label: Text(
                  withinExpectedSession
                      ? _activeAge(device.connectedAt)
                      : 'Re-pairing may be required',
                ),
              ),
              if (device.location != null) Chip(label: Text(device.location!)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Scanned: ${formatter.format(device.scannedAt)}'),
          Text('Connected: ${formatter.format(device.connectedAt)}'),
          Text(
            'Last verified by this phone: ${formatter.format(device.lastConfirmedAt)}',
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.name,
    required this.username,
    required this.connected,
  });

  final String name;
  final String? username;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: colors.surfaceContainer,
      leading: CircleAvatar(
        backgroundColor:
            connected
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
        child: Icon(
          connected ? Icons.check_rounded : Icons.link_off_rounded,
          color: connected ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
      title: Text(name),
      subtitle: Text(connected ? username ?? 'Connected' : 'Not connected'),
      trailing: Text(connected ? 'Ready' : 'Unavailable'),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _PairingScannerScreen extends StatefulWidget {
  const _PairingScannerScreen();

  @override
  State<_PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<_PairingScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null &&
          DevicePairingService.parsePairingCode(value) != null) {
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Scan AniDash Go'),
      actions: [
        IconButton(
          tooltip: 'Toggle flashlight',
          onPressed: _controller.toggleTorch,
          icon: const Icon(Icons.flashlight_on_rounded),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        const Positioned(
          left: 28,
          right: 28,
          bottom: 48,
          child: Text(
            'Scan only the code shown by anidashgo.vercel.app',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    ),
  );
}
