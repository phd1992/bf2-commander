// Browser tests for photos.js. Run: node tests/photos.test.js
// Serves the repo with a tiny static server and drives Chromium through Playwright.
// The test page is sent with a CSP close to production's (own-origin scripts, blob: workers).
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const ROOT = path.resolve(__dirname, "..");
const TYPES = {
  ".js": "text/javascript; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".jpg": "image/jpeg",
  ".heic": "image/heic",
  ".txt": "text/plain; charset=utf-8",
};
// Production-like CSP, plus a variant that also allows eval (which heic2any's worker needs).
const CSP_STRICT =
  "default-src 'self'; script-src 'self' blob:; worker-src 'self' blob:; img-src 'self' blob: data:; connect-src 'self' blob: data:";
const CSP_EVAL = CSP_STRICT.replace("script-src 'self' blob:", "script-src 'self' blob: 'unsafe-eval'");
const PAGES = { "/__strict__.html": CSP_STRICT, "/__eval__.html": CSP_EVAL };
const TEST_PAGE = "<!doctype html><meta charset=utf-8><title>photos test</title><body></body>";

function startServer() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
    if (PAGES[url]) {
      res.writeHead(200, { "Content-Type": TYPES[".html"], "Content-Security-Policy": PAGES[url] });
      return res.end(TEST_PAGE);
    }
    const file = path.join(ROOT, url);
    if (!file.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); return res.end("not found"); }
      res.writeHead(200, { "Content-Type": TYPES[path.extname(file).toLowerCase()] || "application/octet-stream" });
      res.end(data);
    });
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

// Helpers installed inside each test page.
function installHelpers() {
  window.makeJpegFile = (w, h, name) => {
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    const ctx = c.getContext("2d");
    const g = ctx.createLinearGradient(0, 0, w, h);
    g.addColorStop(0, "#08f"); g.addColorStop(1, "#f80");
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    return new Promise((r) => c.toBlob((b) => r(new File([b], name, { type: "image/jpeg" })), "image/jpeg", 0.8));
  };
  window.fixture = async (name, type) => {
    const blob = await (await fetch("/tests/fixtures/" + name)).blob();
    return new File([blob], name, { type });
  };
  window.blobSize = async (blob) => {
    const bmp = await createImageBitmap(blob);
    const s = { w: bmp.width, h: bmp.height };
    bmp.close();
    return s;
  };
  window.describe = async (p) => ({
    width: p.width, height: p.height,
    full: { type: p.full.type, ...(await blobSize(p.full)) },
    thumb: { type: p.thumb.type, ...(await blobSize(p.thumb)) },
  });
}

