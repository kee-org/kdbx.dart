import 'dart:convert';

import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/kee_vault_model/browser_entry_settings_v1.dart';
import 'package:kdbx/src/utils/guid_service.dart';
import 'package:test/test.dart';

/// Every known member at every level, members a newer Kee or KeePassRPC might
/// add, and enum values this version does not know. Written in the form
/// toJson produces (empty and default values left out), so that the output
/// decodes to exactly the same JSON.
const _canonicalJson = r'''
{
  "version": 2,
  "altUrls": ["https://alt.example/login"],
  "regExUrls": ["^https://re\\.example/.*$"],
  "blockedUrls": ["https://blocked.example"],
  "regExBlockedUrls": ["^https://blockre\\.example/.*$"],
  "httpRealm": "Realm",
  "authenticationMethods": ["password", "passkey"],
  "behaviour": "AlwaysAutoFillNeverAutoSubmit",
  "futureEntryMember": {"nested": [1, true, null, "x"]},
  "matcherConfigs": [
    {
      "matcherType": "Url",
      "urlMatchMethod": "Hostname",
      "weight": 2,
      "actionOnMatch": "TotalMatch",
      "actionOnNoMatch": "TotalBlock",
      "futureMatcherConfigMember": "kept",
      "customMatcher": {
        "matchLogic": "Any",
        "queries": ["form"],
        "pageTitles": ["Sign in"],
        "futureEntryMatcherMember": 7
      }
    },
    {"matcherType": "FutureMatcherType", "futureEnumMember": "kept"}
  ],
  "fields": [
    {
      "uuid": "AAECAwQFBgcICQoLDA0ODw==",
      "name": "Login",
      "valuePath": "UserName",
      "value": "{USERNAME}",
      "page": 2,
      "type": "Text",
      "placeholderHandling": "Enabled",
      "futureFieldMember": 1.5,
      "matcherConfigs": [
        {
          "matcherType": "UsernameDefaultHeuristic",
          "weight": 1,
          "actionOnMatch": "WeightedMatch",
          "futureFieldMatcherConfigMember": false,
          "customMatcher": {
            "matchLogic": "All",
            "ids": ["user"],
            "names": ["login"],
            "types": ["text"],
            "queries": ["input[name=login]"],
            "labels": ["User"],
            "autocompleteValues": ["username"],
            "maxLength": 64,
            "minLength": 1,
            "futureFieldMatcherMember": "kept"
          }
        }
      ]
    },
    {
      "uuid": "AAECAwQFBgcICQoLDA0ODw==",
      "valuePath": "Password",
      "page": 1,
      "type": "FutureFieldType",
      "placeholderHandling": "FuturePlaceholder",
      "matcherConfigs": [
        {
          "matcherType": "FutureFieldMatcherType",
          "actionOnMatch": "FutureAction",
          "customMatcher": {"matchLogic": "FutureLogic"}
        }
      ]
    }
  ],
  "authenticationMethodsUnused": true
}
''';

BrowserEntrySettings _parse(String json) => BrowserEntrySettings.fromJson(json,
    minimumMatchAccuracy: MatchAccuracy.Domain);

