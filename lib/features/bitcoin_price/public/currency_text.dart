/// The narrow public contract for rendering a Bitcoin amount.
///
/// [CurrencyText] is the only thing another feature needs from Bitcoin Price to
/// state an amount in the user's chosen unit while honoring the hide-amounts
/// setting. Publishing it here — rather than moving the widget — keeps this
/// feature's internal layout untouched while giving consumers a surface that is
/// not an internal path.
library;

export 'package:bb_mobile/features/bitcoin_price/ui/currency_text.dart'
    show CurrencyText;
