import 'package:meta/meta.dart';

import 'parameter_model.dart';

/// The three covering tiers (GETPAID-APP-E2E-FAILURE-MATRIX §5.2).
enum CoverageTier {
  /// One smoke-floor row per feature (the fast red flag).
  cg1Smoke('CG-1'),

  /// Pairwise (t=2) across all nine dimensions.
  cg2Pairwise('CG-2'),

  /// 3-wise on the recovery core (D3×D4×D9), folded against a pairwise
  /// assignment of the remaining dimensions — the money-safety exhaustion.
  cg3Recovery('CG-3');

  const CoverageTier(this.label);
  final String label;
}

/// A concrete assignment of one value to every dimension: the row a case runs.
@immutable
class ScenarioTuple {
  const ScenarioTuple(this.values);

  /// dimension-id -> chosen value string.
  final Map<String, String> values;

  String get(String dimensionId) {
    final v = values[dimensionId];
    if (v == null) {
      throw ArgumentError('tuple has no value for $dimensionId');
    }
    return v;
  }

  bool isValue(String dimensionId, String value) => values[dimensionId] == value;

  /// A stable, human-readable rendering, ordered by dimension id.
  String describe() {
    final keys = values.keys.toList()..sort();
    return keys.map((k) => '$k=${values[k]}').join(' ');
  }

  ScenarioTuple copyWith(Map<String, String> overrides) =>
      ScenarioTuple({...values, ...overrides});
}

/// A stable identity for a generated case: `CG-<tier>-<seed>-<row>`
/// (GETPAID-APP-E2E-FAILURE-MATRIX §3 naming).
@immutable
class ScenarioId {
  const ScenarioId(this.tier, this.seed, this.row);

  final CoverageTier tier;
  final int seed;
  final int row;

  @override
  String toString() => '${tier.label}-$seed-$row';
}

/// The outcome of the feasibility filter for one tuple (§5.3 step 3). Infeasible
/// tuples are recorded with a reason, never silently dropped.
@immutable
class FeasibilityVerdict {
  const FeasibilityVerdict.feasible() : feasible = true, reason = null;
  const FeasibilityVerdict.infeasible(String this.reason) : feasible = false;

  final bool feasible;
  final String? reason;
}

/// The rule table that prunes contradictory / redundant tuples (§5.3 step 3).
/// Kept as data-like predicates so it is auditable and extensible.
class FeasibilityFilter {
  const FeasibilityFilter();

  FeasibilityVerdict evaluate(ScenarioTuple t) {
    final seed = t.get(ParameterModel.dSeed);
    final manifest = t.get(ParameterModel.dManifest);
    final backup = t.get(ParameterModel.dBackup);

    // A seed that never published sees an empty seed-derived coordinate, so any
    // non-`none` manifest value is redundant with the seed=correct rows.
    if (seed != 'correct' && manifest != 'none') {
      return const FeasibilityVerdict.infeasible(
        'wrong/partial seed sees an empty coordinate; manifest must be none',
      );
    }

    // Backup OFF never publishes a new manifest, so only a pre-existing older
    // manifest (or none) can coexist with it.
    if (backup == 'off' &&
        !(manifest == 'none' || manifest == 'older-populated')) {
      return const FeasibilityVerdict.infeasible(
        'backup=off never publishes; manifest must be none or older-populated',
      );
    }

    // A present, authentic manifest implies a prior publish, i.e. backup was on
    // at some point — pair `current`/`newer`/tamper/forge with an on-* backup.
    const presentAuthentic = {
      'current',
      'newer-version',
      'tampered',
      'forged-author',
      'empty-newest',
      'corrupt-undecryptable',
    };
    if (presentAuthentic.contains(manifest) && backup == 'off') {
      return const FeasibilityVerdict.infeasible(
        'a present manifest implies a prior publish; backup must be on-*',
      );
    }

    return const FeasibilityVerdict.feasible();
  }
}
