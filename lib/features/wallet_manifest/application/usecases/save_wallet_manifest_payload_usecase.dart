import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_file_saver.dart';

class SaveWalletManifestPayloadUsecase {
  static const filename = 'wallet-manifest.json';

  final WalletManifestFileSaver fileSaver;

  SaveWalletManifestPayloadUsecase({required this.fileSaver});

  Future<bool> execute({required String manifestJson}) async {
    return fileSaver.save(content: manifestJson, filename: filename);
  }
}
