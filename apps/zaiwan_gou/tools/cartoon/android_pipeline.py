"""安卓拍照形象的流程在 Mac 上跑一遍（和 android/.../CartoonPipeline.kt 一步一步对应，改了那边要用这个对一遍）：
BlazeFace 找脸 → 人脸网格找 5 个点 → 按 DCT-Net 模板对齐成 288 → 卡通化 → 往外放大 1.5 倍自拍抠图。
再拿 vision5 在同一张照片上找的 5 个点（iOS 的做法）比一比，看两边对齐差多少。

用法：python -I android_pipeline.py <cartoon 模型目录> <照片> <vision 点 json> <输出目录>
<cartoon 模型目录> 就是 android/app/src/main/assets/cartoon/。输出对齐后的照片、卡通图、蒙版、合成图，
以及交给 Flutter 贴纸用的原始像素（cartoon.rgba、mask.raw，288x288）。"""
import json
import math
import os
import sys

import numpy as np
import tensorflow as tf

SIZE = 288
# 抠图往外放大几倍
ZOOM = 1.5
TEMPLATE = [(30.29459953, 51.69630051), (65.53179932, 51.50139999), (48.02519989, 71.73660278),
            (33.54930115, 92.3655014), (62.72990036, 92.20410156)]
TARGET = np.array([(((x + 9 - 56) * 0.75 + 56) * SIZE / 112, ((y + 1 - 56) * 0.75 + 56) * SIZE / 112) for x, y in TEMPLATE])


def interp(path):
    it = tf.lite.Interpreter(model_path=path, num_threads=4)
    it.allocate_tensors()
    return it


def run(it, x):
    it.set_tensor(it.get_input_details()[0]['index'], x)
    it.invoke()
    return [it.get_tensor(d['index']) for d in it.get_output_details()]


def anchors():
    out, strides, layer = [], [8, 16, 16, 16], 0
    while layer < len(strides):
        same = [i for i in range(layer, len(strides)) if strides[i] == strides[layer]]
        fm = math.ceil(128 / strides[layer])
        for y in range(fm):
            for x in range(fm):
                for _ in range(2 * len(same)):
                    out.append(((x + 0.5) / fm, (y + 0.5) / fm))
        layer = same[-1] + 1
    return np.array(out, np.float32)


def sample(img, m, out_w, out_h, fill):
    """img: HxWxC float；m: 2x3，输出像素 (u,v) → 原图 (x,y)。双线性，图外填 fill；fill 为 None 时取最近的边上的像素"""
    h, w = img.shape[:2]
    u, v = np.meshgrid(np.arange(out_w) + 0.5, np.arange(out_h) + 0.5)
    x = m[0, 0] * u + m[0, 1] * v + m[0, 2] - 0.5
    y = m[1, 0] * u + m[1, 1] * v + m[1, 2] - 0.5
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    out = np.zeros((out_h, out_w, img.shape[2]), np.float32)
    acc = np.zeros((out_h, out_w, 1), np.float32)
    for dy, wy in ((0, 1 - fy), (1, fy)):
        for dx, wx in ((0, 1 - fx), (1, fx)):
            xi, yi = x0 + dx, y0 + dy
            ok = ((xi >= 0) & (xi < w) & (yi >= 0) & (yi < h))[..., None]
            px = img[np.clip(yi, 0, h - 1), np.clip(xi, 0, w - 1)]
            wgt = wx * wy
            out += px * wgt if fill is None else np.where(ok, px * wgt, fill * wgt)
    return out


