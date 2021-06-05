import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';

import 'package:archive/archive.dart';
import 'package:kdbx/src/kdbx_entry.dart';
import 'package:supercharged_dart/supercharged_dart.dart';
import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:convert/convert.dart' as convert;
import 'package:crypto/crypto.dart' as crypto;
import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/crypto/key_encrypter_kdf.dart';
import 'package:kdbx/src/crypto/protected_salt_generator.dart';
import 'package:kdbx/src/crypto/protected_value.dart';
import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_deleted_object.dart';
import 'package:kdbx/src/utils/byte_utils.dart';
import 'package:kdbx/src/internal/consts.dart';
import 'package:kdbx/src/internal/crypto_utils.dart';
import 'package:kdbx/src/kdbx_binary.dart';
import 'package:kdbx/src/kdbx_file.dart';
import 'package:kdbx/src/kdbx_group.dart';
import 'package:kdbx/src/kdbx_header.dart';
import 'package:kdbx/src/kdbx_meta.dart';
import 'package:kdbx/src/kdbx_object.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:pointycastle/export.dart';
import 'package:xml/xml.dart' as xml;
import 'package:xml/xml.dart';

final _logger = Logger('kdbx.format');

abstract class Credentials {
  factory Credentials(ProtectedValue password) =>
      Credentials.composite(password, null); //PasswordCredentials(password);
  factory Credentials.composite(ProtectedValue password, Uint8List? keyFile) =>
      KeyFileComposite(
        password: PasswordCredentials(password),
        keyFile: keyFile == null ? null : KeyFileCredentials(keyFile),
      );

  factory Credentials.fromHash(Uint8List hash) => HashCredentials(hash);

  void changePassword(ProtectedValue password);

  Uint8List getHash();
}

class KeyFileComposite implements Credentials {
  KeyFileComposite({required this.password, required this.keyFile});

  PasswordCredentials password;
  KeyFileCredentials? keyFile;

  @override
  Uint8List getHash() {
    final buffer = [...password.getBinary(), ...?keyFile?.getBinary()];
    return crypto.sha256.convert(buffer).bytes as Uint8List;

//    final output = convert.AccumulatorSink<crypto.Digest>();
//    final input = crypto.sha256.startChunkedConversion(output);
////    input.add(password.getHash());
//    input.add(buffer);
//    input.close();
//    return output.events.single.bytes as Uint8List;
  }

  @override
  void changePassword(ProtectedValue password) {
    this.password = PasswordCredentials(password);
  }
}

/// Context used during reading and writing.
class KdbxReadWriteContext {
  KdbxReadWriteContext({
    required this.header,
  })   : _binaries = [],
        _deletedObjects = [];

  static final kdbxContext = Expando<KdbxReadWriteContext>();

  static KdbxReadWriteContext kdbxContextForNode(xml.XmlNode node) {
    final ret = kdbxContext[node.document!];
    if (ret == null) {
      throw StateError('Unable to locate kdbx context for document.');
    }
    return ret;
  }

  static void setKdbxContextForNode(
      xml.XmlNode node, KdbxReadWriteContext ctx) {
    kdbxContext[node.document!] = ctx;
  }

  @protected
  final List<KdbxBinary> _binaries;
  final List<KdbxDeletedObject> _deletedObjects;

  Iterable<KdbxBinary> get binariesIterable => _binaries;

  final KdbxHeader header;

  int get versionMajor => header.version.major;

  void initContext(Iterable<KdbxBinary> binaries,
      Iterable<KdbxDeletedObject> deletedObjects) {
    _binaries.addAll(binaries);
    _deletedObjects.addAll(deletedObjects);
  }

  KdbxBinary? binaryById(int id) {
    if (id >= _binaries.length) {
      return null;
    }
    return _binaries[id];
  }

  void addBinary(KdbxBinary binary) {
    _binaries.add(binary);
  }

  KdbxBinary? findBinaryByValue(KdbxBinary binary) {
    // TODO create a hashset or map?
    return _binaries.firstWhereOrNull((element) => element.valueEqual(binary));
  }

  /// finds the ID of the given binary.
  /// if it can't be found, [KdbxCorruptedFileException] is thrown.
  int findBinaryId(KdbxBinary binary) {
    assert(!binary.isInline);
    final id = _binaries.indexOf(binary);
    if (id < 0) {
      throw KdbxCorruptedFileException('Unable to find binary.'
          ' (${binary.value.length},${binary.isInline})');
    }
    return id;
  }

  /// removes the given binary. Does not check if it is still referenced
  /// in any [KdbxEntry]!!
  void removeBinary(KdbxBinary binary) {
    if (!_binaries.remove(binary)) {
      throw KdbxCorruptedFileException(
          'Tried to remove binary which is not in this file.');
    }
  }

  void removeUnusedBinaries(Set<int> usedIndexes) {
    final reversedUnusedIndexes = _binaries
        .whereIndexed((index, element) => !usedIndexes.contains(index))
        .mapIndexed((index, element) => index)
        .toList()
        .reversed;
    // ignore: prefer_foreach
    for (var index in reversedUnusedIndexes) {
      _binaries.removeAt(index);
    }
  }
}

abstract class CredentialsPart {
  Uint8List getBinary();
}

