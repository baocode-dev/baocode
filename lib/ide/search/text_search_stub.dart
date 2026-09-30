import 'text_search.dart';

Stream<Object> searchText(String root, IdeTextQuery query) =>
    Stream.error(UnsupportedError('Searching files is not supported here.'));
