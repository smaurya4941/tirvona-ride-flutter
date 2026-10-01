import 'package:flutter/foundation.dart';

enum BrandAssetKind {
  logo,
  splash;

  static BrandAssetKind? tryParse(String value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// One admin-set image as the API publishes it (`GET /branding`).
@immutable
class RemoteBrandAsset {
  const RemoteBrandAsset({
    required this.kind,
    required this.path,
    required this.version,
    required this.contentType,
  });

  factory RemoteBrandAsset.fromJson(
    BrandAssetKind kind,
    Map<String, dynamic> json,
  ) => RemoteBrandAsset(
    kind: kind,
    path: json['path'] as String,
    version: json['version'] as String,
    contentType: json['contentType'] as String? ?? 'image/png',
  );

  final BrandAssetKind kind;

  /// Relative to the versioned API base; changes with every new image.
  final String path;
  final String version;
  final String contentType;

  String get fileExtension => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    _ => 'png',
  };
}

/// What the server says right now. A `null` kind means "use the default
/// bundled in the app".
@immutable
class RemoteBranding {
  const RemoteBranding({this.logo, this.splash});

  factory RemoteBranding.fromJson(Map<String, dynamic> json) {
    RemoteBrandAsset? parse(BrandAssetKind kind) {
      final value = json[kind.name];
      return value is Map<String, dynamic>
          ? RemoteBrandAsset.fromJson(kind, value)
          : null;
    }

    return RemoteBranding(
      logo: parse(BrandAssetKind.logo),
      splash: parse(BrandAssetKind.splash),
    );
  }

  final RemoteBrandAsset? logo;
  final RemoteBrandAsset? splash;

  RemoteBrandAsset? operator [](BrandAssetKind kind) => switch (kind) {
    BrandAssetKind.logo => logo,
    BrandAssetKind.splash => splash,
  };
}

/// An admin-set image already downloaded to this phone.
@immutable
class CachedBrandImage {
  const CachedBrandImage({required this.version, required this.filePath});

  factory CachedBrandImage.fromJson(Map<String, dynamic> json) =>
      CachedBrandImage(
        version: json['version'] as String,
        filePath: json['file'] as String,
      );

  final String version;
  final String filePath;

  Map<String, dynamic> toJson() => {'version': version, 'file': filePath};

  @override
  bool operator ==(Object other) =>
      other is CachedBrandImage &&
      other.version == version &&
      other.filePath == filePath;

  @override
  int get hashCode => Object.hash(version, filePath);
}

/// The branding the app shows. `null` = the bundled default
/// (`assets/images/logo.png`, `assets/images/splash_art.png`).
@immutable
class BrandingState {
  const BrandingState({this.logo, this.splash});

  static const defaults = BrandingState();

  factory BrandingState.fromJson(Map<String, dynamic> json) {
    CachedBrandImage? parse(String key) {
      final value = json[key];
      return value is Map<String, dynamic>
          ? CachedBrandImage.fromJson(value)
          : null;
    }

    return BrandingState(logo: parse('logo'), splash: parse('splash'));
  }

  final CachedBrandImage? logo;
  final CachedBrandImage? splash;

  CachedBrandImage? operator [](BrandAssetKind kind) => switch (kind) {
    BrandAssetKind.logo => logo,
    BrandAssetKind.splash => splash,
  };

  BrandingState withImage(BrandAssetKind kind, CachedBrandImage? image) =>
      switch (kind) {
        BrandAssetKind.logo => BrandingState(logo: image, splash: splash),
        BrandAssetKind.splash => BrandingState(logo: logo, splash: image),
      };

  Map<String, dynamic> toJson() => {
    if (logo != null) 'logo': logo!.toJson(),
    if (splash != null) 'splash': splash!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is BrandingState && other.logo == logo && other.splash == splash;

  @override
  int get hashCode => Object.hash(logo, splash);
}
