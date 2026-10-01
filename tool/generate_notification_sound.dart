// Writes assets/sounds/microwave.wav: the "ding" notifications play by
// default (lib/notifications/notification_sound.dart), a microwave's bell
// made from scratch so that it is ours to ship.
//
// A small struck dome bell: a few inharmonic partials, each dying away at
// its own rate (the high ones first), the fundamental a pair a few hertz
// apart so it shimmers as a real bell does, and a click of noise for the
// strike.
//
//   dart run tool/generate_notification_sound.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;
const _seconds = 1.6;

/// The bell's fundamental, in hertz.
const _fundamental = 1650.0;

/// Partials of a struck dome: frequency ratio, amplitude, decay time (to
/// 1/e, seconds).
const _partials = [
  (ratio: 1.0, amplitude: 1.0, decay: 0.55),
  (ratio: 1.0018, amplitude: 0.6, decay: 0.5), // beats with the first
  (ratio: 2.32, amplitude: 0.42, decay: 0.24),
  (ratio: 4.25, amplitude: 0.16, decay: 0.11),
  (ratio: 6.63, amplitude: 0.07, decay: 0.06),
];

/// The loudest sample, of full scale: a notification is not to startle.
const _peak = 0.5;

void main() {
  final count = (_sampleRate * _seconds).round();
  final samples = Float64List(count);
  final random = math.Random(7);
  for (var i = 0; i < count; i++) {
    final t = i / _sampleRate;
    // Struck, not switched on: 1.5ms to full.
    final attack = math.min(1.0, t / 0.0015);
    var value = 0.0;
    for (final (:ratio, :amplitude, :decay) in _partials) {
      value +=
          amplitude *
          math.exp(-t / decay) *
          math.sin(2 * math.pi * _fundamental * ratio * t);
    }
    // The strike: a few milliseconds of noise.
    value += 0.25 * math.exp(-t / 0.004) * (random.nextDouble() * 2 - 1);
    // No click at the very end.
    final release = math.min(1.0, (_seconds - t) / 0.05);
    samples[i] = value * attack * release;
  }
  final loudest = samples.fold(0.0, (m, s) => math.max(m, s.abs()));
  final pcm = ByteData(count * 2);
  for (var i = 0; i < count; i++) {
    final value = (samples[i] / loudest * _peak * 32767).round();
    pcm.setInt16(i * 2, value.clamp(-32768, 32767), Endian.little);
  }
  final file = File('assets/sounds/microwave.wav')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(_wav(pcm.buffer.asUint8List()));
  stdout.writeln('Wrote ${file.path} (${file.lengthSync()} bytes)');
}

/// 16-bit mono PCM [data] as a WAV file.
Uint8List _wav(Uint8List data) {
  final header = ByteData(44);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, _sampleRate, Endian.little);
  header.setUint32(28, _sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
}
