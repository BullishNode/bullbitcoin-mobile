import 'package:bb_mobile/features/legacy_seed_view/presentation/legacy_seed_view_cubit.dart';
import 'package:bb_mobile/ui/components/cards/info_card.dart';
import 'package:bb_mobile/ui/components/text/text.dart';
import 'package:bb_mobile/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class LegacySeedViewScreen extends StatelessWidget {
  const LegacySeedViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          context.read<LegacySeedViewCubit>().clearState();
        } else {}
      },
      child: Scaffold(
        appBar: AppBar(
          title: const BBText(
            'Legacy Seeds',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        body: BlocBuilder<LegacySeedViewCubit, LegacySeedViewState>(
          builder: (context, state) {
            if (!state.loading && state.seeds.isEmpty && state.error == null) {
              context.read<LegacySeedViewCubit>().fetchOldSeeds();
            }
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.error != null) {
              return Center(
                child: BBText(state.error!, style: context.font.bodyLarge),
              );
            }
            if (state.seeds.isEmpty) {
              return Center(
                child: BBText(
                  'No legacy seeds found.',
                  style: context.font.bodyLarge,
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.seeds.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final seed = state.seeds[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoCard(
                      title: 'Mnemonic',
                      description: seed.mnemonic,
                      tagColor: context.colour.primary,
                      bgColor: context.colour.surface,
                    ),
                    if (seed.passphrases.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BBText(
                              'Passphrases:',
                              style: context.font.bodyLarge,
                            ),
                            ...seed.passphrases.map(
                              (p) => BBText(
                                p.passphrase.isNotEmpty
                                    ? p.passphrase
                                    : '(empty)',
                                style: context.font.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
