import 'package:qa_matrix_engine/qa_matrix_engine.dart';

/// Builds a [GeneratedCase] from an explicit, partial tuple for the
/// hand-authored §4 recovery-permutation catalog — the same machinery the
/// combinatorial generator uses (analytic oracle + feasibility filter +
/// scenario classifier), so a named case and a generated one are scored
/// identically. Unspecified dimensions default to the smoke-floor value
/// (all-ok / up-live / online / no-interrupt / in-sync / correct seed).
GeneratedCase namedCase(
  String label,
  Map<String, String> overrides, {
  String feature = 'F5',
  int row = 0,
}) {
  final values = <String, String>{
    ParameterModel.dWalletSet: 'w100_101',
    ParameterModel.dBackup: 'on-acked',
    ParameterModel.dManifest: 'current',
    ParameterModel.dRelay: 'all-ok',
    ParameterModel.dServer: 'up-live',
    ParameterModel.dNetwork: 'online',
    ParameterModel.dInterrupt: 'none',
    ParameterModel.dClock: 'in-sync',
    ParameterModel.dSeed: 'correct',
    ...overrides,
  };
  final tuple = ScenarioTuple(values);
  return GeneratedCase(
    id: ScenarioId(CoverageTier.cg1Smoke, label.hashCode & 0xffff, row),
    tuple: tuple,
    tier: CoverageTier.cg1Smoke,
    feature: feature,
    scenarioClass: classifyScenario(tuple),
    feasibility: const FeasibilityFilter().evaluate(tuple),
    expected: const RecoveryOracle().derive(tuple),
  );
}
