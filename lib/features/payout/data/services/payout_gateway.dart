/// Abstraction over whatever actually moves the money once a payout has
/// been recorded in `payout_history` — a bank transfer rail, an e-wallet
/// payout API, etc.
///
/// [PayoutViewModel] never talks to a payment provider directly; it only
/// goes through this interface, so swapping the mock below for a real
/// gateway (Stripe Connect payouts, DuitNow, TnG's business API...) is a
/// single-class change instead of a rewrite of the view model.
abstract class PayoutGateway {
  /// Kicks off processing for [payoutId] and reports each status change
  /// as it happens. The stream should complete after emitting a terminal
  /// status ('completed' or 'failed' — the two terminal values
  /// payout_history's CHECK constraint allows; 'processing' is a valid
  /// mid-stream value but is UI-only and never persisted).
  Stream<String> process(String payoutId);
}

/// Demo/dev stand-in — no real money moves. Marks the payout completed
/// almost immediately once the success dialog is on screen, for both
/// payment methods. This is a deliberate demo simplification, not a
/// claim about real-world timing: a real TnG eWallet payout does settle
/// near-instantly (a direct wallet-to-wallet API call), but a real bank
/// transfer genuinely takes days to clear through interbank rails. A
/// production [PayoutGateway] for bank transfers would need to report
/// 'pending' for as long as that actually takes (via a webhook or a
/// reconciliation job), not emit 'completed' after half a second like
/// this mock does.
///
/// This is intentionally still mocked: a real payout rail needs a
/// registered business account and signed API agreement with a bank or
/// TnG (and, for Stripe, a Malaysia-eligible Connect setup) — none of
/// which exist for this project. Swap this class out for a real
/// implementation of [PayoutGateway] once those credentials exist; the
/// view model doesn't need to change.
class MockPayoutGateway implements PayoutGateway {
  @override
  Stream<String> process(String payoutId) async* {
    await Future.delayed(const Duration(milliseconds: 500));
    yield 'completed';
  }
}