const results = [];
function check(name, ok, detail) {
  results.push(ok);
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`);
}

(async () => {
  const server = await startServer();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch();
  let exitCode = 0;
  const pageErrors = [];
  async function openPage(pathname) {
    const page = await browser.newPage();
    page.on("pageerror", (e) => pageErrors.push(e.message));
    page.on("console", (m) => {
      const t = m.text();
      // Expected noise: fetching a revoked blob URL, and the CSP eval probe on the strict page.
      if (m.type() === "error" && !/ERR_FILE_NOT_FOUND|unsafe-eval/.test(t)) pageErrors.push(t);
    });
    await page.goto(base + pathname);
    await page.addScriptTag({ url: "/photos.js" });
    await page.evaluate(installHelpers);
    return page;
  }
  try {
    const page = await openPage("/__strict__.html");

    // 1. Large JPEG is downscaled, aspect preserved.
    const big = await page.evaluate(async () => describe(await TJ.images.prepare(await makeJpegFile(4000, 3000, "big.jpg"))));
    check("large 4000x3000 → full 2400x1800, image/jpeg",
      big.full.w === 2400 && big.full.h === 1800 && big.width === 2400 && big.height === 1800 && big.full.type === "image/jpeg",
      JSON.stringify(big.full));
    check("large → thumb 800x600, image/jpeg",
      big.thumb.w === 800 && big.thumb.h === 600 && big.thumb.type === "image/jpeg", JSON.stringify(big.thumb));

    // 2. Small image is not upscaled.
    const small = await page.evaluate(async () => describe(await TJ.images.prepare(await makeJpegFile(640, 480, "small.jpg"))));
    check("small 640x480 not upscaled", small.full.w === 640 && small.full.h === 480 && small.thumb.w === 640 && small.thumb.h === 480,
      `full ${small.full.w}x${small.full.h}, thumb ${small.thumb.w}x${small.thumb.h}`);

    // 3. EXIF orientation 6: stored 400x300, should come out upright as 300x400.
    const rot = await page.evaluate(async () => describe(await TJ.images.prepare(await fixture("orient6.jpg", "image/jpeg"))));
    check("EXIF orientation 6 → upright 300x400", rot.full.w === 300 && rot.full.h === 400 && rot.width === 300 && rot.height === 400,
      `full ${rot.full.w}x${rot.full.h}`);

    // 4a. Under the strict CSP heic2any cannot run (its worker needs eval): must fail fast, not hang.
    const strictHeic = await page.evaluate(async () => {
      const t = performance.now();
      return TJ.images.prepare(await fixture("sample.heic", "image/heic")).then(
        () => ({ resolved: true }),
        (e) => ({ code: e.code, userMessage: e.userMessage, ms: Math.round(performance.now() - t) }));
    });
    check("HEIC under strict CSP rejects quickly with decode_failed",
      strictHeic.code === "decode_failed" && /HEIC/.test(strictHeic.userMessage) && strictHeic.ms < 3000, JSON.stringify(strictHeic));

    // 4b. HEIC via the heic2any fallback on a page whose CSP allows eval (Chromium has no native HEIC
    // decoder). Empty type, like iOS sometimes gives, so detection relies on the extension.
    const evalPage = await openPage("/__eval__.html");
    const heic = await evalPage.evaluate(async () => {
      const nativeOk = await createImageBitmap(await fixture("sample.heic", "image/heic")).then(() => true, () => false);
      try {
        const p = await TJ.images.prepare(await fixture("sample.heic", ""));
        return { nativeOk, ok: true, lib: typeof window.heic2any, scripts: document.querySelectorAll('script[src*="heic2any"]').length, ...(await describe(p)) };
      } catch (e) {
        return { nativeOk, ok: false, code: e.code, msg: e.message, cause: e.cause && String(e.cause) };
      }
    });
    check("HEIC fixture converts via heic2any → 400x300 JPEG",
      !heic.nativeOk && heic.ok && heic.lib === "function" && heic.full.w === 400 && heic.full.h === 300 && heic.full.type === "image/jpeg",
      JSON.stringify(heic));
    if (heic.ok) {
      const second = await evalPage.evaluate(async () => {
        // Neutral name and type: detection must come from the ftyp brand bytes.
        await TJ.images.prepare(await fixture("sample.heic", "image/x-unknown").then((f) => new File([f], "photo.bin", { type: "image/x-unknown" })));
        return document.querySelectorAll('script[src*="heic2any"]').length;
      });
      check("HEIC detected by ftyp brand; heic2any script injected only once", second === 1, `script tags: ${second}`);
    }

    // 5. Bad inputs.
    const bad = await page.evaluate(async () => {
      const fake = new File(["definitely not a jpeg"], "fake.jpg", { type: "image/jpeg" });
      const txt = await fixture("not-a-photo.txt", "text/plain");
      const r = await TJ.images.prepare(fake).then(() => ({ resolved: true }), (e) => ({ code: e.code, userMessage: e.userMessage }));
      const r2 = await TJ.images.prepare(txt).then(() => ({ resolved: true }), (e) => ({ code: e.code, userMessage: e.userMessage }));
      const q = TJ.createUploadQueue({ upload: async () => {}, onChange() {} });
      const items = q.add("place-1", [txt]);
      return {
        fakeJpg: r, txtPrepare: r2, isImageTxt: TJ.images.isImage(txt),
        isImageNoType: TJ.images.isImage(new File(["x"], "IMG_0001.HEIC", { type: "" })),
        item: { ...items[0] }, active: q.activeCount(),
      };
    });
    check("text renamed .jpg rejects with decode_failed + userMessage",
      bad.fakeJpg.code === "decode_failed" && typeof bad.fakeJpg.userMessage === "string" && bad.fakeJpg.userMessage.length > 0,
      JSON.stringify(bad.fakeJpg));
    check("prepare(.txt) rejects with unsupported", bad.txtPrepare.code === "unsupported", JSON.stringify(bad.txtPrepare));
    check("isImage(.txt) is false; isImage(.HEIC with empty type) is true", bad.isImageTxt === false && bad.isImageNoType === true);
    check("queue.add(.txt) → item in error state with message",
      bad.item.status === "error" && !!bad.item.error && bad.item.groupId === "place-1" && bad.active === 0, JSON.stringify(bad.item));

    // 6. Upload queue behaviour.
    const q = await page.evaluate(async () => {
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      let prepareCalls = {};
      let uploadCalls = {};
      let failedOnce = false;
      let maxConcurrent = 0, inFlight = 0;
      const seen = {}; // name -> list of statuses observed
      const files = [await makeJpegFile(300, 200, "a.jpg"), await makeJpegFile(300, 200, "b.jpg"), await makeJpegFile(300, 200, "c.jpg")];
      let queue;
      queue = TJ.createUploadQueue({
        concurrency: 2,
        prepare: async (file) => {
          prepareCalls[file.name] = (prepareCalls[file.name] || 0) + 1;
          inFlight++; maxConcurrent = Math.max(maxConcurrent, inFlight);
          try { return await TJ.images.prepare(file); } finally { inFlight--; }
        },
        upload: async (prepared, item) => {
          uploadCalls[item.name] = (uploadCalls[item.name] || 0) + 1;
          inFlight++; maxConcurrent = Math.max(maxConcurrent, inFlight);
          try {
            await sleep(80);
            if (item.name === "b.jpg" && !failedOnce) { failedOnce = true; throw new Error("network down"); }
            if (!(prepared.full instanceof Blob) || !(prepared.thumb instanceof Blob)) throw new Error("bad prepared");
          } finally { inFlight--; }
        },
        onChange() {
          for (const it of queue ? queue.all() : []) {
            const s = (seen[it.name] = seen[it.name] || []);
            if (s[s.length - 1] !== it.status) s.push(it.status);
          }
        },
      });
      const added = queue.add("place-2", files);
      const initial = added.map((i) => ({ status: i.status, progress: i.progress }));
      const waitFor = async (fn, ms = 8000) => { const t = Date.now(); while (!fn()) { if (Date.now() - t > ms) return false; await sleep(20); } return true; };

      await waitFor(() => queue.activeCount() === 0);
      const afterFirstPass = queue.items("place-2").map((i) => ({ name: i.name, status: i.status, error: i.error, progress: i.progress, hasPreview: !!i.previewUrl }));
      const failed = queue.items("place-2").find((i) => i.status === "error");

      await waitFor(() => queue.all().length === 1); // done items leave after ~1.2 s
      const afterLinger = queue.all().map((i) => i.name);

      queue.retry(failed.id);
      const retryStatus = failed.status;
      await waitFor(() => failed.status === "done");
      const retriedStatus = failed.status;
      await waitFor(() => queue.all().length === 0);
      const emptyAfter = queue.all().length;

      // dismiss: a failed item and a still-queued item.
      const q2 = TJ.createUploadQueue({ concurrency: 1, upload: () => Promise.reject(new Error("x")), onChange() {} });
      const [x, y] = q2.add("place-3", [await makeJpegFile(50, 50, "x.jpg"), await makeJpegFile(50, 50, "y.jpg")]);
      q2.dismiss(y.id); // still queued (concurrency 1)
      await waitFor(() => x.status === "error");
      const xError = x.error;
      const xPreview = x.previewUrl;
      q2.dismiss(x.id);
      const previewRevoked = await fetch(xPreview).then(() => false, () => true);

      return {
        initial, afterFirstPass, afterLinger, retryStatus, retriedStatus, emptyAfter, seen,
        prepareCalls, uploadCalls, maxConcurrent, q2Len: q2.all().length, xError, previewRevoked,
      };
    });
    // add() starts work synchronously, so the first `concurrency` items are already preparing.
    check("queue: first two start preparing (0.3), third waits queued (0.05)",
      q.initial[0].status === "preparing" && q.initial[1].status === "preparing" && q.initial[1].progress === 0.3 &&
      q.initial[2].status === "queued" && q.initial[2].progress === 0.05, JSON.stringify(q.initial));
    check("queue: statuses progress queued → preparing → uploading → done for a/c",
      ["a.jpg", "c.jpg"].every((n) => JSON.stringify(q.seen[n]) === JSON.stringify(["queued", "preparing", "uploading", "done"])),
      JSON.stringify(q.seen));
    const fp = Object.fromEntries(q.afterFirstPass.map((i) => [i.name, i]));
    check("queue: 2nd fails with upload message, others done",
      fp["a.jpg"].status === "done" && fp["c.jpg"].status === "done" && fp["b.jpg"].status === "error" &&
      fp["b.jpg"].error === "Upload failed. Check your connection and try again." && fp["b.jpg"].hasPreview,
      JSON.stringify(q.afterFirstPass));
    check("queue: done items removed after linger", JSON.stringify(q.afterLinger) === '["b.jpg"]', JSON.stringify(q.afterLinger));
    check("queue: retry succeeds without re-preparing",
      q.retriedStatus === "done" && q.prepareCalls["b.jpg"] === 1 && q.uploadCalls["b.jpg"] === 2 && q.emptyAfter === 0,
      `prepare=${JSON.stringify(q.prepareCalls)} upload=${JSON.stringify(q.uploadCalls)}`);
    check("queue: never more than concurrency (2) in flight", q.maxConcurrent <= 2 && q.maxConcurrent >= 1, `max ${q.maxConcurrent}`);
    check("queue: dismiss removes queued and failed items, revokes preview",
      q.q2Len === 0 && !!q.xError && q.previewRevoked, `len ${q.q2Len}, revoked ${q.previewRevoked}`);

    check("no page errors", pageErrors.length === 0, pageErrors.join(" | "));
  } catch (err) {
    console.error(err);
    results.push(false);
  } finally {
    await browser.close();
    server.close();
  }
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  exitCode = failed ? 1 : 0;
  process.exit(exitCode);
})();
