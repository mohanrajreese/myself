/// Architecture and privacy boundary rules, checked against `lib/` sources.
///
/// Kept as a pure function over (path, content) pairs so the rules themselves
/// are unit-tested with fixtures in `boundary_rules_test.dart`.
library;

class Violation {
  const Violation(this.rule, this.path, this.detail);
  final String rule;
  final String path;
  final String detail;

  @override
  String toString() => '[$rule] $path: $detail';
}

const _pureCoreDirs = ['core/errors/', 'core/utils/', 'core/units/', 'core/scheduling/'];
const _purePackages = {'meta', 'collection', 'clock', 'freezed_annotation', 'json_annotation', 'uuid'};
const _storagePackages = {
  'drift',
  'drift_flutter',
  'sqlite3',
  'supabase_flutter',
  'supabase',
  'flutter_secure_storage',
};

final _importPattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

/// Resolves an import URI to a path relative to `lib/`, or null when it does
/// not point into this package.
String? _libPath(String fromPath, String uri) {
  if (uri.startsWith('package:fitbuddy/')) return uri.substring('package:fitbuddy/'.length);
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;
  final segments = fromPath.split('/')..removeLast();
  for (final part in uri.split('/')) {
    if (part == '..') {
      if (segments.isNotEmpty) segments.removeLast();
    } else if (part != '.') {
      segments.add(part);
    }
  }
  return segments.join('/');
}

String? _feature(String libPath) {
  final match = RegExp(r'^features/([^/]+)/').firstMatch(libPath);
  return match?.group(1);
}

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart') || path.startsWith('core/platform/generated/');

/// [sources] maps a path relative to `lib/` to the file's content.
List<Violation> checkBoundaries(Map<String, String> sources) {
  final violations = <Violation>[];

  for (final entry in sources.entries) {
    final path = entry.key;
    final content = entry.value;
    if (_isGenerated(path)) continue;

    final imports = _importPattern.allMatches(content).map((m) => m.group(1)!).toList();
    final isDomain = path.contains('/domain/');
    final isPresentation = path.contains('/presentation/') || path.startsWith('core/widgets/');
    final isSyncSide =
        path.startsWith('core/sync/') || path.startsWith('core/networking/') || path.endsWith('_remote_source.dart');
    final ownFeature = _feature(path);

    for (final uri in imports) {
      final target = _libPath(path, uri);
      final package = uri.startsWith('package:') ? uri.substring(8).split('/').first : null;

      if (isDomain) {
        final okDart = uri.startsWith('dart:') && uri != 'dart:io' && uri != 'dart:ui';
        final okPackage = package != null && package != 'fitbuddy' && _purePackages.contains(package);
        final okInternal = target != null && (target.contains('/domain/') || _pureCoreDirs.any(target.startsWith));
        if (!(okDart || okPackage || okInternal)) {
          violations.add(Violation('domain-purity', path, 'imports $uri'));
        }
      }

      if (isPresentation) {
        if (package != null && _storagePackages.contains(package)) {
          violations.add(Violation('presentation-no-storage', path, 'imports $uri'));
        }
        if (target != null && target.contains('/data/')) {
          violations.add(Violation('presentation-no-data-layer', path, 'imports $uri'));
        }
      }

      if (ownFeature != null && target != null) {
        final otherFeature = _feature(target);
        if (otherFeature != null && otherFeature != ownFeature && !target.contains('/domain/')) {
          violations.add(Violation('feature-isolation', path, 'imports $uri'));
        }
      }

      if (isSyncSide && target != null) {
        if (target.contains('private_database') || target.contains('/private/')) {
          violations.add(Violation('privacy-sync-boundary', path, 'imports $uri'));
        }
      }
    }

    if (isPresentation && content.contains('MethodChannel(')) {
      violations.add(Violation('presentation-no-platform-channel', path, 'uses MethodChannel'));
    }

    if (path != 'core/utils/clock.dart' && RegExp(r'DateTime\.now\(').hasMatch(_stripComments(content))) {
      violations.add(Violation('injected-clock', path, 'calls DateTime.now()'));
    }

    final isFeatureUi = path.startsWith('features/') && path.contains('/presentation/');
    if (isFeatureUi && RegExp(r'\bColor\(0x').hasMatch(_stripComments(content))) {
      violations.add(Violation('design-tokens', path, 'uses a literal Color'));
    }
  }
  return violations;
}

String _stripComments(String content) =>
    content.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '').replaceAll(RegExp(r'//.*'), '');
