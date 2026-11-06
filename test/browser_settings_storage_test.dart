import 'dart:convert';

import 'package:kdbx/kdbx.dart';
import 'package:test/test.dart';

MatchAccuracy? _urlAccuracy(KdbxEntry entry) =>
    entry.browserSettings.matcherConfigs
        .firstWhere((mc) => mc.matcherType == EntryMatcherType.Url)
        .urlMatchMethod;

void main() {
  final format = KdbxFormat(null, null);
  final credentials = Credentials(ProtectedValue.fromString('pw'));

  KdbxFile newFile() =>
      format.create(credentials, 'db', header: KdbxHeader.createV3());

  Future<KdbxFile> saveAndReread(KdbxFile file) async =>
      format.read(await file.save(), credentials);

  group('corrupt DB-level config reads as the defaults', () {
    const corruptBrowserConfigs = [
      '{not json',
      '[1,2]',
      '{"matchedURLAccuracyOverrides": 5}',
    ];
    for (final corrupt in corruptBrowserConfigs) {
      test('KeePassRPC.Config $corrupt', () async {
        final file = newFile();
        file.body.meta.customData['KeePassRPC.Config'] =
            (value: corrupt, lastModified: DateTime.now().toUtc());

        final settings = file.body.meta.browserSettings;
        expect(settings.defaultMatchAccuracy, MatchAccuracy.Domain);
        expect(settings.version, 3);
        expect(file.body.meta.customData['KeePassRPC.Config']?.value, corrupt,
            reason: 'a read must not overwrite the stored value');

        final reread = await saveAndReread(file);
        expect(reread.body.meta.customData['KeePassRPC.Config']?.value, corrupt,
            reason: 'nor may a save that did not set it');
      });
    }

    for (final corrupt in ['{not json', '[1,2]', '{"addon": 3}']) {
      test('KeeVault.Config $corrupt', () async {
        final file = newFile();
        file.body.meta.customData['KeeVault.Config'] =
            (value: corrupt, lastModified: DateTime.now().toUtc());

        final config = file.body.meta.keeVaultSettings;
        expect(config.version, 1);
        expect(file.body.meta.customData['KeeVault.Config']?.value, corrupt,
            reason: 'a read must not overwrite the stored value');
      });
    }

    test('a setter replaces a corrupt value', () async {
      final file = newFile();
      file.body.meta.customData['KeePassRPC.Config'] =
          (value: '{not json', lastModified: DateTime.now().toUtc());
      expect(file.body.meta.browserSettings.defaultMatchAccuracy,
          MatchAccuracy.Domain);

      file.body.meta.browserSettings =
          BrowserDbSettings(defaultMatchAccuracy: MatchAccuracy.Exact);
      final reread = await saveAndReread(file);
      expect(reread.body.meta.browserSettings.defaultMatchAccuracy,
          MatchAccuracy.Exact);
    });
  });

  group('setters are seen by the next read in the same session', () {
    test('BrowserDbSettings', () {
      final file = newFile();
      expect(file.body.meta.browserSettings.defaultMatchAccuracy,
          MatchAccuracy.Domain);
      file.body.meta.browserSettings =
          BrowserDbSettings(defaultMatchAccuracy: MatchAccuracy.Exact);
      expect(file.body.meta.browserSettings.defaultMatchAccuracy,
          MatchAccuracy.Exact);
    });

    test('KeeVaultEmbeddedConfig', () {
      final file = newFile();
      final before = file.body.meta.keeVaultSettings;
      file.body.meta.keeVaultSettings = KeeVaultEmbeddedConfig(
          version: 7, randomId: 'fixed', addon: {'prefs': {}});
      expect(file.body.meta.keeVaultSettings.version, 7);
      expect(file.body.meta.keeVaultSettings.randomId, 'fixed');
      expect(before.version, 1);
    });

    test('a new entry uses the default match accuracy set after it was read',
        () {
      final file = newFile();
      expect(file.body.meta.browserSettings.defaultMatchAccuracy,
          MatchAccuracy.Domain);
      file.body.meta.browserSettings =
          BrowserDbSettings(defaultMatchAccuracy: MatchAccuracy.Hostname);

      final entry = KdbxEntry.create(file, file.body.rootGroup);
      expect(_urlAccuracy(entry), MatchAccuracy.Hostname);
    });
  });

  group('entry KPRPC JSON', () {
    for (final corrupt in ['{not json', '[1,2]', '{"altUrls": 5}']) {
      test('corrupt v2 $corrupt reads as the default and is not rewritten', () {
        final file = newFile();
        final entry = KdbxEntry.create(file, file.body.rootGroup);
        file.body.rootGroup.addEntry(entry);
        entry.setCustomData('KPRPC JSON', corrupt);

        expect(_urlAccuracy(entry), MatchAccuracy.Domain);
        expect(entry.browserSettings.includeUrls, isEmpty);
        expect(entry.getCustomData('KPRPC JSON'), corrupt);
      });
    }

    test('a corrupt v1 string reads as the default and is not rewritten', () {
      final file = newFile();
      final entry = KdbxEntry.create(file, file.body.rootGroup);
      file.body.rootGroup.addEntry(entry);
      entry.setString(
          KdbxKey('KPRPC JSON'), ProtectedValue.fromString('[oops'));

      expect(_urlAccuracy(entry), MatchAccuracy.Domain);
      expect(entry.getString(KdbxKey('KPRPC JSON'))?.getText(), '[oops');
    });

    test('an entry with a pattern Dart cannot compile reads after a save',
        () async {
      final file = newFile();
      final entry = KdbxEntry.create(file, file.body.rootGroup);
      file.body.rootGroup.addEntry(entry);
      entry.browserSettings = BrowserEntrySettings(
        includeUrls: [UnparsableRegExp('(?i)foo'), 'https://a.example'],
        excludeUrls: [UnparsableRegExp('[')],
        matcherConfigs: [
          EntryMatcherConfig.forDefaultUrlMatchBehaviour(MatchAccuracy.Domain)
        ],
      );

      final reread = await saveAndReread(file);
      final settings =
          reread.body.rootGroup.entries.values.single.browserSettings;
      expect(settings.includeUrls,
          ['https://a.example', UnparsableRegExp('(?i)foo')]);
      expect(settings.excludeUrls, [UnparsableRegExp('[')]);
    });

    test('unknown members survive a save and re-read', () async {
      final file = newFile();
      final entry = KdbxEntry.create(file, file.body.rootGroup);
      file.body.rootGroup.addEntry(entry);
      entry.browserSettings = BrowserEntrySettings.fromJson(
          '{"version":2,"futureTop":{"a":1},"matcherConfigs":[{"matcherType":"Url","futureMatcher":"x"}]}',
          minimumMatchAccuracy: MatchAccuracy.Domain);

      final reread = await saveAndReread(file);
      final json = jsonDecode(reread.body.rootGroup.entries.values.single
          .getCustomData('KPRPC JSON')!) as Map<String, dynamic>;
      expect(json['futureTop'], {'a': 1});
      expect(json['matcherConfigs'][0]['futureMatcher'], 'x');
    });
  });
}
