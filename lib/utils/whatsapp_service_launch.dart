class WhatsappServiceLaunch {
  final String token;
  final String languageCode;

  const WhatsappServiceLaunch({
    required this.token,
    required this.languageCode,
  });
}

WhatsappServiceLaunch? whatsappServiceLaunchFromUri(Uri uri) {
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path != '/whatsapp-service') return null;
  final language = uri.queryParameters['lang']?.trim().toLowerCase();
  return WhatsappServiceLaunch(
    token: uri.queryParameters['token']?.trim() ?? '',
    languageCode: language == 'hi' || language == 'mr' ? language! : 'en',
  );
}
