import 'package:bb_mobile/features/lightning_address/domain/primitives/nostr_publish_status.dart';
import 'package:hive/hive.dart';

class LightningAddressSettingsDatasource {
  static const _boxName = 'lightning_address_settings';
  static const _nostrPublishOutcomeKey = 'nostr_publish_outcome';

  Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(_boxName);

  Future<NostrPublishStatus?> getNostrPublishOutcome() async {
    final box = await _openBox();
    final raw = box.get(_nostrPublishOutcomeKey) as String?;
    if (raw == null) return null;
    return switch (raw) {
      'success' => NostrPublishStatus.success,
      'failed' => NostrPublishStatus.failed,
      _ => null,
    };
  }

  Future<void> setNostrPublishOutcome(NostrPublishStatus outcome) async {
    assert(
      outcome == NostrPublishStatus.success ||
          outcome == NostrPublishStatus.failed,
      'only success/failed are persistable; none/pending are transient',
    );
    final box = await _openBox();
    await box.put(_nostrPublishOutcomeKey, outcome.name);
  }

  Future<void> clearNostrPublishOutcome() async {
    final box = await _openBox();
    await box.delete(_nostrPublishOutcomeKey);
  }
}
