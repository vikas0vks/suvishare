import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:suvi_core/suvi_core.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/util/format.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/native_file_picker.dart';
import '../../providers/app_services.dart';
import '../../providers/web_share.dart';
import '../nearby/device_tile.dart';
import '../nearby/qr_scan_screen.dart';
import 'file_category.dart';
import 'send_progress.dart';

/// Recursively lists files in a directory as [SendItem]s (flattened names).
Future<List<SendItem>> collectDirectory(String path) async {
  final out = <SendItem>[];
  await for (final e in Directory(
    path,
  ).list(recursive: true, followLinks: false)) {
    if (e is File) out.add(SendItem.file(e.path));
  }
  return out;
}

/// What the clipboard currently holds, normalised for the send flow.
sealed class ClipboardContent {
  const ClipboardContent();
}

class ClipboardImage extends ClipboardContent {
  const ClipboardImage(this.sendItem);
  final SendItem sendItem;
}

class ClipboardText extends ClipboardContent {
  const ClipboardText(this.text);
  final String text;
}

/// Reads the clipboard: a screenshot/image wins over text; text otherwise;
/// `null` when there is nothing usable. All failures degrade to text-only —
/// the image API is a desktop-platform plugin and must never break paste.
Future<ClipboardContent?> readClipboardContent() async {
  try {
    final png = await Pasteboard.image;
    if (png != null && png.isNotEmpty) {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      return ClipboardImage(
        SendItem.bytes(png, name: 'clipboard-$stamp.png', mime: 'image/png'),
      );
    }
  } catch (_) {
    // Fall through to text.
  }
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t != null && t.trim().isNotEmpty) return ClipboardText(t);
  } catch (_) {}
  return null;
}

/// Entry point for every "send" gesture: FAB, device tile, drag-drop, share intent.
Future<void> startSendFlow(
  BuildContext context,
  WidgetRef ref, {
  Peer? target,
  List<SendItem>? initialItems,
  String? initialText,
}) async {
  var items = List<SendItem>.from(initialItems ?? const []);
  var text = initialText;

  if (items.isEmpty && (text == null || text.isEmpty)) {
    final picked = await _pickContent(context);
    if (picked == null) return;
    items = picked.items;
    text = picked.text;
    if (items.isEmpty && (text == null || text.isEmpty)) return;
  }

  if (!context.mounted) return;
  final choice = target != null
      ? _Target.peer(target)
      : await _pickDevice(context, ref);
  if (choice == null || !context.mounted) return;

  // "Share via link": publish to browsers instead of pushing to a device.
  if (choice.viaLink) {
    await ref.read(webShareProvider.notifier).offer(items);
    if (!context.mounted) return;
    await _showLinkSheet(context, ref);
    return;
  }
  final peer = choice.peer!;

  final services = await ref.read(appServicesProvider.future);
  String? pin;
  // If the receiver demands a PIN we get 401; ask and retry once.
  for (var attempt = 0; attempt < 2; attempt++) {
    final localId = const Uuid().v4();
    final future = services.sender.send(
      target: peer,
      items: items,
      text: text,
      pin: pin,
      localId: localId,
    );
    if (!context.mounted) return;
    final result = await showSendProgress(context, ref, localId, future);
    if (result?.failure == SendFailure.pinRequired && attempt == 0) {
      if (!context.mounted) return;
      pin = await _askPin(context);
      if (pin == null) return;
      continue;
    }
    // The device in the list is gone (app closed / phone asleep / IP moved):
    // drop the stale entry so the list tells the truth, kick off a fresh
    // discovery round, and say what to do in plain words.
    if (result?.failure == SendFailure.unreachable) {
      services.discovery.registry.remove(peer.fingerprint);
      unawaited(services.discovery.refresh());
      unawaited(services.discovery.scanSubnet());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).peerUnreachable(peer.alias),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
    break;
  }
}

class _PickResult {
  _PickResult(this.items, this.text);
  final List<SendItem> items;
  final String? text;
}

