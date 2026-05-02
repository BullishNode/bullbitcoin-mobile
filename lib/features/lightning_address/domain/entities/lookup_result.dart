import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';

sealed class LookupResult {
  const LookupResult();
  NymQuota get quota;
}

class ActiveLookupResult extends LookupResult {
  final String nym;
  @override
  final NymQuota quota;
  const ActiveLookupResult({required this.nym, required this.quota});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveLookupResult && other.nym == nym && other.quota == quota;

  @override
  int get hashCode => Object.hash(runtimeType, nym, quota);
}

class InactiveLookupResult extends LookupResult {
  final String nym;
  @override
  final NymQuota quota;
  const InactiveLookupResult({required this.nym, required this.quota});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InactiveLookupResult && other.nym == nym && other.quota == quota;

  @override
  int get hashCode => Object.hash(runtimeType, nym, quota);
}
