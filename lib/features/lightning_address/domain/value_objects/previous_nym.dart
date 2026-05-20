class PreviousNym {
  final String nym;
  final DateTime createdAt;

  const PreviousNym({required this.nym, required this.createdAt});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PreviousNym && other.nym == nym && other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(nym, createdAt);

  @override
  String toString() => 'PreviousNym(nym: $nym, createdAt: $createdAt)';
}
