Uri? whatsappServiceHandoffUri(String? value) {
  final candidate = Uri.tryParse(value?.trim() ?? '');
  if (candidate == null ||
      candidate.scheme != 'https' ||
      candidate.host != 'wa.me') {
    return null;
  }
  final phone = candidate.pathSegments.length == 1
      ? candidate.pathSegments.single
      : '';
  if (!RegExp(r'^\d{10,15}$').hasMatch(phone)) return null;
  return candidate;
}
