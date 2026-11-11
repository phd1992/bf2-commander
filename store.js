/* Storage for the journal.
 *
 * Two backends behind one interface:
 *   cloud - the Claude artifact runtime: `db` for places and trip details, `assets` for photos.
 *           Shared with everyone the journal is shared with, synced live.
 *   local - IndexedDB in this browser. Used when the page is opened outside Claude
 *           (or the runtime is unavailable) so the app still works, clearly labelled.
 */
(function () {
  "use strict";
  var TJ = (window.TJ = window.TJ || {});

  var state = {
    ready: false,
    mode: null, // "cloud" | "local" | "memory"
    journal: { title: "", subtitle: "", order: [] },
    places: {},
    canWrite: true,
    canUpload: true,
    canDownload: true,
    loadSlow: false, // cloud data has not answered within 10 s
    loadError: null,
  };
  var status = { saving: 0, failed: 0, lastError: null };
  var listeners = [];

  function emit() {
    listeners.slice().forEach(function (fn) {
      try { fn(); } catch (e) { console.error(e); }
    });
  }

  /* ---------- write queue: one write at a time per document, bursts coalesced ---------- */
  var writers = {};

  function refreshStatus() {
    var saving = 0, failed = 0, lastError = null;
    Object.keys(writers).forEach(function (k) {
      var w = writers[k];
      if (w.running || w.next) saving++;
      if (w.failed) { failed++; lastError = w.failed.error; }
    });
    status.saving = saving; status.failed = failed; status.lastError = lastError;
  }

  function busy(key) {
    var w = writers[key];
    return !!(w && (w.running || w.next || w.failed));
  }

  function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  function attempt(fn) {
    return fn().catch(function (e) {
      // transient platform trouble gets one quiet retry
      if (e && (e.code === "unavailable" || e.code === "store_unavailable")) {
        return sleep(700 + Math.random() * 600).then(fn);
      }
      throw e;
    });
  }

  function write(key, fn) {
    var w = writers[key] || (writers[key] = { running: false, next: null, failed: null, waiters: [] });
    w.next = fn; w.failed = null;
    var p = new Promise(function (resolve) { w.waiters.push(resolve); });
    pump(key);
    return p;
  }

  function pump(key) {
    var w = writers[key];
    if (w.running) { refreshStatus(); emit(); return; }
    w.running = true; refreshStatus(); emit();
    (function loop() {
      if (!w.next) {
        w.running = false;
        var waiters = w.waiters; w.waiters = [];
        refreshStatus(); emit();
        waiters.forEach(function (r) { r(!w.failed); });
        return;
      }
      var fn = w.next; w.next = null;
      attempt(fn).then(function () { loop(); }, function (e) {
        console.error("save failed", key, e);
        if (e && e.code === "invalid_argument" && state.mode === "cloud" && state.canWrite === null) state.canWrite = false;
        if (!w.next) w.failed = { fn: fn, error: e };
        loop();
      });
    })();
  }

  function retryFailed() {
    Object.keys(writers).forEach(function (k) {
      var w = writers[k];
      if (w.failed) write(k, w.failed.fn);
    });
  }

  function flush() {
    var keys = Object.keys(writers).filter(function (k) { return writers[k].running || writers[k].next; });
    return Promise.all(keys.map(function (k) {
      return new Promise(function (resolve) { writers[k].waiters.push(resolve); });
    })).then(function () { return status.failed === 0; });
  }

  /* ---------- backends ---------- */
  var backend = null;

  function clone(o) { return JSON.parse(JSON.stringify(o)); }

  function validPos(d) {
    return typeof d.lat === "number" && typeof d.lng === "number" && isFinite(d.lat) && isFinite(d.lng) && Math.abs(d.lat) <= 90 && Math.abs(d.lng) <= 180;
  }

  function normalisePlace(id, d) {
    d = d || {};
    return {
      id: id,
      name: typeof d.name === "string" ? d.name : "",
      location: typeof d.location === "string" ? d.location : "",
      category: typeof d.category === "string" ? d.category : "nature",
      review: typeof d.review === "string" ? d.review : "",
      notes: typeof d.notes === "string" ? d.notes : "",
      visitDate: typeof d.visitDate === "string" ? d.visitDate : "",
      recommendation: typeof d.recommendation === "string" ? d.recommendation : "",
      photos: Array.isArray(d.photos) ? d.photos.filter(function (p) { return p && typeof p.id === "string"; }).map(function (p) {
        return { id: p.id, thumb: typeof p.thumb === "string" ? p.thumb : p.id, w: +p.w || 0, h: +p.h || 0, caption: typeof p.caption === "string" ? p.caption : "" };
      }) : [],
      cover: typeof d.cover === "string" ? d.cover : null,
      lat: validPos(d) ? +d.lat : null,
      lng: validPos(d) ? +d.lng : null,
      posApprox: validPos(d) && d.posApprox === true,
      updatedAt: +d.updatedAt || 0,
    };
  }

  function normaliseJournal(d) {
    d = d || {};
    return {
      title: typeof d.title === "string" ? d.title : "",
      subtitle: typeof d.subtitle === "string" ? d.subtitle : "",
      order: Array.isArray(d.order) ? d.order.filter(function (x) { return typeof x === "string"; }) : [],
    };
  }

  /* cloud ------------------------------------------------------------- */
  function cloudBackend(db, assets, downloads) {
    var gotPlaces = false, gotJournal = false;
    var slowTimer = setTimeout(function () {
      if (!state.ready) { state.loadSlow = true; emit(); }
    }, 10000);

    function settle(fromCache) {
      if (gotPlaces && gotJournal) {
        state.ready = true;
        if (!fromCache) { clearTimeout(slowTimer); state.loadSlow = false; }
      }
      emit();
    }
    function fail(e) {
      clearTimeout(slowTimer);
      state.loadSlow = false;
      state.loadError = e || { code: "unavailable" };
      emit();
    }

    db.collection("places").onSnapshot(function (snap) {
      var next = {};
      snap.docs.forEach(function (doc) {
        var key = "place:" + doc.id;
        if (busy(key) && state.places[doc.id]) next[doc.id] = state.places[doc.id]; // keep the unsaved local edit
        else next[doc.id] = normalisePlace(doc.id, doc.data());
      });
      // places created here whose first write has not landed yet
      Object.keys(state.places).forEach(function (id) {
        if (!next[id] && busy("place:" + id) && !deleting[id]) next[id] = state.places[id];
      });
      Object.keys(deleting).forEach(function (id) { delete next[id]; });
      state.places = next;
      gotPlaces = true;
      settle(snap.metadata && snap.metadata.fromCache);
    }, fail);

    db.doc("journal/main").onSnapshot(function (snap) {
      if (!busy("journal")) state.journal = normaliseJournal(snap.exists ? snap.data() : null);
      gotJournal = true;
      settle(snap.metadata && snap.metadata.fromCache);
    }, fail);

    var uploadMessages = {
      quota_or_state: "Photo storage for this journal is full or unavailable. Remove some photos, then try again.",
      too_large: "This photo is too large to store.",
      rate_limited: "Photos are uploading too quickly. Wait a moment, then retry.",
      upstream_auth: "You seem to be signed out. Reload the page, then retry.",
      not_granted: "Only people who can edit this journal can add photos.",
    };

    return {
      setPlace: function (id, data) { return db.doc("places/" + id).set(data); },
      removePlace: function (id) { return db.doc("places/" + id).delete(); },
      setJournal: function (data) { return db.doc("journal/main").set(data); },
      putPhoto: function (blob) {
        return attempt(function () { return assets.upload(blob, { type: "image/jpeg" }); }).then(function (r) { return r.id; }, function (e) {
          var err = new Error((e && e.message) || "upload failed");
          err.code = e && e.code;
          err.userMessage = uploadMessages[err.code] || "Upload failed. Check your connection and try again.";
          throw err;
        });
      },
      deletePhoto: function (id) { return assets ? assets.delete(id).catch(function () {}) : Promise.resolve(); },
      photoUrl: function (id) { return "/_blob/" + id; },
      getPhotoBlob: function (id) {
        return fetch("/_blob/" + id).then(function (r) {
          if (!r.ok) throw new Error("photo " + id + " " + r.status);
          return r.blob();
        });
      },
      listPhotoIds: function () {
        if (!assets) return Promise.resolve(null);
        return assets.list().then(function (r) { return r.assets.map(function (a) { return a.id; }); }, function () { return null; });
      },
      download: function (filename, blob) {
        if (!downloads) return Promise.reject(Object.assign(new Error("unavailable"), { code: "unavailable" }));
        return downloads.save({ filename: filename, data: blob });
      },
    };
  }

  /* local ------------------------------------------------------------- */
  function idb() {
    return new Promise(function (resolve, reject) {
      var req = indexedDB.open("travel-journal", 1);
      req.onupgradeneeded = function () {
        req.result.createObjectStore("docs");
        req.result.createObjectStore("blobs");
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
  }

  function localBackend(dbh) {
    var urls = {}; // photo id -> object URL
    var mem = { docs: {}, blobs: {} };

    function tx(store, mode, fn) {
      if (!dbh) return Promise.resolve(fn(null));
      return new Promise(function (resolve, reject) {
        var t = dbh.transaction(store, mode), out;
        out = fn(t.objectStore(store));
        t.oncomplete = function () { resolve(out && out.result !== undefined ? out.result : out); };
        t.onerror = t.onabort = function () { reject(t.error); };
      });
    }
    function put(store, key, value) {
      if (!dbh) { mem[store][key] = value; return Promise.resolve(); }
      return tx(store, "readwrite", function (s) { s.put(value, key); });
    }
    function del(store, key) {
      if (!dbh) { delete mem[store][key]; return Promise.resolve(); }
      return tx(store, "readwrite", function (s) { s.delete(key); });
    }
    function all(store) {
      if (!dbh) return Promise.resolve(Object.keys(mem[store]).map(function (k) { return [k, mem[store][k]]; }));
      return new Promise(function (resolve, reject) {
        var out = [], t = dbh.transaction(store, "readonly");
        var cur = t.objectStore(store).openCursor();
        cur.onsuccess = function () {
          var c = cur.result;
          if (c) { out.push([c.key, c.value]); c.continue(); } else resolve(out);
        };
        cur.onerror = function () { reject(cur.error); };
      });
    }
    function newId() {
      var a = new Uint8Array(12); crypto.getRandomValues(a);
      return "ph" + Array.prototype.map.call(a, function (b) { return ("0" + b.toString(16)).slice(-2); }).join("");
    }

    return {
      load: function () {
        return Promise.all([all("docs"), all("blobs")]).then(function (res) {
          res[1].forEach(function (kv) { urls[kv[0]] = URL.createObjectURL(kv[1]); });
          var journal = null, places = {};
          res[0].forEach(function (kv) {
            if (kv[0] === "journal") journal = kv[1];
            else if (kv[0].indexOf("place:") === 0) places[kv[0].slice(6)] = kv[1];
          });
          if (journal) return { journal: journal, places: places };
          // first visit on this device: start from the supplied review notes
          return fetch("seed.json").then(function (r) { return r.json(); }).then(function (seed) {
            var writes = [put("docs", "journal", seed.journal)];
            seed.places.forEach(function (p) { places[p.id] = p; writes.push(put("docs", "place:" + p.id, p)); });
            return Promise.all(writes).then(function () { return { journal: seed.journal, places: places }; });
          }).catch(function () { return { journal: { title: "", subtitle: "", order: [] }, places: {} }; });
        });
      },
      setPlace: function (id, data) { return put("docs", "place:" + id, data); },
      removePlace: function (id) { return del("docs", "place:" + id); },
      setJournal: function (data) { return put("docs", "journal", data); },
      putPhoto: function (blob) {
        var id = newId();
        return put("blobs", id, blob).then(function () { urls[id] = URL.createObjectURL(blob); return id; }, function (e) {
          var err = new Error("local store failed");
          err.userMessage = "This device couldn't store the photo. Free up some space, then retry.";
          throw err;
        });
      },
      deletePhoto: function (id) {
        if (urls[id]) { URL.revokeObjectURL(urls[id]); delete urls[id]; }
        return del("blobs", id).catch(function () {});
      },
      photoUrl: function (id) { return urls[id] || ""; },
      getPhotoBlob: function (id) {
        if (!dbh) return Promise.resolve(mem.blobs[id] || null);
        return tx("blobs", "readonly", function (s) { return s.get(id); });
      },
      listPhotoIds: function () { return Promise.resolve(Object.keys(urls)); },
      download: function (filename, blob) {
        var a = document.createElement("a");
        a.href = URL.createObjectURL(blob); a.download = filename;
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(function () { URL.revokeObjectURL(a.href); }, 60000);
        return Promise.resolve({ status: "saved" });
      },
    };
  }

  /* ---------- init ---------- */
  function use(name) {
    try {
      if (!window.claude || typeof window.claude.use !== "function") return Promise.resolve(null);
      return window.claude.use(name).catch(function () { return null; });
    } catch (e) { return Promise.resolve(null); }
  }

  function init() {
    return Promise.all([use("db"), use("assets"), use("downloads"), use("user")]).then(function (caps) {
      var db = caps[0], assets = caps[1], downloads = caps[2], user = caps[3];
      if (db) {
        state.mode = "cloud";
        state.canUpload = !!assets;
        state.canDownload = !!downloads;
        state.canWrite = null; // unknown until the platform says, or a write is refused
        backend = cloudBackend(db, assets, downloads);
        if (user && typeof user.can === "function") {
          user.can("data.write").then(function (ok) {
            if (ok === false) state.canWrite = false;
            else if (ok === true) state.canWrite = true;
            emit();
          }, function () {});
        }
        emit();
        return;
      }
      return idb().catch(function () { return null; }).then(function (dbh) {
        state.mode = dbh ? "local" : "memory";
        backend = localBackend(dbh);
        return backend.load().then(function (data) {
          state.journal = normaliseJournal(data.journal);
          Object.keys(data.places).forEach(function (id) { state.places[id] = normalisePlace(id, data.places[id]); });
          state.ready = true;
          emit();
        });
      });
    });
  }

  /* ---------- public operations ---------- */
  var deleting = {};

  function placeDoc(p) { var d = clone(p); delete d.id; return d; }

  function savePlace(place) {
    var p = normalisePlace(place.id, place);
    p.updatedAt = Date.now();
    state.places[p.id] = p;
    delete deleting[p.id];
    var doc = placeDoc(p);
    var done = write("place:" + p.id, function () { return backend.setPlace(p.id, doc); });
    if (state.journal.order.indexOf(p.id) < 0) saveJournal({ order: state.journal.order.concat([p.id]) });
    return done;
  }

  function deletePlace(id, opts) {
    var p = opts && opts.keepPhotos ? null : state.places[id];
    delete state.places[id];
    deleting[id] = true;
    var done = write("place:" + id, function () { return backend.removePlace(id); }).then(function (ok) {
      if (ok) delete deleting[id];
      return ok;
    });
    saveJournal({ order: state.journal.order.filter(function (x) { return x !== id; }) });
    if (p) p.photos.forEach(function (ph) { backend.deletePhoto(ph.id); if (ph.thumb !== ph.id) backend.deletePhoto(ph.thumb); });
    return done;
  }

  function saveJournal(patch) {
    var j = normaliseJournal(Object.assign({}, state.journal, patch));
    state.journal = j;
    var doc = clone(j);
    return write("journal", function () { return backend.setJournal(doc); });
  }

  function orderedPlaces() {
    var seen = {}, out = [];
    state.journal.order.forEach(function (id) {
      if (state.places[id] && !seen[id]) { seen[id] = true; out.push(state.places[id]); }
    });
    Object.keys(state.places).sort().forEach(function (id) { if (!seen[id]) out.push(state.places[id]); });
    return out;
  }

  TJ.store = {
    state: state,
    status: status,
    subscribe: function (fn) { listeners.push(fn); },
    init: init,
    savePlace: savePlace,
    deletePlace: deletePlace,
    saveJournal: saveJournal,
    orderedPlaces: orderedPlaces,
    retryFailed: retryFailed,
    flush: flush,
    putPhoto: function (blob) { return backend.putPhoto(blob); },
    deletePhoto: function (id) { return backend.deletePhoto(id); },
    photoUrl: function (id) { return backend ? backend.photoUrl(id) : ""; },
    getPhotoBlob: function (id) { return backend.getPhotoBlob(id); },
    listPhotoIds: function () { return backend.listPhotoIds(); },
    download: function (filename, blob) { return backend.download(filename, blob); },
  };
})();
