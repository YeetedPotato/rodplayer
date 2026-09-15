enum JellyfinItemKind {
  movie,
  series,
  season,
  episode,
  boxSet,
  folder,
  collectionFolder,
  musicAlbum,
  audio,
  person,
  unknown;

  static JellyfinItemKind fromServer(String? value) => switch (value) {
        'Movie' => movie,
        'Series' => series,
        'Season' => season,
        'Episode' => episode,
        'BoxSet' => boxSet,
        'Folder' => folder,
        'CollectionFolder' => collectionFolder,
        'MusicAlbum' => musicAlbum,
        'Audio' => audio,
        'Person' => person,
        _ => unknown,
      };
}

class JellyfinUserData {
  const JellyfinUserData({
    this.isFavorite = false,
    this.played = false,
    this.playbackPositionTicks,
    this.playedPercentage,
  });

  final bool isFavorite;
  final bool played;
  final int? playbackPositionTicks;
  final double? playedPercentage;

  factory JellyfinUserData.fromJson(Object? value, {Map<String, dynamic> fallback = const <String, dynamic>{}}) {
    final json = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return JellyfinUserData(
      isFavorite: _bool(json['IsFavorite'] ?? fallback['IsFavorite']) ?? false,
      played: _bool(json['Played'] ?? fallback['Played']) ?? false,
      playbackPositionTicks: _integer(json['PlaybackPositionTicks'] ?? fallback['PlaybackPositionTicks']),
      playedPercentage: _double(json['PlayedPercentage'] ?? fallback['PlayedPercentage']),
    );
  }
}

class JellyfinItemsPage<T> {
  const JellyfinItemsPage({
    required this.items,
    this.totalRecordCount,
    this.startIndex,
  });

  final List<T> items;
  final int? totalRecordCount;
  final int? startIndex;
}

