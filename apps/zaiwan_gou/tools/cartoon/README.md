# 拍照形象：手机本地卡通化（技术验证）

“我的 › 技术验证 › 拍照形象（本地卡通化）”这一页（只有 iOS 才显示）用到的模型，以及生成和核对它的脚本。

## 模型从哪来

- 模型：DCT-Net 日漫头像（阿里达摩院），ModelScope `damo/cv_unet_person-image-cartoon_compound-models` 里的 `cartoon_anime_h.pb`
  （sha256 `338e7bf7ab4014ba9da864c2dda104f26d8af6c7f468038782d92ccc8e2dedda`）。
  下载地址：`https://modelscope.cn/api/v1/models/damo/cv_unet_person-image-cartoon_compound-models/repo?Revision=master&FilePath=cartoon_anime_h.pb`
- 许可证：Apache 2.0，可以商用。**上线前**要在 App 的开源许可页附上 Apache 2.0 许可证全文，并写明模型来自 DCT-Net。
- 转好的 Core ML 模型：`ios/Runner/Models/DCTNetAnimeHead.mlpackage`（3.0 MB，FP16）。
  输入 `input_image`，形状 [288, 288, 3]，BGR，0–255 的浮点；输出 `mul_6`，形状和颜色顺序相同，也是 0–255。
- 样图：`ios/Runner/Models/cartoon_sample.jpg`，是 DCT-Net 仓库里的示例图 `input.png`（Apache 2.0）缩到 512 像素。
  **只给验证页用，上线前和验证页一起删掉**。

## 流程（手机上）

1. 系统选图器选一张照片（不需要相册权限）。照片只读进内存，在内存里转正并把长边缩到 1280 像素以内，不存盘、不上传。
2. 苹果 Vision 找 5 个点：两眼（瞳孔，没有就用眼睛轮廓的中心）、鼻尖、两个嘴角。
   鼻尖取 Vision“鼻子”轮廓 8 个点的中心。不用“鼻梁线最低点”，因为它会固定往一边偏 10 像素左右（288 像素的头像里）。
3. 按 DCT-Net 官方的模板（ModelScope 的 image_cartoon_pipeline）做相似变换，把头像对齐成 288×288，图外的地方填白。
4. Core ML 跑模型，计算单元选 `.all`，实际跑在神经网络引擎上。
5. 苹果 Vision 的人像分割（iOS 15+）在对齐后的照片上抠出人像，蒙版按面积平均缩成 288×288。
6. Flutter 里画“平涂墨线”贴纸（2026-11-16 定的画风）：保边平滑三遍 → 在 Lab 里用 k-means 压成 12 种颜色 → 5×5 中值滤波 → 比周围暗的细线描成墨线 → 按蒙版抠出，加白边和黑描边。代码在 `packages/avatar_engine/lib/src/photo_sticker.dart`，纯 Dart，安卓以后直接复用；狗耳朵、狗鼻子图层在 `photo_dog_avatar.dart`。

1–5 步的代码在 `ios/Runner/CartoonLab.swift`。

## 画风怎么定的（2026-11-16）

用同一套对齐流程比较了达摩院 7 种官方画风（日漫、3D、手绘、素描、艺术、插画、漫画，都是 Apache 2.0，网络结构一样，只转过日漫一种，其他的转成 Core ML 应该也是 3 MB 左右），都抠成贴纸、叠上设计稿的狗耳朵和狗鼻子放进黄底卡片里看。3D、手绘、漫画、素描偏写实，保留长相太多；艺术风的色块不讨喜；插画最 Q，但自带渐变光影，和平涂的狗耳朵不搭。定了日漫 + 平涂墨线：变形最强、线条干净，平涂后和设计稿最搭。两张样图都是女性，男性照片还没测。

## 2026-11-14 在 iPhone Air 上的实测结果

| 项目 | 结果 |
| --- | --- |
| 模型已加载时，一张照片的总耗时 | 约 28 ms（其中卡通化 3–4 ms，找五官约 5 ms） |
| 第一次使用（含加载模型约 0.35–0.46 s） | 约 0.5–0.7 s |
| 安装包体积 | 从 19.4 MB 增加到 22.8 MB |
| 和 Mac 上原版 TensorFlow 的结果比 | PSNR 35 dB，平均每个像素差约 2/255，肉眼看不出区别 |
| 对齐后 5 个点离模板的距离 | 三张正脸样图最远 4.8–6.5 像素（288 像素的头像里） |

结论：正脸照片对齐后，五官基本落在模板的固定位置上。所以正式美术可以在 288 的模板画布上画分层素材（狗耳朵、狗鼻子等），按固定坐标叠；鼻子这类小部件可以再跟着对齐后的真实鼻尖微调，验证页就是这么画的。
侧脸、戴口罩、多人合照还没测。

## 重新生成和核对模型

需要 Python 3.12，以及 tensorflow、coremltools、opencv-python、numpy（验证时的版本：tensorflow 2.21.0、coremltools 9.0、numpy 2.5.4、opencv 5.0.0）。
下载的模型文件和样图放进单独的空目录；用 `python -I` 跑脚本，免得加载到目录里的同名文件。

```bash
swiftc -O -o vision5 vision5.swift
./vision5 <照片> > points.json
python -I cartoonize.py <模型目录> <照片> points.json <输出目录>
python -I to_coreml.py <模型目录>/cartoon_anime_h.pb <输出目录> <输出目录>/<名字>_aligned.npy <输出目录>/<名字>_tf_out.npy
```

各脚本的作用：

- `vision5.swift`：在 Mac 上用和手机一样的 Vision 规则找 5 个点。
- `cartoonize.py`：TensorFlow 原版流程，作为基准。
- `to_coreml.py`：转成 Core ML，并和基准比较误差。
- `compare_device.py`：把手机上跑出来的结果和基准比较。

用 devicectl 带环境变量 `CARTOON_LAB_AUTORUN=1` 启动 App，它会自动拿样图跑两遍，结果写到 App 沙盒的 `Documents/cartoon_lab/`，用 `xcrun devicectl device copy from --domain-type appDataContainer` 拷回来比较。
