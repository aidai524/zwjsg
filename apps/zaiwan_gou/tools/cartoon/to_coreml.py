"""把 DCT-Net 日漫头像模型（TF1 冻结图）转成 Core ML，并和 TensorFlow 的输出对比。

用法：python -I to_coreml.py <cartoon_anime_h.pb> <输出目录> <对齐好的头像 .npy> <TF 输出 .npy>
输入固定 288x288x3（BGR，0–255），输出取 mul_6（0–255 的浮点，跳过最后转 uint8 的 Cast）。
"""
import os
import sys
import time

import coremltools as ct
import numpy as np


def frozen_function(pb):
    """装了 TF2 时 coremltools 不认 TF1 冻结图文件：包成 TF2 的 concrete function 再交给它"""
    import tensorflow as tf

    graph_def = tf.compat.v1.GraphDef()
    with open(pb, "rb") as f:
        graph_def.ParseFromString(f.read())

    def _import():
        tf.compat.v1.import_graph_def(graph_def, name="")

    wrapped = tf.compat.v1.wrap_function(_import, [])
    g = wrapped.graph
    return wrapped.prune(g.as_graph_element("input_image:0"), g.as_graph_element("mul_6:0"))


def main():
    pb, out_dir, aligned_npy, tf_npy = sys.argv[1:5]
    t0 = time.time()
    model = ct.convert(
        [frozen_function(pb)],
        source="tensorflow",
        inputs=[ct.TensorType(shape=(288, 288, 3))],
        minimum_deployment_target=ct.target.iOS16,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
    )
    print(f"转换用时 {time.time() - t0:.1f} s")
    model.short_description = "DCT-Net 日漫头像：288x288，BGR 0-255 进，0-255 出（Apache 2.0，阿里达摩院）"
    path = os.path.join(out_dir, "DCTNetAnimeHead.mlpackage")
    model.save(path)
    size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(path) for f in fs)
    print(f"Core ML 模型 {size / 1e6:.1f} MB")

    x = np.load(aligned_npy).astype(np.float32)
    ref = np.load(tf_npy).astype(np.float32)
    for unit in (ct.ComputeUnit.CPU_ONLY, ct.ComputeUnit.ALL):
        m = ct.models.MLModel(path, compute_units=unit)
        m.predict({"input_image": x})  # 预热
        t0 = time.time()
        for _ in range(5):
            y = list(m.predict({"input_image": x}).values())[0]
        ms = (time.time() - t0) / 5 * 1000
        y = np.floor(np.clip(np.squeeze(y), 0, 255))
        mse = float(np.mean((y - ref) ** 2))
        psnr = 10 * np.log10(255**2 / mse) if mse > 0 else float("inf")
        print(f"{unit.name}: Mac 上 {ms:.0f} ms；和 TF 比，最大差 {np.abs(y - ref).max():.0f}，平均差 {np.abs(y - ref).mean():.2f}，PSNR {psnr:.1f} dB")
    import cv2
    cv2.imwrite(os.path.join(out_dir, "coreml_cartoon.png"), y.astype(np.uint8))


if __name__ == "__main__":
    main()