Future<_PickResult?> _pickContent(BuildContext context) async {
  final wc = windowClassOf(MediaQuery.sizeOf(context).width);
  if (wc == WindowClass.compact) {
    return showModalBottomSheet<_PickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: _ContentPicker(),
      ),
    );
  }
  return showDialog<_PickResult>(
    context: context,
    builder: (_) => const Dialog(
      child: SizedBox(width: 700, height: 680, child: _ContentPicker()),
    ),
  );
}

class _ContentPicker extends StatefulWidget {
  const _ContentPicker();
  @override
  State<_ContentPicker> createState() => _ContentPickerState();
}

class _ContentPickerState extends State<_ContentPicker> {
  final List<SendItem> _items = [];
  String? _text;
  bool _busy = false;

  int get _totalSize => _items.fold(0, (a, i) => a + (i.size ?? 0));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final usesLargeText = MediaQuery.textScalerOf(context).scale(16) > 21;
    final categories = <_CategoryOption>[
      _CategoryOption(
        ShareFileCategory.general,
        Icons.apps_rounded,
        l.categoryGeneral,
        l.categoryGeneralDesc,
      ),
      _CategoryOption(
        ShareFileCategory.documents,
        Icons.description_rounded,
        l.categoryDocuments,
        l.categoryDocumentsDesc,
      ),
      _CategoryOption(
        ShareFileCategory.images,
        Icons.photo_library_rounded,
        l.categoryImages,
        l.categoryImagesDesc,
      ),
      _CategoryOption(
        ShareFileCategory.videos,
        Icons.video_library_rounded,
        l.categoryVideos,
        l.categoryVideosDesc,
      ),
      _CategoryOption(
        ShareFileCategory.music,
        Icons.library_music_rounded,
        l.categoryMusic,
        l.categoryMusicDesc,
      ),
      _CategoryOption(
        ShareFileCategory.compressed,
        Icons.folder_zip_rounded,
        l.categoryCompressed,
        l.categoryCompressedDesc,
      ),
      _CategoryOption(
        ShareFileCategory.other,
        Icons.extension_rounded,
        l.categoryOther,
        l.categoryOtherDesc,
      ),
    ];
    final extraOptions = <_Option>[
      if (!isMobile) _Option(Icons.folder_rounded, l.pickFolder, _pickFolder),
      _Option(Icons.notes_rounded, l.pickText, _pickText),
      _Option(Icons.content_paste_rounded, l.pickClipboard, _pickClipboard),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SuviSpacing.xl,
        SuviSpacing.md,
        SuviSpacing.xl,
        SuviSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.whatToSend,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l.close,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          AnimatedSize(
            duration: SuviMotion.short,
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.only(bottom: SuviSpacing.md),
                    child: LinearProgressIndicator(),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.browseByCategory,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: scheme.primary),
                  ),
                  const SizedBox(height: SuviSpacing.sm),
                  LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth < 520 ? 2 : 3,
                        mainAxisExtent: usesLargeText ? 144 : 116,
                        mainAxisSpacing: SuviSpacing.sm,
                        crossAxisSpacing: SuviSpacing.sm,
                      ),
                      itemCount: categories.length,
                      itemBuilder: (_, index) => _CategoryCard(
                        option: categories[index],
                        enabled: !_busy,
                        onTap: () => _pickCategory(categories[index].category),
                      ),
                    ),
                  ),
                  const SizedBox(height: SuviSpacing.lg),
                  Text(
                    l.moreWaysToShare,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: scheme.primary),
                  ),
                  const SizedBox(height: SuviSpacing.sm),
                  Wrap(
                    spacing: SuviSpacing.sm,
                    runSpacing: SuviSpacing.sm,
                    children: [
                      for (final option in extraOptions)
                        ActionChip(
                          avatar: Icon(option.icon, size: 19),
                          label: Text(option.label),
                          onPressed: _busy ? null : option.onTap,
                        ),
                    ],
                  ),
                  if (_items.isNotEmpty || (_text?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: SuviSpacing.lg),
                    Wrap(
                      spacing: SuviSpacing.sm,
                      runSpacing: SuviSpacing.sm,
                      children: [
                        for (final i in _items.take(12))
                          InputChip(
                            avatar: Icon(iconForMime(i.mime), size: 18),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                i.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onDeleted: _busy
                                ? null
                                : () => setState(() => _items.remove(i)),
                          ),
                        if (_items.length > 12)
                          Chip(label: Text(l.moreFiles(_items.length - 12))),
                        if (_text?.isNotEmpty ?? false)
                          InputChip(
                            avatar: const Icon(Icons.notes_rounded, size: 18),
                            label: Text(
                              _text!.length > 30
                                  ? '${_text!.substring(0, 30)}…'
                                  : _text!,
                            ),
                            onDeleted: _busy
                                ? null
                                : () => setState(() => _text = null),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: SuviSpacing.sm),
                ],
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: SuviMotion.short,
            child: _items.isEmpty && !(_text?.isNotEmpty ?? false)
                ? const SizedBox.shrink()
                : Container(
                    key: const ValueKey('selection-actions'),
                    padding: const EdgeInsets.only(top: SuviSpacing.md),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.itemsSelected(
                                  _items.length +
                                      ((_text?.isNotEmpty ?? false) ? 1 : 0),
                                  formatBytes(_totalSize),
                                ),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _items.clear();
                                      _text = null;
                                    }),
                              child: Text(l.clearSelection),
                            ),
                          ],
                        ),
                        const SizedBox(height: SuviSpacing.xs),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context)
                                      .pop(_PickResult(List.of(_items), _text)),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(l.continueToDevice),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _guard(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      // A picker failure must say so, not silently add nothing — that reads
      // as "my file just doesn't show up".
      if (mounted) {
        debugPrint('file picker failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).filePickerFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCategory(ShareFileCategory category) => _guard(() async {
    await HapticFeedback.selectionClick();
    if (NativeFilePicker.isSupported) {
      // Android: zero-copy SAF picker — big files appear instantly and
      // are streamed from source at send time.
      final items = await NativeFilePicker.pickFiles(
        mimeTypes: category.mimeTypes,
      );
      if (mounted && items.isNotEmpty) setState(() => _items.addAll(items));
      return;
    }
    final files = await switch (category) {
      ShareFileCategory.general => FilePicker.pickFiles(),
      ShareFileCategory.images => FilePicker.pickFiles(type: FileType.image),
      ShareFileCategory.videos => FilePicker.pickFiles(type: FileType.video),
      ShareFileCategory.music => FilePicker.pickFiles(type: FileType.audio),
      ShareFileCategory.documents ||
      ShareFileCategory.compressed ||
      ShareFileCategory.other => FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: category.extensions,
      ),
    };
    _addPicked(files);
  });

  Future<void> _addPicked(List<PlatformFile> files) async {
    if (files.isEmpty) return;
    final added = <SendItem>[];
    for (final f in files) {
      final path = f.path;
      if (path != null) {
        added.add(SendItem.file(path, name: f.name));
      } else {
        // Web blobs and other pathless sources: stream, never copy.
        added.add(
          SendItem.stream(
            name: f.name,
            opener: f.readAsByteStream,
            sizer: f.length,
          ),
        );
      }
    }
    if (mounted) setState(() => _items.addAll(added));
  }

  Future<void> _pickFolder() => _guard(() async {
    final dir = await fs.getDirectoryPath();
    if (dir == null) return;
    final files = await collectDirectory(dir);
    if (mounted) setState(() => _items.addAll(files));
  });

  Future<void> _pickText() => _guard(() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: _text);
    String? t;
    try {
      t = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.textToSend),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(hintText: l.typeSomething),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l.done),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (mounted && t != null && t.trim().isNotEmpty) {
      setState(() => _text = t);
    }
  });

  /// Clipboard can hold text OR an image (screenshots land there as PNG).
  /// Prefer the image when both are present — that's almost always what a
  /// screenshot-then-share gesture means.
  Future<void> _pickClipboard() => _guard(() async {
    final item = await readClipboardContent();
    if (!mounted) return;
    switch (item) {
      case ClipboardImage(:final sendItem):
        setState(() => _items.add(sendItem));
      case ClipboardText(:final text):
        setState(() => _text = text);
      case null:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).clipboardEmpty)),
        );
    }
  });
}

