String? whatsappBoundaryTokenFromUri(Uri uri) {
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path != '/whatsapp-farm-boundary') return null;
  return uri.queryParameters['token']?.trim() ?? '';
}
