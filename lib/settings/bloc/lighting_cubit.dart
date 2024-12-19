import 'package:bb_mobile/_pkg/storage/hive.dart';
import 'package:bb_mobile/_pkg/storage/storage.dart';
import 'package:bb_mobile/styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ThemeLighting { light, dark, dim, system }

class Lighting extends Cubit<ThemeLighting> {
  Lighting({required HiveStorage hiveStorage})
      : _hiveStorage = hiveStorage,
        super(ThemeLighting.light) {
    init();
  }

  final HiveStorage _hiveStorage;

  @override
  void onChange(Change<ThemeLighting> change) {
    super.onChange(change);
    _hiveStorage.saveValue(
      key: StorageKeys.lighting,
      value: change.nextState.toString(),
    );
  }

  Future<void> init() async {
    final (result, err) = await _hiveStorage.getValue(StorageKeys.lighting);
    if (err != null) return;
    emit(ThemeLighting.values.firstWhere((e) => e.toString() == result));
  }

  void toggle(ThemeLighting theme) => emit(theme);
}

extension X on ThemeLighting {
  ThemeData dark() =>
      this == ThemeLighting.dim ? Themes.dimTheme : Themes.darkTheme;

  ThemeMode mode() {
    switch (this) {
      case ThemeLighting.light:
        return ThemeMode.light;
      case ThemeLighting.dark:
      case ThemeLighting.dim:
        return ThemeMode.dark;
      case ThemeLighting.system:
        return ThemeMode.system;
    }
  }

  ThemeMode currentTheme(BuildContext context) {
    switch (this) {
      case ThemeLighting.light:
        return ThemeMode.light;
      case ThemeLighting.dark:
      case ThemeLighting.dim:
        return ThemeMode.dark;
      case ThemeLighting.system:
        final brightness = MediaQuery.of(context).platformBrightness;
        final isDarkMode = brightness == Brightness.dark;
        return isDarkMode ? ThemeMode.dark : ThemeMode.light;
    }
  }
}