class KeyFileCredentials implements CredentialsPart {
  factory KeyFileCredentials(Uint8List keyFileContents) {
    try {
      final keyFileAsString = utf8.decode(keyFileContents);
      if (_hexValuePattern.hasMatch(keyFileAsString)) {
        return KeyFileCredentials._(
            convert.hex.decode(keyFileAsString) as Uint8List);
      }
      final xmlContent = xml.XmlDocument.parse(keyFileAsString);
      final key = xmlContent.findAllElements('Key').single;
      final dataString = key.findElements('Data').single;
      final dataBytes = base64.decode(dataString.text);
      _logger.finer('Decoded base64 of keyfile.');
      return KeyFileCredentials._(dataBytes);
    } catch (e, stackTrace) {
      _logger.warning(
          'Unable to parse key file as hex or XML, use as is.', e, stackTrace);
      final bytes = crypto.sha256.convert(keyFileContents).bytes as Uint8List;
      return KeyFileCredentials._(bytes);
    }
  }

  KeyFileCredentials._(this._keyFileValue);

  static final RegExp _hexValuePattern =
      RegExp(r'^[a-f\d]{64}', caseSensitive: false);

  final Uint8List _keyFileValue;

  @override
  Uint8List getBinary() {
    return _keyFileValue;
//    return crypto.sha256.convert(_keyFileValue.binaryValue).bytes as Uint8List;
  }
}

class PasswordCredentials implements CredentialsPart {
  PasswordCredentials(this._password);

  final ProtectedValue _password;

  @override
  Uint8List getBinary() {
    return _password.hash;
  }
}

class HashCredentials implements Credentials {
  HashCredentials(this.hash);

  Uint8List hash;

  @override
  Uint8List getHash() => hash;

  @override
  void changePassword(ProtectedValue password) {
    final buffer = password.hash;
    hash = crypto.sha256.convert(buffer).bytes as Uint8List;
  }
}

class KdbxBody extends KdbxNode {
  KdbxBody.create(this.meta, this.rootGroup) : super.create('KeePassFile') {
    node.children.add(meta.node);
    final rootNode = xml.XmlElement(xml.XmlName('Root'));
    node.children.add(rootNode);
    rootNode.children.add(rootGroup.node);
  }

  KdbxBody.read(
    xml.XmlElement node,
    this.meta,
    this.rootGroup,
  ) : super.read(node);

//  final xml.XmlDocument xmlDocument;
  final KdbxMeta meta;
  final KdbxGroup rootGroup;

  @visibleForTesting
  List<KdbxDeletedObject> get deletedObjects => ctx._deletedObjects;

  Future<void> writeV3(WriterHelper writer, KdbxFile kdbxFile,
      ProtectedSaltGenerator saltGenerator) async {
    final xml = generateXml(saltGenerator);
    final xmlBytes = utf8.encode(xml.toXmlString());
    final compressedBytes = (kdbxFile.header.compression == Compression.gzip
        ? KdbxFormat._gzipEncode(xmlBytes as Uint8List)
        : xmlBytes) as Uint8List;

    final encrypted = await _encryptV3(kdbxFile, compressedBytes);
    writer.writeBytes(encrypted);
  }

  void writeV4(WriterHelper writer, KdbxFile kdbxFile,
      ProtectedSaltGenerator saltGenerator, _KeysV4 keys) {
    final bodyWriter = WriterHelper();
    final xml = generateXml(saltGenerator);
    kdbxFile.header.innerHeader.updateBinaries(kdbxFile.ctx.binariesIterable);
    kdbxFile.header.writeInnerHeader(bodyWriter);
    bodyWriter.writeBytes(utf8.encode(xml.toXmlString()) as Uint8List);
    final compressedBytes = (kdbxFile.header.compression == Compression.gzip
        ? KdbxFormat._gzipEncode(bodyWriter.output.toBytes())
        : bodyWriter.output.toBytes());
    final encrypted = _encryptV4(
      kdbxFile,
      compressedBytes,
      keys.cipherKey,
    );
    final transformed = kdbxFile.kdbxFormat
        .hmacBlockTransformerEncrypt(keys.hmacKey, encrypted);
    writer.writeBytes(transformed);
  }

  Future<Uint8List> _encryptV3(
      KdbxFile kdbxFile, Uint8List compressedBytes) async {
    final byteWriter = WriterHelper();
    byteWriter.writeBytes(
        kdbxFile.header.fields[HeaderFields.StreamStartBytes]!.bytes);
    HashedBlockReader.writeBlocks(ReaderHelper(compressedBytes), byteWriter);
    final bytes = byteWriter.output.toBytes();

    final masterKey = await KdbxFormat._generateMasterKeyV3(
        kdbxFile.header, kdbxFile.credentials);
    final encrypted = KdbxFormat._encryptDataAes(masterKey, bytes,
        kdbxFile.header.fields[HeaderFields.EncryptionIV]!.bytes);
    return encrypted;
  }

  Uint8List _encryptV4(
      KdbxFile kdbxFile, Uint8List compressedBytes, Uint8List cipherKey) {
    final header = kdbxFile.header;
    final cipher = header.cipher;
    if (cipher == Cipher.aes) {
      _logger.fine('We need AES');
      final result = kdbxFile.kdbxFormat
          ._encryptContentV4(header, cipherKey, compressedBytes);
//      _logger.fine('Result: ${ByteUtils.toHexList(result)}');
      return result;
    } else if (cipher == Cipher.chaCha20) {
      _logger.fine('We need chacha20');
      return kdbxFile.kdbxFormat
          .transformContentV4ChaCha20(header, compressedBytes, cipherKey);
    } else {
      throw UnsupportedError('Unsupported cipherId $cipher');
    }
  }

