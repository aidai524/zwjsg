"""对比手机上跑出来的结果和 Mac 上 TensorFlow 原版的结果（同一张 512 样图）。

用法：python -I compare_device.py <手机结果目录> <Mac 结果目录> <拼图输出路径>
手机目录里有 aligned.png、cartoon.png、overlay.png；Mac 目录里有 cartoon_sample_aligned.png、cartoon_sample_cartoon.png。
"""
import sys

import cv2
import numpy as np


def psnr(a, b):
    mse = float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))
    return float("inf") if mse == 0 else 10 * np.log10(255**2 / mse)


def main():
    phone, mac, out = sys.argv[1:4]
    pairs = [("aligned.png", "cartoon_sample_aligned.png", "对齐"), ("cartoon.png", "cartoon_sample_cartoon.png", "卡通化")]
    tiles = []
    for p_name, m_name, label in pairs:
        p = cv2.imread(f"{phone}/{p_name}", cv2.IMREAD_COLOR)
        m = cv2.imread(f"{mac}/{m_name}", cv2.IMREAD_COLOR)
        diff = np.abs(p.astype(np.int16) - m.astype(np.int16))
        print(f"{label}：PSNR {psnr(p, m):.1f} dB，平均差 {diff.mean():.2f}，99% 分位差 {np.percentile(diff, 99):.0f}")
        tiles += [m, p]
    overlay = cv2.imread(f"{phone}/overlay.png", cv2.IMREAD_COLOR)
    tiles.append(overlay)
    cv2.imwrite(out, np.hstack(tiles))
    print("拼图顺序：Mac 对齐 | 手机对齐 | Mac 卡通 | 手机卡通 | 手机叠加 →", out)


if __name__ == "__main__":
    main()
