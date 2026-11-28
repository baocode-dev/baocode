import 'dart:async';

import 'package:flutter/foundation.dart';

import 'icon_library.dart';
import 'site_icon.dart';

/// How a site's icon is fetched: [fetchSiteIcon]'s way.
typedef SiteIconFetch = Future<IconImage?> Function(
  Uri site,
  Future<IconImage> Function(Uint8List bytes) take,
);

/// The icons of the sites of upstreams of models that show no other:
/// fetched the first time one is asked for, in the background, and kept
/// (by host) in a library of their own, not among the pictures the user
/// uploaded. Tells its listeners as one comes.
class SiteIcons extends ChangeNotifier {
  SiteIcons({IconLibrary? library, SiteIconFetch? fetch})
    : _library = library ?? IconLibrary(),
      _fetch = fetch ?? fetchSiteIcon;

  /// The app's; main() keeps it in the cache.
  static SiteIcons current = SiteIcons();

  final IconLibrary _library;
  final SiteIconFetch _fetch;

  /// The picture of each host fetched while the app runs, by id: the
  /// library keeps a picture once, under the first name it came with.
  final Map<String, String> _ids = {};

  /// How many pictures were in [_library] when [_ids] was last indexed,
  /// so lookups stay O(1) even in long conversations with many sites.
  int _indexedCount = -1;

  /// The hosts looked up while the app runs (found, not, or under way):
  /// each once.
  final Set<String> _asked = {};

  /// Queued lookups waiting for an in-flight slot, so scrolling quickly past
  /// many turns does not burst dozens of concurrent favicon requests.
  final List<(Uri, String)> _queue = [];
  int _inFlight = 0;
  static const _maxConcurrent = 6;

  /// [site]'s icon, kept from before or fetched since; null while it is
  /// not there (it is fetched then, once), or when the site has none.
  IconImage? of(Uri site) {
    final host = site.host.toLowerCase();
    if (host.isEmpty) return null;
    if (_kept(host) case final image?) return image;
    request(site);
    return null;
  }

  /// Fetches [site]'s icon, unless it is kept or was asked for already.
  void request(Uri site) {
    final host = site.host.toLowerCase();
    if (host.isEmpty || !_asked.add(host)) return;
    _queue.add((site, host));
    _pump();
  }

  void _pump() {
    while (_inFlight < _maxConcurrent && _queue.isNotEmpty) {
      final (site, host) = _queue.removeAt(0);
      _inFlight++;
      unawaited(
        _lookUp(site, host).whenComplete(() {
          _inFlight--;
          _pump();
        }),
      );
    }
  }

  IconImage? _kept(String host) {
    if (_ids[host] case final id?) {
      final image = _library[id];
      if (image != null) return image;
      _ids.remove(host);
    }
    final images = _library.images;
    if (images.length != _indexedCount) {
      _indexedCount = images.length;
      for (final image in images) {
        if (image.name.isNotEmpty) _ids.putIfAbsent(image.name, () => image.id);
      }
      if (_ids[host] case final id?) return _library[id];
    }
    return null;
  }

  Future<void> _lookUp(Uri site, String host) async {
    await _library.load();
    final image =
        _kept(host) ??
        await _fetch(site, (bytes) => _library.add(bytes, name: host));
    if (image == null) return;
    _ids[host] = image.id;
    notifyListeners();
  }
}
