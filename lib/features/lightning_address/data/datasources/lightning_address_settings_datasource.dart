import 'package:hive/hive.dart';

class LightningAddressSettingsDatasource {
  static const _boxName = 'lightning_address_settings';
  static const _autoSweepKey = 'auto_sweep';
  static const _hideWalletKey = 'hide_wallet';

  Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(_boxName);

  Future<bool> getAutoSweep() async {
    final box = await _openBox();
    return box.get(_autoSweepKey, defaultValue: true) as bool;
  }

  Future<void> setAutoSweep(bool value) async {
    final box = await _openBox();
    await box.put(_autoSweepKey, value);
  }

  Future<bool> getHideWallet() async {
    final box = await _openBox();
    return box.get(_hideWalletKey, defaultValue: true) as bool;
  }

  Future<void> setHideWallet(bool value) async {
    final box = await _openBox();
    await box.put(_hideWalletKey, value);
  }

}
