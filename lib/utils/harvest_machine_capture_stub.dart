import 'dart:typed_data';

enum HarvestMachineImageSource { camera, gallery }

class HarvestMachineCaptureResult {
  final Uint8List bytes;
  final String name;

  const HarvestMachineCaptureResult({
    required this.bytes,
    required this.name,
  });
}

Future<HarvestMachineCaptureResult?> pickHarvestMachineImage({
  HarvestMachineImageSource source = HarvestMachineImageSource.camera,
}) async {
  return null;
}
