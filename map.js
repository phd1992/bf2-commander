// Pan/zoom SVG map for the travel journal. No libraries, no network.
// Usage: var map = TJ.createMap(container, { onSelect: fn(id|null), onPlace: fn(lat, lng) });
// Basemap (optional): window.TJ.basemap = { bbox:[w,s,e,n], land:[[[lon,lat],...],...], labels:[...], attribution }
(function () {
  "use strict";
  var TJ = (window.TJ = window.TJ || {});
  var NS = "http://www.w3.org/2000/svg";

  var TAP_SLOP = 6;              // px of movement that turns a tap into a drag
  var DOUBLE_TAP_MS = 300;
  var DOUBLE_TAP_PX = 30;
  var PIN_R = 13;                // ~26 px pin
  var SEL_R = 17;                // ~34 px selected pin
  var CROWD_PX = 70;             // show a pin's name only if no other pin is this close
  var M_PER_DEG = 111320;
  var MAX_SPAN_M = 300;          // max zoom: ~300 m across the viewport
  var FAR_OUT_SPAN = 0.5;        // world units (~55 km) across the viewport: hide minor towns
  var ANIM_MS = 250;
  var FIT_PAD = { l: 40, r: 64, t: 40, b: 40 }; // right side leaves room for the controls
  var KEEP_TOWNS = { "Cape Town": 1, "Stellenbosch": 1, "Franschhoek": 1 };
  var DEFAULT_CENTRE = { lat: -33.92, lon: 18.42 };

  function noop() {}
  function svgEl(name, attrs, parent) {
    var n = document.createElementNS(NS, name);
    if (attrs) for (var key in attrs) n.setAttribute(key, attrs[key]);
    if (parent) parent.appendChild(n);
    return n;
  }
  function htmlEl(name, cls, parent) {
    var n = document.createElement(name);
    if (cls) n.className = cls;
    if (parent) parent.appendChild(n);
    return n;
  }
  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
  function round5(v) { return Math.round(v * 1e5) / 1e5; }
  function fin(v) { return typeof v === "number" && isFinite(v); }
  function boxesHit(a, b) { return a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]; }
  function reducedMotion() {
    return !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  }
  function ease(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }

  TJ.createMap = function (container, opts) {
    opts = opts || {};
    var onSelect = typeof opts.onSelect === "function" ? opts.onSelect : noop;
    var onPlace = typeof opts.onPlace === "function" ? opts.onPlace : noop;

    // ---- projection state: world x = (lon - lon0) * k, world y = -(lat - lat0) (degrees of latitude)
    var lat0 = DEFAULT_CENTRE.lat, lon0 = DEFAULT_CENTRE.lon, k = Math.cos(lat0 * Math.PI / 180);
    var originKind = "default"; // "default" | "pins" | "basemap"
    var basemap = null;         // the TJ.basemap object that has been built
    var view = { cx: 0, cy: 0, s: 1 }; // world centre of the viewport, px per world unit
    var W = 0, H = 0;
    var pins = [], selectedId = null;
    var pinEls = new Map();     // id -> { g, dot, hit, num, chip, chipRect, chipText, name, w }
    var labelEls = [];          // basemap labels
    var fitted = false, interacted = false, placing = false, destroyed = false;
    var anim = 0, raf = 0;
    var measureCache = Object.create(null);

    // ---- DOM
    var addedClass = !container.classList.contains("tjmap");
    container.classList.add("tjmap");
    var svg = svgEl("svg", { class: "tjmap-svg", "aria-label": "Map", role: "group" });
    var landG = svgEl("g", { class: "tjmap-land-layer", "aria-hidden": "true" }, svg);
    var landPath = svgEl("path", { class: "tjmap-land", "vector-effect": "non-scaling-stroke" }, landG);
    var labelG = svgEl("g", { class: "tjmap-labels", "aria-hidden": "true" }, svg);
    var pinG = svgEl("g", { class: "tjmap-pins" }, svg);
    var measureText = svgEl("text", { class: "tjmap-measure", x: "-9999", y: "-9999", "aria-hidden": "true" }, svg);
    container.appendChild(svg);

    var attr = htmlEl("div", "tjmap-attr", container);
    attr.hidden = true;
    var controls = htmlEl("div", "tjmap-controls", container);
    function button(cls, label, text, fn) {
      var b = htmlEl("button", "tjmap-btn " + cls, controls);
      b.type = "button";
      b.setAttribute("aria-label", label);
      b.textContent = text;
      b.addEventListener("click", function (e) { e.preventDefault(); fn(); });
      return b;
    }
    button("tjmap-zoom-in", "Zoom in", "+", function () { zoomBy(2); });
    button("tjmap-zoom-out", "Zoom out", "−", function () { zoomBy(0.5); });
    button("tjmap-fit", "Show all places", "Fit", function () { fit(); });

    // ---- projection helpers
    function project(lat, lon) { return [(lon - lon0) * k, -(lat - lat0)]; }
    function unproject(x, y) { return { lat: lat0 - y, lon: lon0 + x / k }; }
    function toScreen(x, y, v) { v = v || view; return [(x - v.cx) * v.s + W / 2, (y - v.cy) * v.s + H / 2]; }
    function toWorld(sx, sy, v) { v = v || view; return [(sx - W / 2) / v.s + v.cx, (sy - H / 2) / v.s + v.cy]; }

    function setOrigin(lat, lon, kind) {
      var centre = unproject(view.cx, view.cy);
      lat0 = lat; lon0 = lon; k = Math.cos(lat * Math.PI / 180);
      originKind = kind;
      var c = project(centre.lat, centre.lon);
      view.cx = c[0]; view.cy = c[1];
    }

    function validPins() { return pins.filter(function (p) { return fin(p.lat) && fin(p.lng); }); }

    function pinBounds() {
      var vp = validPins();
      if (!vp.length) return null;
      var b = [Infinity, Infinity, -Infinity, -Infinity];
      vp.forEach(function (p) {
        var w = project(p.lat, p.lng);
        if (w[0] < b[0]) b[0] = w[0];
        if (w[1] < b[1]) b[1] = w[1];
        if (w[0] > b[2]) b[2] = w[0];
        if (w[1] > b[3]) b[3] = w[1];
      });
      return b;
    }
    function bboxWorld() {
      if (!basemap) return null;
      var bb = basemap.bbox; // [w, s, e, n]
      var a = project(bb[3], bb[0]), c = project(bb[1], bb[2]);
      return [a[0], a[1], c[0], c[1]];
    }
    // The area the view may show: basemap bbox united with the pins, at least ~1 degree across.
    function extent() {
      var e = bboxWorld(), p = pinBounds();
      if (e && p) e = [Math.min(e[0], p[0]), Math.min(e[1], p[1]), Math.max(e[2], p[2]), Math.max(e[3], p[3])];
      else e = e || p || [0, 0, 0, 0];
      var cx = (e[0] + e[2]) / 2, cy = (e[1] + e[3]) / 2;
      var hw = Math.max((e[2] - e[0]) / 2, 0.5), hh = Math.max((e[3] - e[1]) / 2, 0.5);
      if (!basemap) { hw += 0.25; hh += 0.25; }
      return [cx - hw, cy - hh, cx + hw, cy + hh];
    }
    function minScale() {
      var e = extent();
      return 0.9 * Math.min(W / (e[2] - e[0]), H / (e[3] - e[1]));
    }
    function maxScale() { return Math.max(W, 1) / (MAX_SPAN_M / M_PER_DEG); }
    function clampView(v) {
      var e = extent();
      var s = clamp(v.s, minScale(), maxScale());
      return { cx: clamp(v.cx, e[0], e[2]), cy: clamp(v.cy, e[1], e[3]), s: s };
    }

    // ---- basemap
    function ensureBasemap() {
      var bm = TJ.basemap;
      if (!bm || bm === basemap || !bm.bbox || bm.bbox.length !== 4) return;
      basemap = bm;
      var bb = bm.bbox;
      setOrigin((bb[1] + bb[3]) / 2, (bb[0] + bb[2]) / 2, "basemap");
      var parts = [];
      (bm.land || []).forEach(function (ring) {
        if (!ring || ring.length < 3) return;
        var s = "";
        for (var i = 0; i < ring.length; i++) {
          var w = project(ring[i][1], ring[i][0]);
          s += (i ? "L" : "M") + w[0].toFixed(5) + " " + w[1].toFixed(5);
        }
        parts.push(s + "Z");
      });
      landPath.setAttribute("d", parts.join(""));
      labelEls.forEach(function (l) { l.g.remove(); });
      labelEls = [];
      (bm.labels || []).forEach(function (lab) {
        if (!lab || !fin(lab.lat) || !fin(lab.lon) || !lab.name) return;
        var kind = lab.kind === "water" || lab.kind === "landmark" ? lab.kind : "town";
        var g = svgEl("g", { class: "tjmap-label tjmap-label-" + kind }, labelG);
        if (kind !== "water") svgEl("circle", { class: "tjmap-label-dot", r: kind === "town" ? 2 : 1.5 }, g);
        var t = svgEl("text", { class: "tjmap-label-text" }, g);
        t.textContent = lab.name;
        if (kind === "water") t.setAttribute("text-anchor", "middle");
        else { t.setAttribute("x", "5"); }
        t.setAttribute("y", kind === "water" ? "4" : "3.5");
        var w = project(lab.lat, lab.lon);
        labelEls.push({ g: g, text: t, kind: kind, name: lab.name, x: w[0], y: w[1], w: -1,
          prio: kind === "water" ? 0 : kind === "town" ? (KEEP_TOWNS[lab.name] ? 1 : 2) : 3 });
      });
      labelEls.sort(function (a, b) { return a.prio - b.prio; });
      if (bm.attribution) { attr.textContent = bm.attribution; attr.hidden = false; }
      else attr.hidden = true;
    }

    function measure(text, cls) {
      var key = cls + "|" + text;
      if (measureCache[key]) return measureCache[key];
      measureText.setAttribute("class", "tjmap-measure " + cls);
      measureText.textContent = text;
      var w = 0;
      try { w = measureText.getComputedTextLength(); } catch (e) { w = 0; }
      if (!(w > 0)) return text.length * 6.5; // not rendered yet: estimate, do not cache
      measureCache[key] = w;
      return w;
    }

    // ---- pins
    function buildPin(p) {
      var g = svgEl("g", { class: "tjmap-pin", tabindex: "0", role: "button" });
      var hit = svgEl("circle", { class: "tjmap-pin-hit", r: 22 }, g);
      var chip = svgEl("g", { class: "tjmap-chip" }, g);
      var chipRect = svgEl("rect", { class: "tjmap-chip-bg", rx: 4, height: 20, y: -10 }, chip);
      var chipText = svgEl("text", { class: "tjmap-chip-text", y: 0.5 }, chip);
      var dot = svgEl("circle", { class: "tjmap-pin-dot", r: PIN_R }, g);
      var num = svgEl("text", { class: "tjmap-pin-num", y: 0.5 }, g);
      var rec = { g: g, hit: hit, dot: dot, num: num, chip: chip, chipRect: chipRect, chipText: chipText, id: p.id, name: null, w: 0 };
      g.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " " || e.key === "Spacebar") {
          e.preventDefault();
          if (!placing) onSelect(rec.id);
        }
      });
      g.__tjmapId = p.id;
      g.setAttribute("data-id", String(p.id));
      return rec;
    }

    function syncPins() {
      var active = document.activeElement;
      var seen = new Set();
      var vp = validPins();
      vp.forEach(function (p) {
        seen.add(p.id);
        var rec = pinEls.get(p.id);
        if (!rec) { rec = buildPin(p); pinEls.set(p.id, rec); }
        var name = p.name == null ? "" : String(p.name);
        var number = p.number == null ? "" : String(p.number);
        rec.num.textContent = number;
        rec.g.setAttribute("aria-label", (number ? number + ". " : "") + name);
        if (rec.name !== name) { rec.name = name; rec.chipText.textContent = name; rec.w = -1; }
        var sel = p.id === selectedId;
        rec.g.classList.toggle("is-selected", sel);
        rec.dot.setAttribute("r", sel ? SEL_R : PIN_R);
        rec.lat = p.lat; rec.lng = p.lng; rec.sel = sel;
      });
      pinEls.forEach(function (rec, id) { if (!seen.has(id)) { rec.g.remove(); pinEls.delete(id); } });
      // DOM order: journal order, selected last (on top). Only move nodes that are out of place.
      var order = vp.map(function (p) { return pinEls.get(p.id); });
      order.sort(function (a, b) { return (a.sel ? 1 : 0) - (b.sel ? 1 : 0); });
      var refocus = null;
      order.forEach(function (rec, i) {
        if (pinG.childNodes[i] !== rec.g) {
          if (rec.g === active || rec.g.contains(active)) refocus = rec.g;
          pinG.insertBefore(rec.g, pinG.childNodes[i] || null);
        }
      });
      if (refocus) { try { refocus.focus({ preventScroll: true }); } catch (e) { /* ignore */ } }
    }

    // ---- rendering
    function schedule() {
      if (raf || destroyed) return;
      raf = requestAnimationFrame(function () { raf = 0; render(); });
    }

    function render() {
      if (destroyed || !W || !H) return;
      var tx = W / 2 - view.cx * view.s, ty = H / 2 - view.cy * view.s;
      landG.setAttribute("transform", "translate(" + tx.toFixed(2) + " " + ty.toFixed(2) + ") scale(" + view.s + ")");
      var occupied = layoutPins();
      layoutLabels(occupied);
    }

    function layoutPins() {
      var recs = [];
      pinEls.forEach(function (rec) {
        var w = project(rec.lat, rec.lng);
        var sp = toScreen(w[0], w[1]);
        rec.sx = sp[0]; rec.sy = sp[1];
        recs.push(rec);
      });
      var occupied = [];
      recs.forEach(function (rec) {
        var r = rec.sel ? SEL_R : PIN_R;
        rec.g.setAttribute("transform", "translate(" + rec.sx.toFixed(1) + " " + rec.sy.toFixed(1) + ")");
        rec.box = [rec.sx - r, rec.sy - r, rec.sx + r, rec.sy + r];
        occupied.push(rec.box);
      });
      // Keep chips and labels clear of the zoom controls (bottom-right).
      var ctrlBox = [W - 60, H - 160, W, H];
      var chips = [ctrlBox];
      // Selected pin's chip first so it always wins; then journal order.
      recs.slice().sort(function (a, b) { return (b.sel ? 1 : 0) - (a.sel ? 1 : 0); }).forEach(function (rec) {
        var r = rec.sel ? SEL_R : PIN_R;
        var show = rec.sel;
        if (!show && rec.name) {
          show = true;
          for (var i = 0; i < recs.length; i++) {
            var o = recs[i];
            if (o !== rec && Math.abs(o.sx - rec.sx) < CROWD_PX && Math.abs(o.sy - rec.sy) < CROWD_PX &&
                Math.hypot(o.sx - rec.sx, o.sy - rec.sy) < CROWD_PX) { show = false; break; }
          }
        }
        if (!rec.name) show = false;
        var x0 = 0, cw = 0;
        if (show) {
          if (rec.w < 0) rec.w = measure(rec.name, "tjmap-chip-text");
          cw = rec.w + 14;
          var sides = [r + 4, -r - 4 - cw];
          if (rec.sx + r + 4 + cw > W - 4 && rec.sx - r - 4 - cw >= 4) sides.reverse();
          var pick = null;
          for (var s = 0; s < 2 && pick === null; s++) {
            var cb = [rec.sx + sides[s], rec.sy - 10, rec.sx + sides[s] + cw, rec.sy + 10];
            var free = cb[0] >= 2 && cb[2] <= W - 2 && !boxesHit(cb, ctrlBox) && recs.every(function (o) { return o === rec || !boxesHit(cb, o.box); }) &&
              chips.every(function (c) { return !boxesHit(cb, c); });
            if (free) pick = sides[s];
          }
          if (pick === null) { if (rec.sel) pick = sides[0]; else show = false; }
          x0 = pick;
        }
        rec.chip.style.display = show ? "" : "none";
        if (!show) return;
        rec.chipRect.setAttribute("x", x0.toFixed(1));
        rec.chipRect.setAttribute("width", cw.toFixed(1));
        rec.chipText.setAttribute("x", (x0 + 7).toFixed(1));
        chips.push([rec.sx + x0, rec.sy - 10, rec.sx + x0 + cw, rec.sy + 10]);
      });
      return occupied.concat(chips);
    }

    function layoutLabels(occupied) {
      var farOut = W / view.s > FAR_OUT_SPAN;
      var placed = [];
      labelEls.forEach(function (l) {
        var sp = toScreen(l.x, l.y);
        var show = true, box;
        if (l.kind === "town" && farOut && !KEEP_TOWNS[l.name]) show = false;
        if (show) {
          if (l.w < 0) {
            var m = measure(l.name, "tjmap-label-" + l.kind);
            if (m) l.w = m;
          }
          var w = l.w > 0 ? l.w : l.name.length * 6;
          box = l.kind === "water"
            ? [sp[0] - w / 2 - 2, sp[1] - 9, sp[0] + w / 2 + 2, sp[1] + 7]
            : [sp[0] - 3, sp[1] - 8, sp[0] + 7 + w, sp[1] + 7];
          if (box[2] < 0 || box[0] > W || box[3] < 0 || box[1] > H) show = false;
        }
        if (show && l.kind !== "water") {
          for (var i = 0; i < occupied.length && show; i++) if (boxesHit(box, occupied[i])) show = false;
          for (var j = 0; j < placed.length && show; j++) if (boxesHit(box, placed[j])) show = false;
        }
        l.g.style.display = show ? "" : "none";
        if (show) {
          placed.push(box);
          l.g.setAttribute("transform", "translate(" + sp[0].toFixed(1) + " " + sp[1].toFixed(1) + ")");
        }
      });
    }

    // ---- view changes
    function setView(v) {
      var c = clampView(v);
      view.cx = c.cx; view.cy = c.cy; view.s = c.s;
      schedule();
    }
    function stopAnim() { if (anim) { cancelAnimationFrame(anim); anim = 0; } }
    function animateTo(target, instant) {
      stopAnim();
      target = clampView(target);
      if (instant || reducedMotion() || !W) { setView(target); return; }
      var from = { cx: view.cx, cy: view.cy, s: view.s };
      var t0 = performance.now();
      var ls0 = Math.log(from.s), ls1 = Math.log(target.s);
      // Interpolate so that the screen motion of the centre stays smooth while zooming.
      function step(now) {
        var t = Math.min(1, (now - t0) / ANIM_MS), e = ease(t);
        view.s = Math.exp(ls0 + (ls1 - ls0) * e);
        view.cx = from.cx + (target.cx - from.cx) * e;
        view.cy = from.cy + (target.cy - from.cy) * e;
        render();
        anim = t < 1 ? requestAnimationFrame(step) : 0;
      }
      anim = requestAnimationFrame(step);
    }
    // Zoom by factor f keeping screen point (sx, sy) fixed.
    function zoomAround(sx, sy, f, base) {
      base = base || view;
      var w = toWorld(sx, sy, base);
      var s = clamp(base.s * f, minScale(), maxScale());
      return { s: s, cx: w[0] - (sx - W / 2) / s, cy: w[1] - (sy - H / 2) / s };
    }
    function zoomBy(f) {
      if (!W) return;
      interacted = true;
      animateTo(zoomAround(W / 2, H / 2, f));
    }

    function fitTarget() {
      var b = pinBounds();
      if (!b) {
        var e = bboxWorld() || extent();
        var pad = 8;
        return { cx: (e[0] + e[2]) / 2, cy: (e[1] + e[3]) / 2,
          s: Math.min((W - 2 * pad) / (e[2] - e[0]), (H - 2 * pad) / (e[3] - e[1])) };
      }
      var aw = Math.max(W - FIT_PAD.l - FIT_PAD.r, 40), ah = Math.max(H - FIT_PAD.t - FIT_PAD.b, 40);
      var bw = b[2] - b[0], bh = b[3] - b[1];
      var s = Math.min(bw > 0 ? aw / bw : Infinity, bh > 0 ? ah / bh : Infinity);
      var single = W / (3000 / M_PER_DEG); // don't zoom closer than ~3 km across for a lone pin
      s = Math.min(s, single);
      var mx = (b[0] + b[2]) / 2, my = (b[1] + b[3]) / 2;
      var ox = FIT_PAD.l + aw / 2 - W / 2, oy = FIT_PAD.t + ah / 2 - H / 2;
      return { cx: mx - ox / s, cy: my - oy / s, s: s };
    }
    function fit(instant) {
      if (!W || !H) return;
      fitted = true;
      animateTo(fitTarget(), instant === true);
    }

    function focus(id) {
      var rec = pinEls.get(id);
      if (!rec || !W) return;
      interacted = true;
      var p = project(rec.lat, rec.lng);
      var nearest = Infinity;
      pinEls.forEach(function (o) {
        if (o === rec) return;
        var q = project(o.lat, o.lng);
        var d = Math.hypot(q[0] - p[0], q[1] - p[1]);
        if (d > 0 && d < nearest) nearest = d;
      });
      var s = view.s;
      if (nearest < Infinity) s = Math.max(s, (CROWD_PX + 20) / nearest);
      else s = Math.max(s, W / (8000 / M_PER_DEG));
      animateTo({ cx: p[0], cy: p[1], s: Math.min(s, maxScale()) });
    }

    // ---- size
    function measureSize() {
      var r = container.getBoundingClientRect();
      var nw = Math.round(r.width), nh = Math.round(r.height);
      if (nw === W && nh === H) return false;
      W = nw; H = nh;
      svg.setAttribute("viewBox", "0 0 " + Math.max(W, 1) + " " + Math.max(H, 1));
      return true;
    }
    function resize() {
      if (destroyed) return;
      ensureBasemap();
      measureSize();
      if (!W || !H) return;
      if (!fitted && dataSet) fit(true);
      else { setView(view); render(); }
    }
    var ro = typeof ResizeObserver === "function" ? new ResizeObserver(function () { resize(); }) : null;
    if (ro) ro.observe(container);

    // ---- data
    var dataSet = false;
    function setData(data) {
      if (destroyed) return;
      data = data || {};
      ensureBasemap();
      var hadPins = validPins().length > 0;
      pins = Array.isArray(data.pins) ? data.pins.slice() : [];
      selectedId = data.selectedId == null ? null : data.selectedId;
      var vp = validPins();
      if (!basemap && vp.length && originKind === "default") {
        var b = [Infinity, Infinity, -Infinity, -Infinity];
        vp.forEach(function (p) {
          b[0] = Math.min(b[0], p.lng); b[2] = Math.max(b[2], p.lng);
          b[1] = Math.min(b[1], p.lat); b[3] = Math.max(b[3], p.lat);
        });
        setOrigin((b[1] + b[3]) / 2, (b[0] + b[2]) / 2, "pins");
      }
      syncPins();
      dataSet = true;
      if (!W || !H) measureSize();
      if (!W || !H) return;
      // First data with a size fits; so does the first non-empty data if the user has not moved the map yet.
      if (!fitted || (!hadPins && vp.length && !interacted)) fit(true);
      else { setView(view); render(); }
    }

    // ---- pointer interaction
    var pointers = new Map(); // pointerId -> {x, y}
    var gesture = null;       // { x0, y0, moved, multi, pinId, pinchDist, pinchC }
    var lastTap = null;

    function localPoint(e) {
      var r = svg.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    }
    function pinIdFrom(target) {
      var n = target;
      while (n && n !== svg) { if (n.__tjmapId !== undefined) return { id: n.__tjmapId }; n = n.parentNode; }
      return null;
    }
    function pinchState() {
      var it = pointers.values(), a = it.next().value, b = it.next().value;
      return { c: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, d: Math.hypot(a.x - b.x, a.y - b.y) };
    }

    function onDown(e) {
      if (e.pointerType === "mouse" && e.button !== 0) return;
      stopAnim();
      var p = localPoint(e);
      try { svg.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
      pointers.set(e.pointerId, p);
      if (pointers.size === 1) {
        gesture = { x0: p.x, y0: p.y, moved: false, multi: false, pin: pinIdFrom(e.target), pinch: null };
      } else if (gesture) {
        gesture.multi = true;
        gesture.moved = true;
        if (pointers.size === 2) gesture.pinch = pinchState();
      }
    }
    function onMove(e) {
      var prev = pointers.get(e.pointerId);
      if (!prev || !gesture) return;
      var p = localPoint(e);
      pointers.set(e.pointerId, p);
      if (pointers.size === 1) {
        var dx, dy;
        if (!gesture.moved) {
          if (Math.hypot(p.x - gesture.x0, p.y - gesture.y0) <= TAP_SLOP) return;
          gesture.moved = true;
          interacted = true;
          svg.classList.add("tjmap-dragging");
          dx = p.x - gesture.x0; dy = p.y - gesture.y0;
        } else { dx = p.x - prev.x; dy = p.y - prev.y; }
        setView({ cx: view.cx - dx / view.s, cy: view.cy - dy / view.s, s: view.s });
      } else if (pointers.size >= 2 && gesture.pinch) {
        var st = pinchState(), last = gesture.pinch;
        var f = last.d > 0 && st.d > 0 ? st.d / last.d : 1;
        var w = toWorld(last.c.x, last.c.y);
        var s = clamp(view.s * f, minScale(), maxScale());
        interacted = true;
        setView({ s: s, cx: w[0] - (st.c.x - W / 2) / s, cy: w[1] - (st.c.y - H / 2) / s });
        gesture.pinch = st;
      }
    }
    function onUp(e) {
      if (!pointers.has(e.pointerId)) return;
      var p = localPoint(e);
      pointers.delete(e.pointerId);
      try { svg.releasePointerCapture(e.pointerId); } catch (err) { /* ignore */ }
      if (pointers.size >= 2 && gesture) { gesture.pinch = pinchState(); return; }
      if (pointers.size === 1 && gesture) { gesture.pinch = null; return; }
      var g = gesture;
      gesture = null;
      svg.classList.remove("tjmap-dragging");
      if (g && !g.moved && !g.multi && e.type === "pointerup") tap(p.x, p.y, g.pin);
    }

    function tap(x, y, pin) {
      var now = performance.now();
      if (placing) {
        lastTap = null;
        var w = toWorld(x, y), ll = unproject(w[0], w[1]);
        onPlace(round5(ll.lat), round5(ll.lon));
        return;
      }
      if (pin) { lastTap = null; onSelect(pin.id); return; }
      if (lastTap && now - lastTap.t < DOUBLE_TAP_MS && Math.hypot(x - lastTap.x, y - lastTap.y) < DOUBLE_TAP_PX) {
        lastTap = null;
        interacted = true;
        animateTo(zoomAround(x, y, 2));
        return;
      }
      lastTap = { t: now, x: x, y: y };
      onSelect(null);
    }

    function onWheel(e) {
      e.preventDefault();
      if (!W) return;
      stopAnim();
      var dy = e.deltaY * (e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? H : 1);
      var f = Math.exp(-dy * (e.ctrlKey ? 0.01 : 0.002));
      var p = localPoint(e);
      interacted = true;
      setView(zoomAround(p.x, p.y, f));
    }

    svg.addEventListener("pointerdown", onDown);
    svg.addEventListener("pointermove", onMove);
    svg.addEventListener("pointerup", onUp);
    svg.addEventListener("pointercancel", onUp);
    svg.addEventListener("lostpointercapture", function (e) { if (pointers.has(e.pointerId)) onUp(e); });
    svg.addEventListener("wheel", onWheel, { passive: false });
    svg.addEventListener("contextmenu", function (e) { if (gesture) e.preventDefault(); });

    function setPlacing(on) {
      placing = !!on;
      container.classList.toggle("tjmap-placing", placing);
      lastTap = null;
    }

    function destroy() {
      if (destroyed) return;
      destroyed = true;
      stopAnim();
      if (raf) cancelAnimationFrame(raf);
      if (ro) ro.disconnect();
      svg.remove(); attr.remove(); controls.remove();
      container.classList.remove("tjmap-placing");
      if (addedClass) container.classList.remove("tjmap");
      pinEls.clear();
    }

    ensureBasemap();
    measureSize();
    if (W && H) { var ft = fitTarget(); view.cx = ft.cx; view.cy = ft.cy; view.s = ft.s; schedule(); }

    return {
      setData: setData,
      fit: function () { interacted = true; fit(false); },
      focus: focus,
      setPlacing: setPlacing,
      resize: resize,
      destroy: destroy,
    };
  };
})();
