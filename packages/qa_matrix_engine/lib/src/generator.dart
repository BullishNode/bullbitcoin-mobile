import 'package:meta/meta.dart';

import 'covering_array.dart';
import 'oracle.dart';
import 'parameter_model.dart';
import 'scenario.dart';

/// One compiled row of the matrix: the tuple, its identity, tier, the feature +
/// scenario-class it is attributed to, its feasibility verdict, and the analytic
/// oracle. A [GeneratedCase] is what the Flutter runner compiles into a fake
/// configuration and drives.
@immutable
class GeneratedCase {
  const GeneratedCase({
    required this.id,
    required this.tuple,
    required this.tier,
    required this.feature,
    required this.scenarioClass,
    required this.feasibility,
    required this.expected,
  });

  final ScenarioId id;
  final ScenarioTuple tuple;
  final CoverageTier tier;
  final String feature;
  final String scenarioClass;
  final FeasibilityVerdict feasibility;
  final ExpectedOutcome expected;

  bool get isFeasible => feasibility.feasible;
}

/// The seeded generator (GETPAID-APP-E2E-FAILURE-MATRIX §5.2/§5.3). Same
/// `(model, seed)` ⇒ same case list ⇒ reproducible failures.
class MatrixGenerator {
  MatrixGenerator({
    ParameterModel? model,
    this.filter = const FeasibilityFilter(),
    this.oracle = const RecoveryOracle(),
  }) : model = model ?? ParameterModel.getPaid();

  final ParameterModel model;
  final FeasibilityFilter filter;
  final RecoveryOracle oracle;

  /// CG-1 — the smoke floor: one all-ok/current/correct/online/none/in-sync
  /// recovery row (§5.2). This is the fast red flag Phase 0's smoke case runs.
  GeneratedCase smokeFloor() {
    final tuple = ScenarioTuple({
      ParameterModel.dWalletSet: 'w100_101',
      ParameterModel.dBackup: 'on-acked',
      ParameterModel.dManifest: 'current',
      ParameterModel.dRelay: 'all-ok',
      ParameterModel.dServer: 'up-live',
      ParameterModel.dNetwork: 'online',
      ParameterModel.dInterrupt: 'none',
      ParameterModel.dClock: 'in-sync',
      ParameterModel.dSeed: 'correct',
    });
    return _build(const ScenarioId(CoverageTier.cg1Smoke, 0, 0), tuple, 'F5');
  }

  /// CG-2 — pairwise (t=2) across all nine dimensions (§5.2). Returns every row
  /// (feasible + pruned); callers filter with [GeneratedCase.isFeasible].
  List<GeneratedCase> pairwise({int seed = 0}) {
    final array = CoveringArray.generate(model.levels, 2, seed: seed);
    final cases = <GeneratedCase>[];
    for (var r = 0; r < array.rows.length; r++) {
      final tuple = _tupleFromRow(array.rows[r]);
      cases.add(
        _build(ScenarioId(CoverageTier.cg2Pairwise, seed, r), tuple, 'F5'),
      );
    }
    return cases;
  }

  /// CG-3 — the recovery core: full-factorial D3×D4×D9, each folded against a
  /// pairwise assignment of the remaining dimensions so they stay pair-covered
  /// within the sweep (§5.2). (Decision: D1 is folded in with D2/D5/D6/D7/D8, so
  /// the non-core dimensions are all pair-covered, not just the dossier's five.)
  List<GeneratedCase> recoveryCore({int seed = 0}) {
    final coreIds = [
      ParameterModel.dManifest,
      ParameterModel.dRelay,
      ParameterModel.dSeed,
    ];
    final foldedIds = [
      ParameterModel.dWalletSet,
      ParameterModel.dBackup,
      ParameterModel.dServer,
      ParameterModel.dNetwork,
      ParameterModel.dInterrupt,
      ParameterModel.dClock,
    ];

    // Full factorial over the three core dimensions.
    final coreDims = coreIds.map(model.byId).toList();
    final coreRows = _cartesianValues(coreDims);

    // Pairwise fold over the rest.
    final foldedDims = foldedIds.map(model.byId).toList();
    final foldArray = CoveringArray.generate(
      foldedDims.map((d) => d.cardinality).toList(),
      2,
      seed: seed,
    );

    final cases = <GeneratedCase>[];
    for (var r = 0; r < coreRows.length; r++) {
      final foldRow = foldArray.rows[r % foldArray.rows.length];
      final values = <String, String>{};
      for (var i = 0; i < coreDims.length; i++) {
        values[coreDims[i].id] = coreDims[i].values[coreRows[r][i]];
      }
      for (var i = 0; i < foldedDims.length; i++) {
        values[foldedDims[i].id] = foldedDims[i].values[foldRow[i]];
      }
      cases.add(
        _build(ScenarioId(CoverageTier.cg3Recovery, seed, r),
            ScenarioTuple(values), 'F5'),
      );
    }
    return cases;
  }

  /// The full generated set for a seed (§3 totals): CG-1 ∪ CG-2 ∪ CG-3.
  List<GeneratedCase> generateAll({int seed = 0}) => [
    smokeFloor(),
    ...pairwise(seed: seed),
    ...recoveryCore(seed: seed),
  ];

  // --- internals ---------------------------------------------------------

  GeneratedCase _build(ScenarioId id, ScenarioTuple tuple, String feature) =>
      GeneratedCase(
        id: id,
        tuple: tuple,
        tier: id.tier,
        feature: feature,
        scenarioClass: classifyScenario(tuple),
        feasibility: filter.evaluate(tuple),
        expected: oracle.derive(tuple),
      );

  ScenarioTuple _tupleFromRow(List<int> row) {
    final values = <String, String>{};
    for (var j = 0; j < model.dimensions.length; j++) {
      final dim = model.dimensions[j];
      values[dim.id] = dim.values[row[j]];
    }
    return ScenarioTuple(values);
  }

  List<List<int>> _cartesianValues(List<Dimension> dims) {
    var acc = <List<int>>[<int>[]];
    for (final d in dims) {
      final next = <List<int>>[];
      for (final prefix in acc) {
        for (var v = 0; v < d.cardinality; v++) {
          next.add([...prefix, v]);
        }
      }
      acc = next;
    }
    return acc;
  }
}

/// Attributes a tuple to a scenario class (§3 columns) by its dominant fault.
/// Precedence mirrors "the most specific hostile axis wins".
String classifyScenario(ScenarioTuple t) {
  if (t.get(ParameterModel.dSeed) != 'correct') return 'WS';
  final manifest = t.get(ParameterModel.dManifest);
  final relay = t.get(ParameterModel.dRelay);
  if (manifest == 'forged-author' ||
      manifest == 'tampered' ||
      relay == 'one-forge') {
    return 'HA';
  }
  if (manifest == 'newer-version') return 'VS';
  if (t.get(ParameterModel.dInterrupt) != 'none') return 'IM';
  if (relay == 'all-down' ||
      relay == 'never-eose' ||
      t.get(ParameterModel.dNetwork) == 'offline') {
    return 'IB';
  }
  if (relay == 'one-flood') return 'RE';
  if (manifest == 'empty-newest' || relay == 'divergent') return 'PF';
  if (t.get(ParameterModel.dManifest) == 'older-populated') return 'RB';
  if (t.get(ParameterModel.dManifest) == 'current') return 'HP';
  return 'RB';
}
