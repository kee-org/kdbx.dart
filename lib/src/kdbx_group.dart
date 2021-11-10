import 'dart:collection';

import 'package:kdbx/kdbx.dart';
import 'package:kdbx/src/internal/extension_utils.dart';
import 'package:kdbx/src/kdbx_consts.dart';
import 'package:kdbx/src/kdbx_entry.dart';
import 'package:kdbx/src/kdbx_format.dart';
import 'package:kdbx/src/kdbx_xml.dart';
import 'package:logging/logging.dart';
import 'package:xml/xml.dart';

import 'kdbx_object.dart';

final _logger = Logger('kdbx_group');

class KdbxGroup extends KdbxObject {
  KdbxGroup.create({
    required KdbxReadWriteContext ctx,
    required KdbxGroup? parent,
    required String? name,
  }) : super.create(
          ctx,
          parent?.file,
          KdbxXml.NODE_GROUP,
          parent,
        ) {
    this.name.set(name);
    icon.set(KdbxIcon.Folder);
    expanded.set(true);
  }

  KdbxGroup.read(KdbxReadWriteContext ctx, KdbxGroup? parent, XmlElement node)
      : super.read(ctx, parent, node) {
    node
        .findElements(KdbxXml.NODE_GROUP)
        .map((el) => KdbxGroup.read(ctx, this, el))
        .forEach(_groups.add);
    node
        .findElements('Entry')
        .map((el) => KdbxEntry.read(ctx, this, el))
        .forEach(_entries.add);
  }

  @override
  XmlElement toXml() {
    final el = super.toXml();
    XmlUtils.removeChildrenByName(el, 'Group');
    XmlUtils.removeChildrenByName(el, 'Entry');
    el.children.addAll(groups.values.map((g) => g.toXml()));
    el.children.addAll(_entries.values.map((e) => e.toXml()));
    return el;
  }

  /// Returns all groups plus this group itself.
  LinkedHashMap<String, KdbxGroup> getAllGroups() {
    // ignore: prefer_collection_literals
    final flattenedGroups = LinkedHashMap<String, KdbxGroup>();

    groups.forEach((key, value) {
      flattenedGroups.addAll(value.getAllGroups());
    });
    return flattenedGroups..add(this);
  }

  /// Returns all entries of this group and all sub groups.
  LinkedHashMap<String, KdbxEntry> getAllEntries() {
    // ignore: prefer_collection_literals
    final flattenedEntries = LinkedHashMap<String, KdbxEntry>();

    groups.forEach((key, value) {
      flattenedEntries.addAll(value.getAllEntries());
    });
    return flattenedEntries..addAll(entries);
  }

  // LinkedHashMap<String, KdbxEntry> getAllEntries() =>
  //     getAllGroups().expand((g) => g.entries).findByUuid(uuid)(growable: false);

  UnmodifiableMapView<String, KdbxGroup> get groups =>
      UnmodifiableMapView(_groups);
  final LinkedHashMap<String, KdbxGroup> _groups =
      LinkedHashMap<String, KdbxGroup>();

  UnmodifiableMapView<String, KdbxEntry> get entries =>
      UnmodifiableMapView(_entries);
  final LinkedHashMap<String, KdbxEntry> _entries =
      LinkedHashMap<String, KdbxEntry>();

  void addEntry(KdbxEntry entry) {
    if (entry.parent != this) {
      throw StateError(
          'Invalid operation. Trying to add entry which is already in another group.');
    }
    assert(_entries.findByUuid(entry.uuid) == null,
        'must not already be in this group.');
    modify(() => _entries.add(entry));
  }

  void addGroup(KdbxGroup group) {
    if (group.parent != this) {
      throw StateError(
          'Invalid operation. Trying to add group which is already in another group.');
    }
    modify(() => _groups.add(group));
  }

  /// returns all parents recursively including this group.
  List<KdbxGroup> get breadcrumbs => [...?parent?.breadcrumbs, this];

  StringNode get name => StringNode(this, 'Name');

  StringNode get notes => StringNode(this, 'Notes');

//  String get name => text('Name') ?? '';
  NullableBooleanNode get expanded => NullableBooleanNode(this, 'IsExpanded');

  StringNode get defaultAutoTypeSequence =>
      StringNode(this, 'DefaultAutoTypeSequence');

  NullableBooleanNode get enableAutoType =>
      NullableBooleanNode(this, 'EnableAutoType');

  NullableBooleanNode get enableSearching =>
      NullableBooleanNode(this, 'EnableSearching');

  UuidNode get lastTopVisibleEntry => UuidNode(this, 'LastTopVisibleEntry');

