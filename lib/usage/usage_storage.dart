// The calls' files, on a machine with them; in memory on the web.
export 'usage_storage_stub.dart'
    if (dart.library.io) 'usage_storage_io.dart'
    show usageStorageIn;
