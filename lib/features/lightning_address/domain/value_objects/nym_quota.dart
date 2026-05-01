/// VALUE OBJECT: lifetime nym quota for one Nostr identity (npub).
///
/// Carries the per-npub lifetime registration counters reported by the
/// pay-service: how many distinct nyms this wallet has ever registered
/// (`used`, active + inactive), and the cap above which new-nym registrations
/// are blocked. Past nyms stay reserved forever — they continue to count
/// against `used` even after the user deregisters.
///
/// Invariants:
///   - `used >= 0`, `cap >= 0`
///   - `remaining = max(cap - used, 0)`
///
/// Derivations like `state()` live here, not in callers, so the UI never
/// re-derives `remaining == 1` (Kumulynja PLAN-7).
class NymQuota {
  final int used;
  final int cap;

  const NymQuota({required this.used, required this.cap})
      : assert(used >= 0),
        assert(cap >= 0);

  /// Fresh new-nym registrations still available to this npub. Always
  /// non-negative — a server response with `used > cap` (impossible under
  /// the lock-protected register flow but possible under stale data) clamps
  /// to zero rather than going negative.
  int get remaining {
    final r = cap - used;
    return r < 0 ? 0 : r;
  }

  bool get isExhausted => remaining == 0;

  /// True when one more new-nym registration would hit the cap. Drives the
  /// "after deactivating, you have 1 left" warning copy.
  bool get isLastSlot => remaining == 1;

  QuotaState state() {
    if (isExhausted) return QuotaState.exhausted;
    if (isLastSlot) return QuotaState.lastSlot;
    return QuotaState.available;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NymQuota && other.used == used && other.cap == cap;

  @override
  int get hashCode => Object.hash(used, cap);

  @override
  String toString() => 'NymQuota(used: $used, cap: $cap, remaining: $remaining)';
}

/// Tag enum for UI copy selection. Three-way split because the three states
/// each get a distinct user-facing message; consuming code switches over
/// this and never inspects `remaining` directly.
enum QuotaState {
  /// Caller can still register `> 1` more nyms.
  available,
  /// Caller has exactly one fresh-nym slot left.
  lastSlot,
  /// Caller cannot register any new nyms; can only reactivate existing ones.
  exhausted,
}
