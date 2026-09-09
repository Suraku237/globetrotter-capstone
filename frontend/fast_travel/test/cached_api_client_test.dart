import 'dart:async';
import 'dart:convert';

import 'package:fast_travel/Services/cached_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Preferences extends Fake implements SharedPreferences {
  final values = <String, String>{};
  bool rejectWrites = true;
  @override
  String? getString(String key) => values[key];
  @override
  Future<bool> setString(String key, String value) async {
    if (rejectWrites) throw StateError('Browser quota exceeded');
    values[key] = value;
    return true;
  }
  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const base = 'https://example.test/api';
  final posts = Uri.parse('$base/posts');
  late DateTime now;
  late List<Set<String>> changes;
  late CachedApiClient client;

  CachedApiClient create(Future<http.Response> Function(http.Request) handler,
      {int maxEntries = 80, int maxBytes = 4 * 1024 * 1024,
      Future<SharedPreferences> Function()? preferences}) {
    return CachedApiClient(
      baseUrl: base,
      network: MockClient(handler),
      onChanged: changes.add,
      onUnauthorized: () => changes.add({'unauthorized'}),
      connectionError: CacheConnectionException.new,
      now: () => now,
      maxEntries: maxEntries,
      maxBytes: maxBytes,
      preferences: preferences,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 9, 9);
    changes = [];
  });

  tearDown(() => client.close());

  test('fresh reads reuse response without additional requests', () async {
    var requests = 0;
    client = create((_) async {
      requests++;
      return http.Response('[{"id":"one"}]', 200);
    });
    await client.setScope('alice');
    expect((await client.get(posts)).body, '[{"id":"one"}]');
    expect((await client.get(posts)).body, '[{"id":"one"}]');
    expect(requests, 1);
  });

  test('simultaneous identical reads share one network request', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    client = create((_) {
      requests++;
      return response.future;
    });
    await client.setScope('alice');
    final first = client.get(posts);
    final second = client.get(posts);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    response.complete(http.Response('[]', 200));
    await Future.wait([first, second]);
  });

  test('stale read paints immediately then notifies fresh content', () async {
    final refresh = Completer<http.Response>();
    var requests = 0;
    client = create((_) async {
      if (++requests == 1) return http.Response('["old"]', 200);
      return refresh.future;
    });
    await client.setScope('alice');
    await client.get(posts);
    now = now.add(const Duration(minutes: 2));
    expect((await client.get(posts)).body, '["old"]');
    refresh.complete(http.Response('["new"]', 200));
    await Future<void>.delayed(Duration.zero);
    expect((await client.get(posts)).body, '["new"]');
    expect(changes, contains(equals({'posts'})));
    expect(requests, 2);
  });

  test('persisted data survives restart and a network outage', () async {
    client = create((_) async => http.Response('["saved"]', 200));
    await client.setScope('alice');
    await client.get(posts);
    await client.flush();
    client.close();
    client = create((_) async => throw http.ClientException('offline'));
    await client.setScope('alice');
    expect((await client.get(posts)).body, '["saved"]');
    await Future<void>.delayed(Duration.zero);
    expect(client.unavailable.value, isTrue);
    expect((await client.get(posts)).body, '["saved"]');
  });

  test('cache miss offline is an error, not an empty success', () async {
    client = create((_) async => throw http.ClientException('offline'));
    await client.setScope('alice');
    await expectLater(client.get(posts), throwsA(isA<CacheConnectionException>()));
  });

  test('late response cannot overwrite cache after account switch', () async {
    final delayed = Completer<http.Response>();
    var requests = 0;
    client = create((_) async {
      if (++requests == 1) return delayed.future;
      return http.Response('["bob"]', 200);
    });
    await client.setScope('alice');
    final alice = client.get(posts);
    await Future<void>.delayed(Duration.zero);
    await client.setScope('bob');
    expect((await client.get(posts)).body, '["bob"]');
    final rejected = expectLater(alice, throwsA(isA<CacheConnectionException>()));
    delayed.complete(http.Response('["alice"]', 200));
    await rejected;
    expect((await client.get(posts)).body, '["bob"]');
  });

  test('logout removes persistent data; other accounts cannot restore it', () async {
    client = create((_) async => http.Response('["alice"]', 200));
    await client.setScope('alice');
    await client.get(posts);
    await client.flush();
    await client.setScope(null);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CachedApiClient.storageKey), isFalse);
    await client.setScope('bob');
    expect(changes, isEmpty);
  });

  test('authorization failure evicts old cached private data', () async {
    var status = 200;
    client = create((_) async => http.Response('[]', status));
    await client.setScope('alice');
    final uri = Uri.parse('$base/social/friends');
    await client.get(uri);
    status = 403;
    client.invalidate({'friends'});
    await client.get(uri);
    await Future<void>.delayed(Duration.zero);
    expect((await client.get(uri)).statusCode, 403);
  });

  test('mutations invalidate matching reads but are never replayed', () async {
    var requests = 0;
    client = create((request) async {
      requests++;
      return http.Response('[]', request.method == 'GET' ? 200 : 201);
    });
    await client.setScope('alice');
    await client.get(posts);
    await client.post(posts);
    expect(changes, contains(equals({'posts', 'stats'})));
    await client.get(posts);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 3);
  });

  test('call state is always network-authoritative', () async {
    var requests = 0;
    client = create((_) async {
      requests++;
      return http.Response('[]', 200);
    });
    await client.setScope('alice');
    final calls = Uri.parse('$base/social/calls/incoming');
    await client.get(calls);
    await client.get(calls);
    expect(requests, 2);
  });

  test('oldest entries are evicted when the cache limit is reached', () async {
    var requests = 0;
    client = create((_) async {
      requests++;
      return http.Response('[]', 200);
    }, maxEntries: 2);
    await client.setScope('alice');
    await client.get(posts);
    await client.get(Uri.parse('$base/destinations'));
    await client.get(Uri.parse('$base/itineraries'));
    await client.get(posts);
    expect(requests, 4);
  });

  test('serialized storage including escaping stays below its byte budget', () async {
    client = create((_) async => http.Response(jsonEncode(List.filled(200, '"')), 200),
        maxBytes: 1000);
    await client.setScope('alice');
    await client.get(posts);
    await client.flush();
    final stored = (await SharedPreferences.getInstance())
        .getString(CachedApiClient.storageKey)!;
    expect(utf8.encode(stored).length, lessThanOrEqualTo(1000));
  });

  test('profile survives cache eviction for offline session restoration', () async {
    client = create((_) async => http.Response('[]', 200), maxEntries: 2);
    await client.setScope('alice');
    final me = Uri.parse('$base/me');
    await client.prime(me, {'id': 'alice'});
    await client.get(posts);
    await client.get(Uri.parse('$base/destinations'));
    expect((await client.get(me)).body, '{"id":"alice"}');
  });

  test('switching account while cache initializes never sends old credentials', () async {
    var requests = 0;
    client = create((_) async {
      requests++;
      return http.Response('[]', 200);
    });
    final initializing = client.setScope('alice');
    final request = client.get(posts, headers: {'Authorization': 'old-token'});
    final failure = expectLater(request, throwsA(isA<CacheConnectionException>()));
    await client.setScope('bob');
    await initializing;
    await failure;
    expect(requests, 0);
  });

  test('backgrounding during restoration does not overwrite saved content', () async {
    client = create((_) async => http.Response('["saved"]', 200));
    await client.setScope('alice');
    await client.get(posts);
    await client.flush();
    client.close();
    client = create((_) async => throw http.ClientException('offline'));
    final restoring = client.setScope('alice');
    await client.flush();
    await restoring;
    final stored = (await SharedPreferences.getInstance())
        .getString(CachedApiClient.storageKey)!;
    expect(stored, contains('saved'));
  });

  test('storage failures surface a warning without poisoning the write queue', () async {
    final prefs = _Preferences();
    client = create((_) async => http.Response('[]', 200),
        preferences: () async => prefs);
    await client.setScope('alice');
    await client.get(posts);
    await client.flush();
    expect(client.storageWarning.value, isTrue);
    prefs.rejectWrites = false;
    await client.setScope('bob');
    await client.get(posts);
    await client.flush();
    expect(client.storageWarning.value, isFalse);
    expect(prefs.values[CachedApiClient.storageKey], contains('bob'));
  });

  test('successful profile edits replace cached profile before invalidation', () async {
    client = create((request) async => http.Response(
        request.method == 'GET' ? '{"full_name":"Old"}' : '{"full_name":"New"}', 200));
    await client.setScope('alice');
    final me = Uri.parse('$base/me');
    await client.get(me);
    await client.patch(me, body: '{"full_name":"New"}');
    expect((await client.get(me)).body, '{"full_name":"New"}');
    await Future<void>.delayed(Duration.zero);
  });

  test('rotated credentials invalidate late requests even for the same account', () async {
    final response = Completer<http.Response>();
    client = create((_) => response.future);
    await client.setScope('alice');
    final request = client.get(posts);
    await Future<void>.delayed(Duration.zero);
    await client.setScope('alice', reset: true);
    final rejected = expectLater(request, throwsA(isA<CacheConnectionException>()));
    response.complete(http.Response('[]', 401));
    await rejected;
    expect(changes, isEmpty);
  });
}
