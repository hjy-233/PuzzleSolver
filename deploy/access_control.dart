import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const weeklyInvitationLifetime = Duration(days: 7);
const dailyServerOperationLimit = 1;
const _maximumTrackedDailyIps = 20000;

/// Persistent weekly invitation and per-IP daily heavy-operation accounting.
/// Only the current day's usage journal is retained.
final class AccessControlStore {
  AccessControlStore._({
    required this.dataDirectory,
    required this.now,
    required Random random,
    required String invitationCode,
    required DateTime invitationCreatedAt,
  }) : _random = random,
       _invitationCode = invitationCode,
       _invitationCreatedAt = invitationCreatedAt;

  final Directory dataDirectory;
  final DateTime Function() now;
  final Random _random;
  final Map<String, int> _dailyUse = {};
  String _invitationCode;
  DateTime _invitationCreatedAt;
  DateTime? _loadedDay;
  Future<void> _writeQueue = Future<void>.value();

  String get currentInvitationCode => _invitationCode;

  DateTime get invitationExpiresAt =>
      _invitationCreatedAt.add(weeklyInvitationLifetime);

  static Future<AccessControlStore> open({
    required Directory dataDirectory,
    DateTime Function()? now,
    Random? random,
  }) async {
    final clock = now ?? DateTime.now;
    final randomSource = random ?? Random.secure();
    await dataDirectory.create(recursive: true);
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('chmod', ['700', dataDirectory.path]);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Could not restrict access-control data directory permissions.',
          dataDirectory.path,
        );
      }
    }
    final stateFile = File('${dataDirectory.path}/invitation.json');
    final currentTime = clock().toUtc();
    String invitationCode;
    DateTime createdAt;
    if (await stateFile.exists()) {
      final decoded = jsonDecode(await stateFile.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['code'] is! String ||
          decoded['createdAt'] is! String) {
        throw const FormatException('Stored invitation state is invalid.');
      }
      invitationCode = decoded['code'] as String;
      createdAt = DateTime.parse(decoded['createdAt'] as String).toUtc();
      if (currentTime.difference(createdAt) >= weeklyInvitationLifetime ||
          currentTime.isBefore(createdAt)) {
        invitationCode = _makeCode(randomSource);
        createdAt = currentTime;
      }
    } else {
      invitationCode = _makeCode(randomSource);
      createdAt = currentTime;
    }
    final store = AccessControlStore._(
      dataDirectory: dataDirectory,
      now: clock,
      random: randomSource,
      invitationCode: invitationCode,
      invitationCreatedAt: createdAt,
    );
    await store._persistInvitation();
    await store._loadUsageForCurrentDay();
    return store;
  }

  bool isInvitationValid(String? candidate) {
    if (candidate == null || candidate.length != _invitationCode.length) {
      return false;
    }
    var difference = 0;
    final candidateBytes = utf8.encode(candidate);
    final expectedBytes = utf8.encode(_invitationCode);
    for (var index = 0; index < expectedBytes.length; index++) {
      difference |= candidateBytes[index] ^ expectedBytes[index];
    }
    return difference == 0 && now().toUtc().isBefore(invitationExpiresAt);
  }

  Future<bool> rotateInvitationIfExpired() async {
    final currentTime = now().toUtc();
    if (currentTime.isBefore(invitationExpiresAt) &&
        !currentTime.isBefore(_invitationCreatedAt)) {
      return false;
    }
    return _serialize(() async {
      final refreshedTime = now().toUtc();
      if (refreshedTime.isBefore(invitationExpiresAt) &&
          !refreshedTime.isBefore(_invitationCreatedAt)) {
        return false;
      }
      _invitationCode = _makeCode(_random);
      _invitationCreatedAt = refreshedTime;
      await _persistInvitation();
      return true;
    });
  }

  Future<bool> consumeHeavyOperation(
    String clientAddress, {
    required bool invited,
  }) {
    return _serialize(() async {
      if (invited) return true;
      final today = _utcDay(now());
      if (_loadedDay != today) await _loadUsageForCurrentDay();
      final count = _dailyUse[clientAddress] ?? 0;
      if (count >= dailyServerOperationLimit ||
          (count == 0 && _dailyUse.length >= _maximumTrackedDailyIps)) {
        return false;
      }
      final journal = _usageJournal(today);
      final file = await journal.open(mode: FileMode.append);
      try {
        await file.writeString('$clientAddress\n');
        await file.flush();
      } finally {
        await file.close();
      }
      _dailyUse[clientAddress] = count + 1;
      return true;
    });
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _loadUsageForCurrentDay() async {
    final today = _utcDay(now());
    _dailyUse.clear();
    _loadedDay = today;
    await for (final entity in dataDirectory.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('usage-') &&
          entity.path.endsWith('.txt') &&
          entity.path != _usageJournal(today).path) {
        await entity.delete();
      }
    }
    final journal = _usageJournal(today);
    if (!await journal.exists()) return;
    final contents = await journal.readAsLines();
    for (final address in contents) {
      if (address.isEmpty) continue;
      _dailyUse.update(address, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  File _usageJournal(DateTime day) =>
      File('${dataDirectory.path}/usage-${_dayName(day)}.txt');

  Future<void> _persistInvitation() async {
    final state = jsonEncode({
      'code': _invitationCode,
      'createdAt': _invitationCreatedAt.toIso8601String(),
    });
    await _writePrivateFile(
      File('${dataDirectory.path}/invitation.json'),
      state,
    );
    await _writePrivateFile(
      File('${dataDirectory.path}/invitation-code.txt'),
      '$_invitationCode\nExpires: ${invitationExpiresAt.toIso8601String()}\n',
    );
  }

  Future<void> _writePrivateFile(File destination, String contents) async {
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(destination.path);
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('chmod', ['600', destination.path]);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Could not restrict invitation file permissions.',
          destination.path,
        );
      }
    }
  }

  static String _makeCode(Random random) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
    return List.generate(
      20,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static DateTime _utcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static String _dayName(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}'
      '-${day.month.toString().padLeft(2, '0')}'
      '-${day.day.toString().padLeft(2, '0')}';
}
