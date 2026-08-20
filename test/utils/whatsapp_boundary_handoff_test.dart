import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/utils/whatsapp_boundary_handoff.dart';

void main() {
  test('accepts the exact WhatsApp handoff URL shape', () {
    final uri = whatsappBoundaryHandoffUri(
      'https://wa.me/919876543210?text=CONTINUE',
    );

    expect(uri, isNotNull);
    expect(uri!.host, 'wa.me');
    expect(uri.queryParameters['text'], 'CONTINUE');
  });

  test('rejects arbitrary URLs and invalid phone paths', () {
    expect(whatsappBoundaryHandoffUri('https://example.com/continue'), isNull);
    expect(whatsappBoundaryHandoffUri('https://wa.me/not-a-phone'), isNull);
    expect(whatsappBoundaryHandoffUri('https://wa.me/12345'), isNull);
  });
}
