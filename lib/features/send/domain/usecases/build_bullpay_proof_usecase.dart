import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_utxo.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_utxos_usecase.dart';
import 'package:bb_mobile/features/send/domain/errors/bullpay_proof_error.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bitcoin_base/bitcoin_base.dart' show ECPrivate;
import 'package:crypto/crypto.dart';

const String kBullpayMessageTag = 'bullpay-lnurlp-v1';

// The server no longer enforces a minimum proof value. We still skip truly-dust
// UTXOs (< 100 sat) because spending them later is anti-economic on Liquid.
const int kBullpayMinProofValueSat = 100;

class BullpayProofParams {
  final String outpoint;
  final String pubkeyHex;
  final String sigDerHex;

  const BullpayProofParams({
    required this.outpoint,
    required this.pubkeyHex,
    required this.sigDerHex,
  });
}

class BuildBullpayProofUsecase {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final GetWalletUtxosUsecase _getWalletUtxosUsecase;

  BuildBullpayProofUsecase({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required GetWalletUtxosUsecase getWalletUtxosUsecase,
  })  : _walletRepository = walletRepository,
        _seedRepository = seedRepository,
        _getWalletUtxosUsecase = getWalletUtxosUsecase;

  Future<BullpayProofParams> execute({
    required String walletId,
    required String nym,
  }) async {
    try {
      return await _build(walletId: walletId, nym: nym);
    } on BullpayProofError {
      rethrow;
    } catch (e, st) {
      log.severe(error: e, trace: st);
      throw const BullpayProofInternal('UnexpectedError');
    }
  }

  Future<BullpayProofParams> _build({
    required String walletId,
    required String nym,
  }) async {
    final wallet = await _walletRepository.getWallet(walletId);
    if (wallet == null || !wallet.isLiquid) {
      throw const BullpayProofRequiresProof();
    }

    final lbtcAssetId = wallet.isTestnet
        ? AssetConstants.lbtcTestnet
        : AssetConstants.lbtcMainnet;
    final minSat = BigInt.from(kBullpayMinProofValueSat);

    final utxos = await _getWalletUtxosUsecase.execute(walletId: walletId);
    final candidates = utxos
        .whereType<LiquidWalletUtxo>()
        .where((u) =>
            u.assetIdHex == lbtcAssetId &&
            u.amountSat >= minSat &&
            u.addressIndex != null)
        .toList()
      ..sort((a, b) => a.amountSat.compareTo(b.amountSat));

    if (candidates.isEmpty) {
      throw const BullpayProofRequiresProof();
    }

    final utxo = candidates.first;
    final addressIndex = utxo.addressIndex!;

    final scriptBytes = _hexToBytes(utxo.scriptPubkey);
    if (scriptBytes.length != 22 ||
        scriptBytes[0] != 0x00 ||
        scriptBytes[1] != 0x14) {
      throw const BullpayProofInternal('PubkeyUtxoMismatch');
    }
    final scriptHash = scriptBytes.sublist(2);

    final seed = await _seedRepository.get(wallet.masterFingerprint);
    final root = bip32.Bip32Keys.fromSeed(seed.bytes);
    final extKey =
        root.derivePath('${wallet.derivationPath}/0/$addressIndex');
    final intKey =
        root.derivePath('${wallet.derivationPath}/1/$addressIndex');

    final Uint8List signingPriv;
    final Uint8List signingPub;
    if (_bytesEqual(scriptHash, extKey.identifier)) {
      signingPriv = extKey.private!;
      signingPub = extKey.public;
      _zeroize(intKey.private);
    } else if (_bytesEqual(scriptHash, intKey.identifier)) {
      signingPriv = intKey.private!;
      signingPub = intKey.public;
      _zeroize(extKey.private);
    } else {
      _zeroize(extKey.private);
      _zeroize(intKey.private);
      throw const BullpayProofInternal('PubkeyUtxoMismatch');
    }

    final outpoint = '${utxo.txId}:${utxo.vout}';
    final digest = sha256.convert(<int>[
      ...utf8.encode(kBullpayMessageTag),
      ...utf8.encode(nym),
      ...utf8.encode(outpoint),
    ]).bytes;

    final sigDerHex =
        ECPrivate.fromBytes(signingPriv).signECDSA(digest, sighash: null);
    final pubkeyHex = _bytesToHex(signingPub);

    _zeroize(signingPriv);

    return BullpayProofParams(
      outpoint: outpoint,
      pubkeyHex: pubkeyHex,
      sigDerHex: sigDerHex,
    );
  }
}

void _zeroize(Uint8List? bytes) {
  if (bytes == null) return;
  bytes.fillRange(0, bytes.length, 0);
}

Uint8List _hexToBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

String _bytesToHex(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
