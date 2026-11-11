// Browser tests for map.js. Run: node tests/map.test.js
// Serves the repo with a tiny static server plus a virtual test page, and drives Chromium
// through Playwright on a touch-enabled phone viewport.
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "..");
const SHOT_DIR = "/tmp/claude-0/-home-user-bf2-commander/5e89a918-1199-50b7-ae51-8b9101fb4853/scratchpad/map-agent";
const TYPES = { ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".html": "text/html; charset=utf-8" };
const CSP = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'";

const THEMES = {
  light: "--sea:#cfe0e8;--land:#f3efe6;--coast:#9db3bd;--ink:#1f2328;--muted:#6b7177;--paper:#ffffff;--accent:#2f6f7e;--rose:#c2455a;--line:#d5d2ca;--surface:#fbfaf7;",
  dark: "--sea:#122229;--land:#252a2e;--coast:#3f5761;--ink:#e8e6e1;--muted:#9aa0a5;--paper:#15181b;--accent:#5fb0c2;--rose:#e0697d;--line:#3a3f44;--surface:#1d2125;",
};

const BASEMAP = {
  bbox: [17.75, -34.9, 20.1, -33.2],
  land: [
    // rough mainland east of the Cape Flats
    [[18.3, -33.2], [20.1, -33.2], [20.1, -34.6], [19.6, -34.75], [19.3, -34.6], [19.0, -34.35], [18.82, -34.1],
      [18.6, -34.08], [18.47, -33.97], [18.43, -33.9], [18.36, -33.6], [18.3, -33.2]],
    // rough Cape Peninsula
    [[18.47, -33.97], [18.52, -34.08], [18.47, -34.36], [18.37, -34.12], [18.32, -33.99], [18.38, -33.91], [18.47, -33.97]],
  ],
  labels: [
    { name: "Cape Town", lat: -33.925, lon: 18.424, kind: "town" },
    { name: "Stellenbosch", lat: -33.932, lon: 18.86, kind: "town" },
    { name: "Franschhoek", lat: -33.912, lon: 19.121, kind: "town" },
    { name: "Paarl", lat: -33.727, lon: 18.957, kind: "town" },
    { name: "Somerset West", lat: -34.08, lon: 18.85, kind: "town" },
    { name: "False Bay", lat: -34.22, lon: 18.68, kind: "water" },
    { name: "Atlantic Ocean", lat: -33.85, lon: 18.05, kind: "water" },
    { name: "Table Mountain", lat: -33.963, lon: 18.403, kind: "landmark" },
  ],
  attribution: "Test data",
};

const PINS = [
  { id: "a", name: "Cape Town", lat: -33.925, lng: 18.424, number: 1 },
  { id: "b", name: "Stellenbosch", lat: -33.932, lng: 18.86, number: 2 },
  { id: "c", name: "Franschhoek", lat: -33.912, lng: 19.121, number: 3 },
  { id: "d", name: "Hermanus", lat: -34.418, lng: 19.235, number: 4 },
  { id: "e", name: "Cape Point", lat: -34.357, lng: 18.497, number: 5 },
];

function testPage(theme, withBasemap) {
  return `<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>map test</title>
<style>
:root{${THEMES[theme]}--sans:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;--serif:Georgia,"Times New Roman",serif;}
html,body{margin:0;background:#888;}
#wrap{position:absolute;left:15px;top:20px;}
#map{width:360px;height:480px;}
</style>
<link rel=stylesheet href="/map.css">
<div id=wrap><div id=map></div></div>
<script>window.TJ = {}; ${withBasemap ? "TJ.basemap = " + JSON.stringify(BASEMAP) + ";" : ""}</script>
<script src="/map.js"></script>
<script>
window.calls = [];
window.PINS = ${JSON.stringify(PINS)};
window.map = TJ.createMap(document.getElementById("map"), {
  onSelect: (id) => calls.push(["select", id]),
  onPlace: (lat, lng) => calls.push(["place", lat, lng]),
});
map.setData({ pins: PINS, selectedId: null });
</script>`;
}