class JellyfinLibraryItem {
  const JellyfinLibraryItem({
    required this.id,
    required this.title,
    this.rawType,
    this.mediaType,
    this.seriesName,
    this.seriesId,
    this.seasonId,
    this.parentId,
    this.seasonNumber,
    this.episodeNumber,
    this.productionYear,
    this.premiereDate,
    this.overview,
    this.officialRating,
    this.communityRating,
    this.tagline,
    this.playbackPositionTicks,
    this.playedPercentage,
    this.runTimeTicks,
    this.primaryImageTag,
    this.backdropImageTags = const <String>[],
    this.thumbImageTag,
    this.primaryImageAspectRatio,
    this.userData = const JellyfinUserData(),
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String? rawType;
  final String? mediaType;
  final String? seriesName;
  final String? seriesId;
  final String? seasonId;
  final String? parentId;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? productionYear;
  final DateTime? premiereDate;
  final String? overview;
  final String? officialRating;
  final double? communityRating;
  final String? tagline;
  final int? playbackPositionTicks;
  final double? playedPercentage;
  final int? runTimeTicks;
  final String? primaryImageTag;
  final List<String> backdropImageTags;
  final String? thumbImageTag;
  final double? primaryImageAspectRatio;
  final JellyfinUserData userData;
  final Map<String, dynamic> raw;

  JellyfinItemKind get kind => JellyfinItemKind.fromServer(rawType);
  bool get isFavorite => userData.isFavorite;
  bool get played => userData.played;
  int? get posterImageTagHash => primaryImageTag == null ? null : primaryImageTag.hashCode;
  String? get posterImageTag => primaryImageTag;
  String? get backdropImageTag => backdropImageTags.isEmpty ? null : backdropImageTags.first;
  Duration? get playbackPosition => playbackPositionTicks == null ? null : Duration(microseconds: playbackPositionTicks! ~/ 10);
  Duration? get runTime => runTimeTicks == null ? null : Duration(microseconds: runTimeTicks! ~/ 10);

  factory JellyfinLibraryItem.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] is Map ? Map<String, dynamic>.from(json['ImageTags'] as Map) : const <String, dynamic>{};
    final userData = JellyfinUserData.fromJson(json['UserData'], fallback: json);
    return JellyfinLibraryItem(
      id: _string(json['Id']) ?? '',
      title: _string(json['Name'] ?? json['SeriesName']) ?? '',
      rawType: _string(json['Type']),
      mediaType: _string(json['MediaType']),
      seriesName: _string(json['SeriesName']),
      seriesId: _string(json['SeriesId']),
      seasonId: _string(json['SeasonId']),
      parentId: _string(json['ParentId']),
      seasonNumber: _integer(json['ParentIndexNumber'] ?? json['SeasonNumber']),
      episodeNumber: _integer(json['IndexNumber']),
      productionYear: _integer(json['ProductionYear']),
      premiereDate: _date(json['PremiereDate']),
      overview: _string(json['Overview']),
      officialRating: _string(json['OfficialRating']),
      communityRating: _double(json['CommunityRating']),
      tagline: _string(json['Tagline']),
      playbackPositionTicks: userData.playbackPositionTicks ?? _integer(json['PlaybackPositionTicks']),
      playedPercentage: userData.playedPercentage ?? _double(json['PlayedPercentage']),
      runTimeTicks: _integer(json['RunTimeTicks']),
      primaryImageTag: _string(imageTags['Primary'] ?? json['PrimaryImageTag'] ?? json['ImageTag']),
      backdropImageTags: _strings(json['BackdropImageTags'] ?? json['BackdropImageTag']),
      thumbImageTag: _string(imageTags['Thumb'] ?? json['ThumbImageTag']),
      primaryImageAspectRatio: _double(json['PrimaryImageAspectRatio']),
      userData: userData,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  String subtitle({String fallback = 'Media'}) {
    final year = productionYear;
    final type = rawType ?? mediaType ?? fallback;
    return year == null ? type : '$year · $type';
  }

  String? imageUrl(String baseUrl, {JellyfinImageType type = JellyfinImageType.primary, int? quality = 90}) => jellyfinImageUrl(
        baseUrl: baseUrl,
        itemId: id,
        tag: switch (type) {
          JellyfinImageType.primary => primaryImageTag,
          JellyfinImageType.backdrop => backdropImageTag,
          JellyfinImageType.thumb => thumbImageTag,
        },
        type: type,
        quality: quality,
      );
}

class NextUpItem extends JellyfinLibraryItem {
  const NextUpItem({
    required super.id,
    required super.title,
    super.rawType,
    super.mediaType,
    super.seriesName,
    super.seriesId,
    super.seasonId,
    super.parentId,
    super.seasonNumber,
    super.episodeNumber,
    super.productionYear,
    super.premiereDate,
    super.overview,
    super.officialRating,
    super.communityRating,
    super.tagline,
    super.playbackPositionTicks,
    super.playedPercentage,
    super.runTimeTicks,
    super.primaryImageTag,
    super.backdropImageTags,
    super.thumbImageTag,
    super.primaryImageAspectRatio,
    super.userData,
    super.raw,
  });

  factory NextUpItem.fromJson(Map<String, dynamic> json) => NextUpItem.fromItem(JellyfinLibraryItem.fromJson(json));

  factory NextUpItem.fromItem(JellyfinLibraryItem item) => NextUpItem(
        id: item.id,
        title: item.title,
        rawType: item.rawType,
        mediaType: item.mediaType,
        seriesName: item.seriesName,
        seriesId: item.seriesId,
        seasonId: item.seasonId,
        parentId: item.parentId,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        productionYear: item.productionYear,
        premiereDate: item.premiereDate,
        overview: item.overview,
        officialRating: item.officialRating,
        communityRating: item.communityRating,
        tagline: item.tagline,
        playbackPositionTicks: item.playbackPositionTicks,
        playedPercentage: item.playedPercentage,
        runTimeTicks: item.runTimeTicks,
        primaryImageTag: item.primaryImageTag,
        backdropImageTags: item.backdropImageTags,
        thumbImageTag: item.thumbImageTag,
        primaryImageAspectRatio: item.primaryImageAspectRatio,
        userData: item.userData,
        raw: item.raw,
      );
}

class ResumableItem extends JellyfinLibraryItem {
  const ResumableItem({
    required super.id,
    required super.title,
    super.rawType,
    super.mediaType,
    super.seriesName,
    super.seriesId,
    super.seasonId,
    super.parentId,
    super.seasonNumber,
    super.episodeNumber,
    super.productionYear,
    super.premiereDate,
    super.overview,
    super.officialRating,
    super.communityRating,
    super.tagline,
    super.playbackPositionTicks,
    super.playedPercentage,
    super.runTimeTicks,
    super.primaryImageTag,
    super.backdropImageTags,
    super.thumbImageTag,
    super.primaryImageAspectRatio,
    super.userData,
    super.raw,
  });

  factory ResumableItem.fromJson(Map<String, dynamic> json) => ResumableItem.fromItem(JellyfinLibraryItem.fromJson(json));

  factory ResumableItem.fromItem(JellyfinLibraryItem item) => ResumableItem(
        id: item.id,
        title: item.title,
        rawType: item.rawType,
        mediaType: item.mediaType,
        seriesName: item.seriesName,
        seriesId: item.seriesId,
        seasonId: item.seasonId,
        parentId: item.parentId,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        productionYear: item.productionYear,
        premiereDate: item.premiereDate,
        overview: item.overview,
        officialRating: item.officialRating,
        communityRating: item.communityRating,
        tagline: item.tagline,
        playbackPositionTicks: item.playbackPositionTicks,
        playedPercentage: item.playedPercentage,
        runTimeTicks: item.runTimeTicks,
        primaryImageTag: item.primaryImageTag,
        backdropImageTags: item.backdropImageTags,
        thumbImageTag: item.thumbImageTag,
        primaryImageAspectRatio: item.primaryImageAspectRatio,
        userData: item.userData,
        raw: item.raw,
      );
}

class JellyfinSearchHint {
  const JellyfinSearchHint({
    required this.id,
    required this.title,
    this.rawType,
    this.mediaType,
    this.productionYear,
    this.primaryImageTag,
    this.thumbImageTag,
    this.primaryImageAspectRatio,
    this.raw = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String? rawType;
  final String? mediaType;
  final int? productionYear;
  final String? primaryImageTag;
  final String? thumbImageTag;
  final double? primaryImageAspectRatio;
  final Map<String, dynamic> raw;

  JellyfinItemKind get kind => JellyfinItemKind.fromServer(rawType);

  factory JellyfinSearchHint.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] is Map ? Map<String, dynamic>.from(json['ImageTags'] as Map) : const <String, dynamic>{};
    return JellyfinSearchHint(
      id: _string(json['ItemId'] ?? json['Id']) ?? '',
      title: _string(json['Name']) ?? '',
      rawType: _string(json['Type']),
      mediaType: _string(json['MediaType']),
      productionYear: _integer(json['ProductionYear']),
      primaryImageTag: _string(imageTags['Primary'] ?? json['PrimaryImageTag']),
      thumbImageTag: _string(imageTags['Thumb'] ?? json['ThumbImageTag']),
      primaryImageAspectRatio: _double(json['PrimaryImageAspectRatio']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  String subtitle({String fallback = 'Media'}) {
    final type = rawType ?? mediaType ?? fallback;
    return productionYear == null ? type : '$productionYear · $type';
  }

  String? imageUrl(String baseUrl, {JellyfinImageType type = JellyfinImageType.primary, int? quality = 90}) => jellyfinImageUrl(
        baseUrl: baseUrl,
        itemId: id,
        tag: switch (type) {
          JellyfinImageType.primary => primaryImageTag,
          JellyfinImageType.backdrop => null,
          JellyfinImageType.thumb => thumbImageTag,
        },
        type: type,
        quality: quality,
      );
}

enum JellyfinImageType {
  primary('Primary'),
  backdrop('Backdrop'),
  thumb('Thumb');

  const JellyfinImageType(this.pathName);
  final String pathName;
}

String? jellyfinImageUrl({
  required String baseUrl,
  required String itemId,
  required String? tag,
  required JellyfinImageType type,
  int? quality,
}) {
  final cleanId = itemId.trim();
  final cleanTag = tag?.trim();
  if (cleanId.isEmpty || cleanTag == null || cleanTag.isEmpty) return null;
  final uri = Uri.parse(baseUrl).resolve('/Items/${Uri.encodeComponent(cleanId)}/Images/${type.pathName}');
  return uri.replace(queryParameters: <String, String>{
    'tag': cleanTag,
    if (quality != null) 'quality': '$quality',
  }).toString();
}

int? _integer(Object? value) => value is num ? value.toInt() : int.tryParse('$value');
double? _double(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
String? _string(Object? value) => value == null ? null : '$value';
bool? _bool(Object? value) {
  if (value is bool) return value;
  if (value is! String) return null;
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}
DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value');
List<String> _strings(Object? value) {
  if (value is List) return List<String>.unmodifiable(value.map((item) => '$item'));
  final single = _string(value);
  return single == null || single.isEmpty ? const <String>[] : <String>[single];
}