class _Option {
  _Option(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _CategoryOption {
  const _CategoryOption(this.category, this.icon, this.label, this.description);

  final ShareFileCategory category;
  final IconData icon;
  final String label;
  final String description;
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.option,
    required this.enabled,
    required this.onTap,
  });

  final _CategoryOption option;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${option.label}. ${option.description}',
      child: InkWell(
        borderRadius: BorderRadius.circular(SuviRadius.lg),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.all(SuviSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(SuviRadius.lg),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(SuviRadius.md),
                ),
                child: Icon(
                  option.icon,
                  size: 21,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                option.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where a transfer should go: a discovered peer, or the browser link.
class _Target {
  const _Target.peer(this.peer) : viaLink = false;
  const _Target.link() : peer = null, viaLink = true;
  final Peer? peer;
  final bool viaLink;
}

Future<_Target?> _pickDevice(BuildContext context, WidgetRef ref) async {
  final wc = windowClassOf(MediaQuery.sizeOf(context).width);
  const body = _DevicePicker();
  if (wc == WindowClass.compact) {
    return showModalBottomSheet<_Target>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => body,
    );
  }
  return showDialog<_Target>(
    context: context,
    builder: (_) => const Dialog(child: SizedBox(width: 520, child: body)),
  );
}

/// Shows the browser URL + QR after publishing a link share.
Future<void> _showLinkSheet(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final web = ref.watch(webShareProvider).value;
        final url = web?.url;
        return AlertDialog(
          title: Text(l.shareViaLink),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (url == null)
                Padding(
                  padding: const EdgeInsets.all(SuviSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: SuviSpacing.lg),
                      Text(
                        web?.error == 'not-connected' ? l.webShareNoWifi : '…',
                      ),
                    ],
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(SuviSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(SuviRadius.md),
                  ),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: PrettyQrView.data(data: url),
                  ),
                ),
                const SizedBox(height: SuviSpacing.lg),
                SelectableText(url, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: SuviSpacing.sm),
                Text(
                  l.webShareOn,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            if (url != null)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.copied)));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(l.copy),
              ),
            FilledButton(
              onPressed: () {
                ref.read(webShareProvider.notifier).revokeOffer();
                Navigator.of(ctx).pop();
              },
              child: Text(l.done),
            ),
          ],
        );
      },
    ),
  );
}

