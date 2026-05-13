import 'package:bb_mobile/features/lightning_address/domain/value_objects/nym_quota.dart';
import 'package:bb_mobile/features/lightning_address/domain/value_objects/previous_nym.dart';

sealed class LookupResult {
  const LookupResult();
  NymQuota get quota;
  List<PreviousNym> get previousNyms;
}

class ActiveLookupResult extends LookupResult {
  final String nym;
  @override
  final NymQuota quota;
  @override
  final List<PreviousNym> previousNyms;
  const ActiveLookupResult({
    required this.nym,
    required this.quota,
    this.previousNyms = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveLookupResult &&
          other.nym == nym &&
          other.quota == quota &&
          _listEquals(other.previousNyms, previousNyms);

  @override
  int get hashCode =>
      Object.hash(runtimeType, nym, quota, Object.hashAll(previousNyms));
}

class InactiveLookupResult extends LookupResult {
  final String nym;
  @override
  final NymQuota quota;
  @override
  final List<PreviousNym> previousNyms;
  const InactiveLookupResult({
    required this.nym,
    required this.quota,
    this.previousNyms = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InactiveLookupResult &&
          other.nym == nym &&
          other.quota == quota &&
          _listEquals(other.previousNyms, previousNyms);

  @override
  int get hashCode =>
      Object.hash(runtimeType, nym, quota, Object.hashAll(previousNyms));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
