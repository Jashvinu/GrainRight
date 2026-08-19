class WhatsappBoundaryLaunch {
  final String token;
  final String languageCode;

  const WhatsappBoundaryLaunch({
    required this.token,
    required this.languageCode,
  });
}

WhatsappBoundaryLaunch? whatsappBoundaryLaunchFromUri(Uri uri) {
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path != '/whatsapp-farm-boundary') return null;
  final language = uri.queryParameters['lang']?.trim().toLowerCase();
  return WhatsappBoundaryLaunch(
    token: uri.queryParameters['token']?.trim() ?? '',
    languageCode: language == 'hi' || language == 'mr' ? language! : 'en',
  );
}

String? whatsappBoundaryTokenFromUri(Uri uri) =>
    whatsappBoundaryLaunchFromUri(uri)?.token;
