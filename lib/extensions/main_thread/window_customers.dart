// The window, UI and app-service main thread actors, by `MainContext` id,
// for `ExtensionHostService(customers: …)`:
//
// ```dart
// final service = ExtensionHostService(
//   …,
//   customers: {
//     ...windowCustomers(),
//     ...commandsCustomers(),      // another area's
//     ...workspaceCustomers,        // another area's
//   },
//   services: {
//     // app-wide (one instance shared by every workspace's host):
//     IdeNotifications: notifications,
//     ExtensionStatusBarService: statusBar,
//     ExtensionCommandExecutor: commands,
//     ExtensionDialogs: dialogs,
//     ExtensionFilePickers: pickers,
//     ExtensionExternalOpener: opener,
//     ExtensionWindowFocus: focus,
//     ExtensionStorageService: storage,
//     ExtensionSecretService: secrets,
//     ExtensionAuthenticationUi: authenticationUi,
//     ExtensionUrlService: urls,
//     ExtensionWebviewPlaceholders: webviews,
//     ExtensionWebviewUi: webviewUi,
//     ExtensionQuickInputService: quickInputs,
//     ExtensionQuickInputUi: quickInputUi,
//     ExtensionMessageUi: messageUi,
//     // per workspace (created with the host):
//     RunningExtensionsService: runtime,
//     ExtensionProgressService: progress,
//     ExtensionOutputService: output,
//     ExtensionLabelService: labels,
//     ErrorLog: errors,
//   },
// );
// ```
//
// Each customer pulls what it needs from `context.service<T>()`: one that
// is missing is an error only when the extension host calls it (a host
// with no `ExtensionAuthenticationUi`, for one, answers the authentication
// calls as unsupported). `MainThreadStorage` and `MainThreadLogging`-like
// actors also need the `ExtensionHostService` itself, which the service
// puts into `services` for its own sessions.

import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_authentication.dart';
import 'main_thread_clipboard.dart';
import 'main_thread_console.dart';
import 'main_thread_context.dart';
import 'main_thread_errors.dart';
import 'main_thread_logger.dart';
import 'main_thread_output_service.dart';
import 'main_thread_secret_state.dart';
import 'main_thread_dialogs.dart';
import 'main_thread_download_service.dart';
import 'main_thread_extension_service.dart';
import 'main_thread_label_service.dart';
import 'main_thread_localization.dart';
import 'main_thread_message_service.dart';
import 'main_thread_metered_connection.dart';
import 'main_thread_power.dart';
import 'main_thread_progress.dart';
import 'main_thread_quick_open.dart';
import 'main_thread_status_bar.dart';
import 'main_thread_storage.dart';
import 'main_thread_telemetry.dart';
import 'main_thread_theming.dart';
import 'main_thread_urls.dart';
import 'main_thread_webviews.dart';
import 'main_thread_window.dart';

/// The `MainContext` ids this area implements, with their actors. The
/// output, logger, console and errors actors live with the output area and
/// are added by `outputCustomers`.
Map<int, MainThreadCustomer> windowCustomers() => {
  MainContext.mainThreadMessageService.nid: MainThreadMessageService.customer,
  MainContext.mainThreadProgress.nid: MainThreadProgress.customer,
  MainContext.mainThreadQuickOpen.nid: MainThreadQuickOpen.customer,
  MainContext.mainThreadStatusBar.nid: MainThreadStatusBar.customer,
  MainContext.mainThreadWindow.nid: MainThreadWindow.customer,
  MainContext.mainThreadClipboard.nid: MainThreadClipboard.customer,
  MainContext.mainThreadUrls.nid: MainThreadUrls.customer,
  MainContext.mainThreadStorage.nid: MainThreadStorage.customer,
  MainContext.mainThreadSecretState.nid: MainThreadSecretState.customer,
  MainContext.mainThreadAuthentication.nid: MainThreadAuthentication.customer,
  MainContext.mainThreadDialogs.nid: MainThreadDialogs.customer,
  MainContext.mainThreadLocalization.nid: MainThreadLocalization.customer,
  MainContext.mainThreadTelemetry.nid: MainThreadTelemetry.customer,
  MainContext.mainThreadLabelService.nid: MainThreadLabelService.customer,
  MainContext.mainThreadTheming.nid: MainThreadTheming.customer,
  MainContext.mainThreadDownloadService.nid:
      MainThreadDownloadService.customer,
  MainContext.mainThreadExtensionService.nid:
      MainThreadExtensionService.customer,
  MainContext.mainThreadPower.nid: MainThreadPower.customer,
  MainContext.mainThreadMeteredConnection.nid:
      MainThreadMeteredConnection.customer,
  // Output channels, logging, the ext host's console and its errors.
  MainContext.mainThreadOutputService.nid: MainThreadOutputService.customer,
  MainContext.mainThreadLogger.nid: MainThreadLogger.customer,
  MainContext.mainThreadConsole.nid: MainThreadConsole.customer,
  MainContext.mainThreadErrors.nid: MainThreadErrors.customer,
  // The Webview degradation (see main_thread_webviews.dart).
  MainContext.mainThreadWebviews.nid: MainThreadWebviews.customer,
  MainContext.mainThreadWebviewPanels.nid: MainThreadWebviewPanels.customer,
  MainContext.mainThreadWebviewViews.nid: MainThreadWebviewViews.customer,
  MainContext.mainThreadCustomEditors.nid: MainThreadCustomEditors.customer,
};
