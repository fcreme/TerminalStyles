// appleterminal.js -- JXA helper for building Terminal.app profile data.
//
// Terminal.app stores a profile's colors and background image as Cocoa
// objects, not as text: each color is an NSKeyedArchiver archive of an NSColor,
// and the background image is an archive of an NSMutableData holding a
// security-scoped NSURL bookmark. Neither can be produced from PowerShell --
// they need Foundation/AppKit -- so this script is the bridge.
//
// Discovered by pulling apart a profile Terminal had written itself; handing it
// a bare bookmark (the obvious guess) makes Terminal reject the whole file as
// "corrupt", with no indication of which key was wrong.
//
// Usage:  osascript -l JavaScript appleterminal.js <spec.json> <out.json>
//
//   spec.json  { "colors": { "BackgroundColor": "#0a0006", ... },
//                "image":  "/abs/path/to/image.png" | "" }
//   out.json   { "BackgroundColor": "<base64>", ...,
//                "BackgroundImageBookmark": "<base64>" }
//
// One invocation does the whole profile: osascript costs ~100ms to start, and
// a color-at-a-time design would spend two seconds on a 20-color scheme.

ObjC.import('AppKit');
ObjC.import('Foundation');

function readFile(path) {
    return $.NSString.stringWithContentsOfFileEncodingError(
        path, $.NSUTF8StringEncoding, $()).js;
}

function writeFile(path, text) {
    $.NSString.alloc.initWithUTF8String(text)
        .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, $());
}

function archivedColor(hex) {
    // "#rrggbb" -> base64 NSKeyedArchiver archive of an NSColor.
    //
    // colorWithCalibratedRed..., NOT colorWithSRGBRed...: the sRGB constructor
    // archives the full ICC profile with every color, which is ~5 KB each and
    // would bloat a 20-color profile to 100 KB. The calibrated form is 245
    // bytes and is what Terminal writes itself.
    var h = hex.replace('#', '');
    // Validate BEFORE parseInt. parseInt('zz', 16) is NaN, NSColor accepts NaN
    // components without complaint, and the archive then carries
    // NSRGB = "nan nan nan" -- which Terminal rejects as a corrupt profile,
    // naming no key. The caller's try/catch cannot help, because nothing throws.
    if (!/^[0-9a-fA-F]{6}$/.test(h)) {
        throw new Error('not a 6-digit hex color: ' + hex);
    }
    var r = parseInt(h.substr(0, 2), 16) / 255;
    var g = parseInt(h.substr(2, 2), 16) / 255;
    var b = parseInt(h.substr(4, 2), 16) / 255;
    var color = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(r, g, b, 1.0);
    return $.NSKeyedArchiver.archivedDataWithRootObject(color)
        .base64EncodedStringWithOptions(0).js;
}

function archivedBookmark(path) {
    // Absolute path -> base64 archive of an NSMutableData holding the bookmark.
    //
    // Three layers, and all three matter: NSKeyedArchiver wrapping an
    // NSMutableData wrapping the raw "book" bookmark blob. Archiving the NSURL
    // directly instead yields a URL string with no NS.data, which Terminal
    // rejects just as firmly as a bare bookmark.
    var url = $.NSURL.fileURLWithPath(path);
    var err = Ref();
    var bookmark = url.bookmarkDataWithOptionsIncludingResourceValuesForKeysRelativeToURLError(
        0, $(), $(), err);
    // isNil(), not !bookmark: a nil ObjC return arrives in JXA as a truthy
    // wrapper object, so `!bookmark` is false and `bookmark.length` is
    // undefined -- both halves of the old guard passed a nil straight through,
    // and the profile then carried a BackgroundImageBookmark archiving nothing.
    // That is exactly the malformed shape this file's header warns Terminal
    // rejects as "corrupt" without naming the offending key.
    if (!bookmark || (bookmark.isNil && bookmark.isNil())) { return null; }
    if (bookmark.length === 0) { return null; }
    var mdata = $.NSMutableData.dataWithData(bookmark);
    return $.NSKeyedArchiver.archivedDataWithRootObject(mdata)
        .base64EncodedStringWithOptions(0).js;
}

function run(argv) {
    var spec = JSON.parse(readFile(argv[0]));
    var out = {};

    var colors = spec.colors || {};
    for (var key in colors) {
        if (!colors.hasOwnProperty(key)) { continue; }
        var hex = colors[key];
        if (!hex) { continue; }
        try { out[key] = archivedColor(hex); } catch (e) { /* skip a bad color, keep the rest */ }
    }

    if (spec.image) {
        try {
            var bm = archivedBookmark(spec.image);
            if (bm) { out.BackgroundImageBookmark = bm; }
        } catch (e) { /* no image is a degraded profile, not a failed one */ }
    }

    writeFile(argv[1], JSON.stringify(out));
    return 'ok';
}
