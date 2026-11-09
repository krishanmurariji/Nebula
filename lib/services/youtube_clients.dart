import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Client definitions copied from yt-dlp's current defaults
// (`_DEFAULT_CLIENTS = ('tv_samsung', 'visionos', 'web')`, yt_dlp/extractor/
// youtube/_base.py). YouTube retires clients constantly; the older ones the
// Dart library ships (androidVr, ios, tv …) were all refused on a real phone
// ("unplayable" / HTTP 403), while these two are what yt-dlp itself succeeds
// with. When YouTube changes again, this is the file to refresh.

const String _playerApi = 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';

/// A Samsung smart-TV app. Needs the JavaScript challenge solved (handled by
/// the WebView solver) but no PO token.
const YoutubeApiClient kTvSamsungClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'TVHTML5',
      'clientVersion': '5.20260707',
      'deviceMake': 'Samsung',
      'deviceModel': 'UKS9800',
      'userAgent':
          'Mozilla/5.0 (SMART-TV; Linux; Tizen 2.4.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/2.4.0 TV Safari/538.1',
      'osName': 'Tizen',
      'osVersion': '2.4.0',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
  },
  'contentCheckOk': true,
  'racyCheckOk': true,
}, _playerApi, headers: {
  // The library sends the client *name* here; YouTube expects the number.
  'X-Youtube-Client-Name': '7',
  'X-Youtube-Client-Version': '5.20260707',
});

/// Apple Vision Pro app. yt-dlp marks it as needing no JavaScript player, so
/// no challenge to solve at all. ("Made for kids" videos are not offered.)
const YoutubeApiClient kVisionOsClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'userAgent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
  },
  'contentCheckOk': true,
  'racyCheckOk': true,
}, _playerApi, headers: {
  'X-Youtube-Client-Name': '101',
  'X-Youtube-Client-Version': '1.02',
});
