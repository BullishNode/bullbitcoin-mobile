import 'package:bb_mobile/features/experimental/experimental_router.dart';
import 'package:bb_mobile/features/experimental/import_watch_only_wallet/extended_public_key_entity.dart';
import 'package:bb_mobile/features/experimental/scanner/scanner_widget.dart';
import 'package:bb_mobile/ui/components/buttons/button.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  String _scanned = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ScannerWidget(
            onScanned: (data) {
              setState(() => _scanned = data);
              try {
                final pub = ExtendedPublicKeyEntity.from(data);
                context.replaceNamed(
                  ExperimentalRoutes.watchOnly.name,
                  extra: pub,
                );
              } catch (e) {
                debugPrint(e.toString());
              }
            },
          ),
          if (_scanned.isNotEmpty)
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.25,
              left: 24,
              right: 24,
              child: BBButton.big(
                iconData: Icons.copy,
                textStyle: context.font.labelMedium,
                textColor: context.colour.onPrimary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _scanned));
                  showCopiedSnackBar(context);
                },
                label:
                    _scanned.length > 30
                        ? '${_scanned.substring(0, 10)}…${_scanned.substring(_scanned.length - 10)}'
                        : _scanned,
                bgColor: Colors.transparent,
              ),
            ),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.02,
            left: 0,
            right: 0,
            child: Center(
              child: IconButton(
                onPressed: () => context.pop(),
                icon: Icon(
                  CupertinoIcons.xmark_circle,
                  color: context.colour.onPrimary,
                  size: 64,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showCopiedSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(
        'Copied to clipboard',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: Colors.white),
      ),
      duration: const Duration(seconds: 2),
      backgroundColor: Theme.of(context).colorScheme.onSurface.withAlpha(204),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
