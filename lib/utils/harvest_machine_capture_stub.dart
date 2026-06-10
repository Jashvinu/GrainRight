import 'dart:typed_data';

class HarvestMachineCaptureResult {
  final Uint8List bytes;
  final String name;

  const HarvestMachineCaptureResult({
    required this.bytes,
    required this.name,
  });
}

Future<HarvestMachineCaptureResult?> pickHarvestMachineImage() async {
  return null;
}
