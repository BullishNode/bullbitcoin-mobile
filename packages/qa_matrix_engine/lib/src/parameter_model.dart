import 'package:meta/meta.dart';

/// A single state dimension (GETPAID-APP-E2E-FAILURE-MATRIX §5.1): a named axis
/// with an ordered, finite set of string-valued levels. Values are ordered so a
/// value index is stable across runs (the generator is index-based; the first
/// value of every dimension is its "smoke floor" value).
@immutable
class Dimension {
  const Dimension(this.id, this.name, this.values);

  /// Short stable id, e.g. `D3`.
  final String id;

  /// Human-readable name, e.g. `Manifest state`.
  final String name;

  /// The ordered levels. `values[0]` is the smoke-floor value.
  final List<String> values;

  int get cardinality => values.length;

  int indexOf(String value) {
    final i = values.indexOf(value);
    if (i < 0) {
      throw ArgumentError('value "$value" is not in dimension $id ($name)');
    }
    return i;
  }

  @override
  String toString() => '$id($name)';
}

/// The versioned parameter model: the nine state dimensions the matrix sweeps.
/// Adding a value or a dimension here is the "one-line change" §5.3 promises —
/// the generator, oracle, and reporter all read this table as data.
class ParameterModel {
  ParameterModel(this.dimensions)
    : assert(dimensions.isNotEmpty, 'need at least one dimension') {
    for (final d in dimensions) {
      if (_byId.containsKey(d.id)) {
        throw ArgumentError('duplicate dimension id ${d.id}');
      }
      _byId[d.id] = d;
    }
  }

  final List<Dimension> dimensions;
  final Map<String, Dimension> _byId = {};

  Dimension byId(String id) {
    final d = _byId[id];
    if (d == null) throw ArgumentError('no dimension $id');
    return d;
  }

  int indexOfDimension(String id) {
    final i = dimensions.indexWhere((d) => d.id == id);
    if (i < 0) throw ArgumentError('no dimension $id');
    return i;
  }

  /// Per-dimension cardinalities, in declaration order (the IPOG `levels`).
  List<int> get levels =>
      dimensions.map((d) => d.cardinality).toList(growable: false);

  /// The full Cartesian size — intractable by design (§5.1 = 2,419,200); the
  /// reason a covering strategy exists.
  BigInt get cartesianSize => dimensions.fold(
    BigInt.one,
    (acc, d) => acc * BigInt.from(d.cardinality),
  );

  // --- Canonical dimension ids -------------------------------------------

  static const dWalletSet = 'D1';
  static const dBackup = 'D2';
  static const dManifest = 'D3';
  static const dRelay = 'D4';
  static const dServer = 'D5';
  static const dNetwork = 'D6';
  static const dInterrupt = 'D7';
  static const dClock = 'D8';
  static const dSeed = 'D9';

  /// The default model (exactly the §5.1 table). Values are the ids the
  /// scenario compiler switches on, so they are frozen strings.
  static ParameterModel getPaid() => ParameterModel([
    const Dimension(dWalletSet, 'WalletSet present', [
      'none',
      'w100',
      'w101',
      'w100_101',
      'w101_102',
      'w101_103',
      'w101_102_103',
      'w100_101_102_103',
    ]),
    const Dimension(dBackup, 'Backup state', [
      'on-acked',
      'on-unacked',
      'off',
    ]),
    const Dimension(dManifest, 'Manifest state', [
      'none',
      'current',
      'older-populated',
      'newer-version',
      'corrupt-undecryptable',
      'empty-newest',
      'tampered',
      'forged-author',
    ]),
    const Dimension(dRelay, 'Relay-health profile', [
      'all-ok',
      'one-reject',
      'one-timeout',
      'one-forge',
      'one-flood',
      'all-down',
      'divergent',
      'size-cap',
      'auth-required',
      'never-eose',
    ]),
    const Dimension(dServer, 'Server reachability', [
      'up-live',
      'up-lapsed',
      'down',
      'err-500',
      'err-conflict',
      'err-ratelimited',
      'soft-limit-bolt11',
    ]),
    const Dimension(dNetwork, 'Network', ['online', 'offline', 'flaky-drop']),
    const Dimension(dInterrupt, 'Interrupt point', [
      'none',
      'mid-publish',
      'mid-recovery',
      'mid-register',
      'mid-materialize',
    ]),
    const Dimension(dClock, 'Clock skew', [
      'in-sync',
      '+10min',
      '-10min',
      '+400s',
    ]),
    const Dimension(dSeed, 'Seed correctness', [
      'correct',
      'wrong',
      'partially-wrong',
    ]),
  ]);
}
