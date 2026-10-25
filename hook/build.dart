import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// タイトルの3D素材と球面の大気shaderを、実行環境に合わせて事前に変換する。
/// Dartのアプリコードは生成せず、原本と固定版のSceneから再構築する。
void main(List<String> args) {
  build(args, (input, output) async {
    buildScenes(buildInput: input, buildOutput: output);
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
