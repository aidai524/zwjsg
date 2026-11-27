"""生成“狗版的你”的来电语音：每句台词 × 每个声音，用 MiniMax 语音合成（speech-2.8-hd），
加电话音效，存成 assets/voice/<声音>/<文件名>.m4a。

- 台词只有一份：lib/features/call/call_script.dart（用 export_lines.dart 读出来，文件名也由它算，跟 App 一致）
- 声音的目录名跟 lib/features/call/call_voice.dart 的 CallVoice 对得上；MiniMax 音色 ID 和语速在下面 VOICES
- 密钥只从钥匙串（账户 zwjsg、服务 minimax-api-key）或环境变量 MINIMAX_API_KEY 读，不打印、不写文件
- 发给 MiniMax 的只有这些固定台词，没有任何用户数据
- 生成的是 AI 合成的声音：文件里写上 AIGC 元数据；App 里显示“AI 合成语音”（MiniMax 用户协议要求显著标识）

用法（在 apps/zaiwan_gou 下）：
  python3 tools/voice/make_voice.py          # 只生成还没有的（改了台词就跑这个），删掉用不到的
  python3 tools/voice/make_voice.py --force  # 全部重新生成（换了音色、语速、音效时）
"""
import binascii
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

import numpy as np
import scipy.io.wavfile as wav

HERE = pathlib.Path(__file__).resolve().parent
APP = HERE.parent.parent
sys.path.insert(0, str(HERE))
import phonefx  # noqa: E402

MODEL = "speech-2.8-hd"
# 目录名（= CallVoice.name）→ (MiniMax 系统音色 ID, 语速)
VOICES = {
    "spirit": ("Chinese (Mandarin)_Cute_Spirit", 1.15),  # 憨憨萌兽，默认
    "boy": ("cute_boy", 1.35),  # 可爱男童：天生说得慢，调快
    "girl": ("qiaopi_mengmei", 1.1),  # 俏皮萌妹
}
HOSTS = ["https://api.minimax.cn", "https://api.minimax.io"]  # 国内、国际，按密钥自己认
AIGC = f"AI生成：MiniMax 语音合成（{MODEL}）"


def api_key():
    k = os.environ.get("MINIMAX_API_KEY", "").strip()
    if not k:
        r = subprocess.run(["security", "find-generic-password", "-a", "zwjsg", "-s", "minimax-api-key", "-w"],
                           capture_output=True, text=True)
        k = r.stdout.strip()
    if not k:
        sys.exit("没找到 MiniMax 密钥：先在终端运行 security add-generic-password -a zwjsg -s minimax-api-key -w")
    return k


def post(host, path, body, key):
    req = urllib.request.Request(host + path, data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)


def pick_host(key):
    for host in HOSTS:
        try:
            if (post(host, "/v1/get_voice", {"voice_type": "system"}, key).get("base_resp") or {}).get("status_code") == 0:
                return host
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            pass
    sys.exit("国内（api.minimax.cn）和国际（api.minimax.io）都不认这个密钥")


def script():
    out = subprocess.run(["dart", str(HERE / "export_lines.dart")], cwd=APP, capture_output=True, text=True, check=True)
    data = json.loads(out.stdout)
    if sorted(data["voices"]) != sorted(VOICES):
        sys.exit(f"声音对不上：App 里是 {data['voices']}，这里是 {list(VOICES)}")
    return data["lines"]


def fnv(text):
    """跟 call_voice.dart 的 clipName 一样"""
    h = 0x811C9DC5
    for b in text.encode("utf-8"):
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return f"{h:08x}"


def synth(host, key, text, voice_id, speed):
    d = post(host, "/v1/t2a_v2", {
        "model": MODEL, "text": text, "stream": False,
        "voice_setting": {"voice_id": voice_id, "speed": speed, "vol": 1, "pitch": 0},
        "audio_setting": {"sample_rate": 32000, "format": "wav", "channel": 1},
        "language_boost": "Chinese",
    }, key)
    base = d.get("base_resp") or {}
    if base.get("status_code") != 0:
        raise RuntimeError(f"MiniMax 返回 {base.get('status_code')}：{base.get('status_msg')}")
    return binascii.unhexlify(d["data"]["audio"]), (d.get("extra_info") or {}).get("usage_characters", 0)


def render(raw, text, target, tmp):
    """原声 → 电话音效 → AAC（24 kHz、40 kbps）→ 写上 AIGC 元数据"""
    src, mono, fx, aac = (tmp / n for n in ("src.wav", "mono.wav", "fx.wav", "fx.m4a"))
    src.write_bytes(raw)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", "-c", "1", str(src), str(mono)], check=True)
    sr, x = wav.read(mono)
    y = phonefx.phone(x.astype(np.float64) / 32768, sr, np.random.default_rng(7), lead=0.03, tail=0.08)
    wav.write(fx, phonefx.OUT, y.astype(np.float32))
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac@24000", "-b", "40000", "-c", "1", str(fx), str(aac)], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(aac), "-c", "copy",
                    "-metadata", f"comment={AIGC}", "-metadata", f"title={text}",
                    "-metadata", "artist=再玩我是狗 · 狗版的你", str(target)], check=True)


def main():
    force = "--force" in sys.argv
    lines = script()
    for line in lines:
        assert fnv(line["text"]) == line["file"], f"文件名算法跟 App 对不上：{line['text']}"
    key, host = None, None
    made = skipped = removed = chars = 0
    with tempfile.TemporaryDirectory() as t:
        tmp = pathlib.Path(t)
        for name, (voice_id, speed) in VOICES.items():
            folder = APP / "assets" / "voice" / name
            folder.mkdir(parents=True, exist_ok=True)
            wanted = set()
            for line in lines:
                target = folder / f"{line['file']}.m4a"
                wanted.add(target.name)
                if target.exists() and not force:
                    skipped += 1
                    continue
                if key is None:
                    key = api_key()
                    host = pick_host(key)
                raw, used = synth(host, key, line["text"], voice_id, speed)
                chars += used
                render(raw, line["text"], target, tmp)
                made += 1
                print(f"  {name}/{target.name}  {line['text']}")
            for f in folder.glob("*.m4a"):
                if f.name not in wanted:
                    f.unlink()
                    removed += 1
    size = sum(f.stat().st_size for f in (APP / "assets" / "voice").rglob("*.m4a"))
    print(f"生成 {made} 句，已有 {skipped} 句，删掉 {removed} 个用不到的；计费字符 {chars}；语音一共 {size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
