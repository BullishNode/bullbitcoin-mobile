import 'dart:io';

import 'package:bb_mobile/features/external_receive_wallets/data/external_receive_wallet_settings_datasource.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory hiveDir;
  late ExternalReceiveWalletSettingsDatasource datasource;

  setUp(() {
    hiveDir = Directory.systemTemp.createTempSync(
      'external_receive_wallet_settings_test',
    );
    Hive.init(hiveDir.path);
    datasource = ExternalReceiveWalletSettingsDatasource();
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  test('defaults Liquid settings on and Bitcoin settings off', () async {
    final liquid = ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
      isTestnet: false,
    );
    final bitcoin = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
      isTestnet: false,
    );

    expect(await datasource.getAutoSweepForAccount(liquid), isTrue);
    expect(await datasource.getHideWalletForAccount(liquid), isTrue);
    expect(await datasource.getAutoSweepForAccount(bitcoin), isFalse);
    expect(await datasource.getHideWalletForAccount(bitcoin), isFalse);

    await datasource.setAutoSweepForAccount(bitcoin, true);

    expect(await datasource.getAutoSweepForAccount(bitcoin), isTrue);
  });

  test('purpose compatibility methods use Liquid settings', () async {
    await datasource.setAutoSweepForAccount(
      ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(isTestnet: false),
      false,
    );

    expect(
      await datasource.getAutoSweepForAccount(
        ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(isTestnet: false),
      ),
      isFalse,
    );
  });
}
