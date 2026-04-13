import 'package:hive/hive.dart';

class LightningAddressSettingsDatasource {
  static const _boxName = 'lightning_address_settings';
  static const _autoSweepKey = 'auto_sweep';
  static const _hideWalletKey = 'hide_wallet';
  static const _nymHistoryKey = 'nym_history';

  Future<bool> getAutoSweep() async {
    final box = await Hive.openBox<bool>(_boxName);
    return box.get(_autoSweepKey, defaultValue: true)!;
  }

  Future<void> setAutoSweep(bool value) async {
    final box = await Hive.openBox<bool>(_boxName);
    await box.put(_autoSweepKey, value);
  }

  Future<bool> getHideWallet() async {
    final box = await Hive.openBox<bool>(_boxName);
    return box.get(_hideWalletKey, defaultValue: true)!;
  }

  Future<void> setHideWallet(bool value) async {
    final box = await Hive.openBox<bool>(_boxName);
    await box.put(_hideWalletKey, value);
  }

  Future<List<String>> getNymHistory() async {
    final box = await Hive.openBox<List>(_boxName);
    final history = box.get(_nymHistoryKey);
    if (history == null) return [];
    return history.cast<String>();
  }

  Future<void> addToNymHistory(String nym) async {
    final box = await Hive.openBox<List>(_boxName);
    final history = (box.get(_nymHistoryKey) ?? []).cast<String>();
    if (!history.contains(nym)) {
      history.add(nym);
      await box.put(_nymHistoryKey, history);
    }
  }
}
