/* Travel journal backup: export to / import from a .zip file.
 * Exposes TJ.backup.create(...) and TJ.backup.open(file). Depends on vendor/jszip.min.js,
 * which is loaded lazily the first time a backup is made or opened. */
(function () {
  "use strict";

  window.TJ = window.TJ || {};

  var FORMAT = "travel-journal-backup";
  var VERSION = 1;
  var JSZIP_URL = "vendor/jszip.min.js";
  var MAX_JSON_BYTES = 5 * 1024 * 1024;
  var FETCH_CONCURRENCY = 4;
  var STRING_FIELDS = ["name", "location", "category", "review", "notes", "visitDate", "recommendation"];
  var CATEGORY_LABELS = {
    accommodation: "Accommodation",
    restaurant: "Restaurant/bar",
    nature: "Nature/activity",
    estate: "Estate/garden",
    transport: "Transport"
  };

  var jszipPromise = null;

  function loadJSZip() {
    if (window.JSZip) return Promise.resolve(window.JSZip);
    if (!jszipPromise) {
      jszipPromise = new Promise(function (resolve, reject) {
        var s = document.createElement("script");
        s.src = JSZIP_URL;
        s.async = true;
        s.onload = function () {
          if (window.JSZip) resolve(window.JSZip);
          else reject(new Error("JSZip loaded but did not define window.JSZip"));
        };
        s.onerror = function () { reject(new Error("Could not load " + JSZIP_URL)); };
        document.head.appendChild(s);
      }).catch(function (err) {
        jszipPromise = null; // allow a retry later
        err.userMessage = "The backup tool couldn't be loaded. Please try again.";
        throw err;
      });
    }
    return jszipPromise;
  }

  function userError(message, cause) {
    var err = new Error(message);
    err.userMessage = message;
    if (cause) err.cause = cause;
    return err;
  }

  // Ids become file names inside the zip, so anything path-like is refused.
  function isSafeId(id) {
    return typeof id === "string" && id.length > 0 && id.indexOf("/") === -1 &&
      id.indexOf("\\") === -1 && id.indexOf("..") === -1;
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n; }

  function localDateStamp(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  function str(v) { return typeof v === "string" ? v : ""; }

  // ---------- create ----------

  function collectBlobIds(places) {
    var seen = {};
    var ids = [];
    var photoCount = 0;
    places.forEach(function (place) {
      (place.photos || []).forEach(function (photo) {
        if (!photo) return;
        photoCount++;
        [photo.id, photo.thumb].forEach(function (id) {
          if (isSafeId(id) && !seen[id]) {
            seen[id] = true;
            ids.push(id);
          }
        });
      });
    });
    return { ids: ids, photoCount: photoCount };
  }

  function buildRecap(journal, places) {
    var lines = [str(journal.title) + " — " + str(journal.subtitle), ""];
    places.forEach(function (p) {
      var name = str(p.name);
      if (str(p.location)) name += ", " + p.location;
      var category = str(p.category);
      var label = Object.prototype.hasOwnProperty.call(CATEGORY_LABELS, category) ? CATEGORY_LABELS[category] : category;
      var line = "• " + name + " — " + label;
      if (str(p.review)) line += ": " + p.review;
      if (str(p.recommendation)) line += " (" + p.recommendation + ")";
      lines.push(line);
    });
    return lines.join("\n") + "\n";
  }

  function create(opts) {
    var journal = opts.journal || {};
    var places = opts.places || [];
    var getPhotoBlob = opts.getPhotoBlob;
    var onProgress = typeof opts.onProgress === "function" ? opts.onProgress : function () {};

    return loadJSZip().then(function (JSZip) {
      var zip = new JSZip();
      var now = new Date();
      var collected = collectBlobIds(places);
      var ids = collected.ids;
      var total = ids.length;
      var done = 0;
      var missing = [];
      var next = 0;

      zip.file("journal.json", JSON.stringify({
        format: FORMAT,
        version: VERSION,
        exportedAt: now.toISOString(),
        journal: journal,
        places: places
      }, null, 2), { compression: "DEFLATE" });
      zip.file("recap.txt", buildRecap(journal, places), { compression: "DEFLATE" });

      onProgress(0, total);

      function fetchOne(id) {
        return Promise.resolve()
          .then(function () { return getPhotoBlob(id); })
          .then(function (blob) {
            if (blob) zip.file("photos/" + id + ".jpg", blob, { compression: "STORE", binary: true });
            else missing.push(id);
          }, function () { missing.push(id); })
          .then(function () { onProgress(++done, total); });
      }

      function worker() {
        if (next >= ids.length) return Promise.resolve();
        return fetchOne(ids[next++]).then(worker);
      }

      var workers = [];
      for (var i = 0; i < Math.min(FETCH_CONCURRENCY, ids.length); i++) workers.push(worker());

      return Promise.all(workers).then(function () {
        return zip.generateAsync({ type: "blob", streamFiles: true, mimeType: "application/zip" });
      }).then(function (blob) {
        return {
          blob: blob,
          filename: "travel-journal-backup-" + localDateStamp(now) + ".zip",
          photoCount: collected.photoCount,
          missing: missing
        };
      });
    });
  }

  // ---------- open ----------

  // Reads an entry as text but stops once it exceeds `limit` bytes, so a
  // zip bomb or a lying size header can't exhaust memory.
  function readTextCapped(entry, limit) {
    return new Promise(function (resolve, reject) {
      var chunks = [];
      var size = 0;
      var stopped = false;
      var stream = entry.internalStream("uint8array");
      stream.on("data", function (chunk) {
        if (stopped) return;
        size += chunk.length;
        if (size > limit) {
          stopped = true;
          stream.pause();
          reject(userError("This backup's journal data is too large to open."));
          return;
        }
        chunks.push(chunk);
      });
      stream.on("error", function (e) {
        if (!stopped) { stopped = true; reject(e); }
      });
      stream.on("end", function () {
        if (stopped) return;
        var all = new Uint8Array(size);
        var offset = 0;
        chunks.forEach(function (c) { all.set(c, offset); offset += c.length; });
        resolve(new TextDecoder("utf-8").decode(all));
      });
      stream.resume();
    });
  }

  function normalizePhoto(photo) {
    var out = {};
    Object.keys(photo).forEach(function (k) { out[k] = photo[k]; });
    out.id = photo.id;
    out.thumb = typeof photo.thumb === "string" ? photo.thumb : "";
    out.caption = str(photo.caption);
    return out;
  }

  function normalizePlace(place) {
    var out = {};
    Object.keys(place).forEach(function (k) { out[k] = place[k]; });
    STRING_FIELDS.forEach(function (f) { out[f] = str(place[f]); });
    out.photos = Array.isArray(place.photos)
      ? place.photos.filter(function (ph) { return ph && typeof ph === "object" && typeof ph.id === "string"; }).map(normalizePhoto)
      : [];
    out.cover = typeof place.cover === "string" ? place.cover : null;
    if (typeof out.updatedAt !== "number") out.updatedAt = 0;
    return out;
  }

  function normalize(data) {
    var seen = {};
    var places = (Array.isArray(data.places) ? data.places : [])
      .filter(function (p) {
        if (!p || typeof p !== "object" || typeof p.id !== "string" || !p.id || seen[p.id]) return false;
        seen[p.id] = true;
        return true;
      })
      .map(normalizePlace);

    var srcJournal = data.journal && typeof data.journal === "object" ? data.journal : {};
    var journal = {};
    Object.keys(srcJournal).forEach(function (k) { journal[k] = srcJournal[k]; });
    journal.title = str(srcJournal.title);
    journal.subtitle = str(srcJournal.subtitle);

    // Keep the stored order where it agrees with the places; drop unknown ids, append the rest.
    var inOrder = {};
    var order = [];
    (Array.isArray(srcJournal.order) ? srcJournal.order : []).forEach(function (id) {
      if (typeof id === "string" && seen[id] && !inOrder[id]) { inOrder[id] = true; order.push(id); }
    });
    places.forEach(function (p) { if (!inOrder[p.id]) order.push(p.id); });
    journal.order = order;

    return { journal: journal, places: places };
  }

  function open(file) {
    return loadJSZip().then(function (JSZip) {
      return JSZip.loadAsync(file).catch(function (e) {
        throw userError("This file isn't a travel journal backup.", e);
      });
    }).then(function (zip) {
      var jsonEntry = zip.file("journal.json");
      if (!jsonEntry || jsonEntry.dir) throw userError("This file isn't a travel journal backup.");

      var photoEntries = {};
      zip.forEach(function (path, entry) {
        if (entry.dir) return;
        var m = /^photos\/([^\/]+)\.jpg$/.exec(path);
        if (m && isSafeId(m[1])) photoEntries[m[1]] = entry;
      });

      return readTextCapped(jsonEntry, MAX_JSON_BYTES).then(function (text) {
        var data;
        try { data = JSON.parse(text); } catch (e) {
          throw userError("This backup file is damaged and can't be read.", e);
        }
        if (!data || typeof data !== "object" || data.format !== FORMAT) {
          throw userError("This file isn't a travel journal backup.");
        }
        if (typeof data.version === "number" && data.version > VERSION) {
          throw userError("This backup was made by a newer version of the app and can't be opened here.");
        }
        if (data.version !== VERSION) throw userError("This backup's version isn't supported.");

        var result = normalize(data);
        return {
          journal: result.journal,
          places: result.places,
          exportedAt: typeof data.exportedAt === "string" ? data.exportedAt : null,
          blobIds: Object.keys(photoEntries),
          getPhoto: function (id) {
            var entry = Object.prototype.hasOwnProperty.call(photoEntries, id) ? photoEntries[id] : null;
            if (!entry) return Promise.resolve(null);
            return entry.async("blob").then(function (b) { return b.slice(0, b.size, "image/jpeg"); });
          }
        };
      });
    });
  }

  window.TJ.backup = { create: create, open: open };
})();
