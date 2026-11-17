"""DCT-Net 头像卡通化的 Mac 基准：Vision 找 5 个点 → 按官方模板对齐裁成 288x288 → 跑 cartoon_anime_h.pb。

用法：python -I cartoonize.py <模型目录> <样图> <Vision 5 点 JSON> <输出目录>
对齐方式照抄 ModelScope 的 image_cartoon_pipeline（ratio=0.75，正方形模板，白色填充）。
"""
import json
import os
import sys
import time

import cv2
import numpy as np
import tensorflow.compat.v1 as tf

tf.disable_eager_execution()

SIZE = 288
RATIO = 0.75

# 官方 96x112 模板（各加 1），default_square 时 x 往右挪 8 补成 112x112
REF = np.array([
    [30.29459953, 51.69630051],
    [65.53179932, 51.50139999],
    [48.02519989, 71.73660278],
    [33.54930115, 92.3655014],
    [62.72990036, 92.20410156],
], np.float64) + 1.0
REF[:, 0] += 8.0
TARGET = ((REF - 56.0) * RATIO + 56.0) * SIZE / 112.0


def similarity(src, dst):
    """最小二乘相似变换（旋转 + 等比缩放 + 平移，不镜像），返回 2x3 矩阵"""
    src_mean, dst_mean = src.mean(0), dst.mean(0)
    s, d = src - src_mean, dst - dst_mean
    u, sig, vt = np.linalg.svd(d.T @ s / len(src))
    sign = np.eye(2)
    if np.linalg.det(u) * np.linalg.det(vt) < 0:
        sign[1, 1] = -1
    rot = u @ sign @ vt
    scale = (sig * np.diag(sign)).sum() / s.var(0).sum()
    m = np.zeros((2, 3))
    m[:, :2] = scale * rot
    m[:, 2] = dst_mean - scale * rot @ src_mean
    return m


def main():
    model_dir, image_path, points_json, out_dir = sys.argv[1:5]
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(image_path))[0]

    img = cv2.imread(image_path, cv2.IMREAD_COLOR)  # BGR
    pts = np.array(json.loads(open(points_json).read())["points"], np.float64)
    m = similarity(pts, TARGET)
    head = cv2.warpAffine(img, m, (SIZE, SIZE), borderValue=(255, 255, 255))
    cv2.imwrite(os.path.join(out_dir, f"{name}_aligned.png"), head)

    graph_def = tf.GraphDef()
    with open(os.path.join(model_dir, "cartoon_anime_h.pb"), "rb") as f:
        graph_def.ParseFromString(f.read())
    placeholders = [n for n in graph_def.node if n.op == "Placeholder"]
    for n in placeholders:
        shape = [d.size for d in n.attr["shape"].shape.dim]
        print("输入:", n.name, tf.as_dtype(n.attr["dtype"].type).name, shape)
    ops = sorted({n.op for n in graph_def.node})
    print("算子种类:", len(ops), ops)

    with tf.Graph().as_default() as g:
        tf.import_graph_def(graph_def, name="")
        out = g.get_tensor_by_name("output_image:0")
        print("输出:", out.name, out.dtype.name, out.shape)
        with tf.Session(graph=g) as sess:
            feed = {"input_image:0": head.astype(np.float32)}
            sess.run(out, feed_dict=feed)  # 预热
            t0 = time.time()
            res = sess.run(out, feed_dict=feed)
            ms = (time.time() - t0) * 1000
    res = np.squeeze(res)
    print("输出范围:", float(res.min()), float(res.max()), "形状", res.shape, f"Mac CPU 推理 {ms:.0f} ms")
    cv2.imwrite(os.path.join(out_dir, f"{name}_cartoon.png"), np.clip(res, 0, 255).astype(np.uint8))
    np.save(os.path.join(out_dir, f"{name}_tf_out.npy"), res.astype(np.float32))
    np.save(os.path.join(out_dir, f"{name}_aligned.npy"), head.astype(np.float32))


if __name__ == "__main__":
    main()
