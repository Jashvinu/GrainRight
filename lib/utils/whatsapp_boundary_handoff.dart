/// Returns the only URL shape the boundary page may open after a successful
/// save. Keeping this allowlist in the client prevents a compromised response
/// from turning a map-save link into an arbitrary browser redirect.
Uri? whatsappBoundaryHandoffUri(String? value) {
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
