import 'dart:io';
import 'dart:math';

import '../access_control.dart';
import 'package:test/test.dart';

void main() {
  late Directory dataDirectory;
  late DateTime currentTime;
  late Random randomSource;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('puzzle-access-');
    currentTime = DateTime.utc(2026, 9, 27, 12);
    randomSource = Random(42);
  });

  tearDown(() async {
    if (await dataDirectory.exists()) {
      await dataDirectory.delete(recursive: true);
    }
  });

  Future<AccessControlStore> openStore() => AccessControlStore.open(
    dataDirectory: dataDirectory,
    now: () => currentTime,
    random: randomSource,
  );

  test(
    'allows one heavy operation per IP per UTC day and persists usage',
    () async {
      final store = await openStore();
      for (var use = 0; use < dailyServerOperationLimit; use++) {
        expect(
          await store.consumeHeavyOperation('192.0.2.10', invited: false),
          isTrue,
        );
      }
      expect(
        await store.consumeHeavyOperation('192.0.2.10', invited: false),
        isFalse,
      );

      final restarted = await openStore();
      expect(
        await restarted.consumeHeavyOperation('192.0.2.10', invited: false),
        isFalse,
      );
    },
  );

  test('invited operations bypass daily quota without a usage cap', () async {
    final store = await openStore();
    for (var use = 0; use < dailyServerOperationLimit; use++) {
      await store.consumeHeavyOperation('192.0.2.11', invited: false);
    }
    expect(
      await store.consumeHeavyOperation('192.0.2.11', invited: true),
      isTrue,
    );
    for (var use = 0; use < 20; use++) {
      expect(
        await store.consumeHeavyOperation('192.0.2.11', invited: true),
        isTrue,
      );
    }
  });

  test('invitation remains unchanged and valid across long periods', () async {
    final store = await openStore();
    final invitation = store.currentInvitationCode;
    expect(invitation, hasLength(20));
    expect(store.isInvitationValid(invitation), isTrue);
    expect(
      await File('${dataDirectory.path}/invitation-code.txt').exists(),
      isTrue,
    );

    final restarted = await openStore();
    expect(restarted.currentInvitationCode, invitation);

    currentTime = currentTime.add(const Duration(days: 3650));
    final rotated = await openStore();
    expect(rotated.currentInvitationCode, invitation);
    expect(rotated.isInvitationValid(invitation), isTrue);
    expect(rotated.isInvitationValid('x'), isFalse);
  });

  test('daily quota resets at UTC midnight', () async {
    final store = await openStore();
    for (var use = 0; use < dailyServerOperationLimit; use++) {
      await store.consumeHeavyOperation('192.0.2.12', invited: false);
    }
    currentTime = DateTime.utc(2026, 9, 28, 0, 1);
    expect(
      await store.consumeHeavyOperation('192.0.2.12', invited: false),
      isTrue,
    );
  });

  test('concurrent requests cannot exceed the daily quota', () async {
    final store = await openStore();
    final results = await Future.wait(
      List.generate(
        12,
        (_) => store.consumeHeavyOperation('192.0.2.13', invited: false),
      ),
    );
    expect(results.where((allowed) => allowed), hasLength(1));
  });
}
