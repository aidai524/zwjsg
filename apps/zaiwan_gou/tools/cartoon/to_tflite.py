"""把 DCT-Net 日漫头像模型（TF1 冻结图）转成安卓用的 TFLite（FP16 权重），并和 TensorFlow 原版的输出对比。

用法：python -I to_tflite.py <cartoon_anime_h.pb> <样图> <输出目录>
输入固定 288x288x3（BGR，0–255 的浮点），输出取 mul_6（0–255 的浮点，跳过最后转 uint8 的 Cast），和 iOS 的 Core ML 版一样。
样图只用来对比数值：中间裁成正方形、缩到 288，不用对齐。
"""
import os
import sys
import time

import numpy as np
import tensorflow as tf


def frozen_function(pb):
    """把 TF1 冻结图包成输入固定 288x288x3 的 TF2 函数"""
    graph_def = tf.compat.v1.GraphDef()
    with open(pb, "rb") as f:
        graph_def.ParseFromString(f.read())

    def _import(x):
        (out,) = tf.compat.v1.import_graph_def(
            graph_def, input_map={"input_image:0": x}, return_elements=["mul_6:0"], name=""
        )
        return out

    return tf.compat.v1.wrap_function(_import, [tf.TensorSpec([288, 288, 3], tf.float32)])


def sample_input(path):
    """样图 → 288x288 的 BGR 浮点（0–255）"""
    rgb = tf.io.decode_image(tf.io.read_file(path), channels=3, expand_animations=False)
    h, w = rgb.shape[0], rgb.shape[1]
    side = min(h, w)
    rgb = tf.image.crop_to_bounding_box(rgb, (h - side) // 2, (w - side) // 2, side, side)
    rgb = tf.image.resize(tf.cast(rgb, tf.float32), (288, 288), antialias=True)
    return rgb.numpy()[..., ::-1].copy()


def main():
    pb, sample, out_dir = sys.argv[1:4]
    os.makedirs(out_dir, exist_ok=True)
    fn = frozen_function(pb)

    t0 = time.time()
    converter = tf.lite.TFLiteConverter.from_concrete_functions([fn], fn)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    # 只用 TFLite 自带的算子：用到 TF 算子（Flex）的话，安卓要多带二十多 MB 的运行库
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    tflite = converter.convert()
    path = os.path.join(out_dir, "dctnet_anime_head.tflite")
    with open(path, "wb") as f:
        f.write(tflite)
    print(f"转换用时 {time.time() - t0:.1f} s，TFLite 模型 {len(tflite) / 1e6:.2f} MB")

    x = sample_input(sample)
    ref = np.floor(np.clip(fn(tf.constant(x)).numpy(), 0, 255))

    interp = tf.lite.Interpreter(model_path=path, num_threads=4)
    interp.allocate_tensors()
    inp, out = interp.get_input_details()[0], interp.get_output_details()[0]
    print("输入", inp["name"], inp["shape"], inp["dtype"].__name__, "；输出", out["name"], out["shape"], out["dtype"].__name__)
    interp.set_tensor(inp["index"], x)
    interp.invoke()  # 预热
    t0 = time.time()
    for _ in range(5):
        interp.set_tensor(inp["index"], x)
        interp.invoke()
    ms = (time.time() - t0) / 5 * 1000
    y = np.floor(np.clip(np.squeeze(interp.get_tensor(out["index"])), 0, 255))
    mse = float(np.mean((y - ref) ** 2))
    psnr = 10 * np.log10(255**2 / mse) if mse > 0 else float("inf")
    print(f"Mac 上一张 {ms:.0f} ms；和 TF 比，最大差 {np.abs(y - ref).max():.0f}，平均差 {np.abs(y - ref).mean():.2f}，PSNR {psnr:.1f} dB")
    np.save(os.path.join(out_dir, "sample_input.npy"), x)
    np.save(os.path.join(out_dir, "sample_tf_out.npy"), ref)
    tf.io.write_file(os.path.join(out_dir, "tflite_cartoon.png"), tf.io.encode_png(y[..., ::-1].astype(np.uint8)))


if __name__ == "__main__":
    main()
