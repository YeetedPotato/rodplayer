import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/models/jellyfin_user_profile.dart';

void main() {
  test('parses user profile configuration policy and raw data conservatively', () {
    final profile = JellyfinUserProfile.fromJson(<String, dynamic>{
      'Id': 'user id',
      'Name': 'Erick',
      'ServerId': 'server',
      'ServerName': 'Media',
      'PrimaryImageTag': 'tag',
      'PrimaryImageAspectRatio': 1.2,
      'HasPassword': true,
      'HasConfiguredPassword': false,
      'HasConfiguredEasyPassword': true,
      'EnableAutoLogin': false,
      'LastLoginDate': '2026-01-02T03:04:05Z',
      'Configuration': <String, dynamic>{
        'AudioLanguagePreference': 'eng',
        'SubtitleLanguagePreference': 'spa',
        'SubtitleMode': 'OnlyForced',
        'PlayDefaultAudioTrack': true,
        'RememberAudioSelections': false,
        'RememberSubtitleSelections': true,
        'EnableNextEpisodeAutoPlay': false,
        'HidePlayedInLatest': true,
        'DisplayMissingEpisodes': false,
        'GroupedFolders': <String>['keep'],
      },
      'Policy': <String, dynamic>{'IsAdministrator': true, 'IsHidden': true, 'IsDisabled': false},
    });

    expect(profile.id, 'user id');
    expect(profile.name, 'Erick');
    expect(profile.primaryImageTag, 'tag');
    expect(profile.hasConfiguredEasyPassword, isTrue);
    expect(profile.lastLoginDate, isNotNull);
    expect(profile.configuration.subtitleMode, JellyfinSubtitleMode.onlyForced);
    expect(profile.configuration.hidePlayedInLatest, isTrue);
    expect(profile.policy.isAdministrator, isTrue);
    expect(profile.policy.isHidden, isTrue);

    final json = profile.configuration.copyWith(audioLanguagePreference: 'fre', subtitleMode: JellyfinSubtitleMode.none).toUpdateJson();
    expect(json['AudioLanguagePreference'], 'fre');
    expect(json['SubtitleMode'], 'None');
    expect(json['GroupedFolders'], <String>['keep']);
  });

  test('subtitle modes and malformed optional fields stay conservative', () {
    expect(JellyfinSubtitleMode.fromServer('Default'), JellyfinSubtitleMode.defaultMode);
    expect(JellyfinSubtitleMode.fromServer('Smart'), JellyfinSubtitleMode.smart);
    expect(JellyfinSubtitleMode.fromServer('Always'), JellyfinSubtitleMode.always);
    expect(JellyfinSubtitleMode.fromServer('None'), JellyfinSubtitleMode.none);
    expect(JellyfinSubtitleMode.fromServer('bogus'), isNull);

    final profile = JellyfinUserProfile.fromJson(<String, dynamic>{
      'Configuration': <String, dynamic>{'SubtitleMode': 'bogus', 'PlayDefaultAudioTrack': 'maybe'},
      'Policy': <String, dynamic>{'IsAdministrator': 'nope'},
    });
    expect(profile.id, '');
    expect(profile.name, '');
    expect(profile.configuration.subtitleMode, isNull);
    expect(profile.configuration.playDefaultAudioTrack, isNull);
    expect(profile.policy.isAdministrator, isFalse);
  });
}
