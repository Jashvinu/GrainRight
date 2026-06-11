import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

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
  final completer = Completer<HarvestMachineCaptureResult?>();

  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;
  if (source == HarvestMachineImageSource.camera) {
    input.setAttribute('capture', 'environment');
  }

  void finishNull() {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      finishNull();
      return;
    }

    final file = files[0];
    if (file == null) {
      finishNull();
      return;
    }
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      Uint8List? bytes;

      if (result is ByteBuffer) {
        bytes = result.asUint8List();
      } else if (result is String) {
        final raw = result;
        final index = raw.indexOf(',');
        final data = index >= 0 ? raw.substring(index + 1) : raw;
        try {
          bytes = base64Decode(data);
        } catch (_) {
          bytes = null;
        }
      } else if (result is Uint8List) {
        bytes = result;
      } else if (result is List<int>) {
        bytes = Uint8List.fromList(result);
      }

      if (!completer.isCompleted) {
        if (bytes == null) {
          completer.complete(null);
          return;
        }
        completer.complete(
          HarvestMachineCaptureResult(
            bytes: bytes,
            name: file.name.isNotEmpty ? file.name : 'machine-image.jpg',
          ),
        );
      }
    });

    reader.onError.listen((_) => finishNull());
    reader.readAsArrayBuffer(file);
  });

  input.click();

  return completer.future;
}
