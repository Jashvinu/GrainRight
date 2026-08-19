import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/utils/whatsapp_boundary_launch.dart';

void main() {
  test('extracts a token from the standalone boundary path', () {
    final token = whatsappBoundaryTokenFromUri(
      Uri.parse('/whatsapp-farm-boundary?token=%20valid-token%20'),
    );

    expect(token, 'valid-token');
  });

  test('accepts a trailing slash without hijacking the token', () {
    final token = whatsappBoundaryTokenFromUri(
      Uri.parse('/whatsapp-farm-boundary/?token=valid-token'),
    );

    expect(token, 'valid-token');
  });

  test('keeps normal app routes on the regular application shell', () {
    expect(
      whatsappBoundaryTokenFromUri(Uri.parse('/farmer?token=valid-token')),
      isNull,
    );
  });

  test('returns an empty token for the standalone path without a token', () {
    expect(
      whatsappBoundaryTokenFromUri(Uri.parse('/whatsapp-farm-boundary')),
      '',
    );
  });
}
