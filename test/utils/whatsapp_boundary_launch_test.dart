import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/utils/whatsapp_boundary_launch.dart';

void main() {
  test('extracts a token from the standalone boundary path', () {
    final launch = whatsappBoundaryLaunchFromUri(
      Uri.parse('/whatsapp-farm-boundary?token=%20valid-token%20&lang=hi'),
    );

    expect(launch?.token, 'valid-token');
    expect(launch?.languageCode, 'hi');
  });

  test('accepts a trailing slash without hijacking the token', () {
    final launch = whatsappBoundaryLaunchFromUri(
      Uri.parse('/whatsapp-farm-boundary/?token=valid-token&lang=mr'),
    );

    expect(launch?.token, 'valid-token');
    expect(launch?.languageCode, 'mr');
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

  test('uses English for an absent or unsupported language', () {
    expect(
      whatsappBoundaryLaunchFromUri(
        Uri.parse('/whatsapp-farm-boundary?token=valid-token'),
      )?.languageCode,
      'en',
    );
    expect(
      whatsappBoundaryLaunchFromUri(
        Uri.parse('/whatsapp-farm-boundary?token=valid-token&lang=ta'),
      )?.languageCode,
      'en',
    );
  });
}
