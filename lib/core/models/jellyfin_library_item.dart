class JellyfinLibraryItem {
  const JellyfinLibraryItem({
    required this.id,
    required this.title,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.playbackPositionTicks,
    this.runTimeTicks,
    this.backdropImageTag,
    this.posterImageTag,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? playbackPositionTicks;
  final int? runTimeTicks;
  final String? backdropImageTag;
  final String? posterImageTag;
  final bool isFavorite;

  factory JellyfinLibraryItem.fromJson(Map<String, dynamic> json) {
    final userData = json['UserData'] is Map<String, dynamic>
        ? json['UserData'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final imageTags = json['ImageTags'] is Map<String, dynamic>
        ? json['ImageTags'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final backdropTags = json['BackdropImageTags'] as List<dynamic>?;
    return JellyfinLibraryItem(
      id: '${json['Id'] ?? ''}',
      title: '${json['Name'] ?? json['SeriesName'] ?? ''}',
      seriesName: _string(json['SeriesName']),
      seasonNumber: _integer(json['ParentIndexNumber'] ?? json['SeasonNumber']),
      episodeNumber: _integer(json['IndexNumber']),
      playbackPositionTicks: _integer(userData['PlaybackPositionTicks'] ?? json['PlaybackPositionTicks']),
      runTimeTicks: _integer(json['RunTimeTicks']),
      backdropImageTag: _string(backdropTags?.isNotEmpty == true ? backdropTags!.first : json['BackdropImageTag']),
      posterImageTag: _string(imageTags['Primary']),
      isFavorite: userData['IsFavorite'] == true || json['IsFavorite'] == true,
    );
  }

  Duration? get playbackPosition => playbackPositionTicks == null ? null : Duration(microseconds: playbackPositionTicks! ~/ 10);
  Duration? get runTime => runTimeTicks == null ? null : Duration(microseconds: runTimeTicks! ~/ 10);

  String? imageUrl(String baseUrl, {required bool backdrop}) {
    final tag = backdrop ? backdropImageTag : posterImageTag;
    if (tag == null || tag.isEmpty || id.isEmpty) return null;
    final type = backdrop ? 'Backdrop' : 'Primary';
    return '$baseUrl/Items/$id/Images/$type?tag=${Uri.encodeQueryComponent(tag)}';
  }
}

class NextUpItem extends JellyfinLibraryItem {
  const NextUpItem({required super.id, required super.title, super.seriesName, super.seasonNumber, super.episodeNumber, super.playbackPositionTicks, super.runTimeTicks, super.backdropImageTag, super.posterImageTag, super.isFavorite});
  factory NextUpItem.fromJson(Map<String, dynamic> json) {
    final item = JellyfinLibraryItem.fromJson(json);
    return NextUpItem(id: item.id, title: item.title, seriesName: item.seriesName, seasonNumber: item.seasonNumber, episodeNumber: item.episodeNumber, playbackPositionTicks: item.playbackPositionTicks, runTimeTicks: item.runTimeTicks, backdropImageTag: item.backdropImageTag, posterImageTag: item.posterImageTag, isFavorite: item.isFavorite);
  }
}

class ResumableItem extends JellyfinLibraryItem {
  const ResumableItem({required super.id, required super.title, super.seriesName, super.seasonNumber, super.episodeNumber, super.playbackPositionTicks, super.runTimeTicks, super.backdropImageTag, super.posterImageTag, super.isFavorite});
  factory ResumableItem.fromJson(Map<String, dynamic> json) {
    final item = JellyfinLibraryItem.fromJson(json);
    return ResumableItem(id: item.id, title: item.title, seriesName: item.seriesName, seasonNumber: item.seasonNumber, episodeNumber: item.episodeNumber, playbackPositionTicks: item.playbackPositionTicks, runTimeTicks: item.runTimeTicks, backdropImageTag: item.backdropImageTag, posterImageTag: item.posterImageTag, isFavorite: item.isFavorite);
  }
}

int? _integer(dynamic value) => value is num ? value.toInt() : int.tryParse('$value');
String? _string(dynamic value) => value == null ? null : '$value';