  KdbxReadWriteContext get ctx => rootGroup.ctx;

  Map<KdbxUuid, KdbxObject> _createObjectIndex() => Map.fromEntries({
        ...rootGroup.getAllGroups(),
        ...rootGroup.getAllEntries()
      }.map((k, e) => MapEntry(e.uuid, e)).entries);

  MergeContext merge(KdbxBody other) {
    // sync deleted objects.
    final deleted =
        Map.fromEntries(ctx._deletedObjects.map((e) => MapEntry(e.uuid, e)));
    final incomingDeleted = <KdbxUuid, KdbxDeletedObject>{};

    for (final obj in other.ctx._deletedObjects) {
      if (!deleted.containsKey(obj.uuid)) {
        final del = KdbxDeletedObject.create(ctx, obj.uuid);
        ctx._deletedObjects.add(del);
        incomingDeleted[del.uuid] = del;
        deleted[del.uuid] = del;
      }
    }

    final mergeContext = MergeContext(
      objectIndex: _createObjectIndex(),
      deletedObjects: deleted,
    );

    // sync binaries
    for (final binary in other.ctx.binariesIterable) {
      if (ctx.findBinaryByValue(binary) == null) {
        ctx.addBinary(binary);
        mergeContext.trackChange(this,
            debug: 'adding new binary ${binary.value.length}');
      }
    }
    meta.merge(other.meta, mergeContext);
    rootGroup.merge(mergeContext, other.rootGroup);

    // remove deleted objects
    for (final incomingDelete in incomingDeleted.values) {
      final object = mergeContext.objectIndex[incomingDelete.uuid];
      mergeContext.trackChange(object, debug: 'was deleted.');
    }

    cleanup();

    _logger.info('Finished merging:\n${mergeContext.debugChanges()}');
    final incomingObjects = other._createObjectIndex();
    _logger.info('Merged: ${mergeContext.merged} vs. '
        '(local objects: ${mergeContext.objectIndex.length}, '
        'incoming objects: ${incomingObjects.length})');

    // sanity checks
    if (mergeContext.merged.keys.length != mergeContext.objectIndex.length) {
      //throw Exception('WTF merge failure');
      // TODO figure out what went wrong.
    }
    return mergeContext;
  }

  void cleanup() {
    final now = DateTime.now().toUtc();
    final historyMaxItems = (meta.historyMaxItems.get() ?? 0) > 0
        ? meta.historyMaxItems.get()
        : double.maxFinite as int;
    final usedCustomIcons = HashSet<KdbxUuid>();
    final usedBinaries = <int>{};

    void _trackEntryForCleanup(KdbxEntry e) {
      e.binaryEntries.toList().forEach((b) {
        final id = ctx.findBinaryId(b.value);
        usedBinaries.add(id);
      });
      if (e.customIcon != null) {
        usedCustomIcons.add(e.customIcon!.uuid);
      }
    }

    rootGroup.getAllEntries().values.forEach((e) {
      if (e.history.length > historyMaxItems!) {
        e.history.removeRange(0, e.history.length - historyMaxItems);
      }
      _trackEntryForCleanup(e);
      e.history.toList().forEach((he) {
        _trackEntryForCleanup(he);
      });
    });
    rootGroup.getAllGroups().values.forEach((g) {
      if (g.customIcon != null) {
        usedCustomIcons.add(g.customIcon!.uuid);
      }
    });

    meta.customIcons.forEach((key, value) {
      if (!usedCustomIcons.contains(key)) {
        ctx._deletedObjects
            .add(KdbxDeletedObject.create(ctx, key, deletionTime: now));
        meta.customIcons.remove(key);
      }
    });

    ctx.removeUnusedBinaries(usedBinaries);
  }

  xml.XmlDocument generateXml(ProtectedSaltGenerator saltGenerator) {
    final rootGroupNode = rootGroup.toXml();
    // update protected values...
    for (final el in rootGroupNode.findAllElements(KdbxXml.NODE_VALUE).where(
        (el) =>
            el.getAttribute(KdbxXml.ATTR_PROTECTED)?.toLowerCase() == 'true')) {
      final pv = KdbxFile.protectedValues[el];
      if (pv != null) {
        final newValue = saltGenerator.encryptToBase64(pv.getText());
        el.children.clear();
        el.children.add(xml.XmlText(newValue));
      } else {
//        assert((() {
//          _logger.severe('Unable to find protected value for $el ${el.parent.parent} (children: ${el.children})');
//          return false;
//        })());
        // this is always an error, not just during debug.
        throw StateError('Unable to find protected value for $el ${el.parent}');
      }
    }

    final builder = xml.XmlBuilder();
    builder.processing(
        'xml', 'version="1.0" encoding="utf-8" standalone="yes"');
    builder.element(
      'KeePassFile',
      nest: [
        meta.toXml(),
        () => builder.element('Root', nest: [
              rootGroupNode,
              XmlUtils.createNode(
                KdbxXml.NODE_DELETED_OBJECTS,
                ctx._deletedObjects.map((e) => e.toXml()).toList(),
              ),
            ]),
      ],
    );
//    final doc = xml.XmlDocument();
//    doc.children.add(xml.XmlProcessing(
//        'xml', 'version="1.0" encoding="utf-8" standalone="yes"'));
    final node = builder.buildDocument();

    return node;
  }
}

