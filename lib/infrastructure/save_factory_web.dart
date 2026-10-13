import '../domain/save_repository.dart';
import 'browser_save_store.dart';

Future<SaveRepository> createSaveRepository({required String slot}) async {
  // Pages project paths share one origin. Keep each deployment's saves/locks
  // separate, including when both builds enable the same development tools.
  const namespace = String.fromEnvironment('WEB_SAVE_NAMESPACE');
  return BrowserSaveStore(
    slot: namespace.isEmpty ? slot : '${namespace}_$slot',
  );
}
