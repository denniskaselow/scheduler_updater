import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
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

  await downloadSchedule(
      client, 'https://www.rocketbeans.tv/wochenplan/?details=1');
  await downloadSchedule(
      client, 'https://www.rocketbeans.tv/wochenplan/?details=1&nextWeek=1');
}

Future downloadSchedule(AutoRefreshingAuthClient client, String url) async {
  var response = await http.get(url);
  if (response.statusCode == HttpStatus.OK) {
    var content = response.body;
    var document = parser.parse(content);

    var schedule = document.querySelector('#schedule');
    var scheduleDays = schedule.querySelectorAll('.day');
    RbtvTimeSlot show;
    scheduleDays.forEach((scheduleDay) async {
      var shows = <TimeSlot>[];
      var dayDate = scheduleDay
          .querySelector('.dateHeader span')
          .text
          .split(new RegExp(r'\.? '));
      var scheduleShows = scheduleDay.querySelectorAll('.show');
      var year = int.parse(dayDate[2]);
      var month = months[dayDate[1]];
      var day = int.parse(dayDate[0]);
      scheduleShows.forEach((scheduleShow) {
        var time = scheduleShow.querySelector('.scheduleTime').text;
        var showDetails = scheduleShow.querySelector('.showDetails');
        var name = showDetails.querySelector('h4').text;
        var game = showDetails.querySelector('.game')?.text ?? '';
        var live = showDetails.querySelector('.live') != null;
        var premiere = showDetails.querySelector('.premiere') != null;
        var showDuration = showDetails.querySelector('.showDuration').text;
        var hourMinuteRegexp =
            new RegExp(r'((\d+) Tage )?((\d+) Std\. )?(\d+) Min\.');
        var matches = hourMinuteRegexp.allMatches(showDuration);
        var duration = 1;
        matches.forEach((match) {
          duration = int.parse(match.group(5));
          if (match.group(4) != null) {
            duration += 60 * int.parse(match.group(4));
          }
          if (match.group(2) != null) {
            duration += 24 * 60 * int.parse(match.group(2));
          }
        });
        var hour = int.parse(time.split(':')[0]);
        var minute = int.parse(time.split(':')[1]);
        var startTime = new DateTime(year, month, day, hour, minute);
        var dummyEndTime = startTime.add(new Duration(minutes: duration));
        show = new RbtvTimeSlot(
            name, startTime, dummyEndTime, game, live, premiere);
        shows.add(show);
      });
      var duplicates = [];
      for (int i = 0; i < shows.length - 1; i++) {
        if (shows[i].start == shows[i + 1].start) {
          if (shows[i].end == shows[i + 1].end) {
            duplicates.add(i);
          } else {
            if (shows[i].end.isAfter(shows[i + 1].end)) {
              var tmp = shows[i];
              shows[i] = shows[i + 1];
              shows[i + 1] = tmp;
            }
            shows[i + 1].start = shows[i].end;
          }
        }
        shows[i].end = shows[i + 1].start;
      }
      duplicates.reversed
          .forEach((duplicateIndex) => shows.removeAt(duplicateIndex));
      var path =
          'rbtv/$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}.json';
      var url = 'https://scheduler-40abf.firebaseio.com/$path';
      final encodedShows = json.encode(shows, toEncodable: (timeSlot) {
        if (timeSlot is RbtvTimeSlot) {
          return {
            'name': timeSlot.name,
            'description': timeSlot.description,
            'start': timeSlot.start.toIso8601String(),
            'end': timeSlot.end.toIso8601String(),
            'height': timeSlot.height,
            'live': timeSlot.live,
            'premiere': timeSlot.premiere,
          };
        }
      });
      await client.put(url, body: encodedShows);
    });
  }
}
