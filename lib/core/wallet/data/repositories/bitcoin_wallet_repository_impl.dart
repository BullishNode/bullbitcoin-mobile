import 'dart:typed_data';

import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/seed/data/datasources/seed_datasource.dart';
import 'package:bb_mobile/core/seed/data/models/seed_model.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/wallet/data/datasources/wallet/impl/bdk_wallet_datasource.dart';
import 'package:bb_mobile/core/wallet/data/mappers/wallet_utxo_mapper.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_model.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_utxo.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/bitcoin_wallet_repository.dart';

class BitcoinWalletRepositoryImpl implements BitcoinWalletRepository {
  // TODO: move db to datasource and inject datasource here instead of db
  final SqliteDatabase _sqlite;
  final SeedDatasource _seed;
  final BdkWalletDatasource _bdkWallet;

  BitcoinWalletRepositoryImpl({
    required SqliteDatabase sqliteDatasource,
    required SeedDatasource seedDatasource,
    required BdkWalletDatasource bdkWalletDatasource,
  }) : _sqlite = sqliteDatasource,
       _seed = seedDatasource,
       _bdkWallet = bdkWalletDatasource;

  @override
  Future<String> buildPsbt({
    required String walletId,
    required String address,
    int? amountSat,
    required NetworkFee networkFee,
    bool? drain,
    List<({String txId, int vout})>? unspendable,
    List<WalletUtxo>? selected,
    bool? replaceByFee,
  }) async {
    final metadata =
        await _sqlite.managers.walletMetadatas
            .filter((e) => e.id(walletId))
            .getSingleOrNull();

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              externalDescriptor: metadata.externalPublicDescriptor,
              internalDescriptor: metadata.internalPublicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;
    final psbt = await _bdkWallet.buildPsbt(
      wallet: wallet,
      address: address,
      amountSat: amountSat,
      networkFee: networkFee,
      drain: drain,
      unspendable: unspendable,
      selected:
          selected?.map((utxo) => WalletUtxoMapper.fromEntity(utxo)).toList(),
      replaceByFee: replaceByFee ?? false,
    );

    return psbt;
  }

  @override
  Future<String> signPsbt(String psbt, {required String walletId}) async {
    final metadata =
        await _sqlite.managers.walletMetadatas
            .filter((e) => e.id(walletId))
            .getSingleOrNull();

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final seed =
        await _seed.get(metadata.masterFingerprint) as MnemonicSeedModel;
    final mnemonic = seed.mnemonicWords.join(' ');

    final wallet =
        WalletModel.privateBdk(
              id: metadata.id,
              mnemonic: mnemonic,
              passphrase: seed.passphrase,
              scriptType: ScriptType.fromName(metadata.scriptType),
              isTestnet: metadata.isTestnet,
            )
            as PrivateBdkWalletModel;

    final signedPsbt = await _bdkWallet.signPsbt(wallet: wallet, psbt);

    return signedPsbt;
  }

  @override
  Future<bool> isScriptOfWallet({
    required String walletId,
    required Uint8List script,
  }) async {
    final metadata =
        await _sqlite.managers.walletMetadatas
            .filter((e) => e.id(walletId))
            .getSingleOrNull();

    if (metadata == null) {
      throw Exception('Wallet metadata not found for walletId: $walletId');
    }

    if (!metadata.isBitcoin) {
      throw Exception('Wallet $walletId is not a Bitcoin wallet');
    }

    final wallet =
        WalletModel.publicBdk(
              externalDescriptor: metadata.externalPublicDescriptor,
              internalDescriptor: metadata.internalPublicDescriptor,
              isTestnet: metadata.isTestnet,
              id: metadata.id,
            )
            as PublicBdkWalletModel;

    final isFromWallet = await _bdkWallet.isMine(script, wallet: wallet);

    return isFromWallet;
  }

  @override
  Future<int> getTxSize({required String psbt}) async {
    final txSize = await _bdkWallet.decodeTxSize(psbt);
    return txSize;
  }
}