abstract class OverwriteContext {
  const OverwriteContext();
  static const noop = OverwriteContextNoop();
  void trackChange(KdbxObject object, {String? node, String? debug});
}

class OverwriteContextNoop implements OverwriteContext {
  const OverwriteContextNoop();
  @override
  void trackChange(KdbxObject object, {String? node, String? debug}) {}
}

class MergeChange {
  MergeChange({this.object, this.node, this.debug});

  final KdbxNode? object;

  /// the name of the subnode of [object].
  final String? node;
  final String? debug;

  String debugString() {
    return [node, debug].where((e) => e != null).join(' ');
  }
}

class MergeContext implements OverwriteContext {
  MergeContext({required this.objectIndex, required this.deletedObjects});
  final Map<KdbxUuid, KdbxObject> objectIndex;
  final Map<KdbxUuid, KdbxDeletedObject> deletedObjects;
  final Map<KdbxUuid, KdbxObject> merged = {};
  final List<MergeChange> changes = [];

  void markAsMerged(KdbxObject object) {
    if (merged.containsKey(object.uuid)) {
      throw StateError(
          'object was already market as merged! ${object.uuid}: $object');
    }
    merged[object.uuid] = object;
  }

  @override
  void trackChange(KdbxNode? object, {String? node, String? debug}) {
    changes.add(MergeChange(
      object: object,
      node: node,
      debug: debug,
    ));
  }

  String debugChanges() {
    final group = changes.groupBy<KdbxNode, MergeChange>(
        ((MergeChange element) => element.object!));
    return group.entries
        .map((e) => [
              e.key.toString(),
              ...e.value.map((e) => e.debugString()),
            ].join('\n    '))
        .join('\n');
  }
}

class _KeysV4 {
  _KeysV4(this.hmacKey, this.cipherKey);

  final Uint8List hmacKey;
  final Uint8List cipherKey;
}

class KdbxFormat {
  KdbxFormat([this.argon2]) : assert(kdbxKeyCommonAssertConsistency());

  final Argon2? argon2;
  static bool dartWebWorkaround = false;

  /// Creates a new, empty [KdbxFile] with default settings.
  /// If [header] is not given by default a kdbx 4.0 file will be created.
  KdbxFile create(
    Credentials credentials,
    String name, {
    String? generator,
    KdbxHeader? header,
  }) {
    header ??= argon2 == null ? KdbxHeader.createV3() : KdbxHeader.createV4();
    final ctx = KdbxReadWriteContext(header: header);
    final meta = KdbxMeta.create(
      databaseName: name,
      ctx: ctx,
      generator: generator,
    );
    final rootGroup = KdbxGroup.create(ctx: ctx, parent: null, name: name);
    final body = KdbxBody.create(meta, rootGroup);
    return KdbxFile(
      ctx,
      this,
      credentials,
      header,
      body,
    );
  }

  Future<KdbxFile> read(Uint8List input, Credentials credentials) async {
    final reader = ReaderHelper(input);
    final header = KdbxHeader.read(reader);
    if (header.version.major == KdbxVersion.V3.major) {
      return await _loadV3(header, reader, credentials);
    } else if (header.version.major == KdbxVersion.V4.major) {
      return await _loadV4(header, reader, credentials);
    } else {
      _logger.finer('Unsupported version for $header');
      throw KdbxUnsupportedException('Unsupported kdbx version '
          '${header.version}.'
          ' Only 3.x and 4.x is supported.');
    }
  }

//TODO: perf:
/*
1. we do the XML parsing twice. This takes a long time. I think this is now resolved.

2. The XML parsing happens in one big chunk - this occupies the microtask loop for hundreds or thousands of ms and thus causes immense UI jank. 

https://github.com/renggli/dart-xml says that import 'package:xml/xml_events.dart'; can be  used to get a stream API for handling large XML files. There is no documentation on how to use this to avoid long-running microtasks but perhaps the examples in the readme and these files might give some clues.

parseEvents(bookshelfXml)
    .whereType<XmlTextEvent>()
    .map((event) => event.text.trim())
    .where((text) => text.isNotEmpty)
    .forEach(print);
 
https://github.com/renggli/dart-xml/blob/50f4ee4aec6eac8225b5d3e710f98a9f1c16560e/example/ip_api.dart
https://github.com/renggli/dart-xml/blob/main/example/xml_flatten.dart
*/
  Future<List<KdbxFile>> readTwice(
      Uint8List input, Credentials credentials) async {
    final reader = ReaderHelper(input);
    final header1 = KdbxHeader.read(reader);
    reader.pos = 0;
    final header2 = KdbxHeader.read(reader);
    if (header1.version.major == KdbxVersion.V4.major) {
      final decrypted =
          await _loadV4PreDecryption(header1, reader, credentials);
      final contentReader1 = ReaderHelper(decrypted);
      final contentReader2 = ReaderHelper(decrypted);
      await _loadV4PostDecryptionInnerHeader(
          header1, decrypted, contentReader1);
      final firstDocument = await _loadV4PostDecryptionDocument(
          header1, decrypted, contentReader1);
      final first = await _loadV4PostDecryptionKdbxFile(
          header1, credentials, firstDocument);
      await _loadV4PostDecryptionInnerHeader(
          header2, decrypted, contentReader2);
      final second = await _loadV4PostDecryptionKdbxFile(
          header2, credentials, firstDocument.copy());
      return [first, second];
    } else {
      _logger.finer('Unsupported version for $header1');
      throw KdbxUnsupportedException('Unsupported kdbx version '
          '${header1.version}.'
          ' Only 4.x is supported.');
    }
  }

