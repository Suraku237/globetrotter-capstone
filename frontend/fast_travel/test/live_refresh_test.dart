import 'dart:async';

import 'package:fast_travel/Services/live_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters topics, coalesces overlapping loads and unsubscribes', () async {
    final changes = StreamController<Set<String>>(sync: true);
    final first = Completer<void>();
    var calls = 0;
    var concurrent = 0;
    var maxConcurrent = 0;
    final refresh = LiveRefresh(
      changes: changes.stream,
      topics: {'posts'},
      onRefresh: () async {
        calls++;
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        if (calls == 1) await first.future;
        concurrent--;
      },
    );
    changes.add({'profile'});
    expect(calls, 0);
    final pending = refresh.refresh();
    changes.add({'posts'});
    changes.add({'posts'});
    changes.add({'all'});
    expect(calls, 1);
    first.complete();
    await pending;
    expect(calls, 2);
    expect(maxConcurrent, 1);
    refresh.dispose();
    changes.add({'posts'});
    await refresh.refresh();
    expect(calls, 2);
    await changes.close();
  });

  test('disposing during a load discards queued follow-up work', () async {
    final changes = StreamController<Set<String>>(sync: true);
    final completion = Completer<void>();
    var calls = 0;
    final refresh = LiveRefresh(
      changes: changes.stream,
      topics: {'posts'},
      onRefresh: () {
        calls++;
        return completion.future;
      },
    );
    final pending = refresh.refresh();
    changes.add({'posts'});
    refresh.dispose();
    completion.complete();
    await pending;
    expect(calls, 1);
    await changes.close();
  });
}
