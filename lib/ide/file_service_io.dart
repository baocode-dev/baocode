import 'package:bao_remote/local.dart';

import 'file_service.dart';

export 'package:bao_remote/local.dart'
    show readFileBytes, walkProjectFiles, watchDirectory;

class LocalIdeFileService extends LocalFiles implements IdeFileService {
  LocalIdeFileService(super.root);
}
