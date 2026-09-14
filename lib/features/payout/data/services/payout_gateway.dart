/// Abstraction over whatever actually moves the money once a payout has
/// been recorded in `payout_history` — a bank transfer rail, an e-wallet
/// payout API, etc.
///
/// [PayoutViewModel] never talks to a payment provider directly; it only
/// goes through this interface, so swapping the mock below for a real
/// gateway (Stripe Connect payouts, DuitNow, TnG's business API...) is a
/// single-class change instead of a rewrite of the view model.
abstract class PayoutGateway {
// ui only processing status
  Stream<String> process(String payoutId);
}

// payout marked as paid when success dialog is on screen
class MockPayoutGateway implements PayoutGateway {
  @override
  Stream<String> process(String payoutId) async* {
    await Future.delayed(const Duration(milliseconds: 500));
    yield 'completed';
  }
}