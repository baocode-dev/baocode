// Writes small ZIP archives (and so .vsix packages) for tests: stored or
// deflated entries, no Zip64.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Uint8List buildZip(Map<String, List<int>> files, {bool deflate = true}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  for (final MapEntry(key: name, value: content) in files.entries) {
    final nameBytes = utf8.encode(name);
    final compressed = deflate
        ? ZLibEncoder(raw: true).convert(content)
        : content;
    final method = deflate ? 8 : 0;
    final crc = _crc32(content);
    final offset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x800, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, compressed.length, Endian.little)
      ..setUint32(22, content.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(compressed);
    final entry = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x800, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, compressed.length, Endian.little)
      ..setUint32(24, content.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(entry.buffer.asUint8List())
      ..add(nameBytes);
    count++;
  }
  final centralOffset = out.length;
  final centralBytes = central.takeBytes();
  out.add(centralBytes);
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, centralBytes.length, Endian.little)
    ..setUint32(16, centralOffset, Endian.little);
  out.add(end.buffer.asUint8List());
  return out.takeBytes();
}

/// A .vsix of [files] (paths under `extension/`), with [vsixManifest].
Uint8List buildVsix(
  Map<String, Object> files, {
  String? vsixManifest,
  bool deflate = true,
}) => buildZip({
  '[Content_Types].xml': utf8.encode('<Types/>'),
  'extension.vsixmanifest': ?(vsixManifest == null
      ? null
      : utf8.encode(vsixManifest)),
  for (final MapEntry(:key, :value) in files.entries)
    'extension/$key': value is String
        ? utf8.encode(value)
        : value is List<int>
        ? value
        : utf8.encode(jsonEncode(value)),
}, deflate: deflate);

/// Writes [files] (JSON-encoded when not a string or bytes) under [dir].
void writeFolder(String dir, Map<String, Object> files) {
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('$dir/$key')..parent.createSync(recursive: true);
    if (value is List<int>) {
      file.writeAsBytesSync(value);
    } else {
      file.writeAsStringSync(value is String ? value : jsonEncode(value));
    }
  }
}

String vsixManifestXml({
  required String publisher,
  required String id,
  required String version,
  String? targetPlatform,
  bool preRelease = false,
}) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="$id" Version="$version" Publisher="$publisher" ${targetPlatform == null ? '' : 'TargetPlatform="$targetPlatform"'}/>
    <DisplayName>Tool &amp; More</DisplayName>
    <Description xml:space="preserve">From the vsixmanifest</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.80.0" />
      ${preRelease ? '<Property Id="Microsoft.VisualStudio.Code.PreRelease" Value="true" />' : ''}
    </Properties>
  </Metadata>
</PackageManifest>
''';

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}