def detect(det, img):
    h, w = img.shape[:2]
    scale = 128 / max(h, w)
    pad_x, pad_y = (128 - w * scale) / 2, (128 - h * scale) / 2
    # 128 的输入像素 → 原图像素
    m = np.array([[1 / scale, 0, -pad_x / scale], [0, 1 / scale, -pad_y / scale]])
    x = sample(img.astype(np.float32), m, 128, 128, 0.0) / 127.5 - 1
    reg, cls = run(det, x[None])
    reg, cls = reg[0], cls[0, :, 0]
    a = anchors()
    score = 1 / (1 + np.exp(-np.clip(cls, -100, 100)))
    faces = []
    for i in np.argsort(-score):
        if score[i] < 0.5:
            break
        r = reg[i] / 128
        cx, cy, bw, bh = r[0] + a[i, 0], r[1] + a[i, 1], r[2], r[3]
        kps = [(r[4 + 2 * k] + a[i, 0], r[5 + 2 * k] + a[i, 1]) for k in range(6)]
        box = (cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)
        if any(iou(box, f['box']) > 0.3 for f in faces):
            continue
        faces.append({'score': float(score[i]), 'box': box, 'kps': kps})
    to_px = lambda p: ((p[0] * 128 - pad_x) / scale, (p[1] * 128 - pad_y) / scale)
    for f in faces:
        x0, y0 = to_px(f['box'][:2])
        x1, y1 = to_px(f['box'][2:])
        f['box_px'] = (x0, y0, x1, y1)
        f['kps_px'] = [to_px(k) for k in f['kps']]
    return faces


def iou(a, b):
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0


def landmarks(lm, img, face):
    x0, y0, x1, y1 = face['box_px']
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    (rx, ry), (lx, ly) = face['kps_px'][0], face['kps_px'][1]
    rot = -math.atan2(-(ly - ry), lx - rx)
    rot = (rot + math.pi) % (2 * math.pi) - math.pi
    side = max(x1 - x0, y1 - y0) * 1.5
    c, s = math.cos(rot), math.sin(rot)
    k = side / 256
    # 256 的裁图像素 (u,v) → 原图：((u - 128)·k, (v - 128)·k) 转 rot，再加中心
    m = np.array([[c * k, -s * k, cx - 128 * k * c + 128 * k * s], [s * k, c * k, cy - 128 * k * s - 128 * k * c]])
    crop = sample(img.astype(np.float32), m, 256, 256, 0.0) / 255
    pts, presence, _ = run(lm, crop[None])
    pts = pts.reshape(-1, 3)[:, :2]
    img_pts = np.stack([m[0, 0] * pts[:, 0] + m[0, 1] * pts[:, 1] + m[0, 2], m[1, 0] * pts[:, 0] + m[1, 1] * pts[:, 1] + m[1, 2]], 1)
    return img_pts, float(1 / (1 + np.exp(-presence.ravel()[0])))


def similarity(src, dst):
    sm, dm = src.mean(0), dst.mean(0)
    s, d = src - sm, dst - dm
    dot = (s * d).sum()
    cross = (s[:, 0] * d[:, 1] - s[:, 1] * d[:, 0]).sum()
    norm = (s ** 2).sum()
    a, b = dot / norm, cross / norm
    return np.array([[a, -b, dm[0] - (a * sm[0] - b * sm[1])], [b, a, dm[1] - (b * sm[0] + a * sm[1])]])


def invert(m):
    a, b, c, d = m[0, 0], m[0, 1], m[1, 0], m[1, 1]
    det = a * d - b * c
    inv = np.array([[d, -b], [-c, a]]) / det
    return np.hstack([inv, -inv @ m[:, 2:3]])


def apply(m, p):
    return np.stack([m[0, 0] * p[:, 0] + m[0, 1] * p[:, 1] + m[0, 2], m[1, 0] * p[:, 0] + m[1, 1] * p[:, 1] + m[1, 2]], 1)


