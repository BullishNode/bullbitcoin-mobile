import 'package:qa_matrix_engine/qa_matrix_engine.dart';
import 'package:test/test.dart';

/// Brute-force check that [array] covers every [strength]-way value combination
/// over parameters with the given [levels].
void expectCovers(CoveringArray array, List<int> levels, int strength) {
  final k = levels.length;
  final paramCombos = _combinations(List<int>.generate(k, (i) => i), strength);
  for (final params in paramCombos) {
    final valueLists =
        params.map((p) => List<int>.generate(levels[p], (v) => v)).toList();
    for (final vt in _cartesian(valueLists)) {
      final covered = array.rows.any((row) {
        for (var i = 0; i < params.length; i++) {
          if (row[params[i]] != vt[i]) return false;
        }
        return true;
      });
      expect(
        covered,
        isTrue,
        reason: 'combo params=$params values=$vt not covered',
      );
    }
  }
}

List<List<int>> _cartesian(List<List<int>> valueLists) {
  var acc = <List<int>>[<int>[]];
  for (final values in valueLists) {
    final next = <List<int>>[];
    for (final prefix in acc) {
      for (final v in values) {
        next.add([...prefix, v]);
      }
    }
    acc = next;
  }
  return acc;
}

List<List<int>> _combinations(List<int> items, int r) {
  final result = <List<int>>[];
  void recurse(int start, List<int> current) {
    if (current.length == r) {
      result.add(List<int>.of(current));
      return;
    }
    for (var i = start; i < items.length; i++) {
      current.add(items[i]);
      recurse(i + 1, current);
      current.removeLast();
    }
  }

  recurse(0, <int>[]);
  return result;
}

void main() {
  group('IPOG covering array', () {
    test('pairwise array covers every pair over the full parameter model', () {
      final levels = ParameterModel.getPaid().levels;
      final array = CoveringArray.generate(levels, 2, seed: 1);
      expectCovers(array, levels, 2);
    });

    test('pairwise array is far smaller than the Cartesian product', () {
      final model = ParameterModel.getPaid();
      final array = CoveringArray.generate(model.levels, 2, seed: 1);
      // Cartesian is 2,419,200; a pairwise array must be a tiny fraction.
      expect(array.rows.length, lessThan(300));
      expect(model.cartesianSize, BigInt.from(2419200));
    });

    test('3-wise array covers every triple on a small model', () {
      final levels = [3, 3, 3, 3, 2];
      final array = CoveringArray.generate(levels, 3, seed: 7);
      expectCovers(array, levels, 3);
    });

    test('same seed is reproducible; different seeds may differ', () {
      final levels = ParameterModel.getPaid().levels;
      final a = CoveringArray.generate(levels, 2, seed: 42);
      final b = CoveringArray.generate(levels, 2, seed: 42);
      expect(a.rows, equals(b.rows));
    });

    test('strength >= parameter count degrades to the Cartesian product', () {
      final levels = [2, 3, 2];
      final array = CoveringArray.generate(levels, 3, seed: 0);
      expect(array.rows.length, 2 * 3 * 2);
      expectCovers(array, levels, 3);
    });
  });
}
