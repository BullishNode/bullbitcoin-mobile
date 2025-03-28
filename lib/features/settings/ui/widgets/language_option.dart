import 'package:bb_mobile/core/settings/domain/entity/settings.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LanguageOption extends StatelessWidget {
  const LanguageOption({
    super.key,
    required this.language,
  });

  final Language language;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: context.watch<SettingsCubit>().state?.language == language,
      title: Text(
        '${language.languageCode}${language.countryCode != null ? ' (${language.countryCode})' : ''}',
      ),
      onTap: () {
        context.read<SettingsCubit>().changeLanguage(language);
      },
    );
  }
}
