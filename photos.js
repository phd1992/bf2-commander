/* Photo decoding, resizing and upload queue for the travel journal.
   Exposes TJ.images and TJ.createUploadQueue (classic script, no modules). */
(function () {
  "use strict";

  window.TJ = window.TJ || {};
  var TJ = window.TJ;

  var FULL_EDGE = 2400, FULL_QUALITY = 0.86;
  var THUMB_EDGE = 800, THUMB_QUALITY = 0.8;
  var IMAGE_EXT = /\.(heic|heif|jpe?g|png|webp|gif|avif)$/i;
  var HEIC_EXT = /\.(heic|heif)$/i;
  var HEIC_BRANDS = ["heic", "heix", "hevc", "mif1", "msf1"];

  var MSG_UNSUPPORTED = "This file isn't a photo, so it can't be added.";
  var MSG_DECODE = "This photo couldn't be read. Try exporting it as JPEG and adding it again.";
  var MSG_UPLOAD = "Upload failed. Check your connection and try again.";
  var MSG_HEIC = "This browser can't open HEIC photos. Try exporting it as JPEG and adding it again.";
  var HEIC_TIMEOUT_MS = 90000;

  // Resolve the vendor path against this script's URL, so it works whatever page includes us.
  var HEIC_LIB_URL = (function () {
    var s = document.currentScript;
    try { if (s && s.src) return new URL("vendor/heic2any.min.js", s.src).href; } catch (e) { /* fall through */ }
    return "vendor/heic2any.min.js";
  })();

  function photoError(code, message, cause) {
    var err = new Error(message);
    err.code = code;
    err.userMessage = code === "unsupported" ? MSG_UNSUPPORTED : MSG_DECODE;
    if (cause) err.cause = cause;
    return err;
  }

  function isImage(file) {
    if (!file) return false;
    if (typeof file.type === "string" && file.type.indexOf("image/") === 0) return true;
    return IMAGE_EXT.test(file.name || "");
  }

  // ---- decoding ------------------------------------------------------------

  // Returns { source, width, height, close() } with EXIF orientation already applied.
  function decode(blob) {
    if (typeof createImageBitmap === "function") {
      return createImageBitmap(blob, { imageOrientation: "from-image" }).then(function (bmp) {
        return { source: bmp, width: bmp.width, height: bmp.height, close: function () { bmp.close(); } };
      }, function () {
        return decodeWithImg(blob); // older Safari rejects the options bag or some formats
      });
    }
    return decodeWithImg(blob);
  }

  function decodeWithImg(blob) {
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(blob);
      var img = new Image();
      img.onload = function () {
        var w = img.naturalWidth, h = img.naturalHeight;
        if (!w || !h) { URL.revokeObjectURL(url); reject(new Error("empty image")); return; }
        resolve({
          source: img, width: w, height: h,
          close: function () { URL.revokeObjectURL(url); img.src = ""; }
        });
      };
      img.onerror = function () { URL.revokeObjectURL(url); reject(new Error("img decode failed")); };
      img.decoding = "async";
      img.src = url;
    });
  }

  function looksLikeHeic(file) {
    var type = (file.type || "").toLowerCase();
    if (type === "image/heic" || type === "image/heif") return Promise.resolve(true);
    if (HEIC_EXT.test(file.name || "")) return Promise.resolve(true);
    return file.slice(0, 12).arrayBuffer().then(function (buf) {
      var b = new Uint8Array(buf);
      if (b.length < 12) return false;
      var box = String.fromCharCode(b[4], b[5], b[6], b[7]);
      var brand = String.fromCharCode(b[8], b[9], b[10], b[11]);
      return box === "ftyp" && HEIC_BRANDS.indexOf(brand) !== -1;
    }).catch(function () { return false; });
  }

  var heicLibPromise = null;
  function loadHeicLib() {
    if (typeof window.heic2any === "function") return Promise.resolve(window.heic2any);
    if (!heicLibPromise) {
      heicLibPromise = new Promise(function (resolve, reject) {
        var s = document.createElement("script");
        s.src = HEIC_LIB_URL;
        s.async = true;
        s.onload = function () {
          if (typeof window.heic2any === "function") resolve(window.heic2any);
          else reject(new Error("heic2any missing after load"));
        };
        s.onerror = function () { reject(new Error("heic2any failed to load")); };
        document.head.appendChild(s);
      }).catch(function (err) {
        heicLibPromise = null; // allow a later retry (e.g. flaky network)
        throw err;
      });
    }
    return heicLibPromise;
  }

  // heic2any's libheif build (emscripten embind) calls `new Function` inside its blob worker, and
  // blob workers inherit the page's CSP. Without 'unsafe-eval' the worker dies silently and the
  // conversion never settles, so check up front and fail fast instead of hanging.
  var evalAllowed = null;
  function canEval() {
    if (evalAllowed === null) {
      try { evalAllowed = new Function("return true")() === true; } catch (e) { evalAllowed = false; }
    }
    return evalAllowed;
  }

  function withTimeout(promise, ms) {
    return new Promise(function (resolve, reject) {
      var t = setTimeout(function () { reject(new Error("HEIC conversion timed out")); }, ms);
      promise.then(function (v) { clearTimeout(t); resolve(v); }, function (e) { clearTimeout(t); reject(e); });
    });
  }

  function decodeHeic(file) {
    if (!canEval()) {
      var err = photoError("decode_failed", "HEIC conversion needs 'unsafe-eval' in the page CSP");
      err.userMessage = MSG_HEIC;
      return Promise.reject(err);
    }
    return loadHeicLib().then(function (heic2any) {
      // Generous limit: big HEICs on slow phones take a while, but we must never hang forever.
      return withTimeout(heic2any({ blob: file, toType: "image/jpeg", quality: 0.92 }), HEIC_TIMEOUT_MS);
    }).then(function (out) {
      return decode(Array.isArray(out) ? out[0] : out);
    });
  }

  function decodeAny(file) {
    return decode(file).catch(function (nativeErr) {
      return looksLikeHeic(file).then(function (heic) {
        if (!heic) throw nativeErr;
        return decodeHeic(file);
      });
    });
  }

  // ---- resizing ------------------------------------------------------------

  function fit(w, h, maxEdge) {
    var scale = Math.min(1, maxEdge / Math.max(w, h));
    return { w: Math.max(1, Math.round(w * scale)), h: Math.max(1, Math.round(h * scale)) };
  }

  function makeCanvas(w, h) {
    var c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    return c;
  }

  // Draws src straight onto a canvas of the target size (never a full-resolution canvas).
  // Large ratios go through intermediate halvings so the result isn't aliased; each
  // intermediate is at most 4x the target area and freed as soon as it's used.
  function drawScaled(src, srcW, srcH, w, h) {
    var cur = src, curW = srcW, curH = srcH, tmp = null;
    while (curW / 2 >= w * 2 && curH / 2 >= h * 2) {
      // Jump straight to 2x target, which keeps the step canvas small.
      var stepW = w * 2, stepH = h * 2;
      var step = makeCanvas(stepW, stepH);
      var sctx = step.getContext("2d");
      sctx.imageSmoothingEnabled = true;
      sctx.imageSmoothingQuality = "high";
      sctx.drawImage(cur, 0, 0, curW, curH, 0, 0, stepW, stepH);
      if (tmp) releaseCanvas(tmp);
      tmp = step; cur = step; curW = stepW; curH = stepH;
    }
    var out = makeCanvas(w, h);
    var ctx = out.getContext("2d");
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    ctx.fillStyle = "#fff"; // transparent PNGs would otherwise turn black in JPEG
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(cur, 0, 0, curW, curH, 0, 0, w, h);
    if (tmp) releaseCanvas(tmp);
    return out;
  }

  // Shrinking to 1x1 lets iOS Safari reclaim canvas memory promptly.
  function releaseCanvas(c) { c.width = 1; c.height = 1; }

  function toJpeg(canvas, quality) {
    return new Promise(function (resolve, reject) {
      canvas.toBlob(function (blob) {
        if (blob) resolve(blob);
        else reject(photoError("decode_failed", "canvas.toBlob returned null"));
      }, "image/jpeg", quality);
    });
  }

  function prepare(file) {
    if (!isImage(file)) return Promise.reject(photoError("unsupported", "Not an image: " + (file && file.name)));

    return decodeAny(file).catch(function (err) {
      if (err && err.code) throw err;
      throw photoError("decode_failed", "Could not decode " + (file.name || "image"), err);
    }).then(function (img) {
      var fullCanvas, thumbCanvas;
      try {
        var full = fit(img.width, img.height, FULL_EDGE);
        fullCanvas = drawScaled(img.source, img.width, img.height, full.w, full.h);
      } catch (err) {
        img.close();
        throw photoError("decode_failed", "Could not draw image", err);
      }
      img.close();
      // The thumb is drawn from the already-reduced full canvas, not the original.
      var thumb = fit(full.w, full.h, THUMB_EDGE);
      thumbCanvas = drawScaled(fullCanvas, full.w, full.h, thumb.w, thumb.h);

      return Promise.all([toJpeg(fullCanvas, FULL_QUALITY), toJpeg(thumbCanvas, THUMB_QUALITY)])
        .then(function (blobs) {
          return { full: blobs[0], thumb: blobs[1], width: full.w, height: full.h };
        })
        .finally(function () {
          releaseCanvas(fullCanvas);
          releaseCanvas(thumbCanvas);
        });
    }).catch(function (err) {
      if (err && err.code) throw err;
      throw photoError("decode_failed", "Could not process image", err);
    });
  }

  TJ.images = { isImage: isImage, prepare: prepare };

  // ---- upload queue --------------------------------------------------------

  var PROGRESS = { queued: 0.05, preparing: 0.3, uploading: 0.7, done: 1 };
  var DONE_LINGER_MS = 1200;
  var nextId = 1;

  TJ.createUploadQueue = function (opts) {
    opts = opts || {};
    var upload = opts.upload;
    var onChange = opts.onChange || function () {};
    var concurrency = Math.max(1, opts.concurrency || 2);
    var prepareFn = opts.prepare || TJ.images.prepare;

    var list = [];
    var prepared = {}; // item id -> prepare() result, kept so retry can skip re-decoding
    var running = 0;

    function changed() {
      try { onChange(); } catch (e) { console.error(e); }
    }

    function setStatus(item, status, error) {
      item.status = status;
      item.error = error || null;
      if (status !== "error") item.progress = PROGRESS[status];
    }

    function find(id) {
      for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
      return null;
    }

    function remove(item) {
      var i = list.indexOf(item);
      if (i === -1) return;
      list.splice(i, 1);
      if (item.previewUrl) URL.revokeObjectURL(item.previewUrl);
      item.previewUrl = null;
      delete prepared[item.id];
    }

    function pump() {
      for (var i = 0; i < list.length && running < concurrency; i++) {
        if (list[i].status === "queued") run(list[i]);
      }
    }

    function run(item) {
      running++;
      var stage = "prepare";
      var p;
      if (prepared[item.id]) {
        p = Promise.resolve(prepared[item.id]);
      } else {
        setStatus(item, "preparing");
        changed();
        p = Promise.resolve().then(function () { return prepareFn(item.file); }).then(function (result) {
          prepared[item.id] = result;
          if (!item.previewUrl && result.thumb) item.previewUrl = URL.createObjectURL(result.thumb);
          return result;
        });
      }
      p.then(function (result) {
        stage = "upload";
        setStatus(item, "uploading");
        changed();
        return Promise.resolve().then(function () { return upload(result, item); });
      }).then(function () {
        setStatus(item, "done");
        changed();
        setTimeout(function () {
          if (list.indexOf(item) === -1) return;
          remove(item);
          changed();
        }, DONE_LINGER_MS);
      }, function (err) {
        var msg = err && err.userMessage ? err.userMessage : (stage === "upload" ? MSG_UPLOAD : MSG_DECODE);
        setStatus(item, "error", msg);
        changed();
      }).finally(function () {
        running--;
        pump();
      });
    }

    function add(groupId, fileList) {
      var files = Array.prototype.slice.call(fileList || []);
      var created = files.map(function (file) {
        var item = {
          id: "up" + (nextId++), groupId: groupId, name: file.name || "photo",
          previewUrl: null, status: "queued", progress: PROGRESS.queued, error: null
        };
        // Keep the File off the enumerable shape so items stay plain/serialisable.
        Object.defineProperty(item, "file", { value: file, enumerable: false, writable: true });
        if (!isImage(file)) setStatus(item, "error", MSG_UNSUPPORTED);
        list.push(item);
        return item;
      });
      if (created.length) changed();
      pump();
      return created;
    }

    function retry(id) {
      var item = find(id);
      if (!item || item.status !== "error") return;
      if (!prepared[item.id] && !isImage(item.file)) return; // retrying won't help a non-photo
      setStatus(item, "queued");
      changed();
      pump();
    }

    // Only failed or not-yet-started items can be dismissed; in-flight work is left to finish.
    function dismiss(id) {
      var item = find(id);
      if (!item || (item.status !== "error" && item.status !== "queued")) return;
      remove(item);
      changed();
    }

    return {
      add: add,
      retry: retry,
      dismiss: dismiss,
      items: function (groupId) { return list.filter(function (it) { return it.groupId === groupId; }); },
      all: function () { return list.slice(); },
      activeCount: function () {
        return list.filter(function (it) {
          return it.status === "queued" || it.status === "preparing" || it.status === "uploading";
        }).length;
      }
    };
  };
})();
