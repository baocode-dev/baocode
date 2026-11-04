/// Where the phone app is downloaded: its links on the site, the same the
/// download page's buttons and QR codes lead to (site/download.html,
/// tool/make_download_qr.dart), and Settings → Mobile's codes too. Links
/// that last: site-worker/index.js points them at the release current when
/// one is scanned, so a code shown or photographed keeps working.
library;

/// The site they are on.
const phoneDownloadSite = 'https://baocode.dev';

/// Each phone's link on [phoneDownloadSite], by the download page's card:
/// Android's APK, iOS's TestFlight beta.
const phoneDownloadTargets = {'android': '/dl/android', 'ios': '/dl/ios'};

/// [os]'s download, in full.
String phoneDownloadUrl(String os) =>
    '$phoneDownloadSite${phoneDownloadTargets[os]}';
