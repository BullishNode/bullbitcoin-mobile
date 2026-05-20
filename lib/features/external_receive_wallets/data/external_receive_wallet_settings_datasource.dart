import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:hive/hive.dart';

class ExternalReceiveWalletSettingsDatasource {
  static const _boxName = 'external_receive_wallet_settings';

  Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(_boxName);

  Future<bool> getAutoSweepForAccount(
    ExternalReceiveWalletAccountKey accountKey,
  ) async {
    final box = await _openBox();
    return box.get(
          _autoSweepKey(accountKey),
          defaultValue: _defaultAutoSweep(accountKey),
        )
        as bool;
  }

  Future<void> setAutoSweepForAccount(
    ExternalReceiveWalletAccountKey accountKey,
    bool value,
  ) async {
    final box = await _openBox();
    await box.put(_autoSweepKey(accountKey), value);
  }

  Future<bool> getHideWalletForAccount(
    ExternalReceiveWalletAccountKey accountKey,
  ) async {
    final box = await _openBox();
    return box.get(
          _hideWalletKey(accountKey),
          defaultValue: _defaultHideWallet(accountKey),
        )
        as bool;
  }

  Future<void> setHideWalletForAccount(
    ExternalReceiveWalletAccountKey accountKey,
    bool value,
  ) async {
    final box = await _openBox();
    await box.put(_hideWalletKey(accountKey), value);
  }

  String _autoSweepKey(ExternalReceiveWalletAccountKey accountKey) {
    return '${accountKey.purpose.name}_${accountKey.settingsNetworkKey}_auto_sweep';
  }

  String _hideWalletKey(ExternalReceiveWalletAccountKey accountKey) {
    return '${accountKey.purpose.name}_${accountKey.settingsNetworkKey}_hide_wallet';
  }

  bool _defaultAutoSweep(ExternalReceiveWalletAccountKey accountKey) {
    return accountKey.network.isLiquid;
  }

  bool _defaultHideWallet(ExternalReceiveWalletAccountKey accountKey) {
    return accountKey.network.isLiquid;
  }
}
