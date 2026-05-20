import 'dart:async';

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/audit_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/check_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/get_wallet_manifest_public_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/save_wallet_manifest_payload_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_cubit.dart';
import 'package:bb_mobile/features/wallet_manifest/ui/wallet_manifest_settings_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWalletManifestPublicKeyUsecase extends Mock
    implements GetWalletManifestPublicKeyUsecase {}

class _MockCheckRemoteWalletManifestUsecase extends Mock
    implements CheckRemoteWalletManifestUsecase {}

class _MockPublishLocalWalletManifestUsecase extends Mock
    implements PublishLocalWalletManifestUsecase {}

class _MockRestoreRemoteWalletManifestUsecase extends Mock
    implements RestoreRemoteWalletManifestUsecase {}

class _MockSaveWalletManifestPayloadUsecase extends Mock
    implements SaveWalletManifestPayloadUsecase {}

class _MockAuditRemoteWalletManifestUsecase extends Mock
    implements AuditRemoteWalletManifestUsecase {}

void main() {
  testWidgets(
    'shows manifest npub, remote check, manual publish, and recovery actions',
    (tester) async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      when(
        () => getPublicKey.execute(),
      ).thenAnswer((_) async => 'npub1manifest');
      final cubit = _cubit(getPublicKey, checkRemoteManifest);
      addTearDown(cubit.close);
      await cubit.load();

      await tester.pumpWidget(_harness(cubit));

      expect(find.text('Wallet Manifest'), findsOneWidget);
      expect(find.text('Manifest npub'), findsOneWidget);
      expect(
        find.text(
          'This key is used to find encrypted wallet manifests. Sharing it can link your wallet manifest metadata.',
        ),
        findsOneWidget,
      );
      expect(find.text('npub1manifest'), findsOneWidget);
      expect(find.text('Root fingerprint'), findsNothing);
      expect(find.text('Public key hex'), findsNothing);
      expect(find.text('Refresh'), findsNothing);
      expect(find.text('Check wallet manifest'), findsOneWidget);
      expect(find.text('Audit wallet manifest'), findsOneWidget);
      _expectTextAbove(
        tester,
        'Check wallet manifest',
        'Audit wallet manifest',
      );

      await _scrollToPublishWalletManifest(tester);
      expect(find.text('Replace wallet manifest'), findsOneWidget);
      expect(
        find.text(
          'Publishes a full replacement wallet manifest for the wallets recorded on this device. This does not restore wallets. Use only from a device that has the wallets you want recoverable.',
        ),
        findsOneWidget,
      );

      await _scrollToRestoreWalletManifest(tester);
      expect(find.text('Recover from wallet manifest'), findsOneWidget);
      _expectTextAbove(
        tester,
        'Replace wallet manifest',
        'Recover from wallet manifest',
      );
    },
  );

  testWidgets(
    'shows a generic retry state without raw errors or empty fields',
    (tester) async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      when(
        () => getPublicKey.execute(),
      ).thenThrow(Exception('raw derivation failure'));
      final cubit = _cubit(getPublicKey, checkRemoteManifest);
      addTearDown(cubit.close);
      await cubit.load();

      await tester.pumpWidget(_harness(cubit));

      expect(
        find.text('Unable to derive the wallet manifest npub.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('raw derivation failure'), findsNothing);
      expect(find.text('Manifest npub'), findsNothing);
    },
  );

  testWidgets('fetches and shows the remote wallet manifest only after tap', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{\n  "accounts": []\n}',
        accountCount: 0,
        createdAt: 1710000000,
      ),
    );
    final cubit = _cubit(getPublicKey, checkRemoteManifest);
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));

    expect(find.text('Remote wallet manifest'), findsNothing);

    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Remote wallet manifest'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Remote wallet manifest'), findsOneWidget);
    expect(find.text('No wallets in this manifest'), findsOneWidget);
    expect(find.textContaining('Created: '), findsOneWidget);
    expect(
      find.text('This manifest may contain wallet metadata. Keep it private.'),
      findsOneWidget,
    );
    expect(find.textContaining('"accounts"'), findsOneWidget);
    expect(find.text('Save wallet manifest'), findsOneWidget);
    expect(
      find.text(
        'Saves the fetched manifest to a file you choose. It may contain wallet metadata; store it privately.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('saves the fetched remote wallet manifest after tap', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{\n  "accounts": []\n}',
        accountCount: 0,
        createdAt: 1710000000,
      ),
    );
    when(
      () => saveWalletManifestPayload.execute(
        manifestJson: '{\n  "accounts": []\n}',
      ),
    ).thenAnswer((_) async => true);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();
    await tester.pump();
    await _scrollToSaveWalletManifest(tester);
    await tester.tap(find.text('Save wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Wallet manifest saved.'), findsOneWidget);
    verify(
      () => saveWalletManifestPayload.execute(
        manifestJson: '{\n  "accounts": []\n}',
      ),
    ).called(1);
  });

  testWidgets('shows cancelled and failed fetched manifest save states', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"accounts":[]}',
        accountCount: 0,
        createdAt: 1710000000,
      ),
    );
    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenAnswer((_) async => false);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();
    await tester.pump();
    await _scrollToSaveWalletManifest(tester);
    await tester.tap(find.text('Save wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Wallet manifest save cancelled.'), findsOneWidget);

    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenThrow(Exception('disk details'));
    await _scrollToSaveWalletManifest(tester);
    await tester.tap(find.text('Save wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Unable to save the wallet manifest.'), findsOneWidget);
    expect(find.textContaining('disk details'), findsNothing);
  });

  testWidgets('audits the latest remote wallet manifest after tap', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final auditRemoteWalletManifest = _MockAuditRemoteWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => auditRemoteWalletManifest.execute()).thenAnswer(
      (_) async => const AuditRemoteWalletManifestResult(
        matchingCount: 2,
        missingLocalCount: 0,
        missingRemoteCount: 0,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
      auditRemoteWalletManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _scrollToAuditWalletManifest(tester);
    await tester.tap(find.text('Audit wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Manifest wallet list matches this device. 2 wallet identities matched.',
      ),
      findsOneWidget,
    );
    verify(() => auditRemoteWalletManifest.execute()).called(1);
  });

  testWidgets('shows remote manifest audit missing, failed, and differs states', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final auditRemoteWalletManifest = _MockAuditRemoteWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => auditRemoteWalletManifest.execute()).thenAnswer(
      (_) async => const AuditRemoteWalletManifestResult(
        remoteManifestFound: false,
        matchingCount: 0,
        missingLocalCount: 0,
        missingRemoteCount: 2,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
      auditRemoteWalletManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _scrollToAuditWalletManifest(tester);
    await tester.tap(find.text('Audit wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'No readable wallet manifest was found on Nostr. 2 local manifest-recorded wallet identities are missing from the remote manifest.',
      ),
      findsOneWidget,
    );

    when(
      () => auditRemoteWalletManifest.execute(),
    ).thenThrow(Exception('audit details'));
    await _scrollToAuditWalletManifest(tester);
    await tester.tap(find.text('Audit wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Unable to audit the wallet manifest.'), findsOneWidget);
    expect(find.textContaining('audit details'), findsNothing);

    when(() => auditRemoteWalletManifest.execute()).thenAnswer(
      (_) async => const AuditRemoteWalletManifestResult(
        matchingCount: 1,
        missingLocalCount: 2,
        missingRemoteCount: 3,
      ),
    );
    await _scrollToAuditWalletManifest(tester);
    await tester.tap(find.text('Audit wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Manifest wallet list differs from this device. 1 wallet identity matched. 2 manifest wallet identities missing from this device. 3 local manifest-recorded wallet identities missing from the remote manifest. Recover if manifest wallets are missing from this device. Replace only if this device has the wallets that should be recoverable.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows loading state while checking the remote manifest', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final completer = Completer<CheckRemoteWalletManifestResult?>();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(
      () => checkRemoteManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(getPublicKey, checkRemoteManifest);
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();

    completer.complete(null);
    await tester.pump();
    await tester.pump();

    verify(() => checkRemoteManifest.execute()).called(1);
  });

  testWidgets('shows missing remote manifest state', (tester) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => checkRemoteManifest.execute()).thenAnswer((_) async => null);
    final cubit = _cubit(getPublicKey, checkRemoteManifest);
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('No readable wallet manifest was found on Nostr.'),
      findsOneWidget,
    );
  });

  testWidgets('shows remote manifest fetch failure state', (tester) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(
      () => checkRemoteManifest.execute(),
    ).thenThrow(Exception('relay details'));
    final cubit = _cubit(getPublicKey, checkRemoteManifest);
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await tester.tap(find.text('Check wallet manifest'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Unable to fetch the wallet manifest from Nostr.'),
      findsOneWidget,
    );
    expect(find.textContaining('relay details'), findsNothing);
  });

  testWidgets('publishes the local wallet manifest after tap', (tester) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 2);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));

    expect(
      find.text('Published a wallet manifest with 2 wallets.'),
      findsNothing,
    );

    await _confirmPublish(tester);

    expect(
      find.text('Published a wallet manifest with 2 wallets.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Latest replacement from this device: '),
      findsOneWidget,
    );
    verify(() => publishLocalManifest.execute()).called(1);
  });

  testWidgets('shows loading state while publishing the local manifest', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final completer = Completer<int>();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(
      () => publishLocalManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _confirmPublish(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Replace wallet manifest'));
    await tester.pump();

    completer.complete(1);
    await tester.pump();
    await tester.pump();

    verify(() => publishLocalManifest.execute()).called(1);
  });

  testWidgets('blocks app bar and system back while publishing', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final completer = Completer<int>();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(
      () => publishLocalManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _confirmPublish(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(find.text('Wallet Manifest'), findsOneWidget);
    expect(
      find.text(
        'Wait for wallet manifest publishing or recovery to finish before leaving.',
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Wallet Manifest'), findsOneWidget);
    expect(
      find.text(
        'Wait for wallet manifest publishing or recovery to finish before leaving.',
      ),
      findsOneWidget,
    );

    completer.complete(1);
    await tester.pump();
  });

  testWidgets('shows local manifest publish failure state', (tester) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(
      () => publishLocalManifest.execute(),
    ).thenThrow(Exception('relay details'));
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _confirmPublish(tester);

    expect(
      find.text('Unable to publish the wallet manifest to Nostr.'),
      findsOneWidget,
    );
    expect(find.textContaining('relay details'), findsNothing);
  });

  testWidgets('requires confirmation before publishing the local manifest', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _scrollToPublishWalletManifest(tester);
    await tester.tap(find.text('Replace wallet manifest'));
    await tester.pumpAndSettle();

    expect(find.text('Replace wallet manifest?'), findsOneWidget);
    expect(
      find.text(
        'This will replace the latest wallet manifest on Nostr with the wallets recorded on this device. It does not restore wallets. Only use this if this device has the wallets you want recoverable from the manifest.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => publishLocalManifest.execute());
  });

  testWidgets(
    'recovers wallets from the remote wallet manifest after confirm',
    (tester) async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
      final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
      when(
        () => getPublicKey.execute(),
      ).thenAnswer((_) async => 'npub1manifest');
      when(() => restoreRemoteManifest.execute()).thenAnswer(
        (_) async => const RestoreRemoteWalletManifestResult(
          restoredCount: 2,
          alreadyPresentCount: 1,
          skippedCount: 0,
          failedCount: 0,
          walletStateMayHaveChanged: true,
        ),
      );
      final cubit = _cubit(
        getPublicKey,
        checkRemoteManifest,
        publishLocalManifest,
        restoreRemoteManifest,
      );
      addTearDown(cubit.close);
      await cubit.load();
      var walletRefreshCount = 0;

      await tester.pumpWidget(
        _harness(cubit, onWalletsRestored: () => walletRefreshCount += 1),
      );
      await _confirmRestore(tester);

      await tester.scrollUntilVisible(
        find.text('2 wallets recreated. 1 wallet was already on this device.'),
        200,
      );
      expect(
        find.text('2 wallets recreated. 1 wallet was already on this device.'),
        findsOneWidget,
      );
      verify(() => restoreRemoteManifest.execute()).called(1);
      expect(walletRefreshCount, 1);
    },
  );

  testWidgets('blocks app bar and system back while recovering wallets', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final completer = Completer<RestoreRemoteWalletManifestResult?>();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(
      () => restoreRemoteManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _confirmRestore(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(find.text('Wallet Manifest'), findsOneWidget);
    expect(
      find.text(
        'Wait for wallet manifest publishing or recovery to finish before leaving.',
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Wallet Manifest'), findsOneWidget);
    expect(
      find.text(
        'Wait for wallet manifest publishing or recovery to finish before leaving.',
      ),
      findsOneWidget,
    );

    completer.complete(
      const RestoreRemoteWalletManifestResult(
        restoredCount: 0,
        alreadyPresentCount: 0,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    await tester.pump();
  });

  testWidgets('shows remote manifest recovery missing and failure states', (
    tester,
  ) async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenAnswer((_) async => 'npub1manifest');
    when(() => restoreRemoteManifest.execute()).thenAnswer((_) async => null);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_harness(cubit));
    await _confirmRestore(tester);

    await tester.scrollUntilVisible(
      find.text('No readable wallet manifest was found on Nostr.'),
      200,
    );
    expect(
      find.text('No readable wallet manifest was found on Nostr.'),
      findsOneWidget,
    );

    when(
      () => restoreRemoteManifest.execute(),
    ).thenThrow(Exception('restore details'));
    await _confirmRestore(tester);

    await tester.scrollUntilVisible(
      find.text('Unable to recover wallets from the wallet manifest.'),
      200,
    );
    expect(
      find.text('Unable to recover wallets from the wallet manifest.'),
      findsOneWidget,
    );
    expect(find.textContaining('restore details'), findsNothing);
  });
}

WalletManifestSettingsCubit _cubit(
  GetWalletManifestPublicKeyUsecase getPublicKey,
  CheckRemoteWalletManifestUsecase checkRemoteManifest, [
  PublishLocalWalletManifestUsecase? publishLocalManifest,
  RestoreRemoteWalletManifestUsecase? restoreRemoteManifest,
  SaveWalletManifestPayloadUsecase? saveWalletManifestPayload,
  AuditRemoteWalletManifestUsecase? auditRemoteWalletManifest,
]) {
  return WalletManifestSettingsCubit(
    getPublicKey: getPublicKey,
    checkRemoteManifest: checkRemoteManifest,
    publishLocalManifest:
        publishLocalManifest ?? _MockPublishLocalWalletManifestUsecase(),
    restoreRemoteManifest:
        restoreRemoteManifest ?? _MockRestoreRemoteWalletManifestUsecase(),
    saveWalletManifestPayload:
        saveWalletManifestPayload ?? _MockSaveWalletManifestPayloadUsecase(),
    auditRemoteWalletManifest:
        auditRemoteWalletManifest ?? _MockAuditRemoteWalletManifestUsecase(),
  );
}

Widget _harness(
  WalletManifestSettingsCubit cubit, {
  VoidCallback? onWalletsRestored,
}) {
  return BlocProvider.value(
    value: cubit,
    child: MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WalletManifestSettingsScreen(onWalletsRestored: onWalletsRestored),
    ),
  );
}

void _expectTextAbove(WidgetTester tester, String upperText, String lowerText) {
  final upperTop = tester.getTopLeft(find.text(upperText)).dy;
  final lowerTop = tester.getTopLeft(find.text(lowerText)).dy;

  expect(upperTop, lessThan(lowerTop));
}

Future<void> _confirmPublish(WidgetTester tester) async {
  await _scrollToPublishWalletManifest(tester);
  await tester.tap(find.text('Replace wallet manifest'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Replace manifest'));
  await tester.pump();
}

Future<void> _confirmRestore(WidgetTester tester) async {
  await _scrollToRestoreWalletManifest(tester);
  await tester.tap(find.text('Recover from wallet manifest'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Recover wallets'));
  await tester.pump();
  await tester.pump();
}

Future<void> _scrollToPublishWalletManifest(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Replace wallet manifest'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _scrollToRestoreWalletManifest(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Recover from wallet manifest'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _scrollToSaveWalletManifest(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Save wallet manifest'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _scrollToAuditWalletManifest(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Audit wallet manifest'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}
