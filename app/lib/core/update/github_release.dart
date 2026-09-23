import 'dart:convert';

/// One downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUri,
    required this.size,
  });

  final String name;
  final Uri downloadUri;
  final int size;
}

/// The public, non-draft release metadata used by the in-app updater.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.title,
    required this.releaseUri,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final String version;
  final String title;
  final Uri releaseUri;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;
}

/// Parses only the small subset of GitHub's latest-release response that the
/// app needs. Download links are accepted only from GitHub over HTTPS.
ReleaseInfo parseGitHubRelease(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Release response is not an object');
  }

  final tag = decoded['tag_name'];
  final htmlUrl = decoded['html_url'];
  if (tag is! String || tag.trim().isEmpty || htmlUrl is! String) {
    throw const FormatException('Release response is missing required fields');
  }
  final releaseUri = Uri.tryParse(htmlUrl);
  if (!_isTrustedGitHubUri(releaseUri)) {
    throw const FormatException('Release page is not a trusted GitHub URL');
  }

  final assets = <ReleaseAsset>[];
  final rawAssets = decoded['assets'];
  if (rawAssets is List) {
    for (final item in rawAssets) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['name'];
      final url = item['browser_download_url'];
      final size = item['size'];
      if (name is! String || url is! String || size is! num) continue;
      final uri = Uri.tryParse(url);
      if (!_isTrustedGitHubUri(uri)) continue;
      assets.add(
        ReleaseAsset(name: name, downloadUri: uri!, size: size.toInt()),
      );
    }
  }

  final rawPublishedAt = decoded['published_at'];
  return ReleaseInfo(
    tagName: tag,
    version: normalizeVersion(tag),
    title: (decoded['name'] as String?)?.trim().isNotEmpty == true
        ? (decoded['name'] as String).trim()
        : tag,
    releaseUri: releaseUri!,
    publishedAt: rawPublishedAt is String
        ? DateTime.tryParse(rawPublishedAt)?.toLocal()
        : null,
    assets: List.unmodifiable(assets),
  );
}

bool _isTrustedGitHubUri(Uri? uri) {
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  return uri.host == 'github.com' || uri.host.endsWith('.github.com');
}

String normalizeVersion(String value) {
  final trimmed = value.trim();
  final withoutPrefix = trimmed.startsWith('v') || trimmed.startsWith('V')
      ? trimmed.substring(1)
      : trimmed;
  return withoutPrefix.split('+').first;
}

/// Returns a positive number when [left] is newer than [right].
///
/// Stable versions sort above their pre-release for the same numeric version.
int compareVersions(String left, String right) {
  final a = _ParsedVersion.parse(left);
  final b = _ParsedVersion.parse(right);
  for (var i = 0; i < 3; i++) {
    final result = a.numbers[i].compareTo(b.numbers[i]);
    if (result != 0) return result;
  }
  if (a.preRelease == b.preRelease) return 0;
  if (a.preRelease == null) return 1;
  if (b.preRelease == null) return -1;
  return _comparePreRelease(a.preRelease!, b.preRelease!);
}

int _comparePreRelease(String left, String right) {
  final a = left.split('.');
  final b = right.split('.');
  for (var i = 0; i < a.length || i < b.length; i++) {
    if (i >= a.length) return -1;
    if (i >= b.length) return 1;
    final ai = int.tryParse(a[i]);
    final bi = int.tryParse(b[i]);
    final result = switch ((ai, bi)) {
      (final int x, final int y) => x.compareTo(y),
      (final int _, null) => -1,
      (null, final int _) => 1,
      _ => a[i].compareTo(b[i]),
    };
    if (result != 0) return result;
  }
  return 0;
}

class _ParsedVersion {
  const _ParsedVersion(this.numbers, this.preRelease);

  factory _ParsedVersion.parse(String raw) {
    final normalized = normalizeVersion(raw);
    final split = normalized.split('-');
    final numeric = split.first.split('.');
    return _ParsedVersion(
      List<int>.generate(
        3,
        (i) => i < numeric.length ? int.tryParse(numeric[i]) ?? 0 : 0,
      ),
      split.length > 1 ? split.skip(1).join('-') : null,
    );
  }

  final List<int> numbers;
  final String? preRelease;
}

/// Picks the best asset for the running platform. Unknown layouts safely fall
/// back to the release page instead of guessing a binary.
ReleaseAsset? selectReleaseAsset(
  List<ReleaseAsset> assets, {
  required String platform,
  List<String> androidAbis = const [],
}) {
  final lowerPlatform = platform.toLowerCase();
  final candidates = assets
      .where((asset) => asset.name.toLowerCase().startsWith('suvishare-'))
      .toList(growable: false);

  ReleaseAsset? firstMatching(bool Function(String name) predicate) {
    for (final asset in candidates) {
      if (predicate(asset.name.toLowerCase())) return asset;
    }
    return null;
  }

  if (lowerPlatform == 'android') {
    final abis = androidAbis.map((abi) => abi.toLowerCase()).toList();
    if (abis.any((abi) => abi.contains('arm64'))) {
      final arm64 = firstMatching(
        (name) => name.contains('android-arm64') && name.endsWith('.apk'),
      );
      if (arm64 != null) return arm64;
    }
    if (abis.any((abi) => abi.contains('armeabi') || abi == 'arm')) {
      final arm32 = firstMatching(
        (name) => name.contains('android-arm32') && name.endsWith('.apk'),
      );
      if (arm32 != null) return arm32;
    }
    if (abis.any((abi) => abi.contains('x86_64'))) {
      final x64 = firstMatching(
        (name) => name.contains('android-x86_64') && name.endsWith('.apk'),
      );
      if (x64 != null) return x64;
    }
    return firstMatching(
      (name) => name.contains('android-universal') && name.endsWith('.apk'),
    );
  }
  if (lowerPlatform == 'windows') {
    return firstMatching(
      (name) => name.contains('windows-x64-setup') && name.endsWith('.exe'),
    );
  }
  if (lowerPlatform == 'linux') {
    return firstMatching(
          (name) => name.contains('linux-amd64') && name.endsWith('.deb'),
        ) ??
        firstMatching(
          (name) => name.contains('linux-x64') && name.endsWith('.tar.gz'),
        );
  }
  return null;
}
