import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_comment_history_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_comment_history_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

class GetPaidCommentHistoryScreen extends StatefulWidget {
  const GetPaidCommentHistoryScreen({super.key});

  @override
  State<GetPaidCommentHistoryScreen> createState() =>
      _GetPaidCommentHistoryScreenState();
}

class _GetPaidCommentHistoryScreenState
    extends State<GetPaidCommentHistoryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<GetPaidCommentHistoryCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.loc.getPaidCommentsHistoryTitle)),
      body: SafeArea(
        child:
            BlocBuilder<GetPaidCommentHistoryCubit, GetPaidCommentHistoryState>(
              builder: (context, state) => switch (state.status) {
                GetPaidCommentHistoryStatus.initial ||
                GetPaidCommentHistoryStatus.loading => const Center(
                  child: CircularProgressIndicator(),
                ),
                GetPaidCommentHistoryStatus.failure => _FailureBody(
                  onRetry: context.read<GetPaidCommentHistoryCubit>().refresh,
                ),
                GetPaidCommentHistoryStatus.loaded when state.isEmpty =>
                  const _EmptyBody(),
                GetPaidCommentHistoryStatus.loaded => _HistoryBody(
                  state: state,
                ),
              },
            ),
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  final GetPaidCommentHistoryState state;

  const _HistoryBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GetPaidCommentHistoryCubit>();
    final footerCount = state.hasMore || state.loadMoreFailed ? 1 : 0;
    return RefreshIndicator(
      onRefresh: cubit.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.comments.length + footerCount,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == state.comments.length) {
            return _LoadMoreFooter(state: state, onLoadMore: cubit.loadMore);
          }
          final comment = state.comments[index];
          return ListTile(
            key: ValueKey('lnurl-comment-${comment.intentId}'),
            title: Text(_amountText(context, comment.amountMsat)),
            subtitle: Text(
              '${comment.nym}\n${_receivedAtText(context, comment.receivedAt)}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCommentDetail(context, comment),
          );
        },
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  final GetPaidCommentHistoryState state;
  final VoidCallback onLoadMore;

  const _LoadMoreFooter({required this.state, required this.onLoadMore});

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: Icon(state.loadMoreFailed ? Icons.refresh : Icons.expand_more),
        label: Text(
          state.loadMoreFailed
              ? context.loc.getPaidCommentsRetry
              : context.loc.getPaidCommentsLoadMore,
        ),
      ),
    );
  }
}

class _FailureBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _FailureBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.appColors.error),
            const Gap(16),
            Text(
              context.loc.getPaidCommentsUnavailable,
              textAlign: TextAlign.center,
            ),
            const Gap(16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.loc.getPaidCommentsRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_chat_read_outlined,
              size: 52,
              color: context.appColors.textMuted,
            ),
            const Gap(16),
            Text(context.loc.getPaidCommentsEmpty, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Future<void> _showCommentDetail(
  BuildContext context,
  LightningAddressPaymentComment comment,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sheetContext.loc.getPaidCommentsDetailTitle,
              style: sheetContext.font.titleLarge,
            ),
            const Gap(20),
            _DetailField(
              label: sheetContext.loc.getPaidCommentsAmountLabel,
              value: _amountText(sheetContext, comment.amountMsat),
            ),
            const Gap(12),
            _DetailField(
              label: sheetContext.loc.getPaidCommentsNameLabel,
              value: comment.nym,
            ),
            const Gap(12),
            _DetailField(
              label: sheetContext.loc.getPaidCommentsReceivedLabel,
              value: _receivedAtText(sheetContext, comment.receivedAt),
            ),
            const Gap(20),
            Text(
              sheetContext.loc.getPaidCommentsCommentLabel,
              style: sheetContext.font.labelMedium?.copyWith(
                color: sheetContext.appColors.textMuted,
              ),
            ),
            const Gap(6),
            Text(
              comment.comment,
              key: const ValueKey('private-lnurl-comment-text'),
              style: sheetContext.font.bodyLarge,
            ),
            const Gap(24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(sheetContext.loc.getPaidCommentsClose),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailField extends StatelessWidget {
  final String label;
  final String value;

  const _DetailField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.font.labelMedium?.copyWith(
            color: context.appColors.textMuted,
          ),
        ),
        const Gap(4),
        Text(value, style: context.font.bodyMedium),
      ],
    );
  }
}

String _amountText(BuildContext context, int amountMsat) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  final number = NumberFormat.decimalPattern(locale);
  if (amountMsat % 1000 == 0) {
    return context.loc.getPaidCommentsAmountSats(
      number.format(amountMsat ~/ 1000),
    );
  }
  return context.loc.getPaidCommentsAmountMsats(number.format(amountMsat));
}

String _receivedAtText(BuildContext context, DateTime receivedAt) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(receivedAt.toLocal());
}
