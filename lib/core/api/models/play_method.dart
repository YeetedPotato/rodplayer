enum PlayMethod {
  directPlay('DirectPlay'),
  directStream('DirectStream'),
  transcode('Transcode');

  const PlayMethod(this.jellyfinName);
  final String jellyfinName;

  static PlayMethod fromJson(Object? value) {
    final text = '$value'.toLowerCase();
    if (text == 'directstream') return PlayMethod.directStream;
    if (text == 'transcode') return PlayMethod.transcode;
    return PlayMethod.directPlay;
  }
}
