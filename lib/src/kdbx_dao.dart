import 'package:kdbx/src/kdbx_entry.dart';
import 'package:kdbx/src/kdbx_file.dart';
import 'package:kdbx/src/kdbx_group.dart';
import 'package:kdbx/src/kdbx_object.dart';

/// Helper object for accessing and modifing data inside
/// a kdbx file.
extension KdbxDao on KdbxFile {
  KdbxGroup createGroup({
    required KdbxGroup parent,
    required String name,
  }) {
    final newGroup = KdbxGroup.create(ctx: ctx, parent: parent, name: name);
    parent.addGroup(newGroup);
    return newGroup;
  }

  KdbxGroup findGroupByUuid(KdbxUuid uuid) {
    final group = body.rootGroup.getAllGroups()[uuid.uuid];
    if (group != null) {
      return group;
    }
    throw StateError('Unable to find group with uuid $uuid');
  }

  void deleteGroup(KdbxGroup group, [bool permenant = false]) {
    if (permenant) {
      delete(group);
    } else {
      move(group, getRecycleBinOrCreate());
    }
  }

  void deleteEntry(KdbxEntry entry, [bool permenant = false]) {
    if (permenant) {
      delete(entry);
    } else {
      move(entry, getRecycleBinOrCreate());
    }
  }

  void delete(KdbxObject kdbxObject, {bool alreadyTracked = false}) {
    if (kdbxObject is KdbxGroup) {
      kdbxObject.parent!.internalRemoveGroup(kdbxObject);
    } else if (kdbxObject is KdbxEntry) {
      kdbxObject.parent.internalRemoveEntry(kdbxObject);
    }
    kdbxObject.detachFromParent();
    if (!alreadyTracked) {
      ctx.recordObjectDeletion(kdbxObject);
    }
  }

  void move(KdbxObject kdbxObject, KdbxGroup toGroup) {
    kdbxObject.times.locationChanged.setToNow();
    if (kdbxObject is KdbxGroup) {
      kdbxObject.parent!.internalRemoveGroup(kdbxObject);
      kdbxObject.internalChangeParent(toGroup);
      toGroup.addGroup(kdbxObject);
    } else if (kdbxObject is KdbxEntry) {
      kdbxObject.parent.internalRemoveEntry(kdbxObject);
      kdbxObject.internalChangeParent(toGroup);
      toGroup.addEntry(kdbxObject);
    }
  }
}
