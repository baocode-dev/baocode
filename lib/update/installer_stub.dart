import 'update_service.dart';

/// No updates where there is no dart:io (the web).
PlatformUpdates? platformUpdates({required String updatesDirectory}) => null;

/// What updates the app where it runs (installer_io.dart's).
class PlatformUpdates {
  const PlatformUpdates({
    required this.platform,
    required this.manifestUrl,
    required this.backend,
    required this.installer,
  });

  final String platform;
  final Uri manifestUrl;
  final UpdateBackend backend;
  final UpdateInstaller installer;
}
