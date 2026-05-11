import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_cubit.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PaymentPageEditorScreen extends StatefulWidget {
  final String nym;

  const PaymentPageEditorScreen({super.key, required this.nym});

  @override
  State<PaymentPageEditorScreen> createState() =>
      _PaymentPageEditorScreenState();
}

class _PaymentPageEditorScreenState extends State<PaymentPageEditorScreen> {
  final _headerController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _twitterController = TextEditingController();
  final _instagramController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<PaymentPageCubit>().load(nym: widget.nym);
  }

  @override
  void dispose() {
    _headerController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _twitterController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PaymentPageCubit, PaymentPageState>(
      listenWhen: (previous, current) =>
          previous.page != current.page ||
          (!previous.saved && current.saved) ||
          (!previous.archived && current.archived),
      listener: (context, state) {
        _syncControllers(state);
        if ((state.saved || state.archived) && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment Page')),
        body: SafeArea(
          child: BlocBuilder<PaymentPageCubit, PaymentPageState>(
            builder: (context, state) {
              if (state.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.nym.isEmpty) {
                return const _EmptyNymView();
              }
              return _PaymentPageForm(
                state: state,
                headerController: _headerController,
                descriptionController: _descriptionController,
                websiteController: _websiteController,
                twitterController: _twitterController,
                instagramController: _instagramController,
              );
            },
          ),
        ),
      ),
    );
  }

  void _syncControllers(PaymentPageState state) {
    _setText(_headerController, state.header);
    _setText(_descriptionController, state.description);
    _setText(_websiteController, state.website);
    _setText(_twitterController, state.twitter);
    _setText(_instagramController, state.instagram);
  }

  void _setText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }
}

class _PaymentPageForm extends StatelessWidget {
  final PaymentPageState state;
  final TextEditingController headerController;
  final TextEditingController descriptionController;
  final TextEditingController websiteController;
  final TextEditingController twitterController;
  final TextEditingController instagramController;

  const _PaymentPageForm({
    required this.state,
    required this.headerController,
    required this.descriptionController,
    required this.websiteController,
    required this.twitterController,
    required this.instagramController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          state.hasExistingPage ? 'Edit ${state.nym}' : 'Create ${state.nym}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (state.error != null) ...[
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: headerController,
          decoration: const InputDecoration(labelText: 'Title'),
          enabled: !state.isBusy,
          maxLength: 80,
          onChanged: context.read<PaymentPageCubit>().setHeader,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          enabled: !state.isBusy,
          maxLength: 280,
          maxLines: 4,
          onChanged: context.read<PaymentPageCubit>().setDescription,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: state.displayCurrency,
          decoration: const InputDecoration(labelText: 'Display currency'),
          key: ValueKey(state.displayCurrency),
          items: paymentPageSupportedDisplayCurrencies
              .map(
                (currency) =>
                    DropdownMenuItem(value: currency, child: Text(currency)),
              )
              .toList(growable: false),
          onChanged: state.isBusy || state.isSaving
              ? null
              : (value) {
                  if (value == null) return;
                  context.read<PaymentPageCubit>().setDisplayCurrency(value);
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: websiteController,
          decoration: const InputDecoration(labelText: 'Website'),
          enabled: !state.isBusy,
          keyboardType: TextInputType.url,
          onChanged: context.read<PaymentPageCubit>().setWebsite,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: twitterController,
          decoration: const InputDecoration(labelText: 'Twitter'),
          enabled: !state.isBusy,
          onChanged: context.read<PaymentPageCubit>().setTwitter,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: instagramController,
          decoration: const InputDecoration(labelText: 'Instagram'),
          enabled: !state.isBusy,
          onChanged: context.read<PaymentPageCubit>().setInstagram,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: state.enabled,
          title: const Text('Enabled'),
          onChanged: state.isBusy
              ? null
              : context.read<PaymentPageCubit>().setEnabled,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.isBusy
              ? null
              : context.read<PaymentPageCubit>().save,
          child: Text(state.isSaving ? 'Saving...' : 'Save'),
        ),
        if (state.hasExistingPage) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: state.isBusy
                ? null
                : context.read<PaymentPageCubit>().archive,
            child: Text(state.isArchiving ? 'Archiving...' : 'Archive'),
          ),
        ],
        if (state.saved || state.archived) ...[
          const SizedBox(height: 12),
          Text(state.saved ? 'Saved' : 'Archived'),
        ],
      ],
    );
  }
}

class _EmptyNymView extends StatelessWidget {
  const _EmptyNymView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Create a Lightning Address before creating a payment page',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
