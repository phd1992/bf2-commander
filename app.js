/* Travel journal UI. State lives in TJ.store; this file renders it and wires the controls. */
(function () {
  "use strict";
  var TJ = window.TJ, store = TJ.store, S = store.state;
  function $(id) { return document.getElementById(id); }

  var CATS = [
    ["accommodation", "Accommodation"],
    ["restaurant", "Restaurant/bar"],
    ["nature", "Nature/activity"],
    ["estate", "Estate/garden"],
    ["transport", "Transport"],
  ];
  var RECS = ["Highly recommended", "Recommended", "Optional"];
  var ID_OK = /^[A-Za-z0-9_\-.~:@+]{1,200}$/;

  var ui = {
    view: "cards", filter: "all", reorder: false,
    openId: null, isNew: false, editing: false, managing: false, confirmRemove: null,
    dragging: false, lb: null, feedTarget: null, focusField: null,
    mapSel: null, placing: null,
  };
  try {
    var saved = JSON.parse(localStorage.getItem("tj-ui") || "{}");
    if (saved.view === "list" || saved.view === "cards" || saved.view === "map") ui.view = saved.view;
    if (saved.filter && (saved.filter === "all" || CATS.some(function (c) { return c[0] === saved.filter; }))) ui.filter = saved.filter;
  } catch (e) {}
  function remember() {
    try { localStorage.setItem("tj-ui", JSON.stringify({ view: ui.view, filter: ui.filter })); } catch (e) {}
  }

  var ICON_CAMERA = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l1.6-2.4h6.8L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="3.6"/></svg>';
  var ICON_GRIP = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="9" cy="6" r="1.6"/><circle cx="15" cy="6" r="1.6"/><circle cx="9" cy="12" r="1.6"/><circle cx="15" cy="12" r="1.6"/><circle cx="9" cy="18" r="1.6"/><circle cx="15" cy="18" r="1.6"/></svg>';

  /* ---------- helpers ---------- */
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function catLabel(key) {
    for (var i = 0; i < CATS.length; i++) if (CATS[i][0] === key) return CATS[i][1];
    return key || "";
  }
  function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s"); }
  function fmtDate(iso) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "");
    if (!m) return "";
    return new Date(+m[1], +m[2] - 1, +m[3]).toLocaleDateString(undefined, { day: "numeric", month: "long", year: "numeric" });
  }
  function recClass(r) { return r === RECS[0] ? "rec rec-high" : r === RECS[1] ? "rec rec-yes" : "rec"; }
  function coverOf(p) {
    if (!p.photos.length) return null;
    for (var i = 0; i < p.photos.length; i++) if (p.photos[i].id === p.cover) return p.photos[i];
    return p.photos[0];
  }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function canEdit() { return S.canWrite !== false; }
  function canAddPhotos() { return canEdit() && S.canUpload; }
  function setHTML(el, html) {
    if (el._html === html) return;
    el._html = html;
    el.innerHTML = html;
  }
  function newPlaceId(name) {
    var slug = String(name).toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "place";
    return slug + "-" + Math.random().toString(36).slice(2, 7);
  }

  var toastTimer = null;
  function toast(msg) {
    var t = $("toast");
    // a modal dialog sits in the top layer; the toast must live inside the topmost one to be seen
    var open = Array.prototype.filter.call(document.querySelectorAll("dialog[open]"), function () { return true; });
    var host = open.length ? ($("modal").open ? $("modal") : $("lightbox").open ? $("lightbox") : $("sheet")) : document.body;
    if (t.parentNode !== host) host.appendChild(t);
    t.textContent = msg; t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, 3200);
  }

  function hasPos(p) { return typeof p.lat === "number" && typeof p.lng === "number"; }
  function fmtPos(p) { return hasPos(p) ? p.lat.toFixed(5) + ", " + p.lng.toFixed(5) : ""; }
  // accepts "-33.98, 18.43" or a pasted Google / Apple Maps link
  function parsePos(text) {
    var t = String(text || "").trim(), m;
    if (!t) return null;
    m = /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/.exec(t) || /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/.exec(t) ||
      /[?&](?:q|ll|query|center|destination)=(-?\d+(?:\.\d+)?)(?:,|%2C)\s*(-?\d+(?:\.\d+)?)/i.exec(t) ||
      /^(-?\d+(?:[.,]\d+)?)\s*[,;\s]\s*(-?\d+(?:[.,]\d+)?)$/.exec(t);
    if (!m) return false;
    var lat = parseFloat(m[1].replace(",", ".")), lng = parseFloat(m[2].replace(",", "."));
    if (!isFinite(lat) || !isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
    return { lat: +lat.toFixed(5), lng: +lng.toFixed(5) };
  }
  function mapsLink(p) {
    var q = hasPos(p) && !p.posApprox ? p.lat + "," + p.lng : [p.name, p.location, S.journal.title].filter(Boolean).join(", ");
    return "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(q);
  }

  /* ---------- uploads ---------- */
  var queue = TJ.createUploadQueue({
    onChange: function () { render(); },
    upload: function (prepared) {
      var item = arguments[1];
      var fullId, thumbId;
      return store.putPhoto(prepared.full).then(function (id) {
        fullId = id;
        return store.putPhoto(prepared.thumb);
      }).then(function (id) {
        thumbId = id;
        var place = S.places[item.groupId];
        if (!place) { // the place was deleted while the photo was on its way
          store.deletePhoto(fullId); store.deletePhoto(thumbId);
          return;
        }
        var p = clone(place);
        p.photos.push({ id: fullId, thumb: thumbId, w: prepared.width, h: prepared.height, caption: "" });
        if (!coverOf(place)) p.cover = fullId;
        store.savePlace(p);
      }, function (e) {
        if (fullId) store.deletePhoto(fullId);
        throw e;
      });
    },
  });

  function addFiles(placeId, fileList) {
    var files = Array.prototype.slice.call(fileList || []);
    if (!files.length || !placeId || !S.places[placeId]) return;
    if (!canAddPhotos()) { toast("Only people who can edit this journal can add photos."); return; }
    queue.add(placeId, files);
    render();
  }

  /* ---------- recap ---------- */
  function recapText() {
    var j = S.journal;
    var head = [j.title, j.subtitle].filter(Boolean).join(" — ");
    var lines = store.orderedPlaces().map(function (p) {
      var s = "• " + p.name + (p.location ? ", " + p.location : "") + " — " + catLabel(p.category);
      if (p.review) s += ": " + p.review;
      if (p.recommendation) s += " (" + p.recommendation + ")";
      return s;
    });
    return (head ? head + "\n\n" : "") + lines.join("\n");
  }

  function copyRecap() {
    var text = recapText();
    function fallback() {
      openModal('<h2>Trip recap</h2><p>Copying isn\'t allowed in this view. Select the text below and copy it.</p>' +
        '<textarea class="copy" id="recap-text" readonly></textarea><div class="form-actions"><button type="button" class="btn" data-m="close">Done</button></div>', {});
      var ta = $("recap-text"); ta.value = text; ta.focus(); ta.select();
    }
    try {
      navigator.clipboard.writeText(text).then(function () { toast("Recap copied: " + plural(store.orderedPlaces().length, "place")); }, fallback);
    } catch (e) { fallback(); }
  }

  /* ---------- rendering ---------- */
  var renderQueued = false;
  function render() {
    if (renderQueued) return;
    renderQueued = true;
    Promise.resolve().then(function () { renderQueued = false; renderNow(); });
  }

  function saveStatus() {
    var st = store.status, items = queue.all();
    var active = queue.activeCount();
    var failedUploads = items.filter(function (i) { return i.status === "error"; }).length;
    if (st.failed) return { cls: "is-error", html: 'Couldn\'t save changes · <button type="button" class="linkbtn" data-act="retry-save">Retry</button>' };
    if (active) return { cls: "is-busy", html: "Uploading " + plural(active, "photo") + "…" };
    if (st.saving) return { cls: "is-busy", html: "Saving…" };
    if (failedUploads) return { cls: "is-error", html: plural(failedUploads, "photo") + " not uploaded" };
    if (!S.ready) return { cls: "", html: "" };
    if (S.mode === "cloud") return { cls: "", html: "All changes saved" };
    if (S.mode === "local") return { cls: "", html: "Saved on this device" };
    return { cls: "is-error", html: "Not saved" };
  }

  function bannerText() {
    if (S.loadError) return "Your journal couldn't be loaded. Reload the page to try again.";
    if (S.loadSlow) return S.ready ? "Still connecting. What you see may be out of date." : "Still trying to reach your journal…";
    if (S.mode === "local") return "This copy is saved in this browser only. Open the journal in Claude to keep it in sync across your devices.";
    if (S.mode === "memory") return "This browser is blocking storage, so changes here are lost when the page closes.";
    if (S.mode === "cloud" && S.canWrite === false) return "You have view-only access to this journal.";
    return "";
  }

  function photoArea(p) {
    var c = coverOf(p);
    if (c) {
      return '<div class="card-photo"><img loading="lazy" src="' + esc(store.photoUrl(c.thumb)) + '" alt="' + esc(c.caption || p.name) + '">' +
        (p.photos.length > 1 ? '<span class="card-count">' + plural(p.photos.length, "photo") + "</span>" : "") + "</div>";
    }
    if (!canAddPhotos()) return "";
    return '<div class="ph-empty">' + ICON_CAMERA +
      '<label class="btn btn-small btn-quiet" for="feed-pick" data-act="pick-feed">Add photos</label></div>';
  }

  function queueLine(id) {
    var items = queue.items(id);
    if (!items.length) return "";
    var bad = items.filter(function (i) { return i.status === "error"; }).length;
    var going = items.length - bad;
    var parts = [];
    if (going) parts.push("Uploading " + plural(going, "photo") + "…");
    if (bad) parts.push('<span class="err">' + plural(bad, "photo") + " failed. Open to retry.</span>");
    return '<p class="subline">' + parts.join(" ") + "</p>";
  }

  function cardHTML(p) {
    var sub = [];
    if (p.visitDate) sub.push("<span>" + esc(fmtDate(p.visitDate)) + "</span>");
    if (p.recommendation) sub.push('<span class="' + recClass(p.recommendation) + '">' + esc(p.recommendation) + "</span>");
    return '<article class="card" data-id="' + esc(p.id) + '">' + photoArea(p) +
      '<div class="card-text"><p class="meta"><span>' + esc(catLabel(p.category)) + "</span>" +
      (p.location ? '<span class="loc">' + esc(p.location) + "</span>" : "") + "</p>" +
      '<h2><a href="#p-' + esc(p.id) + '" style="color:inherit;text-decoration:none">' + esc(p.name || "Untitled place") + "</a></h2>" +
      (sub.length ? '<p class="subline">' + sub.join("") + "</p>" : "") +
      (p.review ? '<p class="card-review">' + esc(p.review) + "</p>" : "") +
      queueLine(p.id) + "</div></article>";
  }

  function feedHTML() {
    if (!S.ready) return '<div class="empty"><p>Opening your journal…</p></div>';
    var all = store.orderedPlaces();
    if (!all.length) {
      return '<div class="empty"><h2>No places yet</h2><p>Add the first place you visited. Photos can follow later.</p>' +
        (canEdit() ? '<button type="button" class="btn btn-primary" data-act="add">Add place</button>' : "") + "</div>";
    }
    if (ui.reorder) {
      return '<div style="grid-column:1/-1"><div class="reorder-head"><span>Drag a handle, or use the arrows.</span>' +
        '<button type="button" class="btn btn-primary btn-small" data-act="reorder">Done</button></div><ol class="sortlist" data-sortlist="places">' +
        all.map(function (p, i) {
          return '<li class="sortrow" data-sort="' + esc(p.id) + '"><button type="button" class="grip" aria-label="Drag ' + esc(p.name) + '">' + ICON_GRIP + "</button>" +
            '<span class="label"><b>' + esc(p.name || "Untitled place") + "</b><small>" + esc(catLabel(p.category)) + "</small></span>" +
            '<button type="button" class="iconbtn" data-act="pl-up" aria-label="Move ' + esc(p.name) + ' up"' + (i === 0 ? " disabled" : "") + ">↑</button>" +
            '<button type="button" class="iconbtn" data-act="pl-down" aria-label="Move ' + esc(p.name) + ' down"' + (i === all.length - 1 ? " disabled" : "") + ">↓</button></li>";
        }).join("") + "</ol></div>";
    }
    var shown = ui.filter === "all" ? all : all.filter(function (p) { return p.category === ui.filter; });
    if (!shown.length) {
      return '<div class="empty"><p>No places in ' + esc(catLabel(ui.filter)) + ' yet.</p><button type="button" class="btn btn-quiet" data-act="filter" data-filter="all">Show all places</button></div>';
    }
    if (ui.view === "list") {
      return '<ul class="recap" style="grid-column:1/-1">' + shown.map(function (p) {
        return '<li data-id="' + esc(p.id) + '"><strong>' + esc(p.name || "Untitled place") + "</strong>" + (p.location ? ", " + esc(p.location) : "") +
          ' <span class="cat">' + esc(catLabel(p.category)) + "</span>" + (p.review ? " — " + esc(p.review) : "") +
          (p.recommendation ? ' <span class="' + recClass(p.recommendation) + '">' + esc(p.recommendation) + "</span>" : "") + "</li>";
      }).join("") + "</ul>";
    }
    return shown.map(cardHTML).join("");
  }

  function chipsHTML() {
    var all = store.orderedPlaces(), counts = {};
    all.forEach(function (p) { counts[p.category] = (counts[p.category] || 0) + 1; });
    var out = '<button type="button" class="chip" data-act="filter" data-filter="all" aria-pressed="' + (ui.filter === "all") + '">All<span>' + all.length + "</span></button>";
    CATS.forEach(function (c) {
      out += '<button type="button" class="chip" data-act="filter" data-filter="' + c[0] + '" aria-pressed="' + (ui.filter === c[0]) + '">' + esc(c[1]) + "<span>" + (counts[c[0]] || 0) + "</span></button>";
    });
    return out;
  }

  function renderNow() {
    if (ui.dragging) return;
    var all = store.orderedPlaces();
    document.body.classList.toggle("readonly", !canEdit());
    $("trip-title").textContent = S.journal.title || (S.ready ? "Untitled trip" : " ");
    $("trip-sub").textContent = S.journal.subtitle || "";
    var nPhotos = all.reduce(function (n, p) { return n + p.photos.length; }, 0);
    $("trip-stats").textContent = S.ready ? plural(all.length, "place") + " · " + plural(nPhotos, "photo") : "";
    var b = bannerText();
    $("banner").hidden = !b; $("banner-text").textContent = b;
    setHTML($("chips"), chipsHTML());
    $("view-cards").setAttribute("aria-pressed", ui.view === "cards");
    $("view-list").setAttribute("aria-pressed", ui.view === "list");
    $("view-map").setAttribute("aria-pressed", ui.view === "map");
    var showMap = ui.view === "map" && !ui.reorder && S.ready && all.length > 0;
    $("mapview").hidden = !showMap;
    $("feed").hidden = showMap;
    if (showMap) renderMap(all);
    $("btn-reorder").textContent = ui.reorder ? "Done" : "Reorder";
    setHTML($("feed"), feedHTML());
    var st = saveStatus();
    ["save-status", "sheet-save"].forEach(function (id) {
      var el = $(id); el.className = "save " + st.cls; setHTML(el, st.html);
    });
    renderSheet();
    renderLightbox();
  }

  /* ---------- place sheet ---------- */
  function queueHTML(id) {
    var items = queue.items(id);
    if (!items.length) return "";
    var label = { queued: "Waiting…", preparing: "Preparing…", uploading: "Uploading…", done: "Added" };
    return '<ul class="queue" aria-label="Photo uploads">' + items.map(function (it) {
      var err = it.status === "error";
      return '<li class="q' + (err ? " is-error" : "") + '" data-q="' + esc(it.id) + '">' +
        (it.previewUrl ? '<img class="q-thumb" src="' + esc(it.previewUrl) + '" alt="">' : '<span class="q-thumb"></span>') +
        '<div class="q-main"><span class="q-name">' + esc(it.name) + "</span>" +
        (err ? '<span class="q-state">' + esc(it.error || "Upload failed.") + "</span>"
          : '<div class="bar"><i style="width:' + Math.round((it.progress || 0) * 100) + '%"></i></div><span class="q-state">' + label[it.status] + "</span>") +
        "</div>" +
        (err ? '<div class="q-actions"><button type="button" class="btn btn-small" data-act="q-retry">Retry</button><button type="button" class="btn btn-small btn-quiet" data-act="q-dismiss">Dismiss</button></div>' : "<span></span>") +
        "</li>";
    }).join("") + "</ul>";
  }

  function photosHTML(p) {
    var out = "", c = coverOf(p), add = canAddPhotos();
    var buttons = add ? '<label class="btn btn-primary" for="sheet-pick">' + ICON_CAMERA + 'Add photos</label><label class="btn" for="sheet-camera">Take photo</label>' : "";
    if (!p.photos.length) {
      if (add) {
        out += '<div class="drop">' + ICON_CAMERA + "<p>No photos yet. Choose several from your library, or take one now.</p>" +
          '<div class="photo-actions" style="justify-content:center">' + buttons + '</div><p class="hint">On a computer you can also drag photos onto this page.</p></div>';
      } else if (S.mode === "cloud" && canEdit()) {
        out += '<p class="hint">Only people with edit access to this journal can add photos.</p>';
      }
      return out + queueHTML(p.id);
    }
    if (ui.managing) {
      out += '<ul class="manage" data-sortlist="photos">' + p.photos.map(function (ph, i) {
        var isCover = c && c.id === ph.id;
        var row;
        if (ui.confirmRemove === ph.id) {
          row = '<span class="err">Remove this photo?</span><button type="button" class="btn btn-small btn-danger" data-act="ph-remove-yes">Remove</button><button type="button" class="btn btn-small btn-quiet" data-act="ph-remove-no">Keep</button>';
        } else {
          row = (isCover ? '<span class="tag">Cover photo</span>' : '<button type="button" class="btn btn-small btn-quiet" data-act="ph-cover">Make cover</button>') +
            '<button type="button" class="iconbtn" data-act="ph-up" aria-label="Move photo earlier"' + (i === 0 ? " disabled" : "") + ">↑</button>" +
            '<button type="button" class="iconbtn" data-act="ph-down" aria-label="Move photo later"' + (i === p.photos.length - 1 ? " disabled" : "") + ">↓</button>" +
            '<button type="button" class="btn btn-small btn-quiet" data-act="ph-remove">Remove</button>';
        }
        return '<li class="m" data-sort="' + esc(ph.id) + '" data-ph="' + esc(ph.id) + '"><button type="button" class="grip" aria-label="Drag photo ' + (i + 1) + '">' + ICON_GRIP + "</button>" +
          '<img loading="lazy" src="' + esc(store.photoUrl(ph.thumb)) + '" alt="Photo ' + (i + 1) + '">' +
          '<div class="m-main"><input class="cap" id="cap-' + esc(ph.id) + '" type="text" maxlength="300" placeholder="Caption (optional)" aria-label="Caption for photo ' + (i + 1) + '" value="' + esc(ph.caption) + '">' +
          '<div class="m-row">' + row + "</div></div></li>";
      }).join("") + "</ul>";
    } else {
      var ci = p.photos.indexOf(c);
      out += '<button type="button" class="hero" data-act="lb" data-i="' + ci + '" aria-label="View cover photo"><img src="' + esc(store.photoUrl(c.id)) + '" alt="' + esc(c.caption || p.name) + '"></button>';
      if (p.photos.length > 1) {
        out += '<div class="thumbs">' + p.photos.map(function (ph, i) {
          return '<button type="button" data-act="lb" data-i="' + i + '" aria-label="View photo ' + (i + 1) + '"><img loading="lazy" src="' + esc(store.photoUrl(ph.thumb)) + '" alt="' + esc(ph.caption || "Photo " + (i + 1)) + '"></button>';
        }).join("") + "</div>";
      }
    }
    out += queueHTML(p.id);
    var manageBtn = canEdit() ? '<button type="button" class="btn btn-quiet" data-act="manage">' + (ui.managing ? "Done" : "Edit photos") + "</button>" : "";
    out += '<div class="photo-actions">' + buttons + manageBtn + "</div>";
    return out;
  }

  function viewHTML(p) {
    var sub = [];
    if (p.visitDate) sub.push("<span>Visited " + esc(fmtDate(p.visitDate)) + "</span>");
    if (p.recommendation) sub.push('<span class="' + recClass(p.recommendation) + '">' + esc(p.recommendation) + "</span>");
    return '<p class="meta"><span>' + esc(catLabel(p.category)) + "</span>" + (p.location ? '<span class="loc">' + esc(p.location) + "</span>" : "") + "</p>" +
      '<h2 class="place-name" id="sheet-name">' + esc(p.name || "Untitled place") + "</h2>" +
      (sub.length ? '<p class="subline">' + sub.join("") + "</p>" : "") +
      (p.review ? '<p class="review"' + (canEdit() ? ' data-act="edit-review" data-edit-review title="Tap to edit"' : "") + ">" + esc(p.review) + "</p>"
        : (canEdit() ? '<p class="review is-empty" data-act="edit-review" data-edit-review>No review yet. Tap to write one.</p>' : "")) +
      '<p class="place-links">' + (hasPos(p) ? '<button type="button" class="btn btn-small btn-quiet" data-act="show-on-map">Show on map</button>' : "") +
      '<a class="btn btn-small btn-quiet" target="_blank" rel="noopener" href="' + esc(mapsLink(p)) + '">Open in Google Maps</a></p>' +
      (p.notes ? '<div class="notes"><h3>Dictated notes</h3><p>' + esc(p.notes) + "</p></div>" : "");
  }

  /* ---------- map view ---------- */
  var map = null;
  function renderMap(all) {
    if (!map && TJ.createMap) {
      map = TJ.createMap($("map"), {
        onSelect: function (id) { if (ui.placing) return; ui.mapSel = id; render(); },
        onPlace: function (lat, lng) {
          var place = S.places[ui.placing];
          ui.placing = null; map.setPlacing(false);
          if (!place) { render(); return; }
          var p = clone(place); p.lat = lat; p.lng = lng; p.posApprox = false;
          store.savePlace(p); ui.mapSel = p.id; render(); toast("Pin placed");
        },
      });
    }
    var shown = ui.filter === "all" ? all : all.filter(function (p) { return p.category === ui.filter; });
    var pins = [], unplaced = [];
    all.forEach(function (p, i) {
      if (shown.indexOf(p) < 0) return;
      if (hasPos(p)) pins.push({ id: p.id, name: p.name || "Untitled place", lat: p.lat, lng: p.lng, number: i + 1 });
      else unplaced.push(p);
    });
    if (ui.mapSel && !pins.some(function (x) { return x.id === ui.mapSel; })) ui.mapSel = null;
    if (ui.placing && !S.places[ui.placing]) { ui.placing = null; if (map) map.setPlacing(false); }
    if (map) { map.resize(); map.setData({ pins: pins, selectedId: ui.mapSel }); }

    var html = "";
    if (!map) html += '<p class="hint">The map couldn\'t be loaded.</p>';
    if (ui.placing) {
      html += '<div class="map-note"><span>Tap the map where <b>' + esc(S.places[ui.placing].name) + '</b> is. Zoom in first for a precise spot.</span><button type="button" class="btn btn-small btn-quiet" data-act="place-cancel">Cancel</button></div>';
    } else if (ui.mapSel) {
      var p = S.places[ui.mapSel];
      html += '<div class="map-sel" data-map-id="' + esc(p.id) + '"><p class="meta"><span>' + esc(catLabel(p.category)) + "</span>" + (p.location ? '<span class="loc">' + esc(p.location) + "</span>" : "") + "</p>" +
        "<h2>" + esc(p.name || "Untitled place") + "</h2>" + (p.review ? '<p class="card-review">' + esc(p.review) + "</p>" : "") +
        (p.posApprox ? '<p class="hint">This pin is an approximate position. Move it if it is off.</p>' : "") +
        '<p class="place-links"><button type="button" class="btn btn-small btn-primary" data-act="map-open">Open place</button>' +
        (canEdit() ? '<button type="button" class="btn btn-small btn-quiet" data-act="place-pin">Move pin</button><button type="button" class="btn btn-small btn-quiet" data-act="unpin">Remove pin</button>' : "") + "</p></div>";
    } else if (pins.length) {
      html += '<p class="hint">Tap a numbered pin to read its review. Numbers follow the order of your journal.</p>';
    } else {
      html += '<p class="hint">No places are on the map yet.</p>';
    }
    if (unplaced.length) {
      html += '<div class="unplaced"><h3>Not on the map yet</h3>' + unplaced.map(function (p) {
        return '<div class="unplaced-row" data-map-id="' + esc(p.id) + '"><b>' + esc(p.name || "Untitled place") + "</b>" +
          (canEdit() ? '<button type="button" class="btn btn-small btn-quiet" data-act="place-pin">Place on map</button>' : "") + "</div>";
      }).join("") + "</div>";
    }
    setHTML($("map-panel"), html);
  }
  function showOnMap(id) {
    forceCloseSheet();
    ui.view = "map"; ui.reorder = false; ui.filter = "all"; ui.mapSel = id; remember();
    renderNow();
    if (map) map.focus(id);
    $("mapview").scrollIntoView({ block: "start" });
  }

  function formHTML(p, isNew) {
    return '<form class="form" id="place-form" novalidate>' +
      '<h2 class="place-name" id="sheet-name" style="font-size:28px">' + (isNew ? "Add a place" : "Edit place") + "</h2>" +
      '<div class="field"><label for="f-name">Name</label><input id="f-name" type="text" maxlength="200" required value="' + esc(p.name) + '" autocomplete="off"><span class="err" id="f-name-err" hidden>Give the place a name.</span></div>' +
      '<div class="pair"><div class="field"><label for="f-location">Location</label><input id="f-location" type="text" maxlength="200" value="' + esc(p.location) + '" placeholder="Town or area" autocomplete="off"></div>' +
      '<div class="field"><label for="f-category">Category</label><select id="f-category">' + CATS.map(function (c) {
        return '<option value="' + c[0] + '"' + (p.category === c[0] ? " selected" : "") + ">" + esc(c[1]) + "</option>";
      }).join("") + "</select></div></div>" +
      '<div class="field"><label for="f-review">Review</label><textarea id="f-review" class="serif" rows="6" maxlength="5000">' + esc(p.review) + "</textarea></div>" +
      '<div class="pair"><div class="field"><label for="f-date">Visit date (optional)</label><input id="f-date" type="date" value="' + esc(p.visitDate) + '"></div>' +
      '<div class="field"><label for="f-rec">Recommendation (optional)</label><select id="f-rec"><option value="">Not set</option>' + RECS.map(function (r) {
        return "<option" + (p.recommendation === r ? " selected" : "") + ">" + esc(r) + "</option>";
      }).join("") + "</select></div></div>" +
      '<div class="field"><label for="f-pos">Map position (optional)</label><input id="f-pos" type="text" inputmode="text" autocomplete="off" placeholder="-33.9875, 18.4327" value="' + esc(fmtPos(p)) + '"><small>Paste coordinates or a Google Maps link. You can also use Place on map in the Map view.</small><span class="err" id="f-pos-err" hidden>That doesn\'t look like coordinates. Use latitude, longitude, for example -33.9875, 18.4327.</span></div>' +
      '<div class="field"><label for="f-notes">Dictated notes</label><textarea id="f-notes" rows="5" maxlength="20000" placeholder="Paste raw notes here">' + esc(p.notes) + "</textarea><small>Kept alongside the review exactly as pasted. Not included in the trip recap.</small></div>" +
      '<div class="form-actions"><button type="submit" class="btn btn-primary">' + (isNew ? "Add place" : "Save") + '</button><button type="button" class="btn btn-quiet" data-act="edit-cancel">Cancel</button><span class="spacer"></span>' +
      (isNew ? "" : '<button type="button" class="btn btn-danger" data-act="place-delete">Delete place</button>') + "</div></form>";
  }

  var blankPlace = { name: "", location: "", category: "restaurant", review: "", notes: "", visitDate: "", recommendation: "", photos: [], cover: null, lat: null, lng: null, posApprox: false };

  function renderSheet() {
    var sheet = $("sheet");
    if (!sheet.open) return;
    var p = ui.isNew ? blankPlace : S.places[ui.openId];
    if (!p) { // deleted elsewhere
      if (S.ready) forceCloseSheet();
      return;
    }
    $("sheet-edit").hidden = ui.editing || !canEdit();
    var photos = $("sheet-photos");
    var typing = document.activeElement && photos.contains(document.activeElement) && document.activeElement.tagName === "INPUT";
    if (!typing) {
      setHTML(photos, ui.isNew ? '<p class="hint">Save the place first, then add its photos.</p>' : photosHTML(p));
    }
    if (!ui.editing) setHTML($("sheet-body"), viewHTML(p));
  }

  function openSheet(id) {
    if (!S.places[id]) return;
    ui.openId = id; ui.isNew = false; ui.editing = false; ui.managing = false; ui.confirmRemove = null;
    showSheet();
    setHash("p-" + id);
  }
  function openNew() {
    ui.openId = null; ui.isNew = true; ui.managing = false;
    showSheet();
    startEdit("f-name");
  }
  function showSheet() {
    var sheet = $("sheet");
    $("sheet-photos")._html = null; $("sheet-body")._html = null;
    if (!sheet.open) sheet.showModal();
    renderSheet();
    $("sheet-scroll").scrollTop = 0;
  }
  function startEdit(focusId) {
    var p = ui.isNew ? blankPlace : S.places[ui.openId];
    if (!p || !canEdit()) return;
    ui.editing = true;
    var body = $("sheet-body");
    body._html = null;
    body.innerHTML = formHTML(p, ui.isNew);
    $("sheet-edit").hidden = true;
    var f = $(focusId || "f-review");
    if (f) { f.focus(); if (f.tagName === "TEXTAREA") f.setSelectionRange(f.value.length, f.value.length); }
    ui.formInitial = JSON.stringify(readForm());
  }
  function readForm() {
    return {
      name: $("f-name").value.trim(), location: $("f-location").value.trim(), category: $("f-category").value,
      review: $("f-review").value.trim(), notes: $("f-notes").value, visitDate: $("f-date").value, recommendation: $("f-rec").value,
      pos: $("f-pos").value.trim(),
    };
  }
  function formDirty() { return ui.editing && $("place-form") && JSON.stringify(readForm()) !== ui.formInitial; }
  function saveForm() {
    var v = readForm();
    if (!v.name) { $("f-name-err").hidden = false; $("f-name").focus(); return; }
    var pos = parsePos(v.pos), posText = v.pos;
    if (pos === false) { $("f-pos-err").hidden = false; $("f-pos").focus(); return; }
    delete v.pos;
    var before = ui.isNew ? blankPlace : S.places[ui.openId];
    if (before && posText !== fmtPos(before)) { // only touch the pin when the field was changed
      v.lat = pos ? pos.lat : null; v.lng = pos ? pos.lng : null; v.posApprox = false;
    }
    var p;
    if (ui.isNew) {
      p = Object.assign(clone(blankPlace), v, { id: newPlaceId(v.name) });
    } else {
      if (!S.places[ui.openId]) return;
      p = Object.assign(clone(S.places[ui.openId]), v); // photos may have changed while the form was open; take them fresh
    }
    store.savePlace(p);
    ui.editing = false;
    if (ui.isNew) { ui.isNew = false; ui.openId = p.id; setHash("p-" + p.id); toast("Place added"); }
    $("sheet-body")._html = null;
    render();
  }
  function forceCloseSheet() {
    ui.openId = null; ui.isNew = false; ui.editing = false; ui.managing = false; ui.confirmRemove = null;
    if ($("sheet").open) $("sheet").close();
    setHash("");
    render();
  }
  function requestCloseSheet() {
    if (formDirty()) {
      openModal("<h2>Discard your changes?</h2><p>The edits in this form haven't been saved.</p>" +
        '<div class="form-actions"><button type="button" class="btn btn-primary" data-m="close">Keep editing</button><button type="button" class="btn btn-danger" data-m="discard">Discard</button></div>',
        { discard: function () { closeModal(); forceCloseSheet(); } });
      return;
    }
    forceCloseSheet();
  }
  function cancelEdit() {
    if (ui.isNew) { requestCloseSheet(); return; }
    function go() { ui.editing = false; $("sheet-body")._html = null; render(); }
    if (formDirty()) {
      openModal("<h2>Discard your changes?</h2><p>The edits in this form haven't been saved.</p>" +
        '<div class="form-actions"><button type="button" class="btn btn-primary" data-m="close">Keep editing</button><button type="button" class="btn btn-danger" data-m="discard">Discard</button></div>',
        { discard: function () { closeModal(); go(); } });
    } else go();
  }

  /* hash keeps the open place in the address, so Back closes it and a link reopens it */
  var hashGuard = false;
  function setHash(h) {
    try {
      if ((location.hash || "").replace(/^#/, "") === h) return;
      hashGuard = true;
      if (h) location.hash = h;
      else history.replaceState(null, "", location.pathname + location.search);
      setTimeout(function () { hashGuard = false; }, 0);
    } catch (e) { hashGuard = false; }
  }
  function applyHash() {
    var h = (location.hash || "").replace(/^#/, "");
    if (h.indexOf("p-") === 0 && S.places[h.slice(2)]) {
      if (ui.openId !== h.slice(2) && !formDirty()) openSheet(h.slice(2));
    } else if (!h && $("sheet").open && !ui.isNew && !formDirty() && !$("modal").open) {
      forceCloseSheet();
    }
  }
  window.addEventListener("hashchange", function () { if (!hashGuard) applyHash(); });

  /* ---------- photo edits ---------- */
  function editPhotos(fn) {
    var place = S.places[ui.openId];
    if (!place) return;
    var p = clone(place);
    fn(p);
    if (!p.photos.some(function (ph) { return ph.id === p.cover; })) p.cover = p.photos.length ? p.photos[0].id : null;
    store.savePlace(p);
    render();
  }
  function movePhoto(id, dir) {
    editPhotos(function (p) {
      var i = p.photos.findIndex(function (ph) { return ph.id === id; }), j = i + dir;
      if (i < 0 || j < 0 || j >= p.photos.length) return;
      var t = p.photos[i]; p.photos[i] = p.photos[j]; p.photos[j] = t;
    });
  }
  function removePhoto(id) {
    var gone = null;
    editPhotos(function (p) {
      p.photos = p.photos.filter(function (ph) { if (ph.id === id) { gone = ph; return false; } return true; });
    });
    if (gone) { store.deletePhoto(gone.id); if (gone.thumb !== gone.id) store.deletePhoto(gone.thumb); }
    ui.confirmRemove = null;
    if (S.places[ui.openId] && !S.places[ui.openId].photos.length) ui.managing = false;
    render();
  }

  /* ---------- lightbox ---------- */
  function renderLightbox() {
    var lb = $("lightbox");
    if (!ui.lb) { if (lb.open) lb.close(); return; }
    var p = S.places[ui.lb.placeId];
    if (!p || !p.photos.length) { ui.lb = null; if (lb.open) lb.close(); return; }
    ui.lb.i = Math.max(0, Math.min(ui.lb.i, p.photos.length - 1));
    var ph = p.photos[ui.lb.i];
    var img = $("lb-img"), src = store.photoUrl(ph.id);
    if (img.getAttribute("src") !== src) img.setAttribute("src", src);
    img.alt = ph.caption || p.name;
    $("lb-cap").textContent = (ph.caption ? ph.caption + " · " : "") + (ui.lb.i + 1) + " of " + p.photos.length;
    $("lb-prev").hidden = $("lb-next").hidden = p.photos.length < 2;
    if (!lb.open) lb.showModal();
  }
  function lbStep(d) {
    if (!ui.lb) return;
    var p = S.places[ui.lb.placeId];
    if (!p) return;
    ui.lb.i = (ui.lb.i + d + p.photos.length) % p.photos.length;
    renderLightbox();
  }

  /* ---------- modal ---------- */
  function openModal(html, handlers) {
    var m = $("modal");
    $("modal-body").innerHTML = html;
    m._handlers = handlers || {};
    if (!m.open) m.showModal();
  }
  function closeModal() { var m = $("modal"); if (m.open) m.close(); $("modal-body").innerHTML = ""; }
  $("modal").addEventListener("click", function (e) {
    var b = e.target.closest("[data-m]");
    if (!b) return;
    var name = b.getAttribute("data-m");
    if (name === "close") { closeModal(); return; }
    var h = $("modal")._handlers[name];
    if (h) h(b);
  });

  function editTrip() {
    openModal('<h2>Trip details</h2><form class="form" id="trip-form"><div class="field"><label for="t-title">Title</label><input id="t-title" type="text" maxlength="120" value="' + esc(S.journal.title) + '"></div>' +
      '<div class="field"><label for="t-sub">Dates or subtitle</label><input id="t-sub" type="text" maxlength="120" value="' + esc(S.journal.subtitle) + '"></div>' +
      '<div class="form-actions"><button type="submit" class="btn btn-primary">Save</button><button type="button" class="btn btn-quiet" data-m="close">Cancel</button></div></form>', {});
    $("trip-form").addEventListener("submit", function (e) {
      e.preventDefault();
      store.saveJournal({ title: $("t-title").value.trim(), subtitle: $("t-sub").value.trim() });
      closeModal(); render();
    });
  }

  function confirmDeletePlace() {
    var p = S.places[ui.openId];
    if (!p) return;
    openModal("<h2>Delete " + esc(p.name || "this place") + "?</h2><p>Its review, notes and " + plural(p.photos.length, "photo") + " are removed for good. Download a backup first if you might want them back.</p>" +
      '<div class="form-actions"><button type="button" class="btn btn-danger" data-m="yes">Delete place</button><button type="button" class="btn btn-quiet" data-m="close">Cancel</button></div>',
      { yes: function () { var id = ui.openId; closeModal(); forceCloseSheet(); store.deletePlace(id); render(); toast("Place deleted"); } });
  }

  /* ---------- backup and restore ---------- */
  function fmtSize(n) { return n > 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB"; }

  function backupModal() {
    openModal("<h2>Backup</h2><p>A backup is one .zip file holding every review, your notes and all photos, plus a plain-text recap.</p>" +
      '<div class="opt"><h3>Download a backup</h3><p>Keep the file somewhere safe, such as Files or iCloud Drive.</p><button type="button" class="btn btn-primary" data-m="make">Prepare backup</button></div>' +
      (canEdit() ? '<div class="opt"><h3>Restore from a backup</h3><p>Replaces everything in this journal with the contents of a backup file.</p>' +
        '<label class="btn" for="restore-pick">Choose backup file</label><input class="vh" type="file" id="restore-pick" accept=".zip,application/zip,application/x-zip-compressed"></div>' : "") +
      '<div class="form-actions"><button type="button" class="btn btn-quiet" data-m="close">Close</button></div>',
      { make: makeBackup });
    var pick = $("restore-pick");
    if (pick) pick.addEventListener("change", function () { if (pick.files[0]) chooseRestore(pick.files[0]); });
  }

  function progressModal(title, text) {
    openModal("<h2>" + esc(title) + '</h2><p id="prog-text">' + esc(text) + '</p><progress id="prog" max="1" value="0"></progress>', {});
  }
  function setProgress(done, total, text) {
    var p = $("prog"); if (p) { p.max = Math.max(1, total); p.value = done; }
    if (text && $("prog-text")) $("prog-text").textContent = text;
  }

  function makeBackup() {
    progressModal("Preparing backup", "Collecting photos…");
    store.flush().then(function () {
      return TJ.backup.create({
        journal: clone(S.journal), places: clone(store.orderedPlaces()),
        getPhotoBlob: function (id) { return store.getPhotoBlob(id); },
        onProgress: function (d, t) { setProgress(d, t, "Collecting photos… " + d + " of " + t); },
      });
    }).then(function (res) {
      var missing = res.missing && res.missing.length;
      openModal("<h2>Backup ready</h2><p>" + plural(store.orderedPlaces().length, "place") + " and " + plural(res.photoCount, "photo") + ", " + fmtSize(res.blob.size) + ".</p>" +
        (missing ? '<p class="err">' + plural(missing, "photo file") + " couldn't be read and " + (missing === 1 ? "is" : "are") + " missing from this backup.</p>" : "") +
        '<p class="err" id="bk-err" hidden></p><div class="form-actions"><button type="button" class="btn btn-primary" data-m="save">Save backup file</button><button type="button" class="btn btn-quiet" data-m="close">Close</button></div>',
        { save: function () {
          store.download(res.filename, res.blob).then(function () { closeModal(); toast("Backup saved"); }, function (e) {
            var el = $("bk-err"); if (!el) return;
            el.hidden = false;
            el.textContent = e && e.code === "declined" ? "The backup wasn't saved. Tap Save backup file to try again."
              : e && e.code === "rate_limited" ? "Please wait a moment, then try again."
              : "Saving files isn't available in this view. Open the journal on claude.ai in a browser and try again.";
          });
        } });
    }).catch(function (e) {
      console.error(e);
      openModal("<h2>Backup failed</h2><p>" + esc((e && e.userMessage) || "The backup couldn't be prepared. Check your connection and try again.") + '</p><div class="form-actions"><button type="button" class="btn btn-primary" data-m="retry">Try again</button><button type="button" class="btn btn-quiet" data-m="close">Close</button></div>', { retry: makeBackup });
    });
  }

  function chooseRestore(file) {
    progressModal("Reading backup", "Checking the file…");
    TJ.backup.open(file).then(function (bk) {
      var nPhotos = bk.places.reduce(function (n, p) { return n + p.photos.length; }, 0);
      var when = bk.exportedAt ? new Date(bk.exportedAt).toLocaleString(undefined, { dateStyle: "long", timeStyle: "short" }) : "an unknown date";
      openModal("<h2>Restore this backup?</h2><p>Saved " + esc(when) + ": " + plural(bk.places.length, "place") + " and " + plural(nPhotos, "photo") + ".</p>" +
        "<p>Everything now in the journal (" + plural(store.orderedPlaces().length, "place") + ") is replaced. This can't be undone.</p>" +
        '<div class="form-actions"><button type="button" class="btn btn-danger" data-m="go">Replace journal</button><button type="button" class="btn btn-quiet" data-m="close">Cancel</button></div>',
        { go: function () { runRestore(bk); } });
    }, function (e) {
      openModal("<h2>Can't restore this file</h2><p>" + esc((e && e.userMessage) || "This file couldn't be read.") + '</p><div class="form-actions"><button type="button" class="btn btn-quiet" data-m="close">Close</button></div>', {});
    });
  }

  function runRestore(bk) {
    progressModal("Restoring", "Restoring photos…");
    if ($("sheet").open) forceCloseSheet();
    var oldIds = {}, map = {}, wanted = [], seen = {}, skipped = 0;
    store.orderedPlaces().forEach(function (p) { p.photos.forEach(function (ph) { oldIds[ph.id] = 1; oldIds[ph.thumb] = 1; }); });
    bk.places.forEach(function (p) {
      p.photos.forEach(function (ph) {
        [ph.id, ph.thumb].forEach(function (id) { if (id && !seen[id]) { seen[id] = 1; wanted.push(id); } });
      });
    });
    var uploaded = [];
    store.listPhotoIds().then(function (existing) {
      var have = {};
      (existing || []).forEach(function (id) { have[id] = 1; });
      var i = 0;
      function next() {
        if (i >= wanted.length) return Promise.resolve();
        var id = wanted[i++];
        setProgress(i - 1, wanted.length, "Restoring photos… " + i + " of " + wanted.length);
        if (have[id]) { map[id] = id; return next(); } // already stored in this journal, no need to upload again
        return bk.getPhoto(id).then(function (blob) {
          if (!blob) return;
          return store.putPhoto(blob).then(function (newId) { map[id] = newId; uploaded.push(newId); });
        }).then(next);
      }
      return next();
    }).then(function () {
      var usedIds = {}, order = [], keep = {};
      var places = bk.places.map(function (p) {
        var q = clone(p);
        if (!ID_OK.test(q.id || "") || keep[q.id]) q.id = newPlaceId(q.name);
        keep[q.id] = 1; order.push(q.id);
        q.photos = p.photos.filter(function (ph) { if (map[ph.id]) return true; skipped++; return false; }).map(function (ph) {
          var n = { id: map[ph.id], thumb: map[ph.thumb] || map[ph.id], w: ph.w, h: ph.h, caption: ph.caption || "" };
          usedIds[n.id] = 1; usedIds[n.thumb] = 1;
          return n;
        });
        q.cover = p.cover && map[p.cover] ? map[p.cover] : (q.photos[0] ? q.photos[0].id : null);
        return q;
      });
      // keep the backup's order when its place ids all survived unchanged
      var bkOrder = (bk.journal.order || []).filter(function (id) { return keep[id]; });
      if (bkOrder.length === order.length) order = bkOrder;
      Object.keys(S.places).forEach(function (id) { if (!keep[id]) store.deletePlace(id, { keepPhotos: true }); });
      places.forEach(function (p) { store.savePlace(p); });
      store.saveJournal({ title: bk.journal.title || "", subtitle: bk.journal.subtitle || "", order: order });
      return store.flush().then(function (ok) {
        if (!ok) throw Object.assign(new Error("save failed"), { userMessage: "Some of the restored journal couldn't be saved. Use Retry next to the save status, or restore again." });
        Object.keys(oldIds).forEach(function (id) { if (!usedIds[id]) store.deletePhoto(id); });
        render();
        openModal("<h2>Journal restored</h2><p>" + plural(places.length, "place") + " restored." + (skipped ? " " + plural(skipped, "photo") + " in the backup had no image file and " + (skipped === 1 ? "was" : "were") + " left out." : "") +
          '</p><div class="form-actions"><button type="button" class="btn btn-primary" data-m="close">Done</button></div>', {});
      });
    }).catch(function (e) {
      console.error(e);
      render();
      openModal("<h2>Restore stopped</h2><p>" + esc((e && e.userMessage) || "Something went wrong while restoring.") + (uploaded.length && !(e && /saved/.test(e.userMessage || "")) ? " Your journal was not changed." : "") +
        '</p><div class="form-actions"><button type="button" class="btn btn-quiet" data-m="close">Close</button></div>', {});
    });
  }

  /* ---------- drag to reorder (pointer based, works with touch) ---------- */
  function sortable(container, onDone) {
    container.addEventListener("pointerdown", function (e) {
      var grip = e.target.closest(".grip");
      if (!grip || !container.contains(grip)) return;
      var row = grip.closest("[data-sort]"), list = grip.closest("[data-sortlist]");
      if (!row || !list) return;
      e.preventDefault();
      try { grip.setPointerCapture(e.pointerId); } catch (err) {}
      row.classList.add("dragging"); ui.dragging = true;
      function move(ev) {
        var y = ev.clientY, prev = row.previousElementSibling, next = row.nextElementSibling, r;
        // move the neighbour, never the dragged row: re-inserting the row would drop the pointer capture
        if (prev) { r = prev.getBoundingClientRect(); if (y < r.top + r.height / 2) { list.insertBefore(prev, row.nextSibling); return; } }
        if (next) { r = next.getBoundingClientRect(); if (y > r.top + r.height / 2) list.insertBefore(next, row); }
      }
      function up() {
        grip.removeEventListener("pointermove", move);
        grip.removeEventListener("pointerup", up);
        grip.removeEventListener("pointercancel", up);
        row.classList.remove("dragging"); ui.dragging = false;
        var ids = Array.prototype.map.call(list.children, function (c) { return c.getAttribute("data-sort"); });
        container._html = null;
        onDone(list.getAttribute("data-sortlist"), ids);
        render();
      }
      grip.addEventListener("pointermove", move);
      grip.addEventListener("pointerup", up);
      grip.addEventListener("pointercancel", up);
    });
  }
  sortable($("feed"), function (kind, ids) { if (kind === "places") store.saveJournal({ order: ids }); });
  sortable($("sheet-photos"), function (kind, ids) {
    if (kind !== "photos") return;
    editPhotos(function (p) {
      var by = {}; p.photos.forEach(function (ph) { by[ph.id] = ph; });
      var next = ids.map(function (id) { return by[id]; }).filter(Boolean);
      if (next.length === p.photos.length) p.photos = next;
    });
  });

  function movePlace(id, dir) {
    var ids = store.orderedPlaces().map(function (p) { return p.id; });
    var i = ids.indexOf(id), j = i + dir;
    if (i < 0 || j < 0 || j >= ids.length) return;
    ids[i] = ids[j]; ids[j] = id;
    store.saveJournal({ order: ids });
    render();
  }

  /* ---------- events ---------- */
  document.addEventListener("click", function (e) {
    var t = e.target;
    var act = t.closest("[data-act]");
    var name = act && act.getAttribute("data-act");
    var holder = t.closest("[data-id]"), id = holder && holder.getAttribute("data-id");
    var row = t.closest("[data-sort]"), sortId = row && row.getAttribute("data-sort");
    var phEl = t.closest("[data-ph]"), ph = phEl && phEl.getAttribute("data-ph");
    var qEl = t.closest("[data-q]"), q = qEl && qEl.getAttribute("data-q");
    var mEl = t.closest("[data-map-id]"), mapId = mEl && mEl.getAttribute("data-map-id");

    switch (name) {
      case "pick-feed": ui.feedTarget = id; return; // the label opens the picker itself
      case "filter": ui.filter = act.getAttribute("data-filter"); ui.reorder = false; remember(); render(); return;
      case "add": openNew(); return;
      case "reorder": ui.reorder = !ui.reorder; render(); return;
      case "pl-up": movePlace(sortId, -1); return;
      case "pl-down": movePlace(sortId, 1); return;
      case "retry-save": store.retryFailed(); return;
      case "edit-review": startEdit("f-review"); return;
      case "edit-cancel": cancelEdit(); return;
      case "place-delete": confirmDeletePlace(); return;
      case "manage": ui.managing = !ui.managing; ui.confirmRemove = null; render(); return;
      case "lb": ui.lb = { placeId: ui.openId, i: +act.getAttribute("data-i") || 0 }; renderLightbox(); return;
      case "ph-cover": editPhotos(function (p) { p.cover = ph; }); toast("Cover photo changed"); return;
      case "ph-up": movePhoto(ph, -1); return;
      case "ph-down": movePhoto(ph, 1); return;
      case "ph-remove": ui.confirmRemove = ph; render(); return;
      case "ph-remove-no": ui.confirmRemove = null; render(); return;
      case "ph-remove-yes": removePhoto(ph); return;
      case "q-retry": queue.retry(q); return;
      case "q-dismiss": queue.dismiss(q); render(); return;
      case "show-on-map": showOnMap(ui.openId); return;
      case "map-open": openSheet(mapId); return;
      case "place-pin": ui.placing = mapId; ui.mapSel = null; if (map) map.setPlacing(true); render(); $("mapview").scrollIntoView({ block: "start" }); return;
      case "place-cancel": ui.placing = null; if (map) map.setPlacing(false); render(); return;
      case "unpin": if (S.places[mapId]) { var up = clone(S.places[mapId]); up.lat = null; up.lng = null; up.posApprox = false; store.savePlace(up); ui.mapSel = null; render(); } return;
    }
    if (id && !t.closest("dialog")) {
      e.preventDefault();
      openSheet(id);
    }
  });

  $("btn-recap").addEventListener("click", copyRecap);
  $("btn-backup").addEventListener("click", backupModal);
  $("btn-trip").addEventListener("click", editTrip);
  $("btn-add").addEventListener("click", openNew);
  $("btn-reorder").addEventListener("click", function () { ui.reorder = !ui.reorder; render(); if (ui.reorder) window.scrollTo({ top: $("toolbar").offsetTop }); });
  $("view-cards").addEventListener("click", function () { ui.view = "cards"; ui.reorder = false; remember(); render(); });
  $("view-list").addEventListener("click", function () { ui.view = "list"; ui.reorder = false; remember(); render(); });
  $("view-map").addEventListener("click", function () { ui.view = "map"; ui.reorder = false; remember(); render(); });
  $("sheet-close").addEventListener("click", requestCloseSheet);
  $("sheet-edit").addEventListener("click", function () { startEdit("f-review"); });
  $("sheet").addEventListener("cancel", function (e) { e.preventDefault(); requestCloseSheet(); });
  $("sheet").addEventListener("submit", function (e) { if (e.target.id === "place-form") { e.preventDefault(); saveForm(); } });
  $("modal").addEventListener("cancel", function (e) { if ($("prog")) e.preventDefault(); });

  function onPick(input, target) {
    input.addEventListener("change", function () {
      var files = Array.prototype.slice.call(input.files || []);
      input.value = "";
      addFiles(target(), files);
    });
  }
  onPick($("feed-pick"), function () { return ui.feedTarget; });
  onPick($("sheet-pick"), function () { return ui.openId; });
  onPick($("sheet-camera"), function () { return ui.openId; });

  // captions save when the field is left
  $("sheet-photos").addEventListener("change", function (e) {
    if (!e.target.classList.contains("cap")) return;
    var id = e.target.id.slice(4), value = e.target.value.trim();
    editPhotos(function (p) { p.photos.forEach(function (ph) { if (ph.id === id) ph.caption = value; }); });
  });
  $("sheet-photos").addEventListener("focusout", function () { setTimeout(render, 0); });
  $("sheet-photos").addEventListener("keydown", function (e) { if (e.key === "Enter" && e.target.classList.contains("cap")) e.target.blur(); });

  $("lb-close").addEventListener("click", function () { ui.lb = null; renderLightbox(); });
  $("lb-prev").addEventListener("click", function () { lbStep(-1); });
  $("lb-next").addEventListener("click", function () { lbStep(1); });
  $("lightbox").addEventListener("close", function () { ui.lb = null; });
  $("lightbox").addEventListener("keydown", function (e) { if (e.key === "ArrowLeft") lbStep(-1); if (e.key === "ArrowRight") lbStep(1); });
  (function () {
    var x0 = null;
    $("lightbox").addEventListener("touchstart", function (e) { x0 = e.touches[0].clientX; }, { passive: true });
    $("lightbox").addEventListener("touchend", function (e) {
      if (x0 == null) return;
      var dx = e.changedTouches[0].clientX - x0; x0 = null;
      if (Math.abs(dx) > 50) lbStep(dx < 0 ? 1 : -1);
    });
  })();

  /* drag and drop from the desktop */
  function hasFiles(e) { return e.dataTransfer && Array.prototype.indexOf.call(e.dataTransfer.types || [], "Files") >= 0; }
  var dropCard = null;
  function markDrop(card) {
    if (dropCard && dropCard !== card) dropCard.classList.remove("is-drop");
    dropCard = card;
    if (card) card.classList.add("is-drop");
  }
  document.addEventListener("dragover", function (e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    if ($("sheet").open) { $("sheet").classList.toggle("is-drop", !ui.isNew && !$("modal").open); return; }
    markDrop(e.target.closest ? e.target.closest(".card") : null);
  });
  document.addEventListener("dragleave", function (e) {
    if (e.relatedTarget) return;
    markDrop(null); $("sheet").classList.remove("is-drop");
  });
  document.addEventListener("drop", function (e) {
    if (!hasFiles(e)) return;
    e.preventDefault();
    var card = dropCard;
    markDrop(null); $("sheet").classList.remove("is-drop");
    if ($("modal").open) return;
    if ($("sheet").open) { if (!ui.isNew) addFiles(ui.openId, e.dataTransfer.files); return; }
    if (card) addFiles(card.getAttribute("data-id"), e.dataTransfer.files);
    else toast("Drop photos onto a place to add them there.");
  });

  window.addEventListener("beforeunload", function (e) {
    if (store.status.saving || queue.activeCount() || formDirty()) { e.preventDefault(); e.returnValue = ""; }
  });

  /* ---------- start ---------- */
  store.subscribe(render);
  var firstReady = false;
  store.subscribe(function () {
    if (S.ready && !firstReady) { firstReady = true; applyHash(); }
  });
  render();
  store.init().catch(function (e) {
    console.error(e);
    S.loadError = e || {};
    render();
  });

  TJ.app = { recapText: recapText, queue: queue };
})();
