class NymQuota {
  final int used;
  final int cap;

  const NymQuota({required this.used, required this.cap})
    : assert(used >= 0),
      assert(cap >= 0);

  int get remaining {
    final r = cap - used;
    return r < 0 ? 0 : r;
  }

  bool get isExhausted => remaining == 0;
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
  String toString() =>
      'NymQuota(used: $used, cap: $cap, remaining: $remaining)';
}

enum QuotaState { available, lastSlot, exhausted }
