/// A small deterministic PRNG (SplitMix64-style) so tie-breaks are reproducible
/// from a seed without depending on `dart:math`'s Random implementation.
class DeterministicRng {
  DeterministicRng(int seed) : _state = seed & _mask64;

  static const int _mask64 = 0xFFFFFFFFFFFFFFFF;
  int _state;

  int _next() {
    _state = (_state + 0x9E3779B97F4A7C15) & _mask64;
    var z = _state;
    z = ((z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9) & _mask64;
    z = ((z ^ (z >>> 27)) * 0x94D049BB133111EB) & _mask64;
    return (z ^ (z >>> 31)) & _mask64;
  }

  /// A non-negative int in `[0, bound)`.
  int nextInt(int bound) {
    if (bound <= 0) throw ArgumentError.value(bound, 'bound', 'must be > 0');
    return _next() % bound;
  }
}

/// A concrete t-way combination: a sorted list of parameter indices and the
/// value chosen for each. Its [key] is the identity used for coverage tracking.
class ValueCombination {
  ValueCombination(this.params, this.values)
    : assert(params.length == values.length);

  final List<int> params;
  final List<int> values;

  String get key {
    final b = StringBuffer();
    for (var i = 0; i < params.length; i++) {
      if (i > 0) b.write(',');
      b
        ..write(params[i])
        ..write('=')
        ..write(values[i]);
    }
    return b.toString();
  }
}

/// A seeded IPOG (In-Parameter-Order, General) covering-array generator
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5.3). Produces a deterministic array of
/// value-index rows guaranteeing that every combination of values from any
/// [strength] parameters appears in at least one row. Same [seed] ⇒ same rows.
class CoveringArray {
  /// Rows of value indices (one entry per parameter, in `levels` order).
  final List<List<int>> rows;

  /// The per-parameter cardinalities this array was built for.
  final List<int> levels;

  /// The interaction strength (t) the array covers.
  final int strength;

  CoveringArray._(this.rows, this.levels, this.strength);

  static CoveringArray generate(
    List<int> levels,
    int strength, {
    int seed = 0,
  }) {
    if (strength < 1) {
      throw ArgumentError.value(strength, 'strength', 'must be >= 1');
    }
    final k = levels.length;
    if (strength >= k) {
      return CoveringArray._(_cartesian(levels), levels, k);
    }

    final rng = DeterministicRng(seed);

    // Step 1 — seed with the exhaustive product of the first t parameters.
    final rows = <List<int>>[];
    for (final head in _cartesian(levels.sublist(0, strength))) {
      final row = List<int>.filled(k, -1);
      for (var j = 0; j < strength; j++) {
        row[j] = head[j];
      }
      rows.add(row);
    }

    // Grow one parameter at a time.
    for (var i = strength; i < k; i++) {
      final priorCombos = _combinations(
        List<int>.generate(i, (x) => x),
        strength - 1,
      );

      // The full set of t-way combos that involve parameter i.
      final uncovered = <String>{};
      for (final pc in priorCombos) {
        final paramsSet = [...pc, i];
        final valueLists = paramsSet
            .map((p) => List<int>.generate(levels[p], (v) => v))
            .toList();
        for (final vt in _cartesianOfLists(valueLists)) {
          uncovered.add(_comboKey(paramsSet, vt));
        }
      }

      // Horizontal growth — extend every existing row with the value of i that
      // covers the most still-uncovered combos.
      for (final row in rows) {
        var bestValue = -1;
        var bestKeys = const <String>[];
        for (var v = 0; v < levels[i]; v++) {
          final keys = <String>[];
          for (final pc in priorCombos) {
            var ok = true;
            for (final p in pc) {
              if (row[p] < 0) {
                ok = false;
                break;
              }
            }
            if (!ok) continue;
            final paramsSet = [...pc, i];
            final vals = [for (final p in pc) row[p], v];
            final key = _comboKey(paramsSet, vals);
            if (uncovered.contains(key)) keys.add(key);
          }
          if (keys.length > bestKeys.length) {
            bestKeys = keys;
            bestValue = v;
          }
        }
        row[i] = bestValue < 0 ? rng.nextInt(levels[i]) : bestValue;
        uncovered.removeAll(bestKeys);
      }

      // Vertical growth — cover leftovers by merging into a compatible row or
      // appending a new (partially-fixed) row.
      final leftovers = uncovered.toList()..sort();
      for (final comboKey in leftovers) {
        if (!uncovered.contains(comboKey)) continue;
        final combo = _parseCombo(comboKey);
        var placed = false;
        for (final row in rows) {
          var compatible = true;
          for (var idx = 0; idx < combo.params.length; idx++) {
            final p = combo.params[idx];
            if (row[p] >= 0 && row[p] != combo.values[idx]) {
              compatible = false;
              break;
            }
          }
          if (!compatible) continue;
          for (var idx = 0; idx < combo.params.length; idx++) {
            row[combo.params[idx]] = combo.values[idx];
          }
          uncovered.remove(comboKey);
          placed = true;
          break;
        }
        if (!placed) {
          final row = List<int>.filled(k, -1);
          for (var idx = 0; idx < combo.params.length; idx++) {
            row[combo.params[idx]] = combo.values[idx];
          }
          rows.add(row);
          uncovered.remove(comboKey);
        }
      }
    }

    // Fill any remaining don't-cares deterministically (value 0).
    for (final row in rows) {
      for (var j = 0; j < k; j++) {
        if (row[j] < 0) row[j] = 0;
      }
    }
    return CoveringArray._(rows, levels, strength);
  }

  // --- helpers -----------------------------------------------------------

  static String _comboKey(List<int> params, List<int> values) {
    final b = StringBuffer();
    for (var i = 0; i < params.length; i++) {
      if (i > 0) b.write(',');
      b
        ..write(params[i])
        ..write('=')
        ..write(values[i]);
    }
    return b.toString();
  }

  static ValueCombination _parseCombo(String key) {
    final params = <int>[];
    final values = <int>[];
    for (final part in key.split(',')) {
      final eq = part.split('=');
      params.add(int.parse(eq[0]));
      values.add(int.parse(eq[1]));
    }
    return ValueCombination(params, values);
  }

  static List<List<int>> _cartesian(List<int> levels) =>
      _cartesianOfLists(levels.map((n) => List<int>.generate(n, (i) => i)));

  static List<List<int>> _cartesianOfLists(Iterable<List<int>> valueLists) {
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

  static List<List<int>> _combinations(List<int> items, int r) {
    final result = <List<int>>[];
    if (r < 0 || r > items.length) return result;
    if (r == 0) return [<int>[]];
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
}
