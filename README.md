# Travel journal

A mobile-first journal for short reviews and photos of places visited on a trip.
First trip: South Africa, November 2026.

Published as a private Claude artifact: https://claude.ai/artifact/9Xj32KBro2frbfEMbd9cPL

## Files

| File | Purpose |
| --- | --- |
| `index.html`, `styles.css` | Page markup and styles |
| `app.js` | UI: feed, list view, place sheet, editing, reorder, recap, backup/restore flows |
| `store.js` | Storage. In Claude: the artifact `db` (places, trip details) and `assets` (photos). Elsewhere: IndexedDB in the browser |
| `photos.js` | Photo decode, HEIC handling, resize (2400 px + 800 px JPEG), upload queue |
| `backup.js` | Zip backup (journal.json, photos, recap.txt) and reading it back |
| `seed.json` | The 18 starting reviews (used for local runs; the published journal's data lives in its database) |
| `vendor/` | JSZip 3.10.1, heic2any 0.0.4 |

## Tests

Playwright with Chromium, no install step in this repo:

```
node tests/app.test.js      # end to end on a phone viewport (local storage mode)
node tests/photos.test.js
node tests/backup.test.js
```

## Map

`map.js` draws a self-contained SVG map (no tiles; the page cannot load external images).
`mapdata.js` holds the south-western Cape coastline, built by `tools/build-mapdata.js` from
`@geo-maps/earth-lands-10m` (land data © OpenStreetMap contributors, ODbL). Places outside
that region still get pins, on a plain background.

## Adding entries from Claude Code

There is no MCP server. A Claude Code session can write to the published journal's database
directly. Ask it to add a place to the artifact above; each place is one document in the
`places` collection, and its id must be appended to `order` in `journal/main`:

```json
{ "name": "", "location": "", "category": "accommodation | restaurant | nature | estate | transport",
  "review": "", "notes": "", "visitDate": "YYYY-MM-DD or empty",
  "recommendation": "Highly recommended | Recommended | Optional | empty",
  "photos": [], "cover": null, "lat": null, "lng": null, "posApprox": false, "updatedAt": 0 }
```
