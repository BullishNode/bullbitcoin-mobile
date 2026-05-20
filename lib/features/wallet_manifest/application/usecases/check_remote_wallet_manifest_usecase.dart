import 'dart:convert';

import 'package:bb_mobile/features/wallet_manifest/application/services/bip139_wallet_manifest_codec.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_remote_wallet_manifest_usecase.dart';

class CheckRemoteWalletManifestResult {
  final String manifestJson;
  final int accountCount;

  const CheckRemoteWalletManifestResult({
    required this.manifestJson,
    required this.accountCount,
  });
}

class CheckRemoteWalletManifestUsecase {
  final FetchRemoteWalletManifestUsecase _fetchRemoteManifest;
  final Bip139WalletManifestCodec _codec;

  const CheckRemoteWalletManifestUsecase({
    required FetchRemoteWalletManifestUsecase fetchRemoteManifest,
    Bip139WalletManifestCodec codec = const Bip139WalletManifestCodec(),
  }) : _fetchRemoteManifest = fetchRemoteManifest,
       _codec = codec;

  Future<CheckRemoteWalletManifestResult?> execute() async {
    final snapshot = await _fetchRemoteManifest.execute();
    if (snapshot == null) return null;

    return CheckRemoteWalletManifestResult(
      manifestJson: const JsonEncoder.withIndent(
        '  ',
      ).convert(_codec.toJson(snapshot)),
      accountCount: snapshot.accounts.length,
    );
  }
}