  /// Saves the given file.
  Future<Uint8List> save(KdbxFile file) async {
    _logger.finer('Saving ${file.body.rootGroup.uuid} '
        '(locked: ${file.saveLock.locked})');
    return file.saveLock.synchronized(() => _saveSynchronized(file));
  }

  Future<Uint8List> _saveSynchronized(KdbxFile file) async {
    final body = file.body;
    final header = file.header;

    final output = BytesBuilder();
    final writer = WriterHelper(output);

    // Regular maintenance such as removing old history entries and unused binaries/icons
    body.cleanup();

    header.generateSalts();
    header.write(writer);
    final headerHash =
        (crypto.sha256.convert(writer.output.toBytes()).bytes as Uint8List);

    if (file.header.version < KdbxVersion.V3) {
      throw UnsupportedError('Unsupported version ${header.version}');
    } else if (file.header.version < KdbxVersion.V4) {
      final streamKey =
          file.header.fields[HeaderFields.ProtectedStreamKey]!.bytes;
      final gen = ProtectedSaltGenerator(streamKey);

      body.meta.headerHash.set(headerHash.buffer);
      await body.writeV3(writer, file, gen);
    } else if (header.version.major == KdbxVersion.V4.major) {
      final headerBytes = writer.output.toBytes();
      writer.writeBytes(headerHash);
      final gen = _createProtectedSaltGenerator(header);
      final keys = await _computeKeysV4(header, file.credentials);
      final headerHmac = _getHeaderHmac(headerBytes, keys.hmacKey);
      writer.writeBytes(headerHmac.bytes as Uint8List);
      body.writeV4(writer, file, gen, keys);
    } else {
      throw UnsupportedError('Unsupported version ${header.version}');
    }
    file.onSaved();
    return output.toBytes();
  }

  Future<KdbxFile> _loadV3(
      KdbxHeader header, ReaderHelper reader, Credentials credentials) async {
//    _getMasterKeyV3(header, credentials);
    final masterKey = await _generateMasterKeyV3(header, credentials);
    final encryptedPayload = reader.readRemaining();
    final content = _decryptContent(header, masterKey, encryptedPayload);
    final blocks = HashedBlockReader.readBlocks(ReaderHelper(content));

    _logger.finer('compression: ${header.compression}');
    final ctx = KdbxReadWriteContext(header: header);
    if (header.compression == Compression.gzip) {
      final xml = KdbxFormat._gzipDecode(blocks);
      final string = utf8.decode(xml);
      return KdbxFile(
          ctx, this, credentials, header, _loadXml(ctx, header, string));
    } else {
      return KdbxFile(ctx, this, credentials, header,
          _loadXml(ctx, header, utf8.decode(blocks)));
    }
  }

  Future<Uint8List> _loadV4PreDecryption(
      KdbxHeader header, ReaderHelper reader, Credentials credentials) async {
    final headerBytes = reader.byteData.sublist(0, header.endPos);
    final hash = crypto.sha256.convert(headerBytes).bytes;
    final actualHash = reader.readBytes(hash.length);
    if (!ByteUtils.eq(hash, actualHash)) {
      _logger.fine('Does not match ${ByteUtils.toHexList(hash)} '
          'vs ${ByteUtils.toHexList(actualHash)}');
      throw KdbxCorruptedFileException('Header hash does not match.');
    }
//    _logger
//        .finest('KdfParameters: ${header.readKdfParameters.toDebugString()}');
    _logger.finest('Header hash matches.');
    final keys = await _computeKeysV4(header, credentials);
    final headerHmac =
        _getHeaderHmac(reader.byteData.sublist(0, header.endPos), keys.hmacKey);
    final expectedHmac = reader.readBytes(headerHmac.bytes.length);
//    _logger.fine('Expected: ${ByteUtils.toHexList(expectedHmac)}');
//    _logger.fine('Actual  : ${ByteUtils.toHexList(headerHmac.bytes)}');
    if (!ByteUtils.eq(headerHmac.bytes, expectedHmac)) {
      throw KdbxInvalidKeyException();
    }
//    final hmacTransformer = crypto.Hmac(crypto.sha256, hmacKey.bytes);
//    final blockreader.readBytes(32);
    final bodyContent = hmacBlockTransformer(keys.hmacKey, reader);
    final decrypted = decrypt(header, bodyContent, keys.cipherKey);
    _logger.finer('compression: ${header.compression}');
    if (header.compression == Compression.gzip) {
      final content = KdbxFormat._gzipDecode(decrypted);
      return content;
    }
    throw StateError('Kdbx4 without compression is not yet supported.');
  }

  Future<void> _loadV4PostDecryptionInnerHeader(
      KdbxHeader header, Uint8List content, ReaderHelper reader) async {
    final innerHeader =
        KdbxHeader.readInnerHeaderFields(reader, header.version);
    header.innerHeader.updateFrom(innerHeader);
    return;
  }

  Future<XmlDocument> _loadV4PostDecryptionDocument(
      KdbxHeader header, Uint8List content, ReaderHelper reader) async {
    final xml = utf8.decode(reader.readRemaining());
    return XmlDocument.parse(xml);
  }

