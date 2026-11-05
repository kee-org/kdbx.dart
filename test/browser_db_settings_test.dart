import 'package:kdbx/kdbx.dart';
import 'package:test/test.dart';

void main() {
  group('BrowserDbSettings default match accuracy', () {
    for (final accuracy in MatchAccuracy.values) {
      test('${accuracy.name} survives toJson and fromJson', () {
        final json = BrowserDbSettings(defaultMatchAccuracy: accuracy).toJson();
        expect(BrowserDbSettings.fromJson(json).defaultMatchAccuracy, accuracy);
      });
    }

    test(
        'is stored as the plain name, as the browser add-on and Kee Vault 1 write it',
        () {
      expect(
          BrowserDbSettings(defaultMatchAccuracy: MatchAccuracy.Exact)
              .toMap()['defaultMatchAccuracy'],
          'Exact');
      expect(
          BrowserDbSettings.fromJson(
                  '{"version":3,"defaultMatchAccuracy":"Hostname"}')
              .defaultMatchAccuracy,
          MatchAccuracy.Hostname);
    });

    test('a missing or unknown value falls back to Domain', () {
      expect(BrowserDbSettings.fromJson('{"version":3}').defaultMatchAccuracy,
          MatchAccuracy.Domain);
      expect(
          BrowserDbSettings.fromJson('{"defaultMatchAccuracy":"Nonsense"}')
              .defaultMatchAccuracy,
          MatchAccuracy.Domain);
    });

    test(
        'a non-default value is kept when set on the file and the file is saved and re-read',
        () async {
      final format = KdbxFormat(null, null);
      final credentials = Credentials(ProtectedValue.fromString('pw'));
      final file =
          format.create(credentials, 'db', header: KdbxHeader.createV3());
      file.body.meta.browserSettings =
          BrowserDbSettings(defaultMatchAccuracy: MatchAccuracy.Exact);
      final reread = await format.read(await file.save(), credentials);
      expect(reread.body.meta.browserSettings.defaultMatchAccuracy,
          MatchAccuracy.Exact);
    });
  });
}
