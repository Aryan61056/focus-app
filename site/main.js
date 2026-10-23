import { Halftone, loadImage, fit, smooth, thinkerValue, fogValue, engravingValue } from "./halftone.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));

/* Reveal ----------------------------------------------------------------------------------------------------------- */
// The hero copy plays once on load; everything else plays once as it scrolls in.
requestAnimationFrame(() => requestAnimationFrame(() => $$("[data-reveal-load]").forEach((el) => el.classList.add("is-in"))));
const revealer = new IntersectionObserver((entries) => {
  for (const e of entries) if (e.isIntersecting) { e.target.classList.add("is-in"); revealer.unobserve(e.target); }
}, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
$$(".reveal:not([data-reveal-load])").forEach((el) => revealer.observe(el));

/* Nav: tone follows the section under the notch -------------------------------------------------------------------- */
const nav = $(".nav");
const pill = $(".nav__pill");
const toned = $$("[data-tone]").filter((el) => el !== nav);
const navLinks = $$(".nav__link");
let navQueued = false;
function updateNav() {
  navQueued = false;
  const probe = 34;
  for (const el of toned) {
    const r = el.getBoundingClientRect();
    if (r.top <= probe && r.bottom > probe) { nav.dataset.tone = el.dataset.tone; break; }
  }
  const mid = innerHeight * 0.4;
  let current = null;
  for (const a of navLinks) {
    const target = $(a.getAttribute("href"));
    if (!target) continue;
    const r = target.getBoundingClientRect();
    if (r.top <= mid && r.bottom > mid) current = a;
  }
  navLinks.forEach((a) => a.classList.toggle("is-active", a === current));
}
addEventListener("scroll", () => { if (!navQueued) { navQueued = true; requestAnimationFrame(updateNav); } }, { passive: true });
updateNav();

const menu = $(".nav__menu");
menu.addEventListener("click", () => {
  const open = !pill.classList.contains("is-open");
  pill.classList.toggle("is-open", open);
  menu.setAttribute("aria-expanded", String(open));
});
navLinks.forEach((a) => a.addEventListener("click", () => { pill.classList.remove("is-open"); menu.setAttribute("aria-expanded", "false"); }));

/* Halftone art ----------------------------------------------------------------------------------------------------- */
const ART = { thinker: "assets/art/thinker.jpg", jerome: "assets/art/jerome.jpg", wanderer: "assets/art/wanderer.jpg" };
const VALUE = { thinker: thinkerValue, jerome: engravingValue, wanderer: fogValue };

async function heroArt() {
  const canvas = $(".hero__art");
  const icon = $(".hero__icon");
  const [thinker, wanderer] = await Promise.all([loadImage(ART.thinker), loadImage(ART.wanderer)]);
  const iconCenter = () => {
    const c = canvas.getBoundingClientRect();
    const r = icon.getBoundingClientRect();
    return { x: r.left - c.left + r.width / 2, y: r.top - c.top + r.height / 2 };
  };
  // Keep the bottom of the art quiet where the headline sits.
  const textFade = (y, H) => (1 - smooth(H * 0.42, H * 0.74, y)) * smooth(10, 90, y);
  new Halftone(canvas, [
    {
      // The Thinker sits left of the icon, looking down at it.
      img: thinker,
      place: (W, H) => {
        const h = Math.min(H * 1.02, W * 1.2);
        const w = h * (thinker.naturalWidth / thinker.naturalHeight);
        const head = W < 700 ? W * 0.5 - W * 0.18 : W * 0.5 - Math.min(290, W * 0.2);
        return { x: head - 0.66 * w, y: -H * 0.02, w, h };
      },
      value: (r, g, b, u, v, x, y, W, H) => thinkerValue(r, g, b, u, v) * textFade(y, H) * (W < 700 ? 0.7 : 1),
    },
    {
      // Friedrich's fog drifts in from the right; the wanderer stays a dark figure inside it.
      img: wanderer,
      place: (W, H) => fit(wanderer, { x: W * 0.5, y: -H * 0.12, w: W * 0.62, h: H * 1.2 }, "cover", 0.4, 0.4),
      value: (r, g, b, u, v, x, y, W, H) =>
        fogValue(r, g, b) * 0.9 * smooth(W * 0.56, W * 0.74, x) * textFade(y, H) * (1 - smooth(0.9, 1, u)),
    },
  ], {
    cell: (w) => (w > 900 ? 6 : 4.5),
    origin: iconCenter,
    pointerHost: $(".hero"),
    ripple: 1300,
  });
}

async function roomArt() {
  const canvas = $(".room__art");
  const jerome = await loadImage(ART.jerome);
  new Halftone(canvas, [{
    img: jerome,
    place: (W, H) => {
      const h = H * 1.04;
      const w = h * (jerome.naturalWidth / jerome.naturalHeight);
      return W < 760 ? fit(jerome, { x: 0, y: 0, w: W, h: H }, "cover", 0.5, 0.5) : { x: W - w * 0.98, y: -H * 0.02, w, h };
    },
    value: (r, g, b, u, v, x, y, W) => engravingValue(r, g, b) * smooth(0.02, 0.2, u) * (W < 760 ? 0.18 : smooth(W * 0.42, W * 0.66, x)),
  }], { cell: (w) => (w > 900 ? 6 : 4.5), origin: (W, H) => ({ x: W * 0.8, y: H * 0.45 }), pointerHost: $(".room"), ripple: 1400 });
}

async function footerArt() {
  const canvas = $(".footer__art");
  const wanderer = await loadImage(ART.wanderer);
  new Halftone(canvas, [{
    img: wanderer,
    // Only the fog bank left of the wanderer: the painting is drawn wide and anchored left so he stays out of frame.
    place: (W, H) => fit(wanderer, { x: 0, y: -H * 0.3, w: Math.max(W * 2.2, 1400), h: H * 1.4 }, "cover", 0, 0.45),
    value: (r, g, b, u, v, x, y, W, H) => fogValue(r, g, b) * (1 - smooth(0.34, 0.4, u)) * smooth(40, 210, y) * (1 - smooth(H * 0.52, H * 0.72, y)),
  }], { cell: 5, origin: (W) => ({ x: W / 2, y: 0 }), pointer: false, ripple: 1600 });
}

async function boxArt(box) {
  const name = box.dataset.art;
  const img = await loadImage(ART[name]);
  const canvas = document.createElement("canvas");
  canvas.className = "art__canvas";
  canvas.setAttribute("aria-hidden", "true");
  box.prepend(canvas);
  const ax = parseFloat(box.dataset.ax || "0.5");
  const ay = parseFloat(box.dataset.ay || "0.5");
  // Cards show a crop of the art, so draw the picture larger than the card and anchor the interesting part.
  const contain = box.dataset.fit === "contain";
  new Halftone(canvas, [{
    img,
    place: (W, H) => contain
      ? fit(img, { x: 0, y: H * 0.06, w: W, h: H * 1.05 }, "contain", ax, ay)
      : fit(img, { x: -W * 0.15, y: -H * 0.15, w: W * 1.3, h: H * 1.3 }, "cover", ax, ay),
    value: (r, g, b, u, v) => VALUE[name](r, g, b, u, v) * (name === "wanderer" ? 0.62 : 0.85),
  }], { cell: 5.5, origin: (W, H) => ({ x: W * 0.5, y: H }), ripple: 900, reach: 80 });
}

// If art fails to load, the section keeps its plain green ground.
const quiet = () => {};
heroArt().catch(quiet);
roomArt().catch(quiet);
footerArt().catch(quiet);
$$(".art[data-art]").forEach((box) => boxArt(box).catch(quiet));

/* Island: the notch demo ------------------------------------------------------------------------------------------- */
// The notch springs use the app's own Motion tokens (Tokens.swift): open = response 0.38, damping 0.8.
class Spring {
  constructor(value, { response = 0.38, damping = 0.8 } = {}) {
    this.x = value; this.v = 0; this.target = value;
    this.k = Math.pow((2 * Math.PI) / response, 2);
    this.c = (4 * Math.PI * damping) / response;
  }
  set(target, config) {
    this.target = target;
    if (config) { this.k = Math.pow((2 * Math.PI) / config.response, 2); this.c = (4 * Math.PI * config.damping) / config.response; }
  }
  step(dt) {
    const h = 1 / 240;
    for (let t = 0; t < dt; t += h) {
      const a = -this.k * (this.x - this.target) - this.c * this.v;
      this.v += a * h;
      this.x += this.v * h;
    }
    return Math.abs(this.x - this.target) > 0.05 || Math.abs(this.v) > 0.05;
  }
  jump(v) { this.x = this.target = v; this.v = 0; }
}

const island = $("#island");
const mac = $(".mac", island);
const notch = $(".notch", island);
const winBody = $("[data-win-body]", island);
const winTitle = $("[data-win-title]", island);
const readText = $("[data-read]", island);
const callEl = $("[data-call]", island);
const caption = $("[data-caption]", island);
const stepBtns = $$(".steps button", island);
const islandPlay = $(".island .playpause");

winBody.innerHTML = `
  <div class="win-view" data-view="notes">
    <h4>Calc homework</h4>
    <p class="win-math">∫ x·eˣ dx = x·eˣ − eˣ + C</p>
    <div class="win-line" style="width:92%"></div><div class="win-line" style="width:78%"></div><div class="win-line" style="width:85%"></div><div class="win-line" style="width:40%"></div>
  </div>
  <div class="win-view" data-view="mail">
    <h4>Inbox</h4>
    <div class="win-mail">${Array.from({ length: 4 }, (_, i) => `<div><b></b><div style="flex:1"><div class="win-line" style="width:${50 + i * 9}%;margin-bottom:6px"></div><div class="win-line" style="width:${80 - i * 7}%;margin:0;opacity:.6"></div></div></div>`).join("")}</div>
  </div>
  <div class="win-view" data-view="video">
    <h4>Watch</h4>
    <div class="win-grid">${"<span></span>".repeat(6)}</div>
  </div>`;
const views = Object.fromEntries($$(".win-view", winBody).map((v) => [v.dataset.view, v]));

const STEPS = [
  { view: "notes", title: "Calc homework", ring: "on", notch: "rest", read: "Notes, “Calc homework”. Shares words with your task.", call: "On task", tone: "on",
    caption: "The ring is closed. You are on task, so Hushd says nothing.", hold: 3800 },
  { view: "mail", title: "Inbox", ring: "unsure", notch: "rest", read: "Mail, “Inbox”. Could go either way.", call: "Not sure", tone: "unsure",
    caption: "A dashed ring means not sure. Not sure does nothing.", hold: 3800 },
  { view: "video", title: "Watch", ring: "drift", notch: "peek", read: "Two checks agree this is away from your task.", call: "Drifting", tone: "drift",
    caption: "The ring opens a gap and the color drains slowly. Hushd waits to see if the drift lasts.", hold: 4200 },
  { view: "video", title: "Watch", ring: "drift", notch: "open", read: "The drift lasted. Time for a nudge.", call: "Drifting", tone: "drift",
    caption: "Still away, so the notch opens. It asks about your task, never about where you went.", hold: 4800 },
  { view: "notes", title: "Calc homework", ring: "on", notch: "rest", read: "Notes, “Calc homework”. Back on your task.", call: "On task", tone: "on",
    caption: "Back on task. The notch tucks away and the ring closes.", hold: 3600 },
];

const OPEN = { response: 0.38, damping: 0.8 };
const CLOSE = { response: 0.32, damping: 0.86 };
const PEEK = { response: 0.24, damping: 0.78 };
const springW = new Spring(300, OPEN);
const springH = new Spring(34, OPEN);
const springR = new Spring(14, OPEN);
let springRaf = 0;
let last = 0;

function notchSize(mode) {
  const stageW = mac.clientWidth;
  const small = stageW < 620;
  const rest = Math.min(300, stageW * 0.56);
  if (mode === "open") return { w: Math.min(stageW - 24, 580), h: small ? 128 : 136, r: 30 };
  if (mode === "peek") return { w: Math.min(stageW - 24, rest + 96), h: 38, r: 16 };
  return { w: rest, h: 34, r: 14 };
}

function animateNotch(mode) {
  const s = notchSize(mode);
  const cfg = mode === "open" ? OPEN : mode === "peek" ? PEEK : CLOSE;
  if (reduceMotion) {
    springW.jump(s.w); springH.jump(s.h); springR.jump(s.r);
    paintNotch();
    return;
  }
  springW.set(s.w, cfg); springH.set(s.h, cfg); springR.set(s.r, cfg);
  if (!springRaf) { last = performance.now(); springRaf = requestAnimationFrame(tickNotch); }
}
function paintNotch() {
  notch.style.width = `${springW.x.toFixed(2)}px`;
  notch.style.height = `${springH.x.toFixed(2)}px`;
  notch.style.borderRadius = `0 0 ${springR.x.toFixed(2)}px ${springR.x.toFixed(2)}px`;
}
function tickNotch(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  const moving = [springW.step(dt), springH.step(dt), springR.step(dt)].some(Boolean);
  paintNotch();
  springRaf = moving ? requestAnimationFrame(tickNotch) : 0;
}

// Text swaps cross-fade through a little blur, so two states never sit on top of each other.
function swapText(el, text) {
  if (el.textContent === text) return;
  if (reduceMotion) { el.textContent = text; return; }
  el.classList.add("is-swapping");
  setTimeout(() => { el.textContent = text; el.classList.remove("is-swapping"); }, 200);
}

const thumb = document.createElement("span");
thumb.className = "steps__thumb";
thumb.setAttribute("aria-hidden", "true");
$(".steps", island).prepend(thumb);
function placeThumb(btn) {
  const li = btn.parentElement;
  thumb.style.width = `${btn.offsetWidth}px`;
  thumb.style.transform = `translateX(${li.offsetLeft}px)`;
}

let step = 0;
function go(i) {
  step = i;
  const s = STEPS[i];
  mac.dataset.step = String(i);
  mac.dataset.ring = s.ring;
  notch.dataset.open = String(s.notch === "open");
  notch.dataset.peek = String(s.notch === "peek");
  notch.dataset.ring = s.ring;
  for (const [k, v] of Object.entries(views)) v.classList.toggle("is-on", k === s.view);
  swapText(winTitle, s.title);
  swapText(readText, s.read);
  swapText(callEl, s.call);
  callEl.dataset.tone = s.tone;
  swapText(caption, s.caption);
  stepBtns.forEach((b, j) => { b.setAttribute("aria-selected", String(j === i)); b.tabIndex = j === i ? 0 : -1; });
  placeThumb(stepBtns[i]);
  animateNotch(s.notch);
  schedule();
}

let playing = !reduceMotion;
let islandVisible = false;
let timer = 0;
function schedule() {
  clearTimeout(timer);
  if (playing && islandVisible) timer = setTimeout(() => go((step + 1) % STEPS.length), STEPS[step].hold);
}
function setPlaying(p) {
  playing = p;
  islandPlay.dataset.playing = String(p);
  islandPlay.setAttribute("aria-label", p ? "Pause the story" : "Play the story");
  schedule();
}
islandPlay.addEventListener("click", () => setPlaying(!playing));
islandPlay.dataset.playing = String(playing);
stepBtns.forEach((b, i) => {
  b.addEventListener("click", () => { setPlaying(false); go(i); });
  b.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    const n = (i + (e.key === "ArrowRight" ? 1 : -1) + STEPS.length) % STEPS.length;
    setPlaying(false); go(n); stepBtns[n].focus();
  });
});
$(".notch__back", island).addEventListener("click", () => go(4));

