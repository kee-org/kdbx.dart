import 'package:clock/clock.dart';
import 'package:kdbx/src/kee_vault_model/browser_entry_settings.dart';
import 'package:kdbx/src/kee_vault_model/browser_entry_settings_v1.dart';
import 'package:kdbx/src/kee_vault_model/enums.dart';
import 'package:kdbx/src/utils/guid_service.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:test/test.dart';

import 'internal/test_utils.dart';

final _logger = Logger('browser_entry_settings_test');

class MockGuidService implements IGuidService {
  @override
  String newGuidAsBase64() {
    return 'AAAAAAAAAAAAAAAAAAAAAA==';
  }
}

void main() {
  Logger.root.level = Level.ALL;
  PrintAppender().attachToLogger(Logger.root);
  final kdbxFormat = TestUtil.kdbxFormat();
  if (!kdbxFormat.argon2.isFfi) {
    throw StateError('Expected ffi!');
  }
  var now = DateTime.fromMillisecondsSinceEpoch(0);

  final fakeClock = Clock(() => now);
  void proceedSeconds(int seconds) {
    now = now.add(Duration(seconds: seconds));
  }

  setUp(() {
    now = DateTime.fromMillisecondsSinceEpoch(0);
  });

  void testCase(String persistedV2, String expectedResult) {
    final bes = BrowserEntrySettings.fromJson(persistedV2,
        minimumMatchAccuracy: MatchAccuracy.Domain);
    final configV1 = bes.convertToV1();
    final sut = configV1.toJson();

    expect(sut, expectedResult);
  }

  void testCaseToV2(String persistedV1, String expectedResult) {
    final bes = BrowserEntrySettingsV1.fromJson(persistedV1,
        minimumMatchAccuracy: MatchAccuracy.Domain);
    final configV2 = bes.convertToV2(MockGuidService());
    final sut = configV2.toJson();

    expect(sut, expectedResult);
  }

  void testCaseRT(String persistedV2) {
    final bes = BrowserEntrySettings.fromJson(persistedV2,
        minimumMatchAccuracy: MatchAccuracy.Domain);
    final configV1 = bes.convertToV1();
    final jsonV1 = configV1.toJson();
    final besV1 = BrowserEntrySettingsV1.fromJson(jsonV1,
        minimumMatchAccuracy: MatchAccuracy.Domain);
    final configV2 = besV1.convertToV2(MockGuidService());
    final sut = configV2.toJson();

    expect(sut, persistedV2);
  }

  group('BrowserEntrySettings', () {
    test('config v2->v1', () async {
      testCase(
          '{"version":2,"altUrls":[],"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"},{"matcherType":"Hide"}],"fields":[{"page":-1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"],"queries":[]}}]},{"page":-1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"],"queries":[]}}]}]}',
          '{"version":1,"priority":0,"hide":true,"hTTPRealm":"","formFieldList":[{"displayName":"KeePass password","name":"password","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default","value":"{PASSWORD}"},{"displayName":"KeePass username","name":"username","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default","value":"{USERNAME}"}],"alwaysAutoFill":false,"alwaysAutoSubmit":false,"neverAutoFill":false,"neverAutoSubmit":false,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false,"altURLs":[],"regExURLs":[],"blockedURLs":[],"regExBlockedURLs":[]}');

      testCase(
          '{"version":2,"altUrls":[],"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":-1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"],"queries":[]}}]},{"page":-1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"],"queries":[]}}]}]}',
          '{"version":1,"priority":0,"hide":false,"hTTPRealm":"","formFieldList":[{"displayName":"KeePass password","name":"password","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default","value":"{PASSWORD}"},{"displayName":"KeePass username","name":"username","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default","value":"{USERNAME}"}],"alwaysAutoFill":false,"alwaysAutoSubmit":false,"neverAutoFill":false,"neverAutoSubmit":false,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false,"altURLs":[],"regExURLs":[],"blockedURLs":[],"regExBlockedURLs":[]}');

      testCase(
          '{"version":2,"httpRealm":"re","altUrls":[],"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":-1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"],"queries":[]}}]},{"page":-1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"],"queries":[]}}]}]}',
          '{"version":1,"priority":0,"hide":false,"hTTPRealm":"re","formFieldList":[{"displayName":"KeePass password","name":"password","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default","value":"{PASSWORD}"},{"displayName":"KeePass username","name":"username","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default","value":"{USERNAME}"}],"alwaysAutoFill":false,"alwaysAutoSubmit":false,"neverAutoFill":false,"neverAutoSubmit":false,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false,"altURLs":[],"regExURLs":[],"blockedURLs":[],"regExBlockedURLs":[]}');

      testCase(
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":-1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"matcherType":"UsernameDefaultHeuristic"}]},{"page":-1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"matcherType":"PasswordDefaultHeuristic"}]}]}',
          '{"version":1,"priority":0,"hide":false,"hTTPRealm":"","formFieldList":[{"displayName":"KeePass username","name":"","type":"FFTusername","id":"","page":-1,"placeholderHandling":"Default","value":"{USERNAME}"},{"displayName":"KeePass password","name":"","type":"FFTpassword","id":"","page":-1,"placeholderHandling":"Default","value":"{PASSWORD}"}],"alwaysAutoFill":false,"alwaysAutoSubmit":false,"neverAutoFill":false,"neverAutoSubmit":false,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false,"altURLs":[],"regExURLs":[],"blockedURLs":[],"regExBlockedURLs":[]}');

      testCase(
          '{"version":2,"altUrls":["http://test.com/1","http://test.com/2"],"regExUrls":["3","4"],"blockedUrls":["5","6"],"regExBlockedUrls":["7","8"],"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":-1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"],"queries":[]}}]},{"page":-1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"],"queries":[]}}]}]}',
          '{"version":1,"priority":0,"hide":false,"hTTPRealm":"","formFieldList":[{"displayName":"KeePass password","name":"password","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default","value":"{PASSWORD}"},{"displayName":"KeePass username","name":"username","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default","value":"{USERNAME}"}],"alwaysAutoFill":false,"alwaysAutoSubmit":false,"neverAutoFill":false,"neverAutoSubmit":false,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false,"altURLs":["http://test.com/1","http://test.com/2"],"regExURLs":["3","4"],"blockedURLs":["5","6"],"regExBlockedURLs":["7","8"]}');

      testCase(
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":0,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"matcherType":"UsernameDefaultHeuristic"}]},{"page":-1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"matcherType":"PasswordDefaultHeuristic"}]},{"uuid":"AAAAAAAAAAAAAAAAAAAAAA==","name":"dis Name","valuePath":".","value":"KEEFOX_CHECKED_FLAG_TRUE","page":3,"type":"Toggle","placeholderHandling":"Disabled","matcherConfigs":[{"customMatcher":{"ids":["www"],"names":["rrr"],"types":["checkbox"],"queries":[]}}]},{"uuid":"AAAAAAAAAAAAAAAAAAAAAA==","name":"","valuePath":".","value":"RadioValue","page":1,"type":"Existing","matcherConfigs":[{"customMatcher":{"ids":["radid"],"names":["radname"],"types":["radio"],"queries":[]}}]}]}',
          '{"version":1,"priority":0,"hide":false,"hTTPRealm":"","formFieldList":[{"displayName":"KeePass username","name":"","type":"FFTusername","id":"","page":0,"placeholderHandling":"Default","value":"{USERNAME}"},{"displayName":"KeePass password","name":"","type":"FFTpassword","id":"","page":-1,"placeholderHandling":"Default","value":"{PASSWORD}"},{"displayName":"dis Name","name":"rrr","type":"FFTcheckbox","id":"www","page":3,"placeholderHandling":"Disabled","value":"KEEFOX_CHECKED_FLAG_TRUE"},{"displayName":"AAAAAAAAAAAAAAAAAAAAAA==","name":"radname","type":"FFTradio","id":"radid","page":1,"placeholderHandling":"Default","value":"RadioValue"}],"alwaysAutoFill":false,"alwaysAutoSubmit":false,"neverAutoFill":false,"neverAutoSubmit":false,"blockDomainOnlyMatch":false,"blockHostnameOnlyMatch":false,"altURLs":[],"regExURLs":[],"blockedURLs":[],"regExBlockedURLs":[]}');
    });

    test('config v1->v2', () async {
      testCaseToV2(
          '{"version":1,"hTTPRealm":"","formFieldList":[{"name":"password","displayName":"KeePass password","value":"{PASSWORD}","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default"},{"name":"username","displayName":"KeePass username","value":"{USERNAME}","type":"FFTradio","id":"username","page":-1,"placeholderHandling":"Default"}],"alwaysAutoFill":false,"neverAutoFill":false,"alwaysAutoSubmit":false,"neverAutoSubmit":false,"priority":0,"altURLs":[],"hide":true,"blockHostnameOnlyMatch":false,"blockDomainOnlyMatch":false}',
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"},{"matcherType":"Hide"}],"fields":[{"page":1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"]}}]},{"page":1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"]}}]}]}');

      testCaseToV2(
          '{"version":1,"hTTPRealm":"","formFieldList":[{"name":"password","displayName":"KeePass password","value":"{PASSWORD}","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default"},{"name":"username","displayName":"KeePass username","value":"{USERNAME}","type":"FFTradio","id":"username","page":-1,"placeholderHandling":"Default"}],"alwaysAutoFill":false,"neverAutoFill":false,"alwaysAutoSubmit":false,"neverAutoSubmit":false,"priority":0,"altURLs":[],"hide":false,"blockHostnameOnlyMatch":false,"blockDomainOnlyMatch":false}',
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"]}}]},{"page":1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"]}}]}]}');

      testCaseToV2(
          '{"version":1,"hTTPRealm":"re","formFieldList":[{"name":"password","displayName":"KeePass password","value":"{PASSWORD}","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default"},{"name":"username","displayName":"KeePass username","value":"{USERNAME}","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default"}],"alwaysAutoFill":false,"neverAutoFill":false,"alwaysAutoSubmit":false,"neverAutoSubmit":false,"priority":0,"altURLs":[],"hide":false,"blockHostnameOnlyMatch":false,"blockDomainOnlyMatch":false}',
          '{"version":2,"authenticationMethods":["password"],"httpRealm":"re","matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"]}}]},{"page":1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"]}}]}]}');

      testCaseToV2(
          '{"version":1,"hTTPRealm":"","formFieldList":[{"name":"password","displayName":"KeePass password","value":"{PASSWORD}","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default"},{"name":"username","displayName":"KeePass username","value":"{USERNAME}","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default"}],"alwaysAutoFill":false,"neverAutoFill":false,"alwaysAutoSubmit":false,"neverAutoSubmit":false,"priority":0,"altURLs":["http://test.com/1","http://test.com/2"],"regExURLs":["3","4"],"blockedURLs":["5","6"],"regExBlockedURLs":["7","8"],"hide":false,"blockHostnameOnlyMatch":false,"blockDomainOnlyMatch":false}',
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"]}}]},{"page":1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"]}}]}],"altUrls":["http://test.com/1","http://test.com/2"],"regExUrls":["3","4"],"blockedUrls":["5","6"],"regExBlockedUrls":["7","8"]}');

      testCaseToV2('',
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"matcherType":"UsernameDefaultHeuristic"}]},{"page":1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"matcherType":"PasswordDefaultHeuristic"}]}]}');

      testCaseToV2(
          '{"version":1,"hTTPRealm":"","formFieldList":[{"name":"password","displayName":"KeePass password","value":"{PASSWORD}","type":"FFTpassword","id":"password","page":-1,"placeholderHandling":"Default"},{"name":"username","displayName":"KeePass username","value":"{USERNAME}","type":"FFTusername","id":"username","page":-1,"placeholderHandling":"Default"},{"displayName":"dis Name","name":"rrr","type":"FFTcheckbox","id":"www","page":3,"placeholderHandling":"Disabled","value":"KEEFOX_CHECKED_FLAG_TRUE"},{"displayName":"","name":"radname","type":"FFTradio","id":"radid","page":1,"placeholderHandling":"Default","value":"RadioValue"}],"alwaysAutoFill":false,"neverAutoFill":false,"alwaysAutoSubmit":false,"neverAutoSubmit":false,"priority":0,"altURLs":[],"hide":false,"blockHostnameOnlyMatch":false,"blockDomainOnlyMatch":false}',
          '{"version":2,"authenticationMethods":["password"],"matcherConfigs":[{"matcherType":"Url"}],"fields":[{"page":1,"valuePath":"Password","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Password","matcherConfigs":[{"customMatcher":{"ids":["password"],"names":["password"],"types":["password"]}}]},{"page":1,"valuePath":"UserName","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Text","matcherConfigs":[{"customMatcher":{"ids":["username"],"names":["username"],"types":["text"]}}]},{"page":3,"valuePath":".","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Toggle","matcherConfigs":[{"customMatcher":{"ids":["www"],"names":["rrr"],"types":["checkbox"]}}],"name":"dis Name","value":"KEEFOX_CHECKED_FLAG_TRUE","placeholderHandling":"Disabled"},{"page":1,"valuePath":".","uuid":"AAAAAAAAAAAAAAAAAAAAAA==","type":"Existing","matcherConfigs":[{"customMatcher":{"ids":["radid"],"names":["radname"],"types":["radio"]}}],"name":"AAAAAAAAAAAAAAAAAAAAAA==","value":"RadioValue"}]}');
    });
  });
}
