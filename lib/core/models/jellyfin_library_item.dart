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
    this.unplayedItemCount,
  });

  final bool isFavorite;
  final bool played;
  final int? playbackPositionTicks;
  final double? playedPercentage;
  final int? unplayedItemCount;

  factory JellyfinUserData.fromJson(Object? value, {Map<String, dynamic> fallback = const <String, dynamic>{}}) {
    final json = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return JellyfinUserData(
      isFavorite: _bool(json['IsFavorite'] ?? fallback['IsFavorite']) ?? false,
      played: _bool(json['Played'] ?? fallback['Played']) ?? false,
      playbackPositionTicks: _integer(json['PlaybackPositionTicks'] ?? fallback['PlaybackPositionTicks']),
      playedPercentage: _double(json['PlayedPercentage'] ?? fallback['PlayedPercentage']),
      unplayedItemCount: _integer(json['UnplayedItemCount'] ?? fallback['UnplayedItemCount']),
    );
  }

  JellyfinUserData copyWith({bool? isFavorite, bool? played, int? playbackPositionTicks, double? playedPercentage}) => JellyfinUserData(
        isFavorite: isFavorite ?? this.isFavorite,
        played: played ?? this.played,
        playbackPositionTicks: playbackPositionTicks ?? this.playbackPositionTicks,
        playedPercentage: playedPercentage ?? this.playedPercentage,
        unplayedItemCount: unplayedItemCount,
      );
}

class JellyfinUserDataChange {
  const JellyfinUserDataChange({required this.itemId, this.isFavorite, this.played, this.playbackProgressMayHaveChanged = false});
  final String itemId;
  final bool? isFavorite;
  final bool? played;
  final bool playbackProgressMayHaveChanged;
}

typedef JellyfinUserDataChangedCallback = void Function(JellyfinUserDataChange change);

