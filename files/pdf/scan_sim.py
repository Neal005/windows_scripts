#!/usr/bin/env python3
"""
scan_sim.py - Giả lập PDF scan (chỉ chứa ảnh, không có lớp text) từ một file PDF để test OCR.

Hai chế độ:
  scan : máy scan văn phòng/ADF - ảnh xám, nghiêng nhẹ, vân giấy, mực hơi nhòe, nhiễu cảm biến.
  old  : văn bản giấy cũ - ảnh màu, giấy ngả vàng, đốm ố, vết nước, nếp gấp, mực phai, giấy cong, bụi.
         --table light|heavy làm đường kẻ bảng mờ và đứt quãng (mặc định off).

Yêu cầu:  pip install numpy pillow scipy pymupdf

Ví dụ:
  python scan_sim.py --mode scan --input BaoCao.pdf --output BaoCao_scan.pdf
  python scan_sim.py --mode old  --input BaoCao.pdf --output BaoCao_giaycu.pdf --level 3 --seed 42

Đầu vào là PDF. Muốn đi từ DOCX thì dùng Convert-ToScannedPdf.ps1 / Convert-ToOldPaperScan.ps1
(hai script đó chuyển DOCX -> PDF bằng Word hoặc LibreOffice rồi gọi file này).
"""
import argparse
import io
import random

import numpy as np
import pymupdf
from PIL import Image
from scipy.ndimage import (gaussian_filter, map_coordinates, maximum_filter,
                           maximum_filter1d, uniform_filter1d)

DEFAULT_QUALITY = {"scan": 82, "old": 72}


class Sim:
    def __init__(self, seed):
        self.seed = seed if seed >= 0 else random.randrange(1 << 30)
        self.rand = random.Random(self.seed)
        self.rng = np.random.default_rng(self.seed)

    def lowfreq(self, h, w, cell, sigma, normalize=False):
        z = gaussian_filter(self.rng.standard_normal((h // cell + 2, w // cell + 2)), sigma).astype(np.float32)
        z = np.array(Image.fromarray(z).resize((w, h), Image.BICUBIC))
        return z / (np.abs(z).max() + 1e-6) if normalize else z

    # ------------------------------------------------------------ máy scan văn phòng
    def scan(self, g):
        h, w = g.shape
        s = max(h, w) / 3508.0                                   # chuẩn hoá theo A4 @ 300 dpi
        r, rng = self.rand, self.rng
        ink = np.clip(gaussian_filter(1 - g, 0.7 * max(s, 0.4)) * 1.08, 0, 1)   # quang học + mực lan
        a = 1 - ink
        paper = 0.955 + 0.1 * self.lowfreq(h, w, max(int(20 * s), 4), 3)      # giấy không đều
        paper += rng.standard_normal((h, w)).astype(np.float32) * 0.008         # vân giấy
        paper *= np.linspace(1.0, 0.985, w, dtype=np.float32)[None, :]          # đèn scan tối dần
        a = np.clip(a * paper + rng.standard_normal((h, w)).astype(np.float32) * 0.012, 0, 1)
        im = Image.fromarray((a * 255).astype(np.uint8))
        ang = r.uniform(-0.6, 0.6)                                              # nghiêng khi kéo giấy
        off = (int(r.uniform(-12, 12) * s), int(r.uniform(-10, 10) * s))
        return im.rotate(ang, resample=Image.BICUBIC, expand=False, fillcolor=242, translate=off), ang

    @staticmethod
    def table_lines(g, s):
        """Mặt nạ các đường kẻ ngang/dọc dài (đường bảng), không bắt chữ."""
        dark = (g < 0.5).astype(np.float32)
        L = max(int(70 * s), 15)                        # đoạn thẳng liên tục >= ~6 mm @ 300 dpi
        hor = maximum_filter1d((uniform_filter1d(dark, L, axis=1) > 0.999).astype(np.uint8), L, axis=1)
        ver = maximum_filter1d((uniform_filter1d(dark, L, axis=0) > 0.999).astype(np.uint8), L, axis=0)
        m = (hor | ver) & (dark > 0)
        r = max(int(2 * s), 1) * 2 + 1                  # phủ cả viền khử răng cưa của nét kẻ
        return maximum_filter(m, size=r).astype(bool)

    # ------------------------------------------------------------ giấy cũ
    # mức làm mờ đường kẻ bảng: (độ đậm còn lại, biên độ dao động, sàn, trần, ngưỡng đứt, hệ số tại chỗ đứt, ô nhiễu đứt)
    TABLE_FADE = {
        "light": (0.58, 0.18, 0.35, 0.85, 0.40, 0.35, 6),    # mờ đều, đứt ít và ngắn (~1 mm), không mất hẳn
        "heavy": (0.38, 0.30, 0.08, 0.75, 0.30, 0.08, 12),   # mờ mạnh, đứt 2-5 mm, có đoạn gần như mất hẳn
    }

    def old(self, g, level=2, table="off"):
        K = {1: 0.55, 2: 1.0, 3: 1.6}[level]
        h, w = g.shape
        s = max(h, w) / 3508.0
        r, rng = self.rand, self.rng
        # mực phai, loang, đứt nét
        ink = np.clip(gaussian_filter(1 - g, 1.0 * s) * 1.15, 0, 1)
        if table in self.TABLE_FADE:                                            # đường kẻ bảng mờ + đứt
            base, amp, lo, hi, thr, gapk, cell = self.TABLE_FADE[table]
            lines = self.table_lines(g, s)
            if lines.any():
                lf = self.lowfreq(h, w, max(int(90 * s), 4), 2, True)           # phai không đều theo vùng
                gaps = self.lowfreq(h, w, max(int(cell * s), 3), 1.5, True)     # đứt quãng từng đoạn
                keep = np.clip(base + amp * lf, lo, hi)
                keep = np.where(gaps > thr, keep * gapk, keep)
                ink = np.where(lines, ink * keep, ink)
        fade = np.clip(0.72 + 0.18 * self.lowfreq(h, w, max(int(60 * s), 4), 2, True) - 0.08 * (K - 1), 0.4, 0.95)
        ink = ink * fade
        ink *= np.clip(1 + rng.standard_normal((h, w)).astype(np.float32) * 0.12 * K, 0, 1.5)
        # giấy ố vàng
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
        age = (0.10 * d ** 2 + 0.05 * self.lowfreq(h, w, max(int(40 * s), 4), 2, True)) * K
        for _ in range(int(r.randint(4, 12) * K)):                              # đốm ố
            cx, cy, rad = r.uniform(0, w), r.uniform(0, h), r.uniform(8, 45) * s
            age += 0.10 * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * rad * rad))
        if r.random() < 0.4 * K:                                                # vết nước loang
            cx, cy, rad = r.uniform(.2 * w, .8 * w), r.uniform(.2 * h, .8 * h), r.uniform(150, 350) * s
            rr = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
            age += 0.06 * np.exp(-((rr - rad) / (18 * s)) ** 2) + 0.03 * (rr < rad)
        cy = h * r.uniform(0.47, 0.53)                                          # nếp gấp
        age += 0.07 * K * np.exp(-((yy - cy) / (5 * s)) ** 2)
        paper = np.stack([0.93 - age * 0.9, 0.87 - age * 1.0, 0.72 - age * 1.2], -1)
        paper += rng.standard_normal((h, w, 1)).astype(np.float32) * 0.015
        inkc = np.array([0.12, 0.10, 0.09], dtype=np.float32)
        img = paper * (1 - ink[..., None]) + inkc * ink[..., None]
        n = int(r.randint(150, 400) * K * s * s)                                # bụi
        img[rng.integers(0, h, n), rng.integers(0, w, n)] *= 0.45
        amp = r.uniform(2, 5) * K * s                                           # giấy cong
        dx = amp * np.sin(yy / h * np.pi * r.uniform(0.8, 1.5))
        img = np.stack([map_coordinates(img[..., c], [yy, xx + dx], order=1, mode="nearest") for c in range(3)], -1)
        im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
        ang = r.uniform(-1.6, 1.6) * min(K, 1.3)                                # đặt tay lên mặt kính
        off = (int(r.uniform(-30, 30) * s * K), int(r.uniform(-25, 25) * s * K))
        return im.rotate(ang, resample=Image.BICUBIC, expand=False, fillcolor=(25, 25, 25), translate=off), ang


def render_gray(page, dpi):
    pix = page.get_pixmap(dpi=dpi, colorspace=pymupdf.csGRAY, alpha=False)
    buf = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.stride)
    return buf[:, :pix.width].astype(np.float32) / 255.0


