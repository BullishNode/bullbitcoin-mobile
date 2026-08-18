import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/pos/ui/pos_terminal_qr_saver.dart';
import 'package:bull_ui/bull_ui.dart' show Gap;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

/// The Point of Sale terminal QR plus its Copy / Open / Download actions. The
/// QR encodes the EXACT server-returned terminal URL — no reconstruction or
/// normalization. Download renders the on-screen QR to a high-contrast PNG and
/// hands it to the system Files save dialog; a user cancel is neutral. The URL,
/// QR contents and chosen destination are never logged.
class PosTerminalQr extends StatefulWidget {
  const PosTerminalQr({
    super.key,
    required this.terminalUrl,
    this.saver = const FilePickerPosTerminalQrSaver(),
    @visibleForTesting this.captureOverride,
  });

  final String terminalUrl;
  final PosTerminalQrSaver saver;

  /// Test seam: replaces the on-device `RepaintBoundary` PNG capture (which is
  /// not reliably renderable in the widget-test harness). Null in production.
  final Future<Uint8List?> Function()? captureOverride;

  @override
  State<PosTerminalQr> createState() => _PosTerminalQrState();
}

class _PosTerminalQrState extends State<PosTerminalQr> {
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _downloading = false;

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.terminalUrl);
    if (uri == null) return;
    // Guarded external launch only — the terminal URL is never webviewed.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final pngBytes =
          await (widget.captureOverride?.call() ?? _captureQrPng());
      final outcome = pngBytes == null
          ? QrImageSaveOutcome.failed
          : await widget.saver.save(
              pngBytes: pngBytes,
              fileName: 'pos-terminal-qr.png',
            );
      if (!mounted) return;
      switch (outcome) {
        case QrImageSaveOutcome.saved:
          SnackBarUtils.showSnackBar(
            context,
            context.loc.posTerminalQrDownloadSaved,
          );
        case QrImageSaveOutcome.cancelled:
          // Neutral: the user dismissed the dialog. No message, no error.
          break;
        case QrImageSaveOutcome.failed:
          SnackBarUtils.showSnackBar(
            context,
            context.loc.posTerminalQrDownloadFailed,
          );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<Uint8List?> _captureQrPng() async {
    final boundary =
        _qrBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return null;
    // pixelRatio 3 keeps the scanned QR crisp when printed.
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: RepaintBoundary(
            key: _qrBoundaryKey,
            child: QrDisplayWidget(data: widget.terminalUrl, size: 240),
          ),
        ),
        const Gap(16),
        CopyInput(
          text: widget.terminalUrl,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const Gap(8),
        Row(
          children: [
            Expanded(
              child: BBButton.big(
                label: context.loc.posOpenLink,
                iconData: Icons.open_in_new,
                iconFirst: true,
                onPressed: _open,
                bgColor: colors.secondary,
                textColor: colors.onSecondary,
              ),
            ),
            const Gap(8),
            Expanded(
              child: BBButton.big(
                label: context.loc.posTerminalQrDownloadButton,
                iconData: Icons.download,
                iconFirst: true,
                onPressed: _download,
                disabled: _downloading,
                bgColor: colors.secondary,
                textColor: colors.onSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
