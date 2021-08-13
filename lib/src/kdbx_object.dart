import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_file.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_group.dart';
import 'package:kdbx/src/kdbx_meta.dart';
import 'package:kdbx/src/kdbx_times.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:quiver/iterables.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/uuid_util.dart';
import 'package:xml/xml.dart';

// ignore: unused_element
final _logger = Logger('kdbx.kdbx_object');

class ChangeEvent<T> {
  ChangeEvent({required this.object, required this.isDirty});

  final T object;
  final bool isDirty;

  @override
  String toString() {
    return 'ChangeEvent{object: $object, isDirty: $isDirty}';
  }
}

mixin Changeable<T> {
  final _controller = StreamController<ChangeEvent<T>>.broadcast();

  Stream<ChangeEvent<T>> get changes => _controller.stream;

  bool _isDirty = false;

  /// allow recursive calls to [modify]
  bool _isInModify = false;

  /// Called before the *first* modification (ie. before `isDirty` changes
  /// from false to true)
  @protected
  @mustCallSuper
  void onBeforeModify() {}

  /// Called after the *first* modification (ie. after `isDirty` changed
  /// from false to true)
  @protected
  @mustCallSuper
  void onAfterModify({bool preserveModificationTime = false}) {}

  RET modify<RET>(RET Function() modify,
      {bool preserveModificationTime = false}) {
    if (_isDirty || _isInModify) {
      return modify();
    }
    _isInModify = true;
    onBeforeModify();
    try {
      return modify();
    } finally {
      _isDirty = true;
      _isInModify = false;
      onAfterModify(preserveModificationTime: preserveModificationTime);
      _controller.add(ChangeEvent(object: this as T, isDirty: _isDirty));
    }
  }

  void clean() {
    if (!_isDirty) {
      return;
    }
    _isDirty = false;
    _controller.add(ChangeEvent(object: this as T, isDirty: _isDirty));
  }

  bool get isDirty => _isDirty;
}

abstract class KdbxNodeContext implements KdbxNode {
  KdbxReadWriteContext get ctx;
}

abstract class KdbxNode with Changeable<KdbxNode> {
  KdbxNode.create(String nodeName) : node = XmlElement(XmlName(nodeName)) {
    _isDirty = true;
  }

  KdbxNode.read(this.node);

  /// XML Node used while reading this KdbxNode.
  /// Must NOT be modified. Only copies which are obtained through [toXml].
  /// this node should always represent the original loaded state.
  final XmlElement node;

//  @protected
//  String text(String nodeName) => _opt(nodeName)?.text;

  /// must only be called to save this object.
  /// will mark this object as not dirty.
  @mustCallSuper
  XmlElement toXml() {
    clean();
    return node.copy();
  }
}

extension IterableKdbxObject<K extends String, V extends KdbxObject>
    on LinkedHashMap<K, V> {
  V? findByUuid(KdbxUuid uuid) {
    return this[uuid.uuid as K];
  }

  void add(KdbxObject obj) {
    // ignore: unnecessary_cast
    (this as LinkedHashMap<String, KdbxObject>)[obj.uuid.uuid] = obj;
  }
}

extension UnmodifiableMapViewKdbxObject<K extends String, V extends KdbxObject>
    on UnmodifiableMapView<K, V> {
  V get first {
    return values.first;
  }
}

extension KdbxObjectInternal on KdbxObject {
  List<KdbxSubNode> get objectNodes => [
        icon,
        customIconUuid,
      ];

  /// should only be used in internal code, used to clone
  /// from one kdbx file into another. (like merging).
  void forceSetUuid(KdbxUuid uuid) {
    _uuid.set(uuid, force: true);
  }

  void assertSameUuid(KdbxObject other, String debugAction) {
    if (uuid != other.uuid) {
      throw StateError(
          'Uuid of other object does not match current object for $debugAction');
    }
  }

