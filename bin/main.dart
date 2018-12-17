import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:scheduler_base/scheduler_base.dart';
import 'package:googleapis_auth/auth_io.dart';

const Map<String, int> months = const {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12
};

main(List<String> args) async {
  var content = await new File('serviceaccount.json').readAsString();
  var accountCredentials =
      new ServiceAccountCredentials.fromJson(json.decode(content));
  var client = await clientViaServiceAccount(accountCredentials, [
    'https://www.googleapis.com/auth/firebase.database',
    'https://www.googleapis.com/auth/userinfo.email'
  ]);

  final now = new DateTime.now();
  final sundayStart = now.subtract(Duration(
      days: 3,
      hours: now.hour,
      minutes: now.minute,
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond));
  final int start = sundayStart.millisecondsSinceEpoch ~/ 1000;
  final int end =
      sundayStart.add(Duration(days: 10)).millisecondsSinceEpoch ~/ 1000;

  await downloadSchedule(client,
      'https://api.rocketbeans.tv/v1/schedule/normalized?startDay=$start&endDay=$end');
}

Future downloadSchedule(AutoRefreshingAuthClient client, String url) async {
  var response = await http.get(url);
  if (response.statusCode == HttpStatus.ok) {
    final jsonSchedule = response.body;
    final List<dynamic> scheduleDays = json.decode(jsonSchedule)['data'];
    final scheduleShowsByDay = <int, List<dynamic>>{};
    scheduleDays.forEach((scheduleDay) async {
      final scheduleShows = scheduleDay['elements'];
      scheduleShows.forEach((scheduleShow) {
        final startTime = DateTime.parse(scheduleShow['timeStart']).toLocal();
        scheduleShowsByDay.putIfAbsent(startTime.day, () => []);
        scheduleShowsByDay[startTime.day].add(scheduleShow);
      });
    });
    scheduleDays.skip(1).take(7).forEach((scheduleDay) async {
      final shows = <TimeSlot>[];
      final currentDay = DateTime.parse(scheduleDay['date']).toLocal();
      final year = currentDay.year;
      final month = currentDay.month;
      final day = currentDay.day;
      scheduleShowsByDay[day]?.forEach((scheduleShow) {
        final startTime = DateTime.parse(scheduleShow['timeStart']).toLocal();
        final name = scheduleShow['title'];
        final game = scheduleShow['topic'];
        final live = scheduleShow['type'] == 'live';
        final premiere = scheduleShow['type'] == 'premiere';
        final endTime = DateTime.parse(scheduleShow['timeEnd']).toLocal();
        final show =
            RbtvTimeSlot(name, startTime, endTime, game, live, premiere);
        shows.add(show);
      });
      if (shows.isNotEmpty) {
        var path =
            'rbtv/$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.json';
        var url = 'https://scheduler-40abf.firebaseio.com/$path';
        final encodedShows = json.encode(shows);
        await client.put(url, body: encodedShows);
      }
    });
  }
}