def main():
    model_dir, photo, vision_json, out_dir = sys.argv[1:5]
    dct_path = os.path.join(model_dir, 'dctnet_anime_head.tflite')
    os.makedirs(out_dir, exist_ok=True)
    img = tf.io.decode_image(tf.io.read_file(photo), channels=3, expand_animations=False).numpy()
    det = interp(os.path.join(model_dir, 'face_detector.tflite'))
    lm = interp(os.path.join(model_dir, 'face_landmarks_detector.tflite'))
    faces = detect(det, img)
    print('找到', len(faces), '张脸', [round(f['score'], 3) for f in faces])
    face = max(faces, key=lambda f: f['box_px'][2] - f['box_px'][0])
    mesh, presence = landmarks(lm, img, face)
    print('人脸网格可信度', round(presence, 3))
    vision = np.array(json.load(open(vision_json))['points'])

    eyes = sorted([mesh[468], mesh[473]], key=lambda p: p[0])
    mouth = sorted([mesh[61], mesh[291]], key=lambda p: p[0])
    # 鼻尖用网格的 4 号点：和 iOS 用的 Vision“鼻子”轮廓中心最接近（试过 1、2、19 号和鼻翼一圈的平均）
    five = np.array([eyes[0], eyes[1], mesh[4], mouth[0], mouth[1]])
    print('五个点和 Vision 差（原图像素）', np.round(np.hypot(*(five - vision).T), 1))

    m_mesh = similarity(five, TARGET)
    m_vision = similarity(vision, TARGET)
    # 两种对齐下，模板的 5 个点各自落在哪里（288 头像的像素）：差多少就是对齐差多少
    diff = apply(m_mesh, apply(invert(m_vision), TARGET)) - TARGET
    print('和 iPhone 的对齐差（288 头像像素）', np.round(np.hypot(*diff.T), 1))
    print('对齐后离模板最远', round(float(np.hypot(*(apply(m_mesh, five) - TARGET).T).max()), 1), '像素')

    aligned = sample(img.astype(np.float32), invert(m_mesh), SIZE, SIZE, 255.0)
    dct = interp(dct_path)
    (cartoon,) = run(dct, aligned[..., ::-1].copy())
    cartoon = np.clip(cartoon, 0, 255)[..., ::-1]
    np.save(os.path.join(out_dir, 'aligned.npy'), aligned)
    # 自拍抠图：贴着脸裁的小图模型容易认不出人，往外放大 ZOOM 倍、看得到头和肩膀再抠，抠完缩回 288
    seg = interp(os.path.join(model_dir, 'selfie_segmenter.tflite'))
    inv = invert(m_mesh)
    # 256 的抠图输入像素 c → 288 头像坐标 a = (c·288/256 − 144)·ZOOM + 144 → 原图
    k = SIZE / 256 * ZOOM
    to_aligned = np.array([[k, 0, 144 - 144 * ZOOM], [0, k, 144 - 144 * ZOOM]])
    to_photo = np.vstack([inv, [0, 0, 1]]) @ np.vstack([to_aligned, [0, 0, 1]])
    ctx = sample(img.astype(np.float32), to_photo[:2], 256, 256, 255.0) / 255
    (conf,) = run(seg, ctx[None])
    # 288 头像像素 a → 抠图输入像素 c = ((a − 144)/ZOOM + 144)·256/288
    back = np.array([[1 / k, 0, (144 - 144 / ZOOM) * 256 / SIZE], [0, 1 / k, (144 - 144 / ZOOM) * 256 / SIZE]])
    mask = sample(conf[0], back, SIZE, SIZE, 0.0)[..., 0]
    print(f'抠图：人占 {(mask > 0.5).mean():.0%}')
    # 交给 Flutter 的贴纸：RGBA（第一行在最上面）和每像素 1 字节的蒙版
    rgba = np.concatenate([np.clip(cartoon, 0, 255), np.full((SIZE, SIZE, 1), 255.0)], 2).astype(np.uint8)
    rgba.tofile(os.path.join(out_dir, 'cartoon.rgba'))
    np.clip(mask * 255, 0, 255).astype(np.uint8).tofile(os.path.join(out_dir, 'mask.raw'))
    comp = cartoon * mask[..., None] + np.array([255, 210, 63]) * (1 - mask[..., None])
    for name, arr in [('aligned.png', aligned), ('cartoon.png', cartoon), ('mask.png', np.repeat(mask[..., None] * 255, 3, 2)), ('comp.png', comp)]:
        tf.io.write_file(os.path.join(out_dir, name), tf.io.encode_png(np.clip(arr, 0, 255).astype(np.uint8)))


if __name__ == '__main__':
    main()
