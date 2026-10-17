// Halftone: draws public-domain art as a field of dots, the way Droppy draws its renaissance hands.
// Each layer samples an image into a grid of values (0..1); a dot's area follows its value. Dots ripple in from an
// origin the first time the canvas is seen, and swell softly under the pointer. Nothing redraws while nothing moves.

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const finePointer = matchMedia("(hover: hover) and (pointer: fine)").matches;

const loaded = new Map();
export function loadImage(src) {
  if (!loaded.has(src)) {
    // One retry: a dropped request should cost a moment, not the art.
    const attempt = (tries) => new Promise((resolve, reject) => {
      const img = new Image();
      img.decoding = "async";
      img.onload = () => resolve(img);
      img.onerror = () => (tries > 0 ? setTimeout(() => attempt(tries - 1).then(resolve, reject), 400) : reject(new Error(`Could not load ${src}`)));
      img.src = tries < 1 ? `${src}?retry` : src;
    });
    loaded.set(src, attempt(1));
  }
  return loaded.get(src);
}

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const easeOut = (t) => 1 - Math.pow(1 - t, 3);
export const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a)); return t * t * (3 - 2 * t); };

// Pre-rendered dots, one per radius step, so a frame is a few thousand drawImage calls instead of arc paths.
function makeSprites(color, maxR, steps, dpr) {
  const size = Math.ceil(maxR * 2 * dpr) + 2;
  const sheet = document.createElement("canvas");
  sheet.width = size * steps;
  sheet.height = size;
  const g = sheet.getContext("2d");
  g.fillStyle = color;
  for (let i = 0; i < steps; i++) {
    const r = ((i + 1) / steps) * maxR * dpr;
    g.beginPath();
    g.arc(i * size + size / 2, size / 2, r, 0, Math.PI * 2);
    g.fill();
  }
  return { sheet, size };
}

export class Halftone {
  /**
   * canvas: the target canvas (sized by CSS).
   * layers: [{ img, place(W, H) -> {x, y, w, h}, value(r, g, b, u, v, x, y, W, H) -> 0..1 }], u/v are 0..1 inside
   * the image and x/y are canvas coordinates, for masks that belong to the layout rather than the picture.
   * opts: { cell, color, maxRatio, origin(W, H) -> {x, y}, pointer, ripple, gamma }
   */
  constructor(canvas, layers, opts = {}) {
    this.canvas = canvas;
    this.layers = layers;
    this.o = Object.assign({ cell: 6, color: "#d9f6e6", maxRatio: 0.62, pointer: finePointer, ripple: 1100, steps: 20 }, opts);
    this.ctx = canvas.getContext("2d");
    this.pointer = { x: -1e4, y: -1e4, sx: -1e4, sy: -1e4, inside: false, power: 0 };
    this.start = 0;
    this.started = false;
    this.raf = 0;
    this.visible = false;
    this.resize();
    new ResizeObserver(() => { this.resize(); this.paint(performance.now()); }).observe(canvas);
    new IntersectionObserver(([e]) => {
      this.visible = e.isIntersecting;
      if (this.visible && !this.started) this.play();
      if (this.visible) this.kick();
    }, { rootMargin: "120px" }).observe(canvas);
    if (this.o.pointer) this.bindPointer();
  }

  resize() {
    const r = this.canvas.getBoundingClientRect();
    if (!r.width || !r.height) return;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    this.dpr = dpr;
    this.W = r.width;
    this.H = r.height;
    this.canvas.width = Math.round(r.width * dpr);
    this.canvas.height = Math.round(r.height * dpr);
    const cell = typeof this.o.cell === "function" ? this.o.cell(r.width) : this.o.cell;
    this.cell = cell;
    this.cols = Math.ceil(r.width / cell) + 1;
    this.rows = Math.ceil(r.height / cell) + 1;
    this.maxR = cell * this.o.maxRatio;
    this.sprites = makeSprites(this.o.color, this.maxR, this.o.steps, dpr);
    this.sample();
  }

  // Draw each layer at grid resolution and read its pixels back once. The grid keeps the strongest layer per cell.
  sample() {
    const { cols, rows, cell } = this;
    const field = new Float32Array(cols * rows);
    const off = document.createElement("canvas");
    off.width = cols;
    off.height = rows;
    const g = off.getContext("2d", { willReadFrequently: true });
    for (const layer of this.layers) {
      const p = layer.place(this.W, this.H);
      g.clearRect(0, 0, cols, rows);
      g.drawImage(layer.img, p.x / cell, p.y / cell, p.w / cell, p.h / cell);
      const data = g.getImageData(0, 0, cols, rows).data;
      for (let j = 0; j < rows; j++) {
        for (let i = 0; i < cols; i++) {
          const k = j * cols + i;
          if (data[k * 4 + 3] < 8) continue;
          const u = (i * cell - p.x) / p.w;
          const v = (j * cell - p.y) / p.h;
          const val = layer.value(data[k * 4], data[k * 4 + 1], data[k * 4 + 2], u, v, i * cell, j * cell, this.W, this.H);
          if (val > field[k]) field[k] = val;
        }
      }
    }
    this.field = field;
    const origin = this.o.origin ? this.o.origin(this.W, this.H) : { x: this.W / 2, y: this.H / 2 };
    this.origin = origin;
    this.farthest = Math.hypot(Math.max(origin.x, this.W - origin.x), Math.max(origin.y, this.H - origin.y));
  }

