import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:xml/xml.dart' as xml;

class KdbxObjectCustomData extends KdbxNode {
  KdbxObjectCustomData.create()
      : _data = {},
        super.create(KdbxXml.NODE_CUSTOM_DATA);

  KdbxObjectCustomData.read(xml.XmlElement node)
      : _data = Map.fromEntries(
            node.findElements(KdbxXml.NODE_CUSTOM_DATA_ITEM).map((el) {
          final key = el.singleTextNode(KdbxXml.NODE_KEY);
          final value = el.singleTextNode(KdbxXml.NODE_VALUE);
          return MapEntry(key, value);
        })),
        super.read(node);

  final Map<String, String> _data;

  Iterable<MapEntry<String, String>> get entries => _data.entries;

  String? operator [](String key) => _data[key];
  void operator []=(String key, String value) {
    modify(() => _data[key] = value);
  }

  bool containsKey(String key) => _data.containsKey(key);
  String? remove(String key) => modify(() => _data.remove(key));

  @override
  xml.XmlElement toXml() {
    final el = super.toXml();
    el.children.clear();
    el.children.addAll(
      _data.entries
          .map((e) => XmlUtils.createNode(KdbxXml.NODE_CUSTOM_DATA_ITEM, [
                XmlUtils.createTextNode(KdbxXml.NODE_KEY, e.key),
                XmlUtils.createTextNode(KdbxXml.NODE_VALUE, e.value),
              ])),
    );
    return el;
  }

  void overwriteFrom(KdbxObjectCustomData other) {
    _data.clear();
    _data.addAll(other._data);
  }
}

typedef KdbxMetaCustomDataItem = ({
  String value,
  DateTime? lastModified,
});

class KdbxMetaCustomData extends KdbxNode {
  KdbxMetaCustomData.create()
      : _data = {},
        super.create(KdbxXml.NODE_CUSTOM_DATA);

  KdbxMetaCustomData.read(xml.XmlElement node)
      : _data = Map.fromEntries(
            node.findElements(KdbxXml.NODE_CUSTOM_DATA_ITEM).map((el) {
          final key = el.singleTextNode(KdbxXml.NODE_KEY);
          final value = el.singleTextNode(KdbxXml.NODE_VALUE);
          final lastModified =
              el.singleElement(KdbxXml.NODE_LAST_MODIFICATION_TIME)?.innerText;
          return MapEntry(key, (
            value: value,
            lastModified: lastModified != null
                ? DateTimeUtils.fromBase64(lastModified)
                : null
          ));
        })),
        super.read(node);

  final Map<String, KdbxMetaCustomDataItem> _data;

  Iterable<MapEntry<String, KdbxMetaCustomDataItem>> get entries =>
      _data.entries;

  KdbxMetaCustomDataItem? operator [](String key) => _data[key];
  void operator []=(String key, KdbxMetaCustomDataItem value) {
    modify(() => _data[key] = value);
  }

  bool containsKey(String key) => _data.containsKey(key);
  KdbxMetaCustomDataItem? remove(String key) => modify(() => _data.remove(key));

  @override
  xml.XmlElement toXml() {
    final el = super.toXml();
    el.children.clear();
    el.children.addAll(
      _data.entries.map((e) {
        //TODO: We don't have any context here so have to output everything regardless
        // of intended kdbx version. Maybe we can improve that one day to allow
        // safer output of earlier kdbx versions?
        final d = e.value.lastModified != null
            ? DateTimeUtils.toBase64(e.value.lastModified!)
            : null;

        return XmlUtils.createNode(KdbxXml.NODE_CUSTOM_DATA_ITEM, [
          XmlUtils.createTextNode(KdbxXml.NODE_KEY, e.key),
          XmlUtils.createTextNode(KdbxXml.NODE_VALUE, e.value.value),
          if (d != null)
            XmlUtils.createTextNode(KdbxXml.NODE_LAST_MODIFICATION_TIME, d),
        ]);
      }),
    );
    return el;
  }

  void overwriteFrom(KdbxMetaCustomData other) {
    _data.clear();
    _data.addAll(other._data);
  }
}