  @override
  void import(KdbxGroup other, Map<KdbxUuid, KdbxUuid> uuidMap) {
    _importSubObjects<KdbxGroup>(
      other._groups,
      uuidMap,
      importToHere: (other) =>
          KdbxGroup.create(ctx: ctx, parent: this, name: other.name.get())
            ..forceSetUuid(KdbxUuid.random())
            ..let((x) => addGroup(x))
            .._overwriteFrom(const OverwriteContextNoop(), other),
    );
    _importSubObjects<KdbxEntry>(
      other._entries,
      uuidMap,
      importToHere: (other) => other.cloneInto(this, withNewUuid: true),
    );
  }

  @override
  void merge(MergeContext mergeContext, KdbxGroup other) {
    assertSameUuid(other, 'merge');

    if (other.wasModifiedAfter(this)) {
      _logger.finest('merge: other group was modified $uuid');
      _overwriteFrom(mergeContext, other);
    }
    _mergeSubObjects<KdbxGroup>(
      mergeContext,
      _groups,
      other._groups,
      importToHere: (other) =>
          KdbxGroup.create(ctx: ctx, parent: this, name: other.name.get())
            ..forceSetUuid(other.uuid)
            ..let((x) => addGroup(x))
            .._overwriteFrom(mergeContext, other),
    );
    _mergeSubObjects<KdbxEntry>(
      mergeContext,
      _entries,
      other._entries,
      importToHere: (other) => other.cloneInto(this),
    );
    mergeContext.markAsMerged(this);
  }

  void _importSubObjects<T extends KdbxObject>(
      LinkedHashMap<String, T> otherObjects, Map<KdbxUuid, KdbxUuid> uuidMap,
      {required T Function(T obj) importToHere}) {
    for (final otherObj in otherObjects.values) {
      final originalUuid = otherObj.uuid;
      final newMeObject = importToHere(otherObj);
      uuidMap[originalUuid] = newMeObject.uuid;
      newMeObject.import(otherObj, uuidMap);
    }
  }

  void _mergeSubObjects<T extends KdbxObject>(MergeContext mergeContext,
      LinkedHashMap<String, T> myObjects, LinkedHashMap<String, T> otherObjects,
      {required T Function(T obj) importToHere}) {
    // possibilities:
    // 1. Not changed at all 👍
    // 2. Deleted in other
    // 3. Deleted in this
    // 4. Modified in other
    // 5. Modified in this
    // 6. Moved in other
    // 7. Moved in this
    // 8. Created in other
    // 9. Created in this

    for (final otherObj in otherObjects.values) {
      final meObj = myObjects.findByUuid(otherObj.uuid);
      if (meObj == null) {
        // 3,6,7,8

        final movedObj = mergeContext.objectIndex[otherObj.uuid];
        if (movedObj == null) {
          // 3,8
          if (!mergeContext.deletedObjects.containsKey(otherObj.uuid)) {
            // 8
            final newMeObject = importToHere(otherObj);
            mergeContext.trackChange(newMeObject, debug: 'created');
            newMeObject.merge(mergeContext, otherObj);
          }
          // else 3
        } else {
          // 6,7
          if (otherObj.wasMovedAfter(movedObj)) {
            // 6
            file!.move(movedObj, this);
            mergeContext.trackChange(movedObj, debug: 'moved');
          }
          // else 7
          movedObj.merge(mergeContext, otherObj);
        }
      } else {
        // 1,4,5
        meObj.merge(mergeContext, otherObj);
      }
    }

    // For 9, we don't need to do anything.
    // For 2, we handle it after merging all objects.
  }

  List<KdbxSubNode> get _overwriteNodes => [
        ...objectNodes,
        name,
        notes,
        expanded,
        defaultAutoTypeSequence,
        enableAutoType,
        enableSearching,
        lastTopVisibleEntry,
      ];

  void _overwriteFrom(OverwriteContext mergeContext, KdbxGroup other) {
    overwriteSubNodesFrom(mergeContext, _overwriteNodes, other._overwriteNodes);
    // we should probably check that [lastTopVisibleEntry] is still a
    // valid reference?
    times.overwriteFrom(other.times);
  }

  @override
  String toString() {
    return 'KdbxGroup{uuid=$uuid,name=${name.get()}}';
  }
}

extension KdbxGroupInternal on KdbxGroup {
  void internalRemoveGroup(KdbxGroup group) {
    modify(() {
      if (_groups.remove(group.uuid.uuid) == null) {
        throw StateError('Unable to remove $group from $this (Not found)');
      }
    });
  }

  void internalRemoveEntry(KdbxEntry entry) {
    modify(() {
      if (_entries.remove(entry.uuid.uuid) == null) {
        throw StateError('Unable to remove $entry from $this (Not found)');
      }
    });
  }
}
