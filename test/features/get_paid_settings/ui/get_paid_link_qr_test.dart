import 'dart:typed_data';

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/get_paid_link_qr.dart';
import 'package:bb_mobile/features/get_paid_settings/ui/get_paid_link_qr_saver.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSaver implements GetPaidLinkQrSaver {
  _FakeSaver(this.outcome);
  final QrImageSaveOutcome outcome;
  int calls = 0;
  Uint8List? capturedBytes;
  String? capturedFileName;

  @override
  Future<QrImageSaveOutcome> save({
    required Uint8List pngBytes,
    required String fileName,
  }) async {
    calls++;
    capturedBytes = pngBytes;
    capturedFileName = fileName;
    return outcome;
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

void main() {
  const url = 'https://bullpay.ca/satoshi/pos?ref=abc123';

  testWidgets('encodes the EXACT terminal URL with no normalization', (
    tester,
  ) async {
    await _pump(
      tester,
      const GetPaidLinkQr(
        url: url,
        openLabel: 'Open terminal',
        downloadFileName: 'pos-terminal-qr.png',
      ),
    );

    // The QR component is fed the exact URL string that will be encoded — no
    // reconstruction or normalization.
    final qr = tester.widget<QrDisplayWidget>(find.byType(QrDisplayWidget));
    expect(qr.data, url);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Copy (the URL), Open and Download actions', (
    tester,
  ) async {
    await _pump(
      tester,
      const GetPaidLinkQr(
        url: url,
        openLabel: 'Open terminal',
        downloadFileName: 'pos-terminal-qr.png',
      ),
    );

    // Copy: the URL is shown in a CopyInput (SelectableText carries the value).
    expect(find.text(url), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is BBButton && w.label == 'Open terminal',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => w is BBButton && w.label == 'Download QR'),
      findsOneWidget,
    );
  });

  Future<Uint8List?> fakeCapture() async => Uint8List.fromList(const [1, 2, 3]);

  testWidgets('Download captures a PNG and reports success', (tester) async {
    final saver = _FakeSaver(QrImageSaveOutcome.saved);
    await _pump(
      tester,
      GetPaidLinkQr(
        url: url,
        openLabel: 'Open terminal',
        downloadFileName: 'pos-terminal-qr.png',
        saver: saver,
        captureOverride: fakeCapture,
      ),
    );

    await tester.tap(
      find.byWidgetPredicate((w) => w is BBButton && w.label == 'Download QR'),
    );
    await tester.pump();
    await tester.pump();

    expect(saver.calls, 1);
    expect(saver.capturedFileName, 'pos-terminal-qr.png');
    expect(saver.capturedBytes, isNotNull);
    expect(saver.capturedBytes!.isNotEmpty, isTrue);
    expect(find.text('QR code saved'), findsOneWidget);
    // Drain the 3s custom-snackbar auto-dismiss timer + exit animation.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a cancelled download shows no message (neutral)', (
    tester,
  ) async {
    final saver = _FakeSaver(QrImageSaveOutcome.cancelled);
    await _pump(
      tester,
      GetPaidLinkQr(
        url: url,
        openLabel: 'Open terminal',
        downloadFileName: 'pos-terminal-qr.png',
        saver: saver,
        captureOverride: fakeCapture,
      ),
    );

    await tester.tap(
      find.byWidgetPredicate((w) => w is BBButton && w.label == 'Download QR'),
    );
    await tester.pump();
    await tester.pump();

    expect(saver.calls, 1);
    expect(find.text('QR code saved'), findsNothing);
    expect(
      find.text('Could not save the QR code. Please try again.'),
      findsNothing,
    );
  });

  testWidgets('a failed download shows the error message', (tester) async {
    final saver = _FakeSaver(QrImageSaveOutcome.failed);
    await _pump(
      tester,
      GetPaidLinkQr(
        url: url,
        openLabel: 'Open terminal',
        downloadFileName: 'pos-terminal-qr.png',
        saver: saver,
        captureOverride: fakeCapture,
      ),
    );

    await tester.tap(
      find.byWidgetPredicate((w) => w is BBButton && w.label == 'Download QR'),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Could not save the QR code. Please try again.'),
      findsOneWidget,
    );
    // Drain the 3s custom-snackbar auto-dismiss timer + exit animation.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
