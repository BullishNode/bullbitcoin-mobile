import 'package:qa_matrix_engine/qa_matrix_engine.dart';
import 'package:test/test.dart';

void main() {
  final gen = MatrixGenerator();

  group('smoke floor (CG-1)', () {
    test('is feasible and expects a restore', () {
      final smoke = gen.smokeFloor();
      expect(smoke.tier, CoverageTier.cg1Smoke);
      expect(smoke.feature, 'F5');
      expect(smoke.isFeasible, isTrue);
      expect(smoke.expected.accepts(ExpectedRecoveryClass.restored), isTrue);
    });
  });

  group('pairwise (CG-2)', () {
    test('is deterministic for a fixed seed', () {
      final a = gen.pairwise(seed: 3).map((c) => c.tuple.describe()).toList();
      final b = gen.pairwise(seed: 3).map((c) => c.tuple.describe()).toList();
      expect(a, equals(b));
    });

    test('produces a bounded, non-trivial row count', () {
      final cases = gen.pairwise(seed: 0);
      expect(cases.length, greaterThan(80));
      expect(cases.length, lessThan(300));
    });
  });

  group('recovery core (CG-3)', () {
    test('is full-factorial over D3xD4xD9 (8*10*3 = 240 rows)', () {
      final cases = gen.recoveryCore(seed: 0);
      expect(cases.length, 8 * 10 * 3);
      expect(cases.every((c) => c.feature == 'F5'), isTrue);
    });

    test('covers every manifest x relay x seed triple', () {
      final cases = gen.recoveryCore(seed: 0);
      final seen = <String>{};
      for (final c in cases) {
        seen.add(
          '${c.tuple.get(ParameterModel.dManifest)}|'
          '${c.tuple.get(ParameterModel.dRelay)}|'
          '${c.tuple.get(ParameterModel.dSeed)}',
        );
      }
      expect(seen.length, 8 * 10 * 3);
    });
  });

  group('feasibility filter', () {
    test('prunes a wrong seed paired with a present manifest', () {
      final v = const FeasibilityFilter().evaluate(
        ScenarioTuple({
          ParameterModel.dSeed: 'wrong',
          ParameterModel.dManifest: 'current',
          ParameterModel.dBackup: 'on-acked',
        }),
      );
      expect(v.feasible, isFalse);
      expect(v.reason, isNotNull);
    });

    test('prunes backup=off with a freshly-published manifest', () {
      final v = const FeasibilityFilter().evaluate(
        ScenarioTuple({
          ParameterModel.dSeed: 'correct',
          ParameterModel.dManifest: 'current',
          ParameterModel.dBackup: 'off',
        }),
      );
      expect(v.feasible, isFalse);
    });

    test('allows the smoke tuple', () {
      final v = const FeasibilityFilter().evaluate(gen.smokeFloor().tuple);
      expect(v.feasible, isTrue);
    });
  });

  group('invariant library', () {
    test('has all fourteen invariants P1..P14', () {
      expect(InvariantLibrary.all.length, 14);
      for (var n = 1; n <= 14; n++) {
        expect(() => InvariantLibrary.byId('P$n'), returnsNormally);
      }
    });

    test('the smoke tuple applies the money-safety core', () {
      final applicable =
          InvariantLibrary.applicableTo(gen.smokeFloor().tuple).map((i) => i.id);
      // A current/all-ok/correct restore exercises totality, no-false-no-backup,
      // byte-identity, consent, publish-honesty, posture, idempotency, opacity.
      expect(applicable, containsAll(['P1', 'P2', 'P3', 'P7', 'P9', 'P14']));
    });
  });
}
