class Bip85DerivationPath {
  static const maxHardenedChildIndex = 0x7fffffff;

  static final _mnemonicPathPattern = RegExp(
    r"^m/83696968'/39'/0'/12'/([0-9]+)'$",
  );

  final int index;
  final String value;

  const Bip85DerivationPath._({required this.index, required this.value});

  factory Bip85DerivationPath.mnemonic12({required int index}) {
    if (index < 0 || index > maxHardenedChildIndex) {
      throw ArgumentError.value(
        index,
        'index',
        'must be between 0 and $maxHardenedChildIndex',
      );
    }
    return Bip85DerivationPath._(
      index: index,
      value: "m/83696968'/39'/0'/12'/$index'",
    );
  }

  static Bip85DerivationPath? tryParse(String? value) {
    if (value == null) return null;
    final match = _mnemonicPathPattern.firstMatch(value);
    if (match == null) return null;
    final index = int.tryParse(match.group(1)!);
    if (index == null) return null;
    if (index > maxHardenedChildIndex) return null;
    return Bip85DerivationPath.mnemonic12(index: index);
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bip85DerivationPath && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
