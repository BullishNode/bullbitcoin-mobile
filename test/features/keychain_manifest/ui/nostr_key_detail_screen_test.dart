import 'dart:async';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_routes.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/widgets/nostr_nsec_reveal_dialog.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'nostr_key_fixtures.dart';

/// The reveal dialog turns the platform screenshot block on and off; stub the
/// plugin channel so the widget under test runs unchanged.
const _noScreenshotChannel = MethodChannel(
  'com.flutterplaza.no_screenshot_methods',
);

void main() {
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_noScreenshotChannel, (_) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return <String, Object?>{'text': clipboardText};
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_noScreenshotChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await locator.reset();
  });

  testWidgets('a user key shows its npub, never the hex public key', (
    tester,
  ) async {
    final record = userKeyRecord(description: 'long-form notes');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(userPublicKeyHex);
    expect(find.text('npub'), findsOneWidget);
    expect(find.textContaining(npub.substring(0, 8)), findsOneWidget);
    expect(find.textContaining(userPublicKeyHex), findsNothing);
    expect(find.textContaining('ababab'), findsNothing);
    expect(find.text('personal identity'), findsOneWidget);
    // A user key keeps showing what the user stored, not any generated copy.
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('long-form notes'), findsOneWidget);
    expect(find.text("128002'/1'/1'"), findsOneWidget);
  });

  testWidgets('a user key with no description omits the row', (tester) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Description'), findsNothing);
  });

  testWidgets('each system role explains itself in the description row', (
    tester,
  ) async {
    const expected = {
      "128002'/100'/1'": (
        'nostr_wallet_backup_key',
        'Identifies and signs your encrypted metadata backup so the app can '
            'find and restore it. Managed automatically — you never need to '
            'use this key yourself.',
      ),
      "128002'/101'/1'": (
        'nostr_bullnym_server_auth_key',
        'Authenticates this wallet to the Bull Bitcoin payment server for '
            'your Lightning address, invoices, Payment Page and Point of '
            'Sale. Managed automatically — you never need to use this key '
            'yourself.',
      ),
      "128002'/102'/1'": (
        'nostr_nip05_public_nym_verification_key',
        'Reserved for verifying your payment name publicly over Nostr. Not '
            'used by the app yet — it exists so a future version can enable '
            'verification without changing your keys.',
      ),
    };

    for (final entry in expected.entries) {
      final (reservationId, copy) = entry.value;
      final record = systemKeyRecord(
        path: entry.key,
        reservationId: reservationId,
      );
      await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

      expect(find.text('Description'), findsOneWidget);
      expect(find.text(copy), findsOneWidget, reason: 'for ${entry.key}');

      await locator.reset();
    }
  });

  testWidgets('localized system copy wins over a stored description', (
    tester,
  ) async {
    // Reserved rows are written with a null description by design; if one ever
    // carried stored text, the role copy must still be what the user reads.
    final record = systemKeyRecord(
      purpose: 'whatever was stored',
      description: 'stored description that must not surface',
    );
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Metadata backup'), findsOneWidget);
    expect(find.text('whatever was stored'), findsNothing);
    expect(find.text('stored description that must not surface'), findsNothing);
    expect(
      find.textContaining('Identifies and signs your encrypted metadata'),
      findsOneWidget,
    );
  });

  testWidgets('a user npub opens the shared address viewer with a QR', (
    tester,
  ) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(userPublicKeyHex);
    await tester.tap(find.textContaining(npub.substring(0, 8)));
    await tester.pumpAndSettle();

    // The Bitcoin-address viewer, reused: grouped text plus a QR and copy.
    expect(find.byType(QrDisplayWidget), findsOneWidget);
    expect(find.text('Tap to copy'), findsOneWidget);
    // An npub has no blockchain explorer, so those actions stay off.
    expect(find.textContaining('View in explorer'), findsNothing);
  });

  testWidgets('a user key offers edit and nsec reveal', (tester) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Show nsec'), findsOneWidget);
  });

  testWidgets('a system key hides its npub behind the exact warning', (
    tester,
  ) async {
    final record = systemKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(
      systemPublicKeyHex,
    );
    expect(find.text('Show npub'), findsOneWidget);
    expect(find.textContaining(npub.substring(0, 8)), findsNothing);

    await tester.tap(find.text('Show npub'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Do not use this npub for anything else. Viewing this npub is '
        'strictly for troubleshooting bugs. Do not share it with anyone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.textContaining(npub.substring(0, 8)), findsOneWidget);
    expect(find.textContaining(systemPublicKeyHex), findsNothing);
    expect(find.textContaining('cdcdcd'), findsNothing);
  });

  testWidgets('a system key offers no edit affordance', (tester) async {
    final record = systemKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Show nsec'), findsNothing);
  });

  testWidgets('a system key is named from its role, and never deletable', (
    tester,
  ) async {
    final record = systemKeyRecord(purpose: 'whatever was stored');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Metadata backup'), findsOneWidget);
    expect(find.text('whatever was stored'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.textContaining('Revoke'), findsNothing);
  });

  testWidgets('a user nsec reveal uses the standard sensitive warning', (
    tester,
  ) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DO NOT SHARE WITH ANYONE'), findsOneWidget);
  });

  testWidgets('confirming the warning actually reveals the nsec', (
    tester,
  ) async {
    final record = userKeyRecord();
    final facade = FakeKeychainManifestFacade(
      keys: [record],
      nsec: 'nsec1revealedsecret',
    );
    await _pump(tester, facade, record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(facade.revealCalls, [record.entryId]);
    expect(find.text('nsec 1rev eale dsec ret'), findsOneWidget);
    expect(find.byType(QrDisplayWidget), findsOneWidget);
    expect(find.text('Tap to copy'), findsOneWidget);
    expect(find.text('Copy nsec'), findsNothing);

    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Tap to copy'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('revealedsecret')), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'nsec copy and close actions remain reachable on a compact large-text view',
    (tester) async {
      final record = userKeyRecord();
      final facade = FakeKeychainManifestFacade(
        keys: [record],
        nsec: 'nsec1revealedsecret',
      );
      await _pump(tester, facade, record);

      await tester.tap(find.text('Show nsec'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('nostr_nsec_copy_action')), findsOneWidget);
      final close = find.text('Close');
      expect(close, findsOneWidget);
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(NostrNsecRevealDialog), findsNothing);
    },
  );

  testWidgets('copy clears the nsec and closes its reveal dialog', (
    tester,
  ) async {
    final record = userKeyRecord();
    final facade = FakeKeychainManifestFacade(
      keys: [record],
      nsec: 'nsec1revealedsecret',
    );
    await _pump(tester, facade, record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nostr_nsec_copy_action')));
    await tester.pumpAndSettle();

    expect(clipboardText, 'nsec1revealedsecret');
    expect(find.byType(NostrNsecRevealDialog), findsNothing);
    expect(find.text('nsec 1rev eale dsec ret'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'closing while screenshot protection is pending never derives the nsec',
    (tester) async {
      final protectionEnabled = Completer<Object?>();
      var protectionDisableCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_noScreenshotChannel, (call) {
            switch (call.method) {
              case 'screenshotOff':
                return protectionEnabled.future;
              case 'screenshotOn':
                protectionDisableCalls++;
                return Future<Object?>.value(true);
              default:
                return Future<Object?>.value(true);
            }
          });

      final record = userKeyRecord();
      final facade = FakeKeychainManifestFacade(
        keys: [record],
        nsec: 'nsec1mustneverbederived',
      );
      await _pump(tester, facade, record);

      await tester.tap(find.text('Show nsec'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I understand'));
      await tester.pump();

      expect(facade.revealCalls, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(find.byType(NostrNsecRevealDialog), findsNothing);
      expect(facade.revealCalls, isEmpty);
      expect(protectionDisableCalls, 1);

      protectionEnabled.complete(true);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(facade.revealCalls, isEmpty);
      expect(protectionDisableCalls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );

  testWidgets(
    'failed screenshot protection never derives or displays the nsec',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_noScreenshotChannel, (call) {
            if (call.method == 'screenshotOff') {
              return Future<Object?>.value(false);
            }
            return Future<Object?>.value(true);
          });

      final record = userKeyRecord();
      final facade = FakeKeychainManifestFacade(
        keys: [record],
        nsec: 'nsec1mustneverbederived',
      );
      await _pump(tester, facade, record);

      await tester.tap(find.text('Show nsec'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      expect(find.byType(NostrNsecRevealDialog), findsNothing);
      expect(facade.revealCalls, isEmpty);
      expect(find.textContaining('mustneverbederived'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('dismissing the warning without confirming reveals nothing', (
    tester,
  ) async {
    final record = userKeyRecord();
    final facade = FakeKeychainManifestFacade(keys: [record]);
    await _pump(tester, facade, record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();
    // Tap the barrier to dismiss the sheet instead of confirming.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(facade.revealCalls, isEmpty);
    expect(find.textContaining('nsec1'), findsNothing);
  });

  testWidgets('the edit affordance opens the form prefilled', (tester) async {
    final record = userKeyRecord(description: 'long-form notes');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Nostr key'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('nostr_key_name_field'))),
      isA<TextField>().having(
        (field) => field.controller?.text,
        'name',
        'personal identity',
      ),
    );
    expect(
      tester.widget<TextField>(
        find.byKey(const Key('nostr_key_description_field')),
      ),
      isA<TextField>().having(
        (field) => field.controller?.text,
        'description',
        'long-form notes',
      ),
    );
  });

  testWidgets('a completed edit refreshes the open detail screen', (
    tester,
  ) async {
    final record = userKeyRecord(description: 'old description');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('nostr_key_name_field')),
      'renamed identity',
    );
    await tester.enterText(
      find.byKey(const Key('nostr_key_description_field')),
      'new description',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('renamed identity'), findsOneWidget);
    expect(find.text('new description'), findsOneWidget);
    expect(find.text('old description'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
  KeychainManifestNostrKeyRecord record,
) async {
  locator.registerFactory<NostrNsecRevealPresenter>(
    () => NostrNsecRevealPresenter.forTesting(
      materialize: facade.revealNostrKeyNsec,
    ),
  );
  locator.registerFactory<NostrKeysCubit>(() => nostrKeysCubitForTest(facade));
  final router = GoRouter(
    initialLocation: '/settings/nostr-keys',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('settings-root')),
        routes: [KeychainManifestRoutes.nostrKeys],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  router.pushNamed(KeychainManifestRoutes.nostrKeyDetailName, extra: record);
  await tester.pumpAndSettle();
}