  void overwriteSubNodesFrom(OverwriteContext overwriteContext,
      List<KdbxSubNode> myNodes, List<KdbxSubNode> otherNodes) {
    for (final node in zip([myNodes, otherNodes])) {
      final me = node[0];
      final other = node[1];
      if (me.set(other.get())) {
        overwriteContext.trackChange(this, node: me.name);
      }
    }
  }
}

abstract class KdbxObject extends KdbxNode {
  KdbxObject.create(
    this.ctx,
    this.file,
    String nodeName,
    KdbxGroup? parent,
  )   : times = KdbxTimes.create(ctx),
        _parent = parent,
        super.create(nodeName) {
    _uuid.set(KdbxUuid.random());
  }

  KdbxObject.read(this.ctx, KdbxGroup? parent, XmlElement node)
      : times = KdbxTimes.read(node.findElements('Times').single, ctx),
        _parent = parent,
        super.read(node);

  /// the file this object is part of. will be set AFTER loading, etc.
  /// TODO: We should probably get rid of this `file` reference.
  KdbxFile? file;

  final KdbxReadWriteContext ctx;

  final KdbxTimes times;

  KdbxUuid get uuid => _uuid.get()!;

  UuidNode get _uuid => UuidNode(this, KdbxXml.NODE_UUID);

  IconNode get icon => IconNode(this, 'IconID');

  UuidNode get customIconUuid => UuidNode(this, 'CustomIconUUID');

  KdbxGroup? get parent => _parent;

  KdbxGroup? _parent;

  KdbxCustomIcon? get customIcon =>
      customIconUuid.get()?.let((uuid) => file!.body.meta.customIcons[uuid]);

  set customIcon(KdbxCustomIcon? icon) {
    if (icon != null) {
      file!.body.meta.addCustomIcon(icon);
      customIconUuid.set(icon.uuid);
    } else {
      customIconUuid.set(null);
    }
  }

  @override
  void onAfterModify({bool preserveModificationTime = false}) {
    super.onAfterModify(preserveModificationTime: preserveModificationTime);
    if (!preserveModificationTime) {
      times.modifiedNow();
    }
    // during initial `create` the file will be null.
    file?.dirtyObject(this);
  }

  bool wasModifiedAfter(KdbxObject other) => times.lastModificationTime
      .get()!
      .isAfter(other.times.lastModificationTime.get()!);

  bool wasMovedAfter(KdbxObject other) =>
      times.locationChanged.get()!.isAfter(other.times.locationChanged.get()!);

  @override
  XmlElement toXml() {
    final el = super.toXml();
    XmlUtils.removeChildrenByName(el, 'Times');
    el.children.add(times.toXml());
    return el;
  }

  void internalChangeParent(KdbxGroup parent) {
    modify(() => _parent = parent);
  }

  void merge(MergeContext mergeContext, covariant KdbxObject other);
}

class KdbxUuid {
  const KdbxUuid(this.uuid);

  KdbxUuid.random() : this(base64.encode(Uuid.parse(uuidGenerator.v4())));

  KdbxUuid.fromBytes(Uint8List bytes) : this(base64.encode(bytes));

  /// https://tools.ietf.org/html/rfc4122.html#section-4.1.7
  /// > The nil UUID is special form of UUID that is specified to have all
  ///   128 bits set to zero.
  static const NIL = KdbxUuid('AAAAAAAAAAAAAAAAAAAAAA==');

  static const Uuid uuidGenerator =
      Uuid(options: <String, dynamic>{'grng': UuidUtil.cryptoRNG});

  /// base64 representation of uuid.
  final String uuid;

  String get uuidUrlSafe => base64UrlEncode(toBytes());

  Uint8List toBytes() => base64.decode(uuid);

  @override
  String toString() => uuid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KdbxUuid && uuid == other.uuid;

  @override
  int get hashCode => uuid.hashCode;

  /// Whether this is the [NIL] uuid.
  bool get isNil => this == NIL;
}