  // Future<KdbxFile> _loadV4PostDecryptionTwice(
  //     KdbxHeader header, Credentials credentials, Uint8List content) async {
  //   final contentReader = ReaderHelper(content);
  //   final innerHeader =
  //       KdbxHeader.readInnerHeaderFields(contentReader, header.version);
  //   header.innerHeader.updateFrom(innerHeader);
  //   final xml = utf8.decode(contentReader.readRemaining());
  //   final document = XmlDocument.parse(xml);
  //   final context = KdbxReadWriteContext(binaries: [], header: header);
  //   final body = _processParsedXml(context, header, document);
  //   return KdbxFile(context, this, credentials, header, body);
  // }

  Future<KdbxFile> _loadV4PostDecryptionKdbxFile(
      KdbxHeader header, Credentials credentials, XmlDocument document) async {
    final context = KdbxReadWriteContext(header: header);
    final body = _processParsedXml(context, header, document);
    return KdbxFile(context, this, credentials, header, body);
  }

  Future<KdbxFile> _loadV4(
      KdbxHeader header, ReaderHelper reader, Credentials credentials) async {
    final headerBytes = reader.byteData.sublist(0, header.endPos);
    final hash = crypto.sha256.convert(headerBytes).bytes;
    final actualHash = reader.readBytes(hash.length);
    if (!ByteUtils.eq(hash, actualHash)) {
      _logger.fine('Does not match ${ByteUtils.toHexList(hash)} '
          'vs ${ByteUtils.toHexList(actualHash)}');
      throw KdbxCorruptedFileException('Header hash does not match.');
    }
//    _logger
//        .finest('KdfParameters: ${header.readKdfParameters.toDebugString()}');
    _logger.finest('Header hash matches.');
    final keys = await _computeKeysV4(header, credentials);
    final headerHmac =
        _getHeaderHmac(reader.byteData.sublist(0, header.endPos), keys.hmacKey);
    final expectedHmac = reader.readBytes(headerHmac.bytes.length);
//    _logger.fine('Expected: ${ByteUtils.toHexList(expectedHmac)}');
//    _logger.fine('Actual  : ${ByteUtils.toHexList(headerHmac.bytes)}');
    if (!ByteUtils.eq(headerHmac.bytes, expectedHmac)) {
      throw KdbxInvalidKeyException();
    }
//    final hmacTransformer = crypto.Hmac(crypto.sha256, hmacKey.bytes);
//    final blockreader.readBytes(32);
    final bodyContent = hmacBlockTransformer(keys.hmacKey, reader);
    final decrypted = decrypt(header, bodyContent, keys.cipherKey);
    _logger.finer('compression: ${header.compression}');
    if (header.compression == Compression.gzip) {
      final content = KdbxFormat._gzipDecode(decrypted);
      final contentReader = ReaderHelper(content);
      final innerHeader =
          KdbxHeader.readInnerHeaderFields(contentReader, header.version);

//      _logger.fine('inner header fields: $headerFields');
//      header.innerFields.addAll(headerFields);
      header.innerHeader.updateFrom(innerHeader);
      final xml = utf8.decode(contentReader.readRemaining());
      final context = KdbxReadWriteContext(header: header);
      return KdbxFile(
          context, this, credentials, header, _loadXml(context, header, xml));
    }
    throw StateError('Kdbx4 without compression is not yet supported.');
  }

  Uint8List hmacBlockTransformerEncrypt(Uint8List hmacKey, Uint8List data) {
    final writer = WriterHelper();
    final reader = ReaderHelper(data);
    const blockSize = 1024 * 1024;
    var blockIndex = 0;
    while (true) {
      final blockData = reader.readBytesUpTo(blockSize);
      final calculatedHash = _hmacHashForBlock(hmacKey, blockIndex, blockData);
      writer.writeBytes(calculatedHash);
      writer.writeUint32(blockData.length);
      if (blockData.isEmpty) {
//        writer.writeUint32(0);
        return writer.output.toBytes();
      }
      writer.writeBytes(blockData);
      blockIndex++;
    }
  }

  Uint8List _hmacKeyForBlockIndex(Uint8List hmacKey, int blockIndex) {
    final blockKeySrc = WriterHelper()
      ..writeUint64(blockIndex)
      ..writeBytes(hmacKey);
    return crypto.sha512.convert(blockKeySrc.output.toBytes()).bytes
        as Uint8List;
  }

  Uint8List _hmacHashForBlock(
      Uint8List hmacKey, int blockIndex, Uint8List blockData) {
    final blockKey = _hmacKeyForBlockIndex(hmacKey, blockIndex);
    final tmp = WriterHelper();
    tmp.writeUint64(blockIndex);
    tmp.writeInt32(blockData.length);
    tmp.writeBytes(blockData);
//      _logger.fine('blockHash: ${ByteUtils.toHexList(tmp.output.toBytes())}');
//      _logger.fine('blockKey: ${ByteUtils.toHexList(blockKey.bytes)}');
    final hmac = crypto.Hmac(crypto.sha256, blockKey);
    final calculatedHash = hmac.convert(tmp.output.toBytes());
    return calculatedHash.bytes as Uint8List;
  }

