class PlaybackInfoRequest {
  const PlaybackInfoRequest({
    required this.itemId,
    required this.deviceProfile,
    this.userId,
    this.startTimeTicks = 0,
    this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.maxStreamingBitrate,
  });

  final String itemId;
  final String? userId;
  final Map<String, dynamic> deviceProfile;
  final int startTimeTicks;
  final String? mediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final int? maxStreamingBitrate;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'DeviceProfile': deviceProfile,
        'StartTimeTicks': startTimeTicks,
        if (mediaSourceId != null) 'MediaSourceId': mediaSourceId,
        if (audioStreamIndex != null) 'AudioStreamIndex': audioStreamIndex,
        if (subtitleStreamIndex != null) 'SubtitleStreamIndex': subtitleStreamIndex,
        if (maxStreamingBitrate != null) 'MaxStreamingBitrate': maxStreamingBitrate,
      };
}