class _DevicePicker extends ConsumerWidget {
  const _DevicePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final peers = ref.watch(peersProvider).value ?? const <Peer>[];
    final trusted =
        ref.watch(trustedDevicesProvider).value ?? const <TrustedDevice>[];
    final byFp = {for (final t in trusted) t.fingerprint: t};
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SuviSpacing.xl,
        SuviSpacing.md,
        SuviSpacing.xl,
        SuviSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.chooseDevice,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l.refresh,
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () =>
                    ref.read(appServicesProvider).value?.discovery.refresh(),
              ),
            ],
          ),
          const SizedBox(height: SuviSpacing.md),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SuviSpacing.xxl),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: SuviSpacing.lg),
                    Text(l.lookingForDevices),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: peers.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: SuviSpacing.sm),
                itemBuilder: (_, i) => DeviceTile(
                  peer: peers[i],
                  trusted: byFp[peers[i].fingerprint],
                  onTap: () =>
                      Navigator.of(context).pop(_Target.peer(peers[i])),
                ),
              ),
            ),
          const Divider(height: SuviSpacing.xl),
          if (canScanQr)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(context)
                    .colorScheme
                    .onPrimaryContainer,
                child: const Icon(Icons.qr_code_scanner_rounded),
              ),
              title: Text(l.scanQr),
              subtitle: Text(
                l.scanQrHint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final peer = await scanQrAndConnect(context, ref);
                if (peer != null && context.mounted) {
                  Navigator.of(context).pop(_Target.peer(peer));
                }
              },
            ),
          // Works for devices without the app: phones, iPads, work laptops.
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor: Theme.of(context)
                  .colorScheme
                  .onSecondaryContainer,
              child: const Icon(Icons.link_rounded),
            ),
            title: Text(l.shareViaLink),
            subtitle: Text(
              l.settingsWebShareDesc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).pop(const _Target.link()),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askPin(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.enterPin),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        obscureText: true,
        decoration: InputDecoration(hintText: l.pinHint),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(c.text),
          child: Text(l.send),
        ),
      ],
    ),
  );
}
