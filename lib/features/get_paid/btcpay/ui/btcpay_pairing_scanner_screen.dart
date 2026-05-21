import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/qr_scanner_widget.dart';
import 'package:bb_mobile/core/widgets/snackbar_utils.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BtcpayPairingScannerScreen extends StatefulWidget {
  const BtcpayPairingScannerScreen({super.key});

  @override
  State<BtcpayPairingScannerScreen> createState() =>
      _BtcpayPairingScannerScreenState();
}

class _BtcpayPairingScannerScreenState
    extends State<BtcpayPairingScannerScreen> {
  bool _handled = false;

  void _onScanned(String value) {
    if (!mounted || _handled) return;
    final pairingCode = value.trim();
    if (pairingCode.isEmpty) return;
    try {
      const SamRockPairingRequestParser().parse(pairingCode);
    } on SamRockPairingRequestException {
      SnackBarUtils.showSnackBar(context, 'Not a SamRock pairing QR.');
      return;
    }
    _handled = true;
    context.pop(pairingCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.secondaryFixedDim,
      body: Stack(
        fit: StackFit.expand,
        children: [
          QrScannerWidget(onScanned: _onScanned),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.02,
            left: 0,
            right: 0,
            child: Center(
              child: IconButton(
                onPressed: context.mounted ? () => context.pop() : null,
                icon: Icon(
                  CupertinoIcons.xmark_circle,
                  color: context.appColors.onPrimary,
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