class JellyfinPerson {
  const JellyfinPerson({
    required this.id,
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  final String id;
  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;

  factory JellyfinPerson.fromJson(Map<String, dynamic> json) {
    final imageTags = json['ImageTags'] is Map ? Map<String, dynamic>.from(json['ImageTags'] as Map) : const <String, dynamic>{};
    return JellyfinPerson(
        id: _string(json['Id']) ?? '',
        name: _string(json['Name']) ?? '',
        role: _string(json['Role']),
        type: _string(json['Type']),
        primaryImageTag: _string(json['PrimaryImageTag'] ?? imageTags['Primary']),
      );
  }
}

class JellyfinItemsPage<T> {
  JellyfinItemsPage({
    required List<T> items,
    this.totalRecordCount,
    this.startIndex,
  }) : items = List<T>.unmodifiable(items);

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
    this.seasonName,
    this.parentId,
    this.seasonNumber,
    this.episodeNumber,
    this.productionYear,
    this.premiereDate,
    this.endDate,
    this.overview,
    this.officialRating,
    this.communityRating,
    this.tagline,
    this.genres = const <String>[],
    this.studios = const <String>[],
    this.people = const <JellyfinPerson>[],
    this.status,
    this.childCount,
    this.recursiveItemCount,
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
  final String? seasonName;
  final String? parentId;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? productionYear;
  final DateTime? premiereDate;
  final DateTime? endDate;
  final String? overview;
  final String? officialRating;
  final double? communityRating;
  final String? tagline;
  final List<String> genres;
  final List<String> studios;
  final List<JellyfinPerson> people;
  final String? status;
  final int? childCount;
  final int? recursiveItemCount;
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
      seasonName: _string(json['SeasonName']),
      parentId: _string(json['ParentId']),
      seasonNumber: _integer(json['ParentIndexNumber'] ?? json['SeasonNumber']),
      episodeNumber: _integer(json['IndexNumber']),
      productionYear: _integer(json['ProductionYear']),
      premiereDate: _date(json['PremiereDate']),
      endDate: _date(json['EndDate']),
      overview: _string(json['Overview']),
      officialRating: _string(json['OfficialRating']),
      communityRating: _double(json['CommunityRating']),
      tagline: _tagline(json),
      genres: _stringList(json['Genres']),
      studios: _studios(json['Studios']),
      people: _people(json['People']),
      status: _string(json['Status']),
      childCount: _integer(json['ChildCount']),
      recursiveItemCount: _integer(json['RecursiveItemCount']),
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

  JellyfinLibraryItem withUserDataChange(JellyfinUserDataChange change) {
    if (id.isEmpty || change.itemId != id) return this;
    return JellyfinLibraryItem(
      id: id,
      title: title,
      rawType: rawType,
      mediaType: mediaType,
      seriesName: seriesName,
      seriesId: seriesId,
      seasonId: seasonId,
      seasonName: seasonName,
      parentId: parentId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      productionYear: productionYear,
      premiereDate: premiereDate,
      endDate: endDate,
      overview: overview,
      officialRating: officialRating,
      communityRating: communityRating,
      tagline: tagline,
      genres: genres,
      studios: studios,
      people: people,
      status: status,
      childCount: childCount,
      recursiveItemCount: recursiveItemCount,
      playbackPositionTicks: playbackPositionTicks,
      playedPercentage: playedPercentage,
      runTimeTicks: runTimeTicks,
      primaryImageTag: primaryImageTag,
      backdropImageTags: backdropImageTags,
      thumbImageTag: thumbImageTag,
      primaryImageAspectRatio: primaryImageAspectRatio,
      userData: userData.copyWith(isFavorite: change.isFavorite, played: change.played),
      raw: raw,
    );
  }
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
    super.seasonName,
    super.parentId,
    super.seasonNumber,
    super.episodeNumber,
    super.productionYear,
    super.premiereDate,
    super.endDate,
    super.overview,
    super.officialRating,
    super.communityRating,
    super.tagline,
    super.genres,
    super.studios,
    super.people,
    super.status,
    super.childCount,
    super.recursiveItemCount,
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
        seasonName: item.seasonName,
        parentId: item.parentId,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        productionYear: item.productionYear,
        premiereDate: item.premiereDate,
        endDate: item.endDate,
        overview: item.overview,
        officialRating: item.officialRating,
        communityRating: item.communityRating,
        tagline: item.tagline,
        genres: item.genres,
        studios: item.studios,
        people: item.people,
        status: item.status,
        childCount: item.childCount,
        recursiveItemCount: item.recursiveItemCount,
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
    super.seasonName,
    super.parentId,
    super.seasonNumber,
    super.episodeNumber,
    super.productionYear,
    super.premiereDate,
    super.endDate,
    super.overview,
    super.officialRating,
    super.communityRating,
    super.tagline,
    super.genres,
    super.studios,
    super.people,
    super.status,
    super.childCount,
    super.recursiveItemCount,
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
        seasonName: item.seasonName,
        parentId: item.parentId,
        seasonNumber: item.seasonNumber,
        episodeNumber: item.episodeNumber,
        productionYear: item.productionYear,
        premiereDate: item.premiereDate,
        endDate: item.endDate,
        overview: item.overview,
        officialRating: item.officialRating,
        communityRating: item.communityRating,
        tagline: item.tagline,
        genres: item.genres,
        studios: item.studios,
        people: item.people,
        status: item.status,
        childCount: item.childCount,
        recursiveItemCount: item.recursiveItemCount,
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
  final uri = jellyfinUri(baseUrl, <String>['Items', cleanId, 'Images', type.pathName]);
  return uri.replace(queryParameters: <String, String>{
    'tag': cleanTag,
    if (quality != null) 'quality': '$quality',
  }).toString();
}

Uri jellyfinUri(String baseUrl, Iterable<String> pathSegments, {Map<String, String>? queryParameters}) {
  final base = Uri.parse(baseUrl);
  final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
  return base.replace(pathSegments: <String>[...baseSegments, ...pathSegments], queryParameters: queryParameters);
}

int? _integer(Object? value) => value is num ? value.toInt() : int.tryParse('$value');
double? _double(Object? value) => value is num ? value.toDouble() : double.tryParse('$value');
String? _string(Object? value) => value == null ? null : '$value';
String? _tagline(Map<String, dynamic> json) {
  final taglines = json['Taglines'];
  if (taglines is List) {
    for (final tagline in taglines) {
      final value = _string(tagline)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
  final legacy = _string(json['Tagline'])?.trim();
  return legacy == null || legacy.isEmpty ? null : legacy;
}
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
  return single == null || single.isEmpty ? const <String>[] : List<String>.unmodifiable(<String>[single]);
}
List<String> _stringList(Object? value) => value is List ? List<String>.unmodifiable(value.map((item) => '$item')) : const <String>[];
List<String> _studios(Object? value) {
  if (value is! List) return const <String>[];
  final studios = <String>[];
  for (final item in value) {
    final name = item is Map ? _string(item['Name']) : _string(item);
    if (name != null && name.trim().isNotEmpty) studios.add(name);
  }
  return List<String>.unmodifiable(studios);
}
List<JellyfinPerson> _people(Object? value) {
  if (value is! List) return const <JellyfinPerson>[];
  return List<JellyfinPerson>.unmodifiable(value.whereType<Map>().map((item) => JellyfinPerson.fromJson(Map<String, dynamic>.from(item))));
}