  Uint8List hmacBlockTransformer(Uint8List hmacKey, ReaderHelper reader) {
    final ret = <int>[];
    var blockIndex = 0;
    while (true) {
      final blockHash = reader.readBytes(32);
      final blockLength = reader.readUint32();
      final blockBytes = reader.readBytes(blockLength);
      final calculatedHash = _hmacHashForBlock(hmacKey, blockIndex, blockBytes);
//      _logger
//          .fine('CalculatedHash: ${ByteUtils.toHexList(calculatedHash.bytes)}');
      if (!ByteUtils.eq(blockHash, calculatedHash)) {
        throw KdbxCorruptedFileException('Invalid hash block.');
      }

      if (blockLength < 1) {
        return Uint8List.fromList(ret);
      }
      blockIndex++;
      ret.addAll(blockBytes);
    }
  }

  Uint8List decrypt(
      KdbxHeader header, Uint8List encrypted, Uint8List cipherKey) {
    final cipher = header.cipher;
    if (cipher == Cipher.aes) {
      _logger.fine('We need AES');
      final result = _decryptContentV4(header, cipherKey, encrypted);
      return result;
    } else if (cipher == Cipher.chaCha20) {
      _logger.fine('We need chacha20');
//      throw UnsupportedError('chacha20 not yet supported $cipherId');
      return transformContentV4ChaCha20(header, encrypted, cipherKey);
    } else {
      throw UnsupportedError('Unsupported cipherId $cipher');
    }
  }

  Uint8List transformContentV4ChaCha20(
      KdbxHeader header, Uint8List encrypted, Uint8List cipherKey) {
    final encryptionIv = header.fields[HeaderFields.EncryptionIV]!.bytes;
    final engine = ChaCha7539Engine()
      ..init(false, ParametersWithIV(KeyParameter(cipherKey), encryptionIv));
    return engine.process(encrypted);
  }

//  Uint8List _transformDataV4Aes() {
//  }

  crypto.Digest _getHeaderHmac(Uint8List headerBytes, Uint8List key) {
    final writer = WriterHelper()
      ..writeUint32(0xffffffff)
      ..writeUint32(0xffffffff)
      ..writeBytes(key);
    final hmacKey = crypto.sha512.convert(writer.output.toBytes()).bytes;
    final src = headerBytes;
    final hmacKeyStuff = crypto.Hmac(crypto.sha256, hmacKey);
    return hmacKeyStuff.convert(src);
  }

  Future<_KeysV4> _computeKeysV4(
      KdbxHeader header, Credentials credentials) async {
    final masterSeed = header.fields[HeaderFields.MasterSeed]!.bytes;
    final kdfParameters = header.readKdfParameters;
    if (masterSeed.length != 32) {
      throw const FormatException('Master seed must be 32 bytes.');
    }

    final credentialHash = credentials.getHash();
    final key =
        await KeyEncrypterKdf(argon2).encrypt(credentialHash, kdfParameters);

//    final keyWithSeed = Uint8List(65);
//    keyWithSeed.replaceRange(0, masterSeed.length, masterSeed);
//    keyWithSeed.replaceRange(
//        masterSeed.length, masterSeed.length + key.length, key);
//    keyWithSeed[64] = 1;
    final keyWithSeed = masterSeed + key + Uint8List.fromList([1]);
    assert(keyWithSeed.length == 65);
    final cipher = crypto.sha256.convert(keyWithSeed.sublist(0, 64));
    final hmacKey = crypto.sha512.convert(keyWithSeed);

    return _KeysV4(hmacKey.bytes as Uint8List, cipher.bytes as Uint8List);
  }

  ProtectedSaltGenerator _createProtectedSaltGenerator(KdbxHeader header) {
    final protectedValueEncryption = header.innerRandomStreamEncryption;
    final streamKey = header.protectedStreamKey;
    if (protectedValueEncryption == ProtectedValueEncryption.salsa20) {
      return ProtectedSaltGenerator(streamKey);
    } else if (protectedValueEncryption == ProtectedValueEncryption.chaCha20) {
      return ProtectedSaltGenerator.chacha20(streamKey);
    } else {
      throw KdbxUnsupportedException(
          'Inner encryption: $protectedValueEncryption');
    }
  }

  KdbxBody _loadXml(
      KdbxReadWriteContext ctx, KdbxHeader header, String xmlString) {
    final document = XmlDocument.parse(xmlString);
    return _processParsedXml(ctx, header, document);
  }