void main() {
  group('extra members are preserved', () {
    test('every known and unknown member survives a parse and re-serialise',
        () {
      final settings = _parse(_canonicalJson);
      expect(jsonDecode(settings.toJson()), equals(jsonDecode(_canonicalJson)));
    });

    test('the output is stable: serialising it again gives the same string',
        () {
      final once = _parse(_canonicalJson).toJson();
      expect(_parse(once).toJson(), once);
    });

    test('an unknown enum value has no typed value but is written back', () {
      final settings = _parse(_canonicalJson);
      final unknownMatcher = settings.matcherConfigs[1];
      expect(unknownMatcher.matcherType, isNull);
      expect(unknownMatcher.extraMembers['matcherType'], 'FutureMatcherType');
      expect(settings.fields![1].type, isNull);
      expect(settings.fields![1].placeholderHandling, isNull);
      expect(settings.fields![1].toMap()['type'], 'FutureFieldType');
      expect(settings.fields![1].toMap()['placeholderHandling'],
          'FuturePlaceholder');
    });

    test('a known value written over an unknown enum value wins', () {
      final settings = _parse(_canonicalJson);
      final unknownMatcher = settings.matcherConfigs[1];
      unknownMatcher.matcherType = EntryMatcherType.Hide;
      expect(unknownMatcher.toMap()['matcherType'], 'Hide');
      unknownMatcher.matcherType = null;
      expect(unknownMatcher.toMap()['matcherType'], 'FutureMatcherType');
    });

    test('an unknown enum value is written back when the field is unchanged',
        () {
      final settings = _parse(_canonicalJson);
      final rewritten = _parse(settings.toJson());
      expect(rewritten.matcherConfigs[1].toMap()['matcherType'],
          'FutureMatcherType');
      expect(rewritten.fields![1].toMap()['type'], 'FutureFieldType');
    });

    test('equality and hashCode include extra members', () {
      final a = _parse(_canonicalJson);
      final b = _parse(_canonicalJson);
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final c = a.copyWith(extraMembers: {
        ...a.extraMembers,
        'another': 1,
      });
      expect(c, isNot(a));

      final fieldA = a.fields!.first;
      expect(fieldA.copyWith(extraMembers: {...fieldA.extraMembers, 'x': 1}),
          isNot(fieldA));
    });

    test('copyWith keeps the extra members of every model', () {
      final settings = _parse(_canonicalJson);
      final entryMatcherConfig = settings.matcherConfigs.first;
      final entryMatcher = entryMatcherConfig.customMatcher!;
      final field = settings.fields!.first;
      final fieldMatcherConfig = field.matcherConfigs!.first;
      final fieldMatcher = fieldMatcherConfig.customMatcher!;

      expect(settings.copyWith(realm: 'other').extraMembers,
          settings.extraMembers);
      expect(entryMatcherConfig.copyWith(weight: 3).extraMembers,
          entryMatcherConfig.extraMembers);
      expect(entryMatcher.copyWith(queries: []).extraMembers,
          entryMatcher.extraMembers);
      expect(field.copyWith(name: 'other').extraMembers, field.extraMembers);
      expect(fieldMatcherConfig.copyWith(weight: 3).extraMembers,
          fieldMatcherConfig.extraMembers);
      expect(fieldMatcher.copyWith(ids: []).extraMembers,
          fieldMatcher.extraMembers);

      expect(
          settings
              .copyWith(matcherConfigs: [])
              .toMap()
              .containsKey('futureEntryMember'),
          isTrue);
    });

    test('a copy does not share the extra members map with its source', () {
      final settings = _parse(_canonicalJson);
      final source = {'a': 1};
      final field = Field(extraMembers: source);
      source['a'] = 2;
      expect(field.extraMembers['a'], 1);
      expect(() => field.extraMembers['b'] = 3, throwsUnsupportedError);
      expect(settings.extraMembers.containsKey('futureEntryMember'), isTrue);
    });
  });

  group('invalid regular expressions', () {
    const json = r'''
{
  "version": 2,
  "altUrls": ["https://a.example"],
  "regExUrls": ["(?i)foo", "[", "^https://ok\\.example$"],
  "regExBlockedUrls": ["(?i)bar"],
  "authenticationMethods": [],
  "fields": [],
  "matcherConfigs": [{"matcherType": "Url"}]
}
''';

    test('an uncompilable pattern is kept and does not throw', () {
      final settings = _parse(json);
      expect(settings.includeUrls[0], 'https://a.example');
      expect(settings.includeUrls[1], UnparsableRegExp('(?i)foo'));
      expect(settings.includeUrls[2], UnparsableRegExp('['));
      expect(settings.includeUrls[3], isA<RegExp>());
      expect(settings.excludeUrls, [UnparsableRegExp('(?i)bar')]);
    });

    test('an uncompilable pattern never matches', () {
      final pattern = UnparsableRegExp('(?i)foo');
      expect(pattern.allMatches('foo'), isEmpty);
      expect(pattern.matchAsPrefix('foo'), isNull);
      expect(pattern.matchAsPrefix('(?i)foo'), isNull);
    });

    test('an uncompilable pattern round-trips losslessly', () {
      expect(jsonDecode(_parse(json).toJson()), equals(jsonDecode(json)));
    });

    test('the value equality of UnparsableRegExp is on the source', () {
      expect(UnparsableRegExp('(?i)a'), UnparsableRegExp('(?i)a'));
      expect(UnparsableRegExp('(?i)a').hashCode,
          UnparsableRegExp('(?i)a').hashCode);
      expect(UnparsableRegExp('(?i)a'), isNot(UnparsableRegExp('(?i)b')));
      expect(UnparsableRegExp('a'), isNot('a'));
    });

    test('converting to v1 and back keeps the pattern', () {
      final v1 = _parse(json).convertToV1();
      final v1Json = jsonDecode(v1.toJson()) as Map<String, dynamic>;
      expect(v1Json['regExURLs'], ['(?i)foo', '[', '^https://ok\\.example\$']);
      expect(v1Json['regExBlockedURLs'], ['(?i)bar']);

      final back = BrowserEntrySettingsV1.fromJson(v1.toJson(),
              minimumMatchAccuracy: MatchAccuracy.Domain)
          .convertToV2(_NoGuid());
      expect(back.includeUrls[1], UnparsableRegExp('(?i)foo'));
      expect(back.includeUrls[2], UnparsableRegExp('['));
    });

    test('the v1 model keeps an uncompilable pattern too', () {
      const v1Json =
          '{"regExURLs":["(?i)x"],"regExBlockedURLs":["["],"altURLs":[],"blockedURLs":[]}';
      final v1 = BrowserEntrySettingsV1.fromJson(v1Json,
          minimumMatchAccuracy: MatchAccuracy.Domain);
      expect(v1.includeUrls, [UnparsableRegExp('(?i)x')]);
      expect(v1.excludeUrls, [UnparsableRegExp('[')]);
      expect(jsonDecode(v1.toJson())['regExURLs'], ['(?i)x']);
      expect(jsonDecode(v1.toJson())['regExBlockedURLs'], ['[']);
    });
  });
}

class _NoGuid implements IGuidService {
  @override
  String newGuidAsBase64() => 'AAAAAAAAAAAAAAAAAAAAAA==';
}
