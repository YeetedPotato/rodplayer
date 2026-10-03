final class JellyfinLiveTvChannel {
  const JellyfinLiveTvChannel(
      {required this.id,
      required this.name,
      this.channelNumber,
      this.callSign,
      this.primaryImageTag});
  final String id;
  final String name;
  final String? channelNumber;
  final String? callSign;
  final String? primaryImageTag;

  factory JellyfinLiveTvChannel.fromJson(Map<String, dynamic> json) {
    final id = json['Id'];
    final name = json['Name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty)
      throw const FormatException('Invalid Live TV channel');
    final imageTags = json['ImageTags'];
    final primary = json['PrimaryImageTag'] ??
        (imageTags is Map ? imageTags['Primary'] : null);
    return JellyfinLiveTvChannel(
      id: id,
      name: name,
      channelNumber: (json['Number'] ?? json['ChannelNumber'])?.toString(),
      callSign: json['CallSign'] is String ? json['CallSign'] as String : null,
      primaryImageTag: primary is String ? primary : null,
    );
  }
}

final class JellyfinLiveTvProgram {
  const JellyfinLiveTvProgram(
      {required this.id,
      required this.name,
      required this.start,
      required this.end,
      this.channelId,
      this.overview,
      this.isAiring});
  final String id;
  final String name;
  final DateTime start;
  final DateTime end;
  final String? channelId;
  final String? overview;
  final bool? isAiring;

  factory JellyfinLiveTvProgram.fromJson(Map<String, dynamic> json) {
    final id = json['Id'];
    final name = json['Name'];
    final start = json['StartDate'];
    final end = json['EndDate'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        start is! String ||
        end is! String) throw const FormatException('Invalid Live TV program');
    final parsedStart = DateTime.tryParse(start);
    final parsedEnd = DateTime.tryParse(end);
    if (parsedStart == null ||
        parsedEnd == null ||
        !parsedEnd.isAfter(parsedStart))
      throw const FormatException('Invalid Live TV program range');
    return JellyfinLiveTvProgram(
      id: id,
      name: name,
      start: parsedStart.toUtc(),
      end: parsedEnd.toUtc(),
      channelId:
          json['ChannelId'] is String ? json['ChannelId'] as String : null,
      overview: json['Overview'] is String ? json['Overview'] as String : null,
      isAiring: json['IsAiring'] is bool ? json['IsAiring'] as bool : null,
    );
  }
}
