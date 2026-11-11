// Browser test for backup.js. Run: node tests/backup.test.js
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "..");
const TYPES = { ".js": "text/javascript", ".html": "text/html", ".json": "application/json" };

function startServer() {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent(req.url.split("?")[0]);
    if (urlPath === "/__blank.html") {
      res.writeHead(200, { "Content-Type": "text/html" });
      return res.end("<!doctype html><html><head><meta charset=utf-8></head><body></body></html>");
    }
    const file = path.join(ROOT, urlPath);
    if (!file.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
      res.end(data);
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

const EXPECTED_RECAP =
  "South Africa — November 2026\n" +
  "\n" +
  "• Vineyard Hotel, Cape Town — Accommodation: Lovely gardens (Stay again)\n" +
  "• Kloof Street House — Restaurant/bar: Great cocktails\n" +
  "• Mystery Spot, Karoo — glamping: Odd but fun\n";

let failures = 0;
function check(name, ok, detail) {
  console.log((ok ? "PASS " : "FAIL ") + name + (ok || !detail ? "" : " — " + detail));
  if (!ok) failures++;
}

(async () => {
  const server = await startServer();
  const base = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    page.on("pageerror", (e) => console.log("page error:", e.message));
    await page.goto(base + "/__blank.html");
    await page.addScriptTag({ url: base + "/backup.js" });

    const r = await page.evaluate(async () => {
      const out = {};
      out.jszipPreloaded = !!window.JSZip;

      function makeJpeg(w, h, color) {
        const c = document.createElement("canvas");
        c.width = w; c.height = h;
        const g = c.getContext("2d");
        g.fillStyle = color; g.fillRect(0, 0, w, h);
        g.fillStyle = "#fff"; g.fillRect(2, 2, w / 3, h / 3);
        return new Promise((res) => c.toBlob(res, "image/jpeg", 0.8));
      }
      async function bytes(blob) { return Array.from(new Uint8Array(await blob.arrayBuffer())); }

      const blobs = {};
      const colors = ["#c33", "#3c3", "#33c", "#cc3"];
      for (let i = 0; i < 4; i++) {
        blobs["p" + i] = await makeJpeg(120, 90, colors[i]);
        blobs["p" + i + "_t"] = await makeJpeg(24, 18, colors[i]);
      }
      const photo = (i) => ({ id: "p" + i, thumb: "p" + i + "_t", w: 120, h: 90, caption: i === 0 ? "Pool" : "" });
      const journal = { title: "South Africa", subtitle: "November 2026", order: ["vineyard-hotel", "kloof-st", "mystery"] };
      const places = [
        { id: "vineyard-hotel", name: "Vineyard Hotel", location: "Cape Town", category: "accommodation", review: "Lovely gardens",
          notes: "Room 12", visitDate: "2026-11-02", recommendation: "Stay again", photos: [photo(0), photo(1)], cover: "p0", updatedAt: 1731300000000 },
        { id: "kloof-st", name: "Kloof Street House", location: "", category: "restaurant", review: "Great cocktails",
          notes: "", visitDate: "", recommendation: "", photos: [photo(2)], cover: null, updatedAt: 1731300000001 },
        { id: "mystery", name: "Mystery Spot", location: "Karoo", category: "glamping", review: "Odd but fun",
          notes: "", visitDate: "", recommendation: "", photos: [photo(3)], cover: "p3", updatedAt: 1731300000002 }
      ];

      // 1. Round trip
      const progress = [];
      let inFlight = 0, maxInFlight = 0;
      const made = await TJ.backup.create({
        journal, places,
        getPhotoBlob: async (id) => {
          inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
          await new Promise((r) => setTimeout(r, 5));
          inFlight--;
          return blobs[id];
        },
        onProgress: (d, t) => progress.push([d, t])
      });
      out.jszipLoadedLazily = !!window.JSZip && document.querySelectorAll('script[src="vendor/jszip.min.js"]').length === 1;
      out.filename = made.filename;
      out.photoCount = made.photoCount;
      out.missing1 = made.missing;
      out.blobType = made.blob.type;
      out.progress = progress;
      out.maxInFlight = maxInFlight;

      const opened = await TJ.backup.open(new File([made.blob], made.filename));
      out.journalIn = journal; out.placesIn = places;
      out.journalOut = opened.journal; out.placesOut = opened.places;
      out.exportedAt = opened.exportedAt;
      out.blobIds = opened.blobIds.slice().sort();
      out.photoMatches = [];
      for (const id of Object.keys(blobs)) {
        const b = await opened.getPhoto(id);
        const a = await bytes(blobs[id]);
        const c = b ? await bytes(b) : [];
        out.photoMatches.push({ id, type: b && b.type, sizeOk: !!b && b.size === blobs[id].size,
          bytesOk: c.length === a.length && a.every((x, i) => x === c[i]) });
      }
      out.unknownPhoto = await opened.getPhoto("nope");

      // Inspect raw zip content
      const raw = await JSZip.loadAsync(made.blob);
      out.recap = await raw.file("recap.txt").async("string");
      const jsonText = await raw.file("journal.json").async("string");
      out.jsonPretty = jsonText.indexOf('\n  "format": "travel-journal-backup"') !== -1;
      const meta = JSON.parse(jsonText);
      out.jsonMeta = { format: meta.format, version: meta.version };
      out.compression = {
        json: raw.file("journal.json")._data.compression.magic,
        jpg: raw.file("photos/p0.jpg")._data.compression.magic
      };

      // 2. Missing photo
      const made2 = await TJ.backup.create({
        journal, places,
        getPhotoBlob: (id) => id === "p2" ? Promise.reject(new Error("gone")) : (id === "p3_t" ? Promise.resolve(null) : Promise.resolve(blobs[id])),
        onProgress: () => {}
      });
      out.missing2 = made2.missing.slice().sort();
      const opened2 = await TJ.backup.open(made2.blob);
      out.missingPhotoNull = (await opened2.getPhoto("p2")) === null;
      out.missingNotInIds = opened2.blobIds.indexOf("p2") === -1;
      out.otherPhotoThere = !!(await opened2.getPhoto("p1"));

      // 3. Bad files
      async function errOf(p) { try { await p; return null; } catch (e) { return { msg: e.message, user: e.userMessage }; } }
      out.notZip = await errOf(TJ.backup.open(new File(["hello, not a zip"], "x.zip")));
      const z1 = new JSZip(); z1.file("readme.txt", "hi");
      out.noJson = await errOf(TJ.backup.open(await z1.generateAsync({ type: "blob" })));
      const z2 = new JSZip(); z2.file("journal.json", JSON.stringify({ format: "something-else", version: 1 }));
      out.wrongFormat = await errOf(TJ.backup.open(await z2.generateAsync({ type: "blob" })));
      const z3 = new JSZip(); z3.file("journal.json", JSON.stringify({ format: "travel-journal-backup", version: 99, journal: {}, places: [] }));
      out.newVersion = await errOf(TJ.backup.open(await z3.generateAsync({ type: "blob" })));
      const z4 = new JSZip(); z4.file("journal.json", "x".repeat(5 * 1024 * 1024 + 10), { compression: "DEFLATE" });
      out.tooBig = await errOf(TJ.backup.open(await z4.generateAsync({ type: "blob", compression: "DEFLATE" })));

      // 4. Tolerant open
      const z5 = new JSZip();
      z5.file("journal.json", JSON.stringify({
        format: "travel-journal-backup", version: 1, exportedAt: "2026-11-01T10:00:00.000Z",
        journal: { title: "Trip", order: ["b", "ghost", "b"] },
        places: [
          { id: "a", name: "Alpha", category: "nature", review: "ok", cover: null, updatedAt: 1 },
          { id: "b", name: "Beta", location: "Here", category: "estate", review: "", notes: "n", visitDate: "", recommendation: "",
            photos: [{ id: "x1", thumb: "x1t", w: 1, h: 1, caption: "" }], cover: "x1", updatedAt: 2 }
        ]
      }));
      z5.file("photos/x1.jpg", blobs.p0);
      z5.file("photos/sub/evil.jpg", blobs.p0);
      z5.file("photos/..evil.jpg", blobs.p0);
      z5.file("other/x9.jpg", blobs.p0);
      const t = await TJ.backup.open(await z5.generateAsync({ type: "blob" }));
      out.tolerant = { journal: t.journal, places: t.places, blobIds: t.blobIds, exportedAt: t.exportedAt };
      return out;
    });

    const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const deepEq = (a, b) => require("util").isDeepStrictEqual(a, b);

    check("JSZip not loaded until needed, then loaded once via relative script tag", !r.jszipPreloaded && r.jszipLoadedLazily);
    check("filename is travel-journal-backup-YYYY-MM-DD.zip (local date)",
      (() => { const d = new Date(); const p = (n) => String(n).padStart(2, "0");
        return r.filename === `travel-journal-backup-${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}.zip`; })(), r.filename);
    check("photoCount is 4 and nothing missing", r.photoCount === 4 && r.missing1.length === 0, JSON.stringify([r.photoCount, r.missing1]));
    check("blob is a zip", r.blobType === "application/zip", r.blobType);
    check("round trip preserves journal", deepEq(r.journalOut, r.journalIn), JSON.stringify(r.journalOut));
    check("round trip preserves places (deep equal)", deepEq(r.placesOut, r.placesIn), JSON.stringify(r.placesOut));
    check("round trip preserves order", eq(r.journalOut.order, ["vineyard-hotel", "kloof-st", "mystery"]));
    check("exportedAt is an ISO time", typeof r.exportedAt === "string" && !isNaN(Date.parse(r.exportedAt)) && r.exportedAt.endsWith("Z"), r.exportedAt);
    check("blobIds lists all 8 blobs", eq(r.blobIds, ["p0", "p0_t", "p1", "p1_t", "p2", "p2_t", "p3", "p3_t"]), JSON.stringify(r.blobIds));
    check("photo bytes identical and typed image/jpeg",
      r.photoMatches.length === 8 && r.photoMatches.every((m) => m.sizeOk && m.bytesOk && m.type === "image/jpeg"), JSON.stringify(r.photoMatches));
    check("getPhoto of unknown id resolves null", r.unknownPhoto === null);
    check("onProgress reaches (total,total) with total=8",
      eq(r.progress[r.progress.length - 1], [8, 8]) && r.progress.every((p) => p[1] === 8), JSON.stringify(r.progress));
    check("photo fetches limited to 4 concurrent", r.maxInFlight <= 4 && r.maxInFlight > 1, String(r.maxInFlight));
    check("recap.txt content exact", r.recap === EXPECTED_RECAP, JSON.stringify(r.recap));
    check("journal.json pretty-printed with format/version", r.jsonPretty && eq(r.jsonMeta, { format: "travel-journal-backup", version: 1 }));
    check("DEFLATE for json, STORE for jpg", r.compression.json === "\b\u0000" && r.compression.jpg === "\u0000\u0000", JSON.stringify(r.compression));
    check("rejecting/null getPhotoBlob → listed in missing", eq(r.missing2, ["p2", "p3_t"]), JSON.stringify(r.missing2));
    check("missing photo: open().getPhoto resolves null and not in blobIds", r.missingPhotoNull && r.missingNotInIds && r.otherPhotoThere);
    const hasMsg = (e) => !!e && typeof e.user === "string" && e.user.length > 0;
    check("non-zip file rejects with userMessage", hasMsg(r.notZip), JSON.stringify(r.notZip));
    check("zip without journal.json rejects with userMessage", hasMsg(r.noJson), JSON.stringify(r.noJson));
    check("zip with foreign journal.json rejects with userMessage", hasMsg(r.wrongFormat), JSON.stringify(r.wrongFormat));
    check("unsupported version rejects with userMessage", hasMsg(r.newVersion), JSON.stringify(r.newVersion));
    check("journal.json over 5 MB rejects with userMessage", hasMsg(r.tooBig), JSON.stringify(r.tooBig));

    const t = r.tolerant;
    check("tolerant: order rebuilt (unknown/duplicate dropped, missing appended)", eq(t.journal.order, ["b", "a"]), JSON.stringify(t.journal.order));
    check("tolerant: missing journal strings become \"\"", t.journal.title === "Trip" && t.journal.subtitle === "");
    const a = t.places[0];
    check("tolerant: place without photos/notes gets [] and \"\"",
      eq(a.photos, []) && a.notes === "" && a.location === "" && a.visitDate === "" && a.recommendation === "" && a.name === "Alpha",
      JSON.stringify(a));
    check("tolerant: entries outside photos/ and unsafe ids ignored", eq(t.blobIds, ["x1"]), JSON.stringify(t.blobIds));
  } catch (e) {
    console.log("FAIL test crashed — " + (e && e.stack || e));
    failures++;
  } finally {
    await browser.close();
    server.close();
  }
  console.log(failures ? `\n${failures} check(s) failed` : "\nAll checks passed");
  process.exit(failures ? 1 : 0);
})();
