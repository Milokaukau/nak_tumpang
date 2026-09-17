abstract class PayoutGateway {
// ui only processing status
  Stream<String> process(String payoutId);
}

// payout goes through a brief 'processing' step before being marked paid
class MockPayoutGateway implements PayoutGateway {
  @override
  Stream<String> process(String payoutId) async* {
    yield 'processing';
    await Future.delayed(const Duration(milliseconds: 900));
    yield 'completed';
  }
}