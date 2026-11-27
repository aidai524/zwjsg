# 狗版的你的来电语音

超时来电里“狗版的你”说的每句台词，都提前用 MiniMax 语音合成（`speech-2.8-hd`）生成好、加好电话音效，打包进 App。来电时直接放，不联网；放不了（资源缺了之类）才改用手机自带的语音念。

- 台词只有一份：`lib/features/call/call_script.dart`。括号里的英文是 MiniMax 的语气词（`(pant)` 喘气、`(sniffs)` 吸鼻子等），生成语音时用，字幕里去掉。
- 三个声音，用户在“超时来电”页自己挑（`lib/features/call/call_voice.dart` 的 `CallVoice`，目录名就是它的名字）：

  | 目录 | App 里叫 | MiniMax 系统音色 | 语速 |
  |---|---|---|---|
  | `spirit` | 憨憨萌兽（默认） | `Chinese (Mandarin)_Cute_Spirit` | 1.15 |
  | `boy` | 可爱男生 | `cute_boy` | 1.35 |
  | `girl` | 俏皮女生 | `qiaopi_mengmei` | 1.1 |

- 文件：`assets/voice/<声音>/<文件名>.m4a`，文件名是台词原文（带语气词）UTF-8 的 FNV-1a 32 位哈希，App 和脚本用同一个算法。台词一改文件名就变。
- 音效（`phonefx.py`，生成时一次处理好）：很轻的线路底噪、轻微过载、压缩、170 Hz–6.5 kHz 的通话频段。编码成 AAC（24 kHz、40 kbps）。

## 改了台词以后

在 `apps/zaiwan_gou` 下运行：

```bash
python3 tools/voice/make_voice.py
```

只生成还没有的，删掉用不到的。换了音色、语速或者音效，加 `--force` 全部重新生成。Flutter 测试会检查每句台词在每个声音下都有文件、没有多余的。

要用到：Python 3（numpy、scipy）、macOS 自带的 `afconvert`、`ffmpeg`、Flutter 带的 `dart`（脚本用 `export_lines.dart` 读台词）。

加一个声音：`CallVoice` 加一个，`make_voice.py` 的 `VOICES` 加一个，`pubspec.yaml` 加上 `assets/voice/<名字>/`。

## 密钥

存在本机的钥匙串里（账户 `zwjsg`、服务 `minimax-api-key`），不进仓库：

```bash
security add-generic-password -a zwjsg -s minimax-api-key -w
```

按提示粘贴两次，屏幕上不显示。也可以用环境变量 `MINIMAX_API_KEY`。脚本运行时才读，不打印、不写文件；国内（`api.minimax.cn`）还是国际（`api.minimax.io`）平台，按密钥自己认。

## 费用和合规

- 按字符计费，系统音色不另收音色费。三个声音全部重新生成一遍不到 2000 个计费字符。
- 发给 MiniMax 的只有这些固定台词，没有任何用户数据。
- MiniMax 的用户协议要求对外发布的 AI 生成内容要显著标识：来电界面通话中写着“AI 合成语音”，挑声音的地方也写了；每个文件的元数据（comment）写着“AI生成：MiniMax 语音合成”。
