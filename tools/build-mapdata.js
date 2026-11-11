#!/usr/bin/env node
/*
 * Regenerates ../mapdata.js (the embedded basemap for the south-western Cape).
 *
 * Usage:
 *   node --max-old-space-size=4096 tools/build-mapdata.js <path-to-package-or-geojson> [out.js]
 *
 * <path> is either an unpacked @geo-maps package directory (containing
 * map.geo.json) or the .geo.json file itself. Built against
 * @geo-maps/earth-lands-10m@0.6.0 (OSM-derived land polygons, 10 m resolution).
 * No dependencies beyond node itself.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const BBOX = [17.75, -34.90, 20.10, -33.20]; // west, south, east, north
const TOLERANCE = 0.0008;   // Douglas-Peucker tolerance, degrees (~80 m)
const MIN_AREA_KM2 = 0.02;  // drop rings smaller than this...
const KEEP_POINTS = [[18.37, -33.80]]; // ...unless they contain one of these (Robben Island)
const DECIMALS = 4;

const LABELS = [
  { name: 'Cape Town', lat: -33.925, lon: 18.424, kind: 'town' },
  { name: 'Stellenbosch', lat: -33.934, lon: 18.861, kind: 'town' },
  { name: 'Franschhoek', lat: -33.912, lon: 19.120, kind: 'town' },
  { name: 'Paarl', lat: -33.734, lon: 18.962, kind: 'town' },
  { name: "Simon's Town", lat: -34.193, lon: 18.435, kind: 'town' },
  { name: 'Hout Bay', lat: -34.045, lon: 18.354, kind: 'town' },
  { name: 'Somerset West', lat: -34.080, lon: 18.850, kind: 'town' },
  { name: 'Hermanus', lat: -34.418, lon: 19.235, kind: 'town' },
  { name: 'False Bay', lat: -34.22, lon: 18.66, kind: 'water' },
  { name: 'Table Bay', lat: -33.86, lon: 18.44, kind: 'water' },
  { name: 'Atlantic Ocean', lat: -34.15, lon: 18.05, kind: 'water' },
  { name: 'Cape Point', lat: -34.357, lon: 18.497, kind: 'landmark' },
  { name: 'Table Mountain', lat: -33.963, lon: 18.410, kind: 'landmark' },
];

const ATTRIBUTION = 'Land data © OpenStreetMap contributors (ODbL), via geo-maps';

// ---------- helpers ----------
function ringBBoxIntersects(ring) {
  let w = Infinity, s = Infinity, e = -Infinity, n = -Infinity;
  for (const [x, y] of ring) {
    if (x < w) w = x; if (x > e) e = x; if (y < s) s = y; if (y > n) n = y;
  }
  return !(e < BBOX[0] || w > BBOX[2] || n < BBOX[1] || s > BBOX[3]);
}

// Sutherland-Hodgman clip of one ring against the bbox rectangle.
function clipRing(ring) {
  const edges = [
    { inside: p => p[0] >= BBOX[0], cross: (a, b) => lerpX(a, b, BBOX[0]) },
    { inside: p => p[0] <= BBOX[2], cross: (a, b) => lerpX(a, b, BBOX[2]) },
    { inside: p => p[1] >= BBOX[1], cross: (a, b) => lerpY(a, b, BBOX[1]) },
    { inside: p => p[1] <= BBOX[3], cross: (a, b) => lerpY(a, b, BBOX[3]) },
  ];
  let out = ring;
  for (const edge of edges) {
    const input = out;
    out = [];
    if (!input.length) break;
    let prev = input[input.length - 1];
    for (const cur of input) {
      const ci = edge.inside(cur), pi = edge.inside(prev);
      if (ci) {
        if (!pi) out.push(edge.cross(prev, cur));
        out.push(cur);
      } else if (pi) {
        out.push(edge.cross(prev, cur));
      }
      prev = cur;
    }
  }
  return out;
}
function lerpX(a, b, x) { const t = (x - a[0]) / (b[0] - a[0]); return [x, a[1] + t * (b[1] - a[1])]; }
function lerpY(a, b, y) { const t = (y - a[1]) / (b[1] - a[1]); return [a[0] + t * (b[0] - a[0]), y]; }

function perpDist(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const len2 = dx * dx + dy * dy;
  if (len2 === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
  let t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}
// Iterative Douglas-Peucker on an open polyline (keeps both ends).
function dp(pts, tol) {
  const n = pts.length;
  if (n < 3) return pts.slice();
  const keep = new Uint8Array(n);
  keep[0] = keep[n - 1] = 1;
  const stack = [[0, n - 1]];
  while (stack.length) {
    const [i, j] = stack.pop();
    let maxD = -1, idx = -1;
    for (let k = i + 1; k < j; k++) {
      const d = perpDist(pts[k], pts[i], pts[j]);
      if (d > maxD) { maxD = d; idx = k; }
    }
    if (maxD > tol) { keep[idx] = 1; stack.push([i, idx], [idx, j]); }
  }
  return pts.filter((_, k) => keep[k]);
}
// Closed ring: split at the first point and the point farthest from it.
function simplifyRing(ring, tol) {
  if (ring.length < 4) return ring;
  let far = 0, fd = -1;
  for (let k = 1; k < ring.length; k++) {
    const d = Math.hypot(ring[k][0] - ring[0][0], ring[k][1] - ring[0][1]);
    if (d > fd) { fd = d; far = k; }
  }
  const a = dp(ring.slice(0, far + 1), tol);
  const b = dp(ring.slice(far).concat([ring[0]]), tol);
  return a.slice(0, -1).concat(b.slice(0, -1));
}

function areaKm2(ring) {
  let s = 0;
  const latMid = ring.reduce((t, p) => t + p[1], 0) / ring.length;
  const kx = 111.32 * Math.cos(latMid * Math.PI / 180), ky = 110.57;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    s += (ring[j][0] * kx) * (ring[i][1] * ky) - (ring[i][0] * kx) * (ring[j][1] * ky);
  }
  return Math.abs(s) / 2;
}
function pointInRing(pt, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i], [xj, yj] = ring[j];
    if ((yi > pt[1]) !== (yj > pt[1]) && pt[0] < (xj - xi) * (pt[1] - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
function round(v) { const f = 10 ** DECIMALS; return Math.round(v * f) / f; }
function cleanRing(ring) {
  const out = [];
  for (const p of ring) {
    const q = [round(p[0]), round(p[1])];
    const last = out[out.length - 1];
    if (!last || last[0] !== q[0] || last[1] !== q[1]) out.push(q);
  }
  while (out.length > 1 && out[0][0] === out[out.length - 1][0] && out[0][1] === out[out.length - 1][1]) out.pop();
  return out;
}

// ---------- main ----------
function main() {
  const src = process.argv[2];
  if (!src) { console.error('usage: build-mapdata.js <package-dir|map.geo.json> [out.js]'); process.exit(1); }
  const file = fs.statSync(src).isDirectory() ? path.join(src, 'map.geo.json') : src;
  const outFile = process.argv[3] || path.join(__dirname, '..', 'mapdata.js');

  console.error('reading', file);
  const gj = JSON.parse(fs.readFileSync(file, 'utf8'));
  const geoms = gj.type === 'GeometryCollection' ? gj.geometries
    : gj.type === 'FeatureCollection' ? gj.features.map(f => f.geometry)
    : [gj.type === 'Feature' ? gj.geometry : gj];

  const outers = [];
  for (const g of geoms) {
    if (!g) continue;
    const polys = g.type === 'Polygon' ? [g.coordinates] : g.type === 'MultiPolygon' ? g.coordinates : [];
    for (const poly of polys) if (poly[0] && ringBBoxIntersects(poly[0])) outers.push(poly[0]); // holes ignored
  }
  console.error('outer rings touching bbox:', outers.length);

  const land = [];
  let dropped = 0;
  for (let ring of outers) {
    if (ring.length > 1 && ring[0][0] === ring[ring.length - 1][0] && ring[0][1] === ring[ring.length - 1][1]) ring = ring.slice(0, -1);
    let r = clipRing(ring);
    if (r.length < 3) continue;
    const keep = KEEP_POINTS.some(p => pointInRing(p, r));
    if (!keep && areaKm2(r) < MIN_AREA_KM2) { dropped++; continue; }
    r = cleanRing(simplifyRing(r, TOLERANCE));
    if (r.length < 3) { dropped++; continue; }
    land.push(r);
  }
  land.sort((a, b) => b.length - a.length);
  const pts = land.reduce((t, r) => t + r.length, 0);
  console.error(`rings: ${land.length}, points: ${pts}, dropped small: ${dropped}`);

  // Label sanity check (report only; labels are never moved).
  const onLand = p => land.some(r => pointInRing([p.lon, p.lat], r));
  let fails = 0;
  for (const l of LABELS) {
    const want = l.kind === 'water' ? false : true;
    const got = onLand(l);
    const ok = got === want;
    if (!ok) fails++;
    console.error(`${ok ? 'OK  ' : 'FAIL'} ${l.kind.padEnd(8)} ${l.name.padEnd(15)} ${got ? 'land' : 'water'}`);
  }
  console.error(fails ? `${fails} label(s) failed the check` : 'all labels pass');

  const ringStr = r => '[' + r.map(p => `[${p[0]},${p[1]}]`).join(',') + ']';
  const labelStr = l => `    { name: ${JSON.stringify(l.name)}, lat: ${l.lat}, lon: ${l.lon}, kind: ${JSON.stringify(l.kind)} }`;
  const js = `// Generated by tools/build-mapdata.js from @geo-maps/earth-lands-10m@0.6.0 - do not edit by hand.
// Land data (c) OpenStreetMap contributors, ODbL 1.0.
window.TJ = window.TJ || {};
TJ.basemap = {
  bbox: [${BBOX.join(', ')}],
  land: [
${land.map(r => '    ' + ringStr(r)).join(',\n')}
  ],
  labels: [
${LABELS.map(labelStr).join(',\n')}
  ],
  attribution: ${JSON.stringify(ATTRIBUTION)}
};
`;
  fs.writeFileSync(outFile, js);
  console.error('wrote', outFile, fs.statSync(outFile).size, 'bytes');
}

main();
