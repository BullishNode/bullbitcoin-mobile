import 'dart:convert';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/wallet_backup/data/bullnym_wallet_backup_remote_repository.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_encryption.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  late _MockBullnymFacade bullnym;
  late BullnymWalletBackupRemoteRepository repository;

  setUpAll(() {
    registerFallbackValue(
      BullnymAuthSigner(npubHex: '11' * 32, signHashHex: (_) => '22' * 64),
    );
    registerFallbackValue(BullnymBackupStream.walletBackup);
    registerFallbackValue(BullnymBackupHead.absent(generation: 0, etag: null));
    registerFallbackValue(
      AuthenticatedBackupCiphertext(base64.encode(List<int>.filled(64, 0))),
    );
  });

  setUp(() {
    bullnym = _MockBullnymFacade();
    repository = BullnymWalletBackupRemoteRepository(bullnym);
  });

  test('maps the unified Bullnym head into the wallet backup domain', () async {
    final ciphertext = AuthenticatedBackupCiphertext(
      base64.encode(List<int>.filled(64, 7)),
    );
    when(
      () => bullnym.fetchBackup(
        signer: any(named: 'signer'),
        stream: BullnymBackupStream.walletBackup,
      ),
    ).thenAnswer(
      (_) async => BullnymBackupHead.present(
        generation: 3,
        etag: '33' * 32,
        ciphertext: ciphertext,
        ciphertextSha256: '44' * 32,
        updatedAtSecs: 20,
      ),
    );

    final result = await repository.fetch(_signer());

    final head =
        (result as Ok<WalletBackupRemoteHead, WalletBackupFailure>).value;
    expect(head.generation, 3);
    expect(head.etag, '33' * 32);
    expect(head.ciphertext!.value, ciphertext.value);
    verify(
      () => bullnym.fetchBackup(
        signer: any(named: 'signer'),
        stream: BullnymBackupStream.walletBackup,
      ),
    ).called(1);
  });

  test('accepts applied and exact-retry store receipts identically', () async {
    final current = WalletBackupRemoteHead.absent(generation: 0, etag: null);
    final ciphertext = WalletBackupCiphertext(
      base64.encode(List<int>.filled(64, 7)),
    );
    when(
      () => bullnym.storeBackup(
        signer: any(named: 'signer'),
        stream: BullnymBackupStream.walletBackup,
        currentHead: any(named: 'currentHead'),
        ciphertext: any(named: 'ciphertext'),
      ),
    ).thenAnswer(
      (_) async => BullnymBackupStoreReceipt(generation: 1, etag: '11' * 32),
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      final result = await repository.store(
        signer: _signer(),
        current: current,
        ciphertext: ciphertext,
      );
      final checkpoint = _requireValue(result);
      expect(checkpoint.generation, 1);
      expect(checkpoint.etag, '11' * 32);
    }

    verify(
      () => bullnym.storeBackup(
        signer: any(named: 'signer'),
        stream: BullnymBackupStream.walletBackup,
        currentHead: any(named: 'currentHead'),
        ciphertext: any(named: 'ciphertext'),
      ),
    ).called(2);
  });

  test('maps Bullnym head conflicts into the typed retry signal', () async {
    when(
      () => bullnym.storeBackup(
        signer: any(named: 'signer'),
        stream: BullnymBackupStream.walletBackup,
        currentHead: any(named: 'currentHead'),
        ciphertext: any(named: 'ciphertext'),
      ),
    ).thenThrow(
      const BullnymException.serverRejectedRequest(
        code: 'BackupHeadConflict',
        diagnosticReason: 'conflict',
        statusCode: 409,
        retryable: true,
      ),
    );

    final result = await repository.store(
      signer: _signer(),
      current: WalletBackupRemoteHead.absent(generation: 0, etag: null),
      ciphertext: WalletBackupCiphertext(
        base64.encode(List<int>.filled(64, 7)),
      ),
    );

    expect(_requireFailure(result), isA<WalletBackupHeadConflictFailure>());
  });

  test('maps conditional delete receipts and absent no-ops', () async {
    final absent = WalletBackupRemoteHead.absent(generation: 0, etag: null);
    final present = WalletBackupRemoteHead.present(
      generation: 1,
      etag: '11' * 32,
      ciphertext: WalletBackupCiphertext(
        base64.encode(List<int>.filled(64, 7)),
      ),
      ciphertextSha256: '22' * 32,
      updatedAtSecs: 20,
    );
    when(
      () => bullnym.deleteBackup(
        signer: any(named: 'signer'),
        stream: BullnymBackupStream.walletBackup,
        currentHead: any(named: 'currentHead'),
      ),
    ).thenAnswer((invocation) async {
      final head = invocation.namedArguments[#currentHead] as BullnymBackupHead;
      return head.found
          ? BullnymBackupDeleteReceipt(generation: 2, etag: '33' * 32)
          : null;
    });

    final absentResult = await repository.delete(
      signer: _signer(),
      current: absent,
    );
    final presentResult = await repository.delete(
      signer: _signer(),
      current: present,
    );

    expect(_requireValue(absentResult), isNull);
    expect(_requireValue(presentResult)!.generation, 2);
  });
}

final class _MockBullnymFacade extends Mock implements BullnymFacade {}

WalletBackupSigner _signer() =>
    WalletBackupSigner(publicKeyHex: '11' * 32, signHashHex: (_) => '22' * 64);

T _requireValue<T>(Result<T, WalletBackupFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => fail('Expected Ok, got ${failure.runtimeType}'),
};

WalletBackupFailure _requireFailure<T>(Result<T, WalletBackupFailure> result) =>
    switch (result) {
      Ok() => fail('Expected Err, got Ok'),
      Err(:final failure) => failure,
    };