new IntersectionObserver(([e]) => { islandVisible = e.isIntersecting; schedule(); }, { threshold: 0.35 }).observe(mac);
addEventListener("resize", () => { animateNotch(STEPS[step].notch); placeThumb(stepBtns[step]); });
go(0);

// The clock ticks only while the demo is on screen.
const clock = $("[data-clock]", island);
let seconds = 24 * 60 + 10;
setInterval(() => {
  if (!islandVisible || document.hidden) return;
  seconds++;
  clock.textContent = `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}, 1000);

/* Carousel --------------------------------------------------------------------------------------------------------- */
const rail = $("[data-rail]");
const track = $("[data-track]", rail);
const slides = $$(".slide", track);
const pager = $("[data-pager]", rail);
const railPlay = $("[data-rail-play]", rail);
const SLIDE_MS = 5200;
rail.style.setProperty("--slide-ms", `${SLIDE_MS}ms`);
const dots = slides.map((s, i) => {
  const b = document.createElement("button");
  b.type = "button";
  b.setAttribute("role", "tab");
  b.setAttribute("aria-label", `Slide ${i + 1} of ${slides.length}`);
  b.innerHTML = "<i></i>";
  b.addEventListener("click", () => { toSlide(i); restartRail(); });
  pager.append(b);
  return b;
});
let current = -1;
function markSlide(i) {
  if (i === current) return;
  current = i;
  slides.forEach((s, j) => s.classList.toggle("is-current", j === i));
  dots.forEach((d, j) => {
    d.setAttribute("aria-selected", String(j === i));
    // Restart the progress fill on the new dot.
    const fill = d.firstChild;
    fill.style.animation = "none";
    void fill.offsetWidth;
    fill.style.animation = "";
  });
}
function slideLeft(i) { return slides[i].offsetLeft - slides[0].offsetLeft; }
function toSlide(i) { track.scrollTo({ left: slideLeft(i), behavior: reduceMotion ? "auto" : "smooth" }); markSlide(i); }
let railQueued = false;
track.addEventListener("scroll", () => {
  if (railQueued) return;
  railQueued = true;
  requestAnimationFrame(() => {
    railQueued = false;
    const x = track.scrollLeft;
    let best = 0;
    slides.forEach((s, i) => { if (Math.abs(slideLeft(i) - x) < Math.abs(slideLeft(best) - x)) best = i; });
    // At the far end the last slide may never reach the snap start; count it as current there.
    if (x + track.clientWidth >= track.scrollWidth - 4) best = slides.length - 1;
    markSlide(best);
  });
}, { passive: true });

let railPlaying = !reduceMotion;
let railHover = false;
let railVisible = false;
let railTimer = 0;
function restartRail() {
  clearTimeout(railTimer);
  const paused = !railPlaying || railHover || !railVisible;
  rail.dataset.paused = String(paused);
  if (!paused) railTimer = setTimeout(() => { toSlide((current + 1) % slides.length); restartRail(); }, SLIDE_MS);
}
railPlay.dataset.playing = String(railPlaying);
railPlay.addEventListener("click", () => {
  railPlaying = !railPlaying;
  railPlay.dataset.playing = String(railPlaying);
  railPlay.setAttribute("aria-label", railPlaying ? "Pause the slides" : "Play the slides");
  restartRail();
});
track.addEventListener("pointerenter", () => { railHover = true; restartRail(); });
track.addEventListener("pointerleave", () => { railHover = false; restartRail(); });
track.addEventListener("focusin", () => { railHover = true; restartRail(); });
track.addEventListener("focusout", () => { railHover = false; restartRail(); });
new IntersectionObserver(([e]) => { railVisible = e.isIntersecting; restartRail(); }, { threshold: 0.4 }).observe(track);
markSlide(0);

/* Promise cards and FAQ: explanations one click away --------------------------------------------------------------- */
$$(".pcard").forEach((card) => {
  const btn = $(".pcard__more", card);
  const detail = $(".pcard__detail", card);
  detail.setAttribute("aria-hidden", "true");
  btn.addEventListener("click", () => {
    const open = !card.classList.contains("is-open");
    card.classList.toggle("is-open", open);
    btn.setAttribute("aria-expanded", String(open));
    detail.setAttribute("aria-hidden", String(!open));
  });
});
$$(".q").forEach((q) => {
  const btn = $("button", q);
  btn.addEventListener("click", () => {
    const open = !q.classList.contains("is-open");
    q.classList.toggle("is-open", open);
    btn.setAttribute("aria-expanded", String(open));
  });
});

/* Word scroll: the sentence lights up word by word as you scroll through it ---------------------------------------- */
const ws = $(".wordscroll");
const words = [];
$$("[data-wordsplit]", ws).forEach((p) => {
  const parts = p.textContent.trim().split(/\s+/);
  p.textContent = "";
  parts.forEach((w, i) => {
    const span = document.createElement("span");
    span.className = "ws-word";
    span.textContent = w;
    p.append(span);
    if (i < parts.length - 1) p.append(" ");
    words.push(span);
  });
});
if (reduceMotion) ws.classList.add("ws-static");
else {
  let wsQueued = false;
  const lit = new Array(words.length).fill(-1);
  const paintWords = () => {
    wsQueued = false;
    const r = ws.getBoundingClientRect();
    const p = clamp(-r.top / (r.height - innerHeight));
    const t = p * (words.length + 3) - 1;
    words.forEach((w, i) => {
      const o = Math.round((0.16 + 0.84 * clamp(t - i)) * 100) / 100;
      if (o !== lit[i]) { lit[i] = o; w.style.setProperty("--o", o); }
    });
  };
  addEventListener("scroll", () => { if (!wsQueued) { wsQueued = true; requestAnimationFrame(paintWords); } }, { passive: true });
  paintWords();
}
