import 'package:rodplayer/core/models/jellyfin_library_item.dart';

String mediaItemTitle(JellyfinLibraryItem item) => item.title.isEmpty ? 'Untitled' : item.title;

bool isDirectlyPlayable(JellyfinLibraryItem item) =>
    item.id.isNotEmpty && (item.kind == JellyfinItemKind.movie || item.kind == JellyfinItemKind.episode || item.kind == JellyfinItemKind.audio);

double? rawProgress(JellyfinLibraryItem item) {
  final percent = item.playedPercentage;
  if (percent != null) return (percent / 100).clamp(0, 1).toDouble();
  final position = item.playbackPositionTicks;
  final runtime = item.runTimeTicks;
  if (position == null || runtime == null || runtime <= 0) return null;
  return (position / runtime).clamp(0, 1).toDouble();
}

double? visualProgress(JellyfinLibraryItem item) {
  final progress = rawProgress(item);
  return progress == null || progress <= 0 ? null : progress;
}

bool hasMeaningfulResumeProgress(JellyfinLibraryItem item) => (rawProgress(item) ?? 0) > 0;

String episodeCode(JellyfinLibraryItem item) {
  final season = item.seasonNumber == null ? null : 'S${item.seasonNumber!.toString().padLeft(2, '0')}';
  final episode = item.episodeNumber == null ? null : 'E${item.episodeNumber!.toString().padLeft(2, '0')}';
  return season == null && episode == null ? '' : '${season ?? ''}${episode ?? ''}';
}

String itemMetadata(JellyfinLibraryItem item) => [
      item.productionYear?.toString(),
      item.officialRating,
      item.communityRating == null ? null : '★ ${item.communityRating}',
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
