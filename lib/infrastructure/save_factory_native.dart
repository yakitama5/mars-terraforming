import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/save_repository.dart';
import 'file_save_store.dart';

Future<SaveRepository> createSaveRepository({required String slot}) async {
  final directory = await getApplicationSupportDirectory();
  return FileSaveStore(Directory('${directory.path}/saves'), slot: slot);
}
