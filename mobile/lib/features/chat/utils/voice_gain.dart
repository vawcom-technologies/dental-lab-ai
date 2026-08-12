import 'dart:math' as math;
import 'dart:typed_data';

/// Boosts quiet WAV voice notes by peak-normalizing 16-bit PCM.
///
/// Leaves non-WAV / non-PCM16 payloads unchanged. Caps gain so silence isn't
/// turned into loud noise.
Uint8List amplifyVoiceWav(
  Uint8List bytes, {
  double targetPeak = 0.88,
  double maxGain = 6.0,
}) {
  if (bytes.length < 44) return bytes;
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46) {
    return bytes;
  }

  final data = ByteData.sublistView(bytes);
  var offset = 12;
  var dataStart = -1;
  var dataSize = 0;
  var audioFormat = 0;
  var bitsPerSample = 0;

  while (offset + 8 <= bytes.length) {
    final id0 = bytes[offset];
    final id1 = bytes[offset + 1];
    final id2 = bytes[offset + 2];
    final id3 = bytes[offset + 3];
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkData = offset + 8;

    final isFmt = id0 == 0x66 && id1 == 0x6d && id2 == 0x74 && id3 == 0x20;
    final isData = id0 == 0x64 && id1 == 0x61 && id2 == 0x74 && id3 == 0x61;

    if (isFmt && chunkData + 16 <= bytes.length) {
      audioFormat = data.getUint16(chunkData, Endian.little);
      bitsPerSample = data.getUint16(chunkData + 14, Endian.little);
    } else if (isData) {
      dataStart = chunkData;
      dataSize = chunkSize;
      break;
    }

    offset = chunkData + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (dataStart < 0 ||
      dataSize <= 0 ||
      audioFormat != 1 ||
      bitsPerSample != 16) {
    return bytes;
  }

  final end = math.min(dataStart + dataSize, bytes.length);
  if (end - dataStart < 2) return bytes;

  var peak = 0;
  for (var i = dataStart; i + 1 < end; i += 2) {
    final sample = data.getInt16(i, Endian.little).abs();
    if (sample > peak) peak = sample;
  }
  if (peak < 32) return bytes; // near-silence — don't amplify noise floor

  final desired = (32767 * targetPeak).round();
  final gain = math.min(maxGain, desired / peak);
  if (gain <= 1.05) return bytes;

  final out = Uint8List.fromList(bytes);
  final outData = ByteData.sublistView(out);
  for (var i = dataStart; i + 1 < end; i += 2) {
    final sample = data.getInt16(i, Endian.little);
    final boosted = (sample * gain).round().clamp(-32768, 32767);
    outData.setInt16(i, boosted, Endian.little);
  }
  return out;
}
