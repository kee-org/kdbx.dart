import 'dart:convert';

import 'package:kdbx/kdbx.dart';
import 'package:test/test.dart';

// An explicit Url match method of Domain is stored as written, and absent stays absent. KeePassRPC treats the two as
// different stored values (Equals compares them, and an absent method means Domain only at match time), so the model
// must not write the explicit one away.

Map<String, dynamic> _storedMatcher(KdbxEntry entry) {
  final json = jsonDecode(entry.getCustomData('KPRPC JSON')!) as Map<String, dynamic>;
  return (json['matcherConfigs'] as List).first as Map<String, dynamic>;
}

void main() {
  final format = KdbxFormat(null, null);
  final credentials = Credentials(ProtectedValue.fromString('pw'));

  test('an explicit Domain is written and reads back as Domain', () async {
    final file = format.create(credentials, 'db', header: KdbxHeader.createV3());
    final entry = KdbxEntry.create(file, file.body.rootGroup);
    file.body.rootGroup.addEntry(entry);
    entry.browserSettings = BrowserEntrySettings(
      matcherConfigs: [
        EntryMatcherConfig(matcherType: EntryMatcherType.Url, urlMatchMethod: MatchAccuracy.Domain),
      ],
    );

    expect(_storedMatcher(entry), {'matcherType': 'Url', 'urlMatchMethod': 'Domain'});

    final reread = await format.read(await file.save(), credentials);
    final matcher = reread.body.rootGroup.entries.values.single.browserSettings.matcherConfigs.single;
    expect(matcher.urlMatchMethod, MatchAccuracy.Domain);
  });

  test('an absent method is written as absent and reads back as absent', () async {
    final file = format.create(credentials, 'db', header: KdbxHeader.createV3());
    final entry = KdbxEntry.create(file, file.body.rootGroup);
    file.body.rootGroup.addEntry(entry);
    entry.browserSettings = BrowserEntrySettings(
      matcherConfigs: [EntryMatcherConfig(matcherType: EntryMatcherType.Url)],
    );

    expect(_storedMatcher(entry), {'matcherType': 'Url'});

    final reread = await format.read(await file.save(), credentials);
    final matcher = reread.body.rootGroup.entries.values.single.browserSettings.matcherConfigs.single;
    expect(matcher.urlMatchMethod, isNull);
  });

  test('Hostname and Exact are written as before', () {
    for (final method in [MatchAccuracy.Hostname, MatchAccuracy.Exact]) {
      final matcher = EntryMatcherConfig(matcherType: EntryMatcherType.Url, urlMatchMethod: method);
      expect(matcher.toMap()['urlMatchMethod'], method.name);
    }
  });

  group('a v1 configuration converts as KeePassRPC converts it', () {
    // The entry is saved and read again: KdbxEntry.create caches a default configuration that setString does not
    // clear, and an entry read from a file has no such cache.
    Future<KdbxEntry> v1Entry(String json) async {
      final file = format.create(credentials, 'db', header: KdbxHeader.createV3());
      final entry = KdbxEntry.create(file, file.body.rootGroup);
      file.body.rootGroup.addEntry(entry);
      entry.setString(KdbxKey('KPRPC JSON'), ProtectedValue.fromString(json));
      final reread = await format.read(await file.save(), credentials);
      return reread.body.rootGroup.entries.values.single;
    }

    test('no flag gives no method, which reads as Domain', () async {
      final entry = await v1Entry('{"version":1,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false}');
      expect(entry.browserSettings.matcherConfigs.single.urlMatchMethod, isNull);
      expect(entry.browserSettings.matcherConfigs.single.toMap(), {'matcherType': 'Url'});
    });

    test('blockDomainOnlyMatch gives Hostname, and blockHostnameOnlyMatch gives Exact', () async {
      expect(
        (await v1Entry('{"version":1,"blockDomainOnlyMatch":true,"blockHostnameOnlyMatch":false}'))
            .browserSettings
            .matcherConfigs
            .single
            .urlMatchMethod,
        MatchAccuracy.Hostname,
      );
      expect(
        (await v1Entry('{"version":1,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":true}'))
            .browserSettings
            .matcherConfigs
            .single
            .urlMatchMethod,
        MatchAccuracy.Exact,
      );
    });
  });
}
