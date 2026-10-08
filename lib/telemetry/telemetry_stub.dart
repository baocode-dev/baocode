import 'telemetry_service.dart';

/// No telemetry where there is no dart:io (the web).
PlatformTelemetry? platformTelemetry() => null;

/// What the app reports with (telemetry_io.dart's).
class PlatformTelemetry {
  const PlatformTelemetry({
    required this.url,
    required this.os,
    required this.arch,
    required this.sender,
  });

  final Uri url;
  final String os;
  final String arch;
  final TelemetrySender sender;
}