  KdbxBody _processParsedXml(
      KdbxReadWriteContext ctx, KdbxHeader header, XmlDocument document) {
    final gen = _createProtectedSaltGenerator(header);

    KdbxReadWriteContext.setKdbxContextForNode(document, ctx);

//TODO: perf: 300ms. Solutions: Enable lazy decryption; Stop Protecting JSONRPC contents; Look for Protected attribute in KdbxGroup.read() process instead of through this independent "moveNext" for loop across the entire XML structure.
//NB: Figures for my phone in profiling mode while running the entire process twice.
    for (final el in document
        .findAllElements(KdbxXml.NODE_VALUE)
        .where((el) => el.getAttributeBool(KdbxXml.ATTR_PROTECTED))) {
      try {
        final pw = gen.decryptBase64(el.text.trim());
        if (pw == null) {
          continue;
        }
        KdbxFile.protectedValues[el] = ProtectedValue.fromString(pw);
      } catch (e, stackTrace) {
        final stringKey =
            el.parentElement!.singleElement(KdbxXml.NODE_KEY)?.text;
        final uuid = el.parentElement?.parentElement
            ?.singleElement(KdbxXml.NODE_UUID)
            ?.text;
        _logger.severe(
            'Error while decoding protected value in '
            '{${el.breadcrumbsNames()}} of key'
            ' {$stringKey} of entry {$uuid}.',
            e,
            stackTrace);

        rethrow;
      }
    }

    final keePassFile = document.findElements('KeePassFile').single;
    final meta = keePassFile.findElements('Meta').single;
    final root = keePassFile.findElements('Root').single;

    final kdbxMeta = KdbxMeta.read(meta, ctx);
    // kdbx < 4 has binaries in the meta section, >= 4 in the binary header.
    final binaries = kdbxMeta.binaries?.isNotEmpty == true
        ? kdbxMeta.binaries!
        : header.innerHeader.binaries
            .map((e) => KdbxBinary.readBinaryInnerHeader(e));

    final deletedObjects = root
            .findElements(KdbxXml.NODE_DELETED_OBJECTS)
            .singleOrNull
            ?.let((el) => el
                .findElements(KdbxDeletedObject.NODE_NAME)
                .map((node) => KdbxDeletedObject.read(node, ctx))) ??
        [];
    ctx.initContext(binaries, deletedObjects);

    final rootGroup =
        KdbxGroup.read(ctx, null, root.findElements(KdbxXml.NODE_GROUP).single);
    _logger.fine('successfully read Meta.');
    return KdbxBody.read(keePassFile, kdbxMeta, rootGroup);
  }

  Uint8List _decryptContent(
      KdbxHeader header, Uint8List masterKey, Uint8List encryptedPayload) {
    final encryptionIv = header.fields[HeaderFields.EncryptionIV]!.bytes;
    final decryptCipher = CBCBlockCipher(AESFastEngine());
    decryptCipher.init(
        false, ParametersWithIV(KeyParameter(masterKey), encryptionIv));
    final paddedDecrypted =
        AesHelper.processBlocks(decryptCipher, encryptedPayload);

    final streamStart = header.fields[HeaderFields.StreamStartBytes]!.bytes;

    if (paddedDecrypted.lengthInBytes < streamStart.lengthInBytes) {
      _logger.warning(
          'decrypted content was shorter than expected stream start block.');
      throw KdbxInvalidKeyException();
    }

    if (!ByteUtils.eq(
        streamStart, paddedDecrypted.sublist(0, streamStart.lengthInBytes))) {
      throw KdbxInvalidKeyException();
    }

    final decrypted = AesHelper.unpad(paddedDecrypted);

    // ignore: unnecessary_cast
    final content = decrypted.sublist(streamStart.lengthInBytes) as Uint8List;
    return content;
  }

  Uint8List _decryptContentV4(
      KdbxHeader header, Uint8List cipherKey, Uint8List encryptedPayload) {
    final encryptionIv = header.fields[HeaderFields.EncryptionIV]!.bytes;

    final decryptCipher = CBCBlockCipher(AESFastEngine());
    decryptCipher.init(
        false, ParametersWithIV(KeyParameter(cipherKey), encryptionIv));
    final paddedDecrypted =
        AesHelper.processBlocks(decryptCipher, encryptedPayload);

    final decrypted = AesHelper.unpad(paddedDecrypted);
    return decrypted;
  }

  Uint8List _encryptContentV4(
      KdbxHeader header, Uint8List cipherKey, Uint8List bytes) {
    final encryptionIv = header.fields[HeaderFields.EncryptionIV]!.bytes;
    return KdbxFormat._encryptDataAes(cipherKey, bytes, encryptionIv);
  }

  static Future<Uint8List> _generateMasterKeyV3(
      KdbxHeader header, Credentials credentials) async {
    final rounds = header.v3KdfTransformRounds;
    final seed = header.fields[HeaderFields.TransformSeed]!.bytes;
    final masterSeed = header.fields[HeaderFields.MasterSeed]!.bytes;
    _logger.finer(
        'Rounds: $rounds (${ByteUtils.toHexList(header.fields[HeaderFields.TransformRounds]!.bytes)})');
    final transformedKey = await KeyEncrypterKdf.encryptAesAsync(
        EncryptAesArgs(seed, credentials.getHash(), rounds));

    final masterKey = crypto.sha256
        .convert(Uint8List.fromList(masterSeed + transformedKey))
        .bytes as Uint8List;
    return masterKey;
  }

  static Uint8List _encryptDataAes(
      Uint8List masterKey, Uint8List payload, Uint8List encryptionIv) {
    final encryptCipher = CBCBlockCipher(AESFastEngine());
    encryptCipher.init(
        true, ParametersWithIV(KeyParameter(masterKey), encryptionIv));
    return AesHelper.processBlocks(
        encryptCipher, AesHelper.pad(payload, encryptCipher.blockSize));
  }

  static Uint8List _gzipEncode(Uint8List bytes) {
    if (dartWebWorkaround) {
      return (GZipEncoder().encode(bytes) ?? []) as Uint8List;
    }
    return GZipCodec().encode(bytes) as Uint8List;
  }

  static Uint8List _gzipDecode(Uint8List bytes) {
    if (dartWebWorkaround) {
      return GZipDecoder().decodeBytes(bytes) as Uint8List;
    }
    return GZipCodec().decode(bytes) as Uint8List;
  }
}
