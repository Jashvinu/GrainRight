import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

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
  final picker = ImagePicker();
  final image = await picker.pickImage(
    source: source == HarvestMachineImageSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 88,
    maxWidth: 1920,
  );
  if (image == null) return null;

  final bytes = await image.readAsBytes();
  if (bytes.isEmpty) return null;

  return HarvestMachineCaptureResult(
    bytes: bytes,
    name: image.name.isNotEmpty ? image.name : 'machine-image.jpg',
  );
}