function startServer() {
  const server = http.createServer((req, res) => {
    const u = new URL(req.url, "http://x");
    if (u.pathname === "/__map__.html") {
      res.writeHead(200, { "Content-Type": TYPES[".html"], "Content-Security-Policy": CSP });
      return res.end(testPage(u.searchParams.get("theme") || "light", u.searchParams.get("basemap") !== "0"));
    }
    const file = path.join(ROOT, decodeURIComponent(u.pathname));
    if (!file.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
      res.end(data);
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

let failures = 0;
async function check(name, fn) {
  try {
    await fn();
    console.log("PASS " + name);
  } catch (e) {
    failures++;
    console.log("FAIL " + name + "\n     " + (e && e.message ? e.message : e));
  }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
function near(a, b, tol, msg) { assert(Math.abs(a - b) <= tol, `${msg}: ${a.toFixed(2)} vs ${b.toFixed(2)} (tol ${tol})`); }

async function frames(page) {
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
}
async function pinPositions(page) {
  await frames(page);
  return page.evaluate(() => {
    const out = {};
    document.querySelectorAll(".tjmap-pin").forEach((g) => {
      const r = g.querySelector(".tjmap-pin-dot").getBoundingClientRect();
      out[g.dataset.id] = { x: r.left + r.width / 2, y: r.top + r.height / 2, d: r.width };
    });
    return out;
  });
}
async function box(page) {
  return page.evaluate(() => {
    const r = document.getElementById("map").getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, w: r.width, h: r.height };
  });
}
async function calls(page) { return page.evaluate(() => window.calls.splice(0)); }
function dist(p, q) { return Math.hypot(p.x - q.x, p.y - q.y); }
function allInside(pos, b) {
  return Object.entries(pos).every(([, p]) => p.x >= b.left && p.x <= b.right && p.y >= b.top && p.y <= b.bottom);
}
// An empty map point (no pin within 40 px), searched on a grid inside the container.
function emptyPoint(pos, b) {
  for (let y = b.top + 30; y < b.bottom - 30; y += 20) {
    for (let x = b.left + 30; x < b.right - 70; x += 20) {
      if (Object.values(pos).every((p) => Math.hypot(p.x - x, p.y - y) > 40)) return { x, y };
    }
  }
  throw new Error("no empty point found");
}
async function mouseDrag(page, from, dx, dy) {
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  for (let i = 1; i <= 8; i++) await page.mouse.move(from.x + (dx * i) / 8, from.y + (dy * i) / 8);
  await page.mouse.up();
}

(async () => {
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  const server = await startServer();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2, reducedMotion: "reduce",
  });
  const errors = [];
  const external = [];
  context.on("request", (r) => { if (!r.url().startsWith(base)) external.push(r.url()); });

  const page = await context.newPage();
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  await page.goto(base + "/__map__.html");
  await frames(page);
  const cdp = await context.newCDPSession(page);
  const b = await box(page);

  await check("pins render with their numbers and aria labels", async () => {
    const info = await page.evaluate(() => [...document.querySelectorAll(".tjmap-pin")].map((g) => ({
      id: g.dataset.id, num: g.querySelector(".tjmap-pin-num").textContent, label: g.getAttribute("aria-label"),
      tab: g.getAttribute("tabindex"), role: g.getAttribute("role"),
    })));
    assert(info.length === 5, "expected 5 pins, got " + info.length);
    const a = info.find((p) => p.id === "a");
    assert(a.num === "1" && a.label === "1. Cape Town" && a.tab === "0" && a.role === "button", JSON.stringify(a));
    const pos = await pinPositions(page);
    near(pos.a.d, 26, 1.5, "pin diameter");
  });

  await check("land path, labels, attribution and controls exist", async () => {
    const r = await page.evaluate(() => ({
      d: document.querySelector(".tjmap-land").getAttribute("d").length,
      attr: document.querySelector(".tjmap-attr").textContent,
      btns: [...document.querySelectorAll(".tjmap-controls button")].map((x) => [x.type, x.getAttribute("aria-label"), x.offsetWidth, x.offsetHeight]),
      touch: getComputedStyle(document.querySelector(".tjmap-svg")).touchAction,
      cls: document.getElementById("map").className,
    }));
    assert(r.d > 50, "land path empty");
    assert(r.attr === "Test data", "attribution " + r.attr);
    assert(r.btns.length === 3 && r.btns.every((x) => x[0] === "button" && x[1] && x[2] >= 44 && x[3] >= 44), JSON.stringify(r.btns));
    assert(r.touch === "none", "touch-action " + r.touch);
    assert(/\btjmap\b/.test(r.cls), "container class");
  });

  await check("fit() on first setData shows all pins inside the container", async () => {
    const pos = await pinPositions(page);
    assert(allInside(pos, b), JSON.stringify(pos));
  });

  await check("minor towns hidden when zoomed far out, key towns kept", async () => {
    const vis = await page.evaluate(() => Object.fromEntries([...document.querySelectorAll(".tjmap-label")].map((g) =>
      [g.textContent, g.style.display !== "none"])));
    assert(vis["Paarl"] === false && vis["Somerset West"] === false, JSON.stringify(vis));
    assert(vis["False Bay"] === true, "water label should show " + JSON.stringify(vis));
  });

  await check("clicking a pin calls onSelect(id)", async () => {
    const pos = await pinPositions(page);
    await page.mouse.click(pos.b.x, pos.b.y);
    const c = await calls(page);
    assert(c.length === 1 && c[0][0] === "select" && c[0][1] === "b", JSON.stringify(c));
  });

  await check("tapping a pin (touch) calls onSelect(id)", async () => {
    const pos = await pinPositions(page);
    await page.touchscreen.tap(pos.d.x, pos.d.y);
    const c = await calls(page);
    assert(c.length === 1 && c[0][1] === "d", JSON.stringify(c));
  });

  await check("clicking empty map calls onSelect(null)", async () => {
    await page.waitForTimeout(350);
    const pos = await pinPositions(page);
    const p = emptyPoint(pos, b);
    await page.mouse.click(p.x, p.y);
    const c = await calls(page);
    assert(c.length === 1 && c[0][0] === "select" && c[0][1] === null, JSON.stringify(c));
  });

  await check("selected pin is larger, on top and shows its name chip", async () => {
    await page.evaluate(() => map.setData({ pins: PINS, selectedId: "a" }));
    const pos = await pinPositions(page);
    near(pos.a.d, 34, 1.5, "selected diameter");
    const r = await page.evaluate(() => {
      const g = document.querySelector('.tjmap-pin[data-id="a"]');
      return { last: g.parentNode.lastElementChild === g, chip: g.querySelector(".tjmap-chip").style.display !== "none",
        text: g.querySelector(".tjmap-chip-text").textContent };
    });
    assert(r.last && r.chip && r.text === "Cape Town", JSON.stringify(r));
  });

  await check("mouse drag pans by the drag delta and does not select", async () => {
    await page.waitForTimeout(350);
    const before = await pinPositions(page);
    const p = emptyPoint(before, b);
    await mouseDrag(page, p, 60, 40);
    const after = await pinPositions(page);
    for (const id of Object.keys(before)) {
      near(after[id].x - before[id].x, 60, 1.5, "dx " + id);
      near(after[id].y - before[id].y, 40, 1.5, "dy " + id);
    }
    const c = await calls(page);
    assert(c.length === 0, "unexpected calls " + JSON.stringify(c));
  });

  await check("touch drag pans and does not select (even starting on a pin)", async () => {
    const before = await pinPositions(page);
    const s = before.c;
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: s.x, y: s.y, id: 1 }] });
    for (let i = 1; i <= 6; i++) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: s.x - 8 * i, y: s.y + 5 * i, id: 1 }] });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    const after = await pinPositions(page);
    near(after.a.x - before.a.x, -48, 1.5, "dx");
    near(after.a.y - before.a.y, 30, 1.5, "dy");
    const c = await calls(page);
    assert(c.length === 0, "unexpected calls " + JSON.stringify(c));
  });

  await check("setData again after panning keeps the view", async () => {
    const before = await pinPositions(page);
    await page.evaluate(() => map.setData({ pins: PINS.map((p) => ({ ...p })), selectedId: "b" }));
    const after = await pinPositions(page);
    for (const id of Object.keys(before)) near(dist(before[id], after[id]), 0, 0.5, "moved " + id);
  });

  await check("wheel zoom keeps the point under the cursor fixed", async () => {
    await page.evaluate(() => map.fit());
    const before = await pinPositions(page);
    const cur = { x: b.left + 140, y: b.top + 200 };
    await page.mouse.move(cur.x, cur.y);
    await page.mouse.wheel(0, -240);
    const after = await pinPositions(page);
    const f = dist(after.a, after.c) / dist(before.a, before.c);
    assert(f > 1.2, "zoom factor " + f);
    for (const id of Object.keys(before)) {
      near(after[id].x, cur.x + (before[id].x - cur.x) * f, 2, "x " + id);
      near(after[id].y, cur.y + (before[id].y - cur.y) * f, 2, "y " + id);
    }
    const c = await calls(page);
    assert(c.length === 0, "unexpected calls " + JSON.stringify(c));
  });

  await check("two-finger pinch zooms around the pinch centre", async () => {
    await page.evaluate(() => map.fit());
    const before = await pinPositions(page);
    const c0 = { x: b.left + 170, y: b.top + 240 };
    const pts = (h) => [{ x: c0.x - h, y: c0.y, id: 1 }, { x: c0.x + h, y: c0.y, id: 2 }];
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: pts(30) });
    for (let h = 40; h <= 75; h += 5) await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: pts(h) });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    const after = await pinPositions(page);
    const f = dist(after.a, after.c) / dist(before.a, before.c);
    near(f, 2.5, 0.15, "pinch factor");
    for (const id of Object.keys(before)) {
      near(after[id].x, c0.x + (before[id].x - c0.x) * f, 2.5, "x " + id);
      near(after[id].y, c0.y + (before[id].y - c0.y) * f, 2.5, "y " + id);
    }
    const c = await calls(page);
    assert(c.length === 0, "unexpected calls " + JSON.stringify(c));
  });

  await check("double-tap zooms in", async () => {
    await page.evaluate(() => map.fit());
    await page.waitForTimeout(350);
    const before = await pinPositions(page);
    const p = emptyPoint(before, b);
    await page.touchscreen.tap(p.x, p.y);
    await page.waitForTimeout(60);
    await page.touchscreen.tap(p.x, p.y);
    const after = await pinPositions(page);
    const f = dist(after.a, after.c) / dist(before.a, before.c);
    near(f, 2, 0.05, "double-tap factor");
    await page.waitForTimeout(350);
    await calls(page);
  });

  await check("zoom buttons and Fit work", async () => {
    await page.evaluate(() => map.fit());
    const p0 = await pinPositions(page);
    await page.click('button[aria-label="Zoom in"]');
    const p1 = await pinPositions(page);
    near(dist(p1.a, p1.c) / dist(p0.a, p0.c), 2, 0.02, "zoom in factor");
    await page.click('button[aria-label="Zoom out"]');
    const p2 = await pinPositions(page);
    near(dist(p2.a, p2.c) / dist(p0.a, p0.c), 1, 0.02, "zoom out factor");
    await mouseDrag(page, emptyPoint(p2, b), 120, 0);
    await page.click('button[aria-label="Zoom in"]');
    await page.click('button[aria-label="Zoom in"]');
    const p3 = await pinPositions(page);
    assert(!allInside(p3, b), "pins should be off-screen before Fit");
    await page.click('button[aria-label="Show all places"]');
    const p4 = await pinPositions(page);
    assert(allInside(p4, b), "Fit should show all pins " + JSON.stringify(p4));
    const c = await calls(page);
    assert(c.length === 0, "buttons should not select " + JSON.stringify(c));
  });

  await check("placing mode: tap calls onPlace with the tapped coordinate, not onSelect", async () => {
    await page.evaluate(() => map.fit());
    await page.click('button[aria-label="Zoom in"]');
    await page.evaluate(() => map.setPlacing(true));
    const cursor = await page.evaluate(() => getComputedStyle(document.querySelector(".tjmap-svg")).cursor);
    assert(cursor === "crosshair", "cursor " + cursor);
    const pos = await pinPositions(page);
    const t = emptyPoint(pos, b);
    await page.touchscreen.tap(t.x, t.y);
    const c = await calls(page);
    assert(c.length === 1 && c[0][0] === "place", JSON.stringify(c));
    const [, lat, lng] = c[0];
    assert(String(lat).split(".")[1].length <= 5 && String(lng).split(".")[1].length <= 5, "5 decimals: " + lat + "," + lng);
    assert(lat > -34.9 && lat < -33.2 && lng > 17.75 && lng < 20.1, "inside bbox");
    await page.evaluate(([lat, lng]) => {
      map.setPlacing(false);
      map.setData({ pins: PINS.concat([{ id: "new", name: "New place", lat, lng, number: 6 }]), selectedId: null });
    }, [lat, lng]);
    const after = await pinPositions(page);
    near(dist(after.new, t), 0, 2, "placed pin vs tap");
  });

  await check("placing mode: tapping a pin places instead of selecting; drag does not place", async () => {
    await page.evaluate(() => map.setPlacing(true));
    const pos = await pinPositions(page);
    const onScreen = Object.keys(pos).find((id) => pos[id].x > b.left + 20 && pos[id].x < b.right - 70 && pos[id].y > b.top + 20 && pos[id].y < b.bottom - 20);
    assert(onScreen, "no pin on screen");
    await page.touchscreen.tap(pos[onScreen].x, pos[onScreen].y);
    let c = await calls(page);
    assert(c.length === 1 && c[0][0] === "place", JSON.stringify(c));
    await mouseDrag(page, emptyPoint(pos, b), 30, 30);
    c = await calls(page);
    assert(c.length === 0, "drag placed: " + JSON.stringify(c));
    await page.evaluate(() => { map.setPlacing(false); map.setData({ pins: PINS, selectedId: null }); });
  });

  await check("focus(id) centres the pin and separates it from neighbours", async () => {
    await page.evaluate(() => map.focus("b"));
    const pos = await pinPositions(page);
    near(pos.b.x, b.left + b.w / 2, 2, "x");
    near(pos.b.y, b.top + b.h / 2, 2, "y");
    const others = Object.keys(pos).filter((id) => id !== "b").map((id) => dist(pos[id], pos.b));
    assert(Math.min(...others) >= 70, "nearest " + Math.min(...others));
  });

  await check("keyboard: Enter on a focused pin selects it", async () => {
    await page.focus('.tjmap-pin[data-id="c"]');
    await page.keyboard.press("Enter");
    const c = await calls(page);
    assert(c.length === 1 && c[0][1] === "c", JSON.stringify(c));
  });

  await check("zoom and pan are clamped", async () => {
    await page.evaluate(() => map.fit());
    const p0 = await pinPositions(page);
    await page.mouse.move(b.left + 180, b.top + 240);
    for (let i = 0; i < 30; i++) await page.mouse.wheel(0, 400);
    const p1 = await pinPositions(page);
    const out = dist(p1.a, p1.c) / dist(p0.a, p0.c);
    assert(out > 0.3, "zoomed out too far: " + out);
    for (let i = 0; i < 80; i++) await page.mouse.wheel(0, -400);
    const p2 = await pinPositions(page);
    // a-c is ~58 km; at ~300 m per 360 px that is ~70,000 px. Must be capped near there.
    const ac = dist(p2.a, p2.c);
    assert(ac > 30000 && ac < 120000, "max zoom distance " + ac);
    await page.evaluate(() => map.fit());
    for (let i = 0; i < 6; i++) await mouseDrag(page, { x: b.left + 20, y: b.top + 200 }, 300, 0);
    const land = await page.evaluate(() => document.querySelector(".tjmap-land").getBoundingClientRect().toJSON());
    assert(land.right > b.left && land.left < b.right, "view panned off the map " + JSON.stringify(land));
    await calls(page);
  });

  await check("setData with 0 pins works and fit() shows the basemap", async () => {
    await page.evaluate(() => { map.setData({ pins: [], selectedId: null }); map.fit(); });
    await frames(page);
    const r = await page.evaluate(() => ({
      n: document.querySelectorAll(".tjmap-pin").length,
      land: document.querySelector(".tjmap-land").getBoundingClientRect().toJSON(),
    }));
    assert(r.n === 0, "pins left: " + r.n);
    assert(r.land.width > 100 && r.land.left >= b.left - 2 && r.land.right <= b.right + 2, JSON.stringify(r.land));
    await page.evaluate(() => map.setData({ pins: PINS, selectedId: null }));
  });

  await check("animated fit (no reduced motion) settles with all pins visible", async () => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.click('button[aria-label="Zoom in"]');
    await page.waitForTimeout(400);
    await page.click('button[aria-label="Zoom in"]');
    await page.waitForTimeout(400);
    await page.evaluate(() => map.fit());
    await page.waitForTimeout(60);
    const mid = await pinPositions(page);
    await page.waitForTimeout(400);
    const end = await pinPositions(page);
    assert(allInside(end, b), "after animation");
    assert(dist(mid.a, end.a) > 1, "fit should animate");
    await page.emulateMedia({ reducedMotion: "reduce" });
  });

  await check("resize() re-lays out and keeps pins on screen after Fit", async () => {
    await page.evaluate(() => { document.getElementById("map").style.height = "300px"; map.resize(); map.fit(); });
    const b2 = await box(page);
    const pos = await pinPositions(page);
    assert(b2.h === 300 && allInside(pos, b2), JSON.stringify(pos));
    await page.evaluate(() => { document.getElementById("map").style.height = "480px"; map.resize(); map.fit(); });
  });

  await page.evaluate(() => map.setData({ pins: PINS, selectedId: "b" }));
  await frames(page);
  await page.locator("#map").screenshot({ path: path.join(SHOT_DIR, "map-light.png") });

  await check("destroy() removes the map", async () => {
    await page.evaluate(() => map.destroy());
    const n = await page.evaluate(() => document.getElementById("map").children.length);
    assert(n === 0, "children left " + n);
  });

  // Dark theme screenshot
  const dark = await context.newPage();
  dark.on("pageerror", (e) => errors.push(e.message));
  await dark.goto(base + "/__map__.html?theme=dark");
  await dark.evaluate(() => map.setData({ pins: PINS, selectedId: "e" }));
  await frames(dark);
  await dark.locator("#map").screenshot({ path: path.join(SHOT_DIR, "map-dark.png") });
  await dark.close();

  // No basemap
  const bare = await context.newPage();
  bare.on("pageerror", (e) => errors.push(e.message));
  await bare.goto(base + "/__map__.html?basemap=0");
  await check("works with TJ.basemap undefined (fitted to pins, no land)", async () => {
    const bb = await box(bare);
    const pos = await pinPositions(bare);
    assert(Object.keys(pos).length === 5 && allInside(pos, bb), JSON.stringify(pos));
    const r = await bare.evaluate(() => ({
      d: document.querySelector(".tjmap-land").getAttribute("d"),
      attrHidden: document.querySelector(".tjmap-attr").hidden,
      bg: getComputedStyle(document.querySelector(".tjmap-svg")).backgroundColor,
    }));
    assert(!r.d && r.attrHidden, JSON.stringify(r));
    assert(r.bg === "rgb(207, 224, 232)", "sea background " + r.bg);
    await bare.screenshot({ path: path.join(SHOT_DIR, "map-nobasemap.png"), clip: { x: 15, y: 20, width: 360, height: 480 } });
    await bare.mouse.click(pos.c.x, pos.c.y);
    const c = await calls(bare);
    assert(c.length === 1 && c[0][1] === "c", JSON.stringify(c));
    await bare.evaluate(() => map.setData({ pins: [], selectedId: null }));
    await bare.evaluate(() => map.fit());
    await frames(bare);
  });
  await bare.close();

  await check("no page errors and no external requests", async () => {
    assert(errors.length === 0, errors.join("\n"));
    assert(external.length === 0, external.join("\n"));
  });

  await browser.close();
  server.close();
  console.log(failures ? `\n${failures} check(s) failed` : "\nAll checks passed");
  console.log("Screenshots: " + SHOT_DIR);
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
