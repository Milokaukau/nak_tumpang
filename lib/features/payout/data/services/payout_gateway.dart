abstract class PayoutGateway {
  Stream<String> process(String payoutId);
}

class MockPayoutGateway implements PayoutGateway {
  @override
  Stream<String> process(String payoutId) async* {
    yield 'processing';
    await Future.delayed(const Duration(milliseconds: 900));
    yield 'completed';
  }
}