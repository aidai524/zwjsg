import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 开源许可页（“我的 › 开源许可”，Flutter 自带的 LicensePage）要列的东西里，Dart 包的许可 Flutter 自己会列；
/// 这里补上 Dart 包以外、打包进 App 的第三方模型和运行库（2026-11-26）。两个平台带的不一样：
/// - 安卓：听狗叫的声音分类模型 YAMNet（android/app/src/main/assets/yamnet.tflite）、它的类别名（AudioSet 本体）、
///   跑模型的 LiteRT 运行库（build.gradle.kts 里的 com.google.ai.edge.litert:litert）；
///   拍照形象（2026-11-27）的 DCT-Net 模型、MediaPipe 的人脸检测、人脸关键点和自拍抠图模型（assets/cartoon/）、
///   App 里的相机用的 CameraX（androidx.camera）
/// - iOS：照片卡通化的 DCT-Net 模型（ios/Runner/Models/DCTNetAnimeHead.mlpackage）和示例图
///
/// 许可证全文在 assets/licenses/：从 LiteRT 1.4.2 的 AAR 自带的 LICENSE 拆成两份（Apache 2.0 全文、它附的 Caffe 版权声明），没改过。
/// 新打包进第三方的模型、字体、素材时，在这里加一条。只在 main() 里注册一次（安卓超时来电页的引擎用不到）
abstract final class AppLicenses {
  static const apacheAsset = 'assets/licenses/apache-2.0.txt';
  static const caffeAsset = 'assets/licenses/litert-caffe-notice.txt';

  static const yamnet = 'YAMNet 声音分类模型';
  static const audioSet = 'AudioSet 声音类别名';
  static const litert = 'LiteRT 运行库';
  static const dctNet = 'DCT-Net 卡通化模型';
  static const mediaPipe = 'MediaPipe 人脸和抠图模型';
  static const cameraX = 'CameraX 相机库';

  static bool _registered = false;

  /// 加到 [LicenseRegistry]：许可页打开时才去读许可证全文
  static void register({TargetPlatform? platform}) {
    if (_registered) return;
    _registered = true;
    final target = platform ?? defaultTargetPlatform;
    LicenseRegistry.addLicense(() => entries(target));
  }

  /// [platform] 上的 App 里带着的那几条
  static Stream<LicenseEntry> entries(TargetPlatform platform) async* {
    final apache = await rootBundle.loadString(apacheAsset);
    switch (platform) {
      case TargetPlatform.android:
        yield LicenseEntryWithLineBreaks(const [yamnet], '$_yamnetIntro\n\n$apache');
        yield const LicenseEntryWithLineBreaks([audioSet], _audioSetNotice);
        final caffe = await rootBundle.loadString(caffeAsset);
        yield LicenseEntryWithLineBreaks(const [litert], '$_litertIntro\n\n$apache\n\n$caffe');
        yield LicenseEntryWithLineBreaks(const [dctNet], '$_dctNetAndroidIntro\n\n$apache');
        yield LicenseEntryWithLineBreaks(const [mediaPipe], '$_mediaPipeIntro\n\n$apache');
        yield LicenseEntryWithLineBreaks(const [cameraX], '$_cameraXIntro\n\n$apache');
      case TargetPlatform.iOS:
        yield LicenseEntryWithLineBreaks(const [dctNet], '$_dctNetIntro\n\n$apache');
      default:
        break;
    }
  }

  static const _yamnetIntro = '安卓版学狗叫时，用这个模型在手机上判断每一声是什么声音（App 里的 yamnet.tflite，'
      '是 tensorflow/models 里的 YAMNet，由 MediaPipe 打包，https://github.com/tensorflow/models/tree/master/research/audioset/yamnet）。\n\n'
      'Copyright 2019 The TensorFlow Authors. All Rights Reserved.\n\n'
      '按 Apache License 2.0 授权，全文如下：';

  static const _audioSetNotice = 'YAMNet 的 521 个声音类别名称（App 里的 yamnet_labels.txt）来自 Google 的 AudioSet 本体'
      '（AudioSet Ontology，https://github.com/audioset/ontology），原样使用，没有修改。\n\n'
      'The ontology is made available by Google Inc. under a Creative Commons Attribution-ShareAlike 4.0 '
      'International (CC BY-SA 4.0) license: https://creativecommons.org/licenses/by-sa/4.0/';

  static const _litertIntro = '安卓版用 Google 的 LiteRT（原来的 TensorFlow Lite，com.google.ai.edge.litert:litert 1.4.2，'
      'https://github.com/google-ai-edge/LiteRT）在手机上运行 YAMNet 和拍照形象用到的几个模型。\n\n'
      '按 Apache License 2.0 授权，下面是它自带的许可文件，包括其中附的 Caffe 版权声明：';

  static const _dctNetAndroidIntro = '安卓版用自拍做卡通形象时，用的是 DCT-Net 日漫头像模型（阿里巴巴达摩院，'
      'ModelScope damo/cv_unet_person-image-cartoon_compound-models，https://github.com/menyifang/DCT-Net），'
      '转成 TFLite（App 里的 dctnet_anime_head.tflite）在手机上运行。\n\n'
      'Copyright (c) Alibaba, Inc. and its affiliates.\n\n'
      '按 Apache License 2.0 授权，全文如下：';

  static const _mediaPipeIntro = '安卓版用自拍做卡通形象时，用 Google MediaPipe 的三个模型在手机上找人脸、找五官、把人抠出来：'
      '人脸检测 BlazeFace（短距离，face_detector.tflite）和人脸关键点 Face Mesh V2（face_landmarks_detector.tflite），'
      '都出自 MediaPipe 的 face_landmarker.task；自拍抠图 SelfieSegmenter（selfie_segmenter.tflite）。'
      'https://ai.google.dev/edge/mediapipe/solutions/guide\n\n'
      'Copyright The MediaPipe Authors.\n\n'
      '按 Apache License 2.0 授权，全文如下：';

  static const _cameraXIntro = '安卓版拍自拍用的是 Google 的 CameraX 相机库（androidx.camera 1.5.3，'
      'https://developer.android.com/jetpack/androidx/releases/camera），拍到的照片只在内存里。\n\n'
      'Copyright The Android Open Source Project\n\n'
      '按 Apache License 2.0 授权，全文如下：';

  /// 示例图是 ios/Runner/Models/cartoon_sample.jpg（原生的卡通化验证在用），上线前要删；删了就把“示例图”那句也删掉
  static const _dctNetIntro = 'iOS 版用自拍做卡通形象时，用的是 DCT-Net 日漫头像模型（阿里巴巴达摩院，'
      'ModelScope damo/cv_unet_person-image-cartoon_compound-models，https://github.com/menyifang/DCT-Net），'
      '转成 Core ML 在手机上运行；App 里还带着 DCT-Net 的一张示例图。\n\n'
      'Copyright (c) Alibaba, Inc. and its affiliates.\n\n'
      '按 Apache License 2.0 授权，全文如下：';
}
