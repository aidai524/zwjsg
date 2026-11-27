# 听狗叫的声音分类

超时来电里学狗叫，先按音量切出每一声（`lib/core/bark_detector.dart`），再看手机上的声音分类器怎么说。分类器只给每类声音打分，归成狗叫、人声、拍手、吹气由 `lib/core/sound_labels.dart` 定；判断规则只在 Dart 这一份。

| | iOS | 安卓 |
|---|---|---|
| 分类器 | 系统自带的 SoundAnalysis（`SNClassifySoundRequest` `.version1`，303 类，iOS 15 起） | Google 开源的 YAMNet（521 类），用 LiteRT 1.4.2 跑（`SoundClassifier.kt`） |
| 安装包 | 不变大 | 模型 4.1 MB + 运行库（arm64 4.5 MB、armeabi-v7a 2.6 MB） |
| 代码 | `ios/Runner/CallPlugin.swift` 的 `makeAnalyzer`、`SoundObserver` | `CallPlugin.kt` 的 `MicListener`、`SoundClassifier.kt` |
| 类别表 | `test/fixtures/apple_sound_labels.txt` | `android/app/src/main/assets/yamnet_labels.txt` |

两边都是 1 秒一窗、每 0.25 秒一次，原生把分数 ≥ 2% 的前 12 类原样交给 Flutter。声音只在内存里过一下，不录音、不保存、不上传。

iOS 没用 `flutter_litert`（2026-11-24 用户定）：它在 iOS 上第一次编译要再下载约 102 MB 运行库，装进 App 估计大 15–25 MB（带着用不上的 GPU、Core ML 加速，去不掉）。代价是同一声在两边的分数会有些差别。

## 模型

- 文件：`android/app/src/main/assets/yamnet.tflite`，MediaPipe 的音频分类模型（float32），4,126,810 字节，SHA-256 `4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf`。
- 下载地址：`https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/yamnet.tflite`
- 授权：YAMNet 和 LiteRT 都是 Apache 2.0；类别名来自 Google 的 AudioSet 本体（CC BY-SA 4.0）。许可证全文和署名放在 App 的“我的 › 开源许可”里（安卓，`lib/core/licenses.dart`，2026-11-26）。
- 输入 15600 个 -1..1 的数（16 kHz 单声道 0.975 秒），输出 [1, 521] 的分数。安装包里不压缩（`build.gradle.kts` 的 `noCompress`），直接映射进内存。
- 类别名在模型自带的元数据里，导出来放在 `assets/yamnet_labels.txt`：

```bash
python3 -I -c "import sys, zipfile; sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read('yamnet_label_list.txt').decode())" android/app/src/main/assets/yamnet.tflite > android/app/src/main/assets/yamnet_labels.txt
```

## iOS 的类别表

iPhone 和 Mac 上的系统分类器是同一个，在 Mac 上导出：

```bash
swift tools/bark/apple_labels.swift > test/fixtures/apple_sound_labels.txt
```

Flutter 测试会检查 `sound_labels.dart` 里的每个名字在这两个类别表里都有。

## 调阈值

阈值都在 `BarkDetector`：叫出来的（人声或狗叫）到 `vocalMin`（10%）算一声；拍手、吹气到 `otherMin`（20%）并且比叫出来的高才不算；狗叫到 `veryDogMin`（50%）狗版的你会夸一句。

在真机上“试一下来电”学狗叫，爪印下面会多写一行分类器给的分数（狗叫、人声、拍打、吹气），照着调。2026-11-24 在 Mac 上用同一个 YAMNet 试过：真狗叫 89–96%，系统语音念的“汪汪”判成说话（像狗 0%），合成的拍手判成鞭炮、枪声一类，没有一类到 20%，按规则会算一声（拿不准的算）。
