import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

enum GameSound {
  tap,
  card,
  bid,
  trump,
  trick,
  deal,
  success,
  fail,
  reaction,
}

class GameAudio {
  GameAudio._();

  static final Map<GameSound, Uint8List> _cache = {};

  static Future<void> play(AudioPlayer player, GameSound sound) async {
    try {
      final bytes = _cache.putIfAbsent(sound, () => _buildWave(sound));
      await player.play(
        BytesSource(bytes, mimeType: 'audio/wav'),
        volume: sound == GameSound.card ? 0.34 : 0.48,
      );
    } catch (_) {
      // Audio must never interrupt a card action or the game connection.
    }
  }

  static Uint8List _buildWave(GameSound sound) {
    // Each entry is a short note/chord: frequencies (Hz), then duration (ms).
    final sequence = switch (sound) {
      GameSound.tap => <(List<double>, int)>[
          ([560], 48),
        ],
      GameSound.card => <(List<double>, int)>[
          ([760, 1140], 72),
        ],
      GameSound.bid => <(List<double>, int)>[
          ([590], 72),
          ([790], 90),
        ],
      GameSound.trump => <(List<double>, int)>[
          ([523], 75),
          ([659], 75),
          ([784, 1046], 135),
        ],
      GameSound.trick => <(List<double>, int)>[
          ([740], 62),
          ([587], 62),
          ([880, 1175], 125),
        ],
      GameSound.deal => <(List<double>, int)>[
          ([980], 45),
          ([720], 45),
          ([870], 45),
          ([610], 55),
        ],
      GameSound.success => <(List<double>, int)>[
          ([523, 659], 90),
          ([659, 784], 90),
          ([784, 988, 1175], 165),
        ],
      GameSound.fail => <(List<double>, int)>[
          ([392], 95),
          ([311], 100),
          ([220, 262], 165),
        ],
      GameSound.reaction => <(List<double>, int)>[
          ([650], 55),
          ([880], 65),
        ],
    };

    const sampleRate = 22050;
    const bytesPerSample = 2;
    final sampleCounts = sequence
        .map((entry) => (sampleRate * entry.$2 / 1000).round())
        .toList();
    final totalSamples = sampleCounts.fold<int>(0, (sum, count) => sum + count);
    final dataLength = totalSamples * bytesPerSample;
    final bytes = Uint8List(44 + dataLength);
    final header = ByteData.sublistView(bytes);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * bytesPerSample, Endian.little);
    header.setUint16(32, bytesPerSample, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);

    var sampleOffset = 0;
    var dataOffset = 44;
    for (var noteIndex = 0; noteIndex < sequence.length; noteIndex++) {
      final frequencies = sequence[noteIndex].$1;
      final count = sampleCounts[noteIndex];
      for (var i = 0; i < count; i++) {
        final progress = i / count;
        final attack = math.min(1.0, progress * 24);
        final release = math.min(1.0, (1 - progress) * 9);
        final envelope = attack * release;
        final time = (sampleOffset + i) / sampleRate;
        var wave = 0.0;
        for (final frequency in frequencies) {
          final phase = 2 * math.pi * frequency * (time - sampleOffset / sampleRate);
          wave += math.sin(phase) * .72 + math.sin(phase * 2) * .12;
        }
        wave /= frequencies.length;
        final value = (wave * envelope * .26 * 32767)
            .round()
            .clamp(-32768, 32767)
            .toInt();
        header.setInt16(dataOffset, value, Endian.little);
        dataOffset += bytesPerSample;
      }
      sampleOffset += count;
    }

    return bytes;
  }
}
