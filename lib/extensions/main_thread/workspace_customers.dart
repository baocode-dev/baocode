import 'package:bao_exthost/bao_exthost.dart';

import 'main_thread_context.dart';
import 'main_thread_file_system.dart';
import 'main_thread_file_system_event_service.dart';
import 'main_thread_search.dart';
import 'main_thread_workspace.dart';

/// The workspace, files, search and trust main thread actors, by
/// `MainContext` id, for `ExtensionHostService(customers: …)`.
final Map<int, MainThreadCustomer> workspaceCustomers = {
  MainContext.mainThreadWorkspace.nid: MainThreadWorkspace.customer,
  MainContext.mainThreadSearch.nid: MainThreadSearch.customer,
  MainContext.mainThreadFileSystem.nid: MainThreadFileSystem.customer,
  MainContext.mainThreadFileSystemEventService.nid:
      MainThreadFileSystemEventService.customer,
};