def convert(input_pdf, output_pdf, mode="scan", dpi=300, quality=None, seed=-1, level=2, table="off", log=print):
    """Chuyển input_pdf thành PDF ảnh giả lập scan. Trả về seed đã dùng."""
    quality = quality or DEFAULT_QUALITY[mode]
    sim = Sim(seed)
    src = pymupdf.open(input_pdf)
    out = pymupdf.open()
    for i, page in enumerate(src):
        g = render_gray(page, dpi)
        im, ang = sim.scan(g) if mode == "scan" else sim.old(g, level, table)
        bio = io.BytesIO()
        opts = {"subsampling": 0} if mode == "scan" else {}
        im.save(bio, "JPEG", quality=quality, dpi=(dpi, dpi), optimize=True, **opts)
        p = out.new_page(width=im.width * 72.0 / dpi, height=im.height * 72.0 / dpi)
        p.insert_image(p.rect, stream=bio.getvalue())
        if log:
            log("  trang %d/%d  %dx%d px  nghieng %+.2f deg" % (i + 1, len(src), im.width, im.height, ang))
    out.set_metadata({"producer": "Scanner", "creator": "Scanner"})
    out.save(output_pdf, garbage=3, deflate=True)
    src.close(); out.close()
    return sim.seed


def main():
    ap = argparse.ArgumentParser(description="Giả lập PDF scan (chỉ ảnh) để test OCR.")
    ap.add_argument("--input", "-i", required=True, help="PDF đầu vào")
    ap.add_argument("--output", "-o", required=True, help="PDF đầu ra")
    ap.add_argument("--mode", "-m", choices=["scan", "old"], default="scan", help="scan = máy scan, old = giấy cũ")
    ap.add_argument("--dpi", type=int, default=300)
    ap.add_argument("--quality", type=int, default=None, help="JPEG 1-100 (mặc định scan=82, old=72)")
    ap.add_argument("--seed", type=int, default=-1, help="-1 = ngẫu nhiên")
    ap.add_argument("--level", type=int, choices=[1, 2, 3], default=2, help="mức cũ cho mode old")
    ap.add_argument("--table", choices=["off", "light", "heavy"], default="off",
                    help="làm mờ đường kẻ bảng (mode old): off | light | heavy")
    a = ap.parse_args()
    seed = convert(a.input, a.output, a.mode, a.dpi, a.quality, a.seed, a.level, a.table,
                   log=lambda m: print(m, flush=True))
    print("  seed=%d%s" % (seed, "  level=%d  table=%s" % (a.level, a.table) if a.mode == "old" else ""))


if __name__ == "__main__":
    main()