  play() {
    this.started = true;
    this.start = performance.now();
    this.kick();
  }

  bindPointer() {
    const host = this.o.pointerHost || this.canvas.parentElement;
    host.addEventListener("pointermove", (e) => {
      const r = this.canvas.getBoundingClientRect();
      this.pointer.x = e.clientX - r.left;
      this.pointer.y = e.clientY - r.top;
      if (!this.pointer.inside) { this.pointer.sx = this.pointer.x; this.pointer.sy = this.pointer.y; }
      this.pointer.inside = true;
      this.kick();
    });
    host.addEventListener("pointerleave", () => { this.pointer.inside = false; this.kick(); });
  }

  kick() {
    if (!this.raf && this.visible) this.raf = requestAnimationFrame((t) => this.frame(t));
  }

  frame(now) {
    this.raf = 0;
    const p = this.pointer;
    // The swell follows the pointer through a soft spring, so it trails like something with weight.
    p.sx += (p.x - p.sx) * 0.16;
    p.sy += (p.y - p.sy) * 0.16;
    p.power += ((p.inside ? 1 : 0) - p.power) * 0.1;
    const rippling = !reduceMotion && now - this.start < this.o.ripple + 900;
    const settling = p.power > 0.004 || (p.inside && Math.hypot(p.x - p.sx, p.y - p.sy) > 0.5);
    this.paint(now);
    if (this.visible && (rippling || settling)) this.kick();
  }

  paint(now) {
    if (!this.field) return;
    const { ctx, cols, rows, cell, field, dpr, origin, farthest } = this;
    const { sheet, size } = this.sprites;
    const steps = this.o.steps;
    const p = this.pointer;
    const sigma2 = 2 * Math.pow(this.o.reach || 110, 2);
    const elapsed = reduceMotion || !this.started ? (this.started ? 1e9 : 0) : now - this.start;
    const ripple = this.o.ripple;
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    for (let j = 0; j < rows; j++) {
      const y = j * cell;
      for (let i = 0; i < cols; i++) {
        let v = field[j * cols + i];
        if (v < 0.02) continue;
        const x = i * cell;
        // The ripple: each dot waits for a wave that leaves the origin, then grows in over 700 ms.
        const d = Math.hypot(x - origin.x, y - origin.y) / farthest;
        const t = clamp((elapsed - d * ripple) / 700);
        if (t <= 0) continue;
        let s = Math.sqrt(v) * easeOut(t);
        if (p.power > 0.004) {
          const dd = (x - p.sx) * (x - p.sx) + (y - p.sy) * (y - p.sy);
          s *= 1 + 0.75 * p.power * Math.exp(-dd / sigma2);
        }
        const idx = Math.min(steps - 1, Math.round(s * (steps - 1)));
        if (idx < 0) continue;
        ctx.drawImage(sheet, idx * size, 0, size, size, x * dpr - size / 2, y * dpr - size / 2, size, size);
      }
    }
  }
}

// Shared value functions --------------------------------------------------------------------------------------------

export const lum = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

// Rodin's Thinker, photographed against sky: drop sky and cloud, keep the bronze as a bright dot body.
export function thinkerValue(r, g, b, u, v) {
  if (u < 0.17 || u > 0.83 || v < 0.06 || v > 0.95) return 0;
  const L = lum(r, g, b);
  const chroma = Math.max(r, g, b) - Math.min(r, g, b);
  const sky = (b > g + 12 && b > r + 26) || (L > 160 && chroma < 46);
  if (sky) return 0;
  // A tree sits behind the left knee and a building at the right foot; the crop above and these edges keep them out.
  if (u < 0.26 && v > 0.74) return 0;
  const body = 0.16 + 0.84 * Math.pow(clamp((L - 22) / 125), 1.15);
  const fadeBottom = 1 - smooth(0.8, 0.95, v);
  return body * fadeBottom;
}

// Friedrich's sea of fog: bright fog becomes dots, the wanderer and his rocks stay as dark silhouette.
export function fogValue(r, g, b, u, v) {
  const L = lum(r, g, b);
  return Math.pow(clamp((L - 95) / 140), 1.35);
}

// Dürer's engraving: lit paper becomes dots, the cut lines stay as gaps.
export function engravingValue(r, g, b) {
  const L = lum(r, g, b);
  return Math.pow(clamp((L - 105) / 135), 1.9);
}

// Fit helpers: cover or contain an image into a box, anchored by ax/ay (0..1).
export function fit(img, box, mode = "cover", ax = 0.5, ay = 0.5) {
  const s = mode === "cover"
    ? Math.max(box.w / img.naturalWidth, box.h / img.naturalHeight)
    : Math.min(box.w / img.naturalWidth, box.h / img.naturalHeight);
  const w = img.naturalWidth * s;
  const h = img.naturalHeight * s;
  return { x: box.x + (box.w - w) * ax, y: box.y + (box.h - h) * ay, w, h };
}
