
import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Timer;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Math;
import MGRSHelper;
import Reports;
class MilGuardView extends WatchUi.View {
// Index into _fonts. Each row starts at its "design" font (what it uses
// on the Fenix 8) and steps down until the text fits the screen.
const F_LARGE  = 0;
const F_MEDIUM = 1;
const F_TINY   = 3;
const F_XTINY  = 4;

const C_GREEN  = 0x55AA55;  // muted green
const C_RED    = 0xAA5555;  // muted red
const C_WHITE  = 0xAAAAAA;  // light gray instead of pure white
const C_YELLOW = 0xAAAA55;  // optional: muted yellow
const C_ORANGE = 0xAA5500;  // optional: muted orange

private var _fonts as Array<Graphics.FontDefinition> = [
    Graphics.FONT_LARGE,
    Graphics.FONT_MEDIUM,
    Graphics.FONT_SMALL,
    Graphics.FONT_TINY,
    Graphics.FONT_XTINY
] as Array<Graphics.FontDefinition>;

private var _gpsQuality as Number = Position.QUALITY_NOT_AVAILABLE;
private var _clockTime as System.ClockTime = System.getClockTime();
private var _timer as Timer.Timer? = null;
private var _mgrsString as String = "Waiting for GPS";
private var _altitude as Float? = null;
private var _heading as Float? = null;   // stays null on watches without a compass
private var _lastHeading as Float = -1.0;

// Screen info, filled in onLayout
private var _shape = System.SCREEN_SHAPE_ROUND;
private var _sub = null;                  // Instinct corner window (BoundingBox) or null
private var _mono as Boolean = false;     // black-and-white screen

// Page 0 is the main land nav screen. Pages 1 to Reports.COUNT each show
// one report. The delegate changes pages from the up/down buttons.
private var _page as Number = 0;

function initialize() {
    View.initialize();
}

function onLayout(dc as Dc) as Void {
    _shape = System.getDeviceSettings().screenShape;
    if (WatchUi has :getSubscreen) {
        _sub = WatchUi.getSubscreen();
    }
    // Every watch with a subscreen (Instinct 2, Instinct 3 Solar, Instinct E)
    // has a black-and-white screen, so use that to detect monochrome.
    _mono = (_sub != null);
}

function onShow() as Void {
    Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    if (_page == 0) {
        startLive();
    }
    WatchUi.requestUpdate();
}

function onHide() as Void {
    stopLive();
    Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
}

// The clock refresh and the compass are only needed on the main screen,
// so they are switched off while a report is showing. GPS stays on so
// the grid is current as soon as you page back.
private function startLive() as Void {
    stopLive();
    _clockTime = System.getClockTime();
    var timer = new Timer.Timer();
    timer.start(method(:onTick), 500, true);
    _timer = timer;
    Sensor.enableSensorEvents(method(:onSensor));
}

private function stopLive() as Void {
    var timer = _timer;
    if (timer != null) {
        timer.stop();
        _timer = null;
    }
    Sensor.enableSensorEvents(null);
}

function onTick() as Void {
    _clockTime = System.getClockTime();
    WatchUi.requestUpdate();
}

// -----------------------------------------------------------------------
// Paging: main screen -> 9-line -> SALUTE -> LACE -> back to main
// -----------------------------------------------------------------------
function nextPage() as Void {
    setPage((_page + 1) % (Reports.COUNT + 1));
}

function previousPage() as Void {
    setPage((_page + Reports.COUNT) % (Reports.COUNT + 1));
}

private function setPage(page as Number) as Void {
    var wasMain = (_page == 0);
    _page = page;
    if (wasMain && page != 0) {
        stopLive();
    } else if (!wasMain && page == 0) {
        startLive();
    }
    WatchUi.requestUpdate();
}

function onPosition(info as Position.Info) as Void {
    if (info.accuracy >= Position.QUALITY_USABLE) {
        _gpsQuality = info.accuracy;
        var coords = info.position.toDegrees(); // [lat, lon]
        _mgrsString = MGRSHelper.convert(coords[0], coords[1], 5);
        _altitude = info.altitude;
    } else {
        _gpsQuality = Position.QUALITY_NOT_AVAILABLE;
        _mgrsString = "Waiting for GPS";
        _altitude = null;
    }
    // Reports don't show GPS data, so there is nothing to redraw there
    if (_page == 0) {
        WatchUi.requestUpdate();
    }
}

function onSensor(sensorInfo as Sensor.Info) as Void {
    if (sensorInfo.heading != null) {
        var newHeading = (sensorInfo.heading * 180.0 / Math.PI).toFloat();
        if (newHeading < 0.0) { newHeading += 360.0; }

        var diff = newHeading - _lastHeading;
        if (diff > 180.0) { diff -= 360.0; }
        if (diff < -180.0) { diff += 360.0; }

        if ((_lastHeading < 0.0) || (diff < -1.0) || (diff > 1.0)) {
            _heading = newHeading;
            _lastHeading = newHeading;
        }
    }
}

// -----------------------------------------------------------------------
// Drawing
// Row positions are fractions of screen height. Second number = vertical
// space the row may use.
// -----------------------------------------------------------------------
function onUpdate(dc as Dc) as Void {
    dc.setColor(C_WHITE, Graphics.COLOR_BLACK);
    dc.clear();

    drawPageDots(dc);

    if (_page > 0) {
        drawReport(dc, _page - 1);
        return;
    }

    drawBattery(dc);

    // Black-and-white screens can't show GPS quality by color, so spell
    // it out in the top row (the battery is in the corner window there)
    if (_mono && _gpsQuality != Position.QUALITY_NOT_AVAILABLE) {
        drawRow(dc, (_gpsQuality == Position.QUALITY_GOOD) ? "GPS GOOD" : "GPS FAIR",
                C_WHITE, 0.10, 0.09, F_XTINY);
    }

    var t = _clockTime;
    drawRow(dc, t.hour.format("%02d") + ":" + t.min.format("%02d") + " L",
            C_WHITE, 0.215, 0.12, F_MEDIUM);

    drawRule(dc, 0.295);
    drawMgrs(dc);
    drawRule(dc, 0.625);
    drawDataBlock(dc);
}

// One dot per page on the right edge; the current page is filled in
private function drawPageDots(dc as Dc) as Void {
    var r = dotRadius(dc);
    var x = dotX(dc);
    var count = Reports.COUNT + 1;
    var spacing = r * 4;
    var y = dc.getHeight() / 2 - (spacing * (count - 1)) / 2;
    for (var i = 0; i < count; i++) {
        if (i == _page) {
            dc.setColor(paint(C_GREEN), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, r);
        } else {
            dc.setColor(C_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, y, r);
        }
        y += spacing;
    }
}

private function dotRadius(dc as Dc) as Number {
    var r = (dc.getWidth() * 0.011).toNumber();
    return (r < 2) ? 2 : r;
}

// Distance of the dots from the screen edge
private function dotInset(dc as Dc) as Number {
    return (dc.getWidth() * 0.05).toNumber();
}

private function dotX(dc as Dc) as Number {
    return dc.getWidth() - dotInset(dc);
}

// Thin green line across the middle of the screen at yFrac
private function drawRule(dc as Dc, yFrac as Float) as Void {
    var y = dc.getHeight() * yFrac;
    var b = rowBounds(dc, y, 1.0);
    var len = dc.getWidth() * 0.5;
    if (len > b[1] - b[0]) { len = b[1] - b[0]; }
    dc.setColor(paint(C_GREEN), Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle((b[0] + b[1]) / 2.0 - len / 2.0, y, len, lineWidth(dc));
}

// 2 px lines on high-resolution screens, 1 px on the rest
private function lineWidth(dc as Dc) as Number {
    return (dc.getHeight() >= 300) ? 2 : 1;
}

private function drawBattery(dc as Dc) as Void {
    var level = System.getSystemStats().battery;
    var color = C_RED;
    if (level >= 65) {
        color = C_GREEN;
    } else if (level >= 20) {
        color = C_WHITE;
    } else if (level >= 10) {
        color = C_YELLOW;
    }
    var text = level.format("%d") + "%";
    var last = _fonts.size() - 1;

    var sub = _sub;
    if (sub != null) {
        // Instinct: put the battery inside the corner window
        var subFont = _fonts[last];
        for (var i = 2; i <= last; i++) {
            if (dc.getTextWidthInPixels(text, _fonts[i]) <= sub.width * 0.8) {
                subFont = _fonts[i];
                break;
            }
        }
        dc.setColor(paint(color), Graphics.COLOR_TRANSPARENT);
        drawCentered(dc, sub.x + sub.width / 2.0, sub.y + sub.height / 2.0, subFont, text);
        return;
    }

    // Battery icon with the percentage to its right, centered as a pair
    var y = dc.getHeight() * 0.10;
    var slotH = dc.getHeight() * 0.09;
    for (var k = F_TINY; k <= last; k++) {
        var font = _fonts[k];
        var fh = dc.getFontHeight(font);
        if (fh * 0.8 > slotH && k < last) {
            continue; // too tall for this row
        }
        var iconH = (fh * 0.42).toNumber();
        var iconW = (iconH * 1.9).toNumber();
        var nubW = (iconW * 0.1).toNumber();
        if (nubW < 2) { nubW = 2; }
        var gap = (fh * 0.3).toNumber();
        var total = iconW + nubW + gap + dc.getTextWidthInPixels(text, font);
        var b = rowBounds(dc, y, fh * 0.3);
        if (k < last && total > b[1] - b[0]) {
            continue; // too wide, try a smaller font
        }

        var x = ((b[0] + b[1]) / 2.0 - total / 2.0).toNumber();
        var top = (y - iconH / 2.0).toNumber();
        var lw = lineWidth(dc);
        dc.setColor(paint(color), Graphics.COLOR_TRANSPARENT);
        // Outline
        dc.drawRectangle(x, top, iconW, iconH);
        if (lw > 1) {
            dc.drawRectangle(x + 1, top + 1, iconW - 2, iconH - 2);
        }
        // Terminal
        dc.fillRectangle(x + iconW, top + iconH / 4, nubW, iconH - 2 * (iconH / 4));
        // Charge level
        var inset = lw * 2;
        var fillW = ((iconW - 2 * inset) * level / 100.0).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(x + inset, top + inset, fillW, iconH - 2 * inset);
        }
        dc.drawText(x + iconW + nubW + gap, y, font, text,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return;
    }
}

private function drawMgrs(dc as Dc) as Void {
    var color = mgrsColor();
    var nl = _mgrsString.find("\n");
    if (nl == null) {
        // "Waiting for GPS"
        drawRow(dc, _mgrsString, color, 0.46, 0.26, F_LARGE);
        return;
    }
    var idx = nl as Number;
    var top = _mgrsString.substring(0, idx) as String;                          // "14R NV"
    var coords = _mgrsString.substring(idx + 1, _mgrsString.length()) as String; // "38140 72680"
    drawRow(dc, top, color, 0.385, 0.15, F_LARGE);
    drawRow(dc, coords, color, 0.535, 0.15, F_LARGE);
}

// Two rows of two values under the grid, split by a vertical line.
// Time is on the left and position on the right, which also puts the
// two widest values on the same row so neither side looks heavier:
//     Zulu time   | Altitude
//     Julian date | Azimuth
private function drawDataBlock(dc as Dc) as Void {
    var now = Time.now();
    var utc = Gregorian.utcInfo(now, Time.FORMAT_SHORT);
    var zulu = utc.hour.format("%02d") + ":" + utc.min.format("%02d") + ":" + utc.sec.format("%02d");
    var jd = julianDay(now, utc).format("%03d");

    var altText = "ALT --";
    var altShort = "ALT --";
    var alt = _altitude;
    if (alt != null) {
        if (alt >= 1000.0) {
            altShort = (alt / 1000.0).format("%.2f") + "km";
        } else {
            altShort = alt.format("%.1f") + "m";
        }
        altText = "ALT " + altShort;
    }

    var azText = "AZ --";
    var azShort = "AZ --";
    var hd = _heading;
    if (hd != null) {
        azShort = ((hd + 0.5).toNumber() % 360).format("%03d") + "°";
        azText = "AZ " + azShort;
    }

    // Left, right, left, right. Full labels if they fit, short ones on
    // narrow screens.
    var full = [zulu + " Z", altText, "J " + jd, azText] as Array<String>;
    var compact = [zulu + "Z", altShort, "J" + jd, azShort] as Array<String>;

    var w = dc.getWidth().toFloat();
    var h = dc.getHeight().toFloat();
    var cx = w / 2.0;
    var y1 = h * 0.705;
    var y2 = h * 0.805;
    var pad = w * 0.035;               // space between the center line and each value
    var last = _fonts.size() - 1;

    var texts = compact;
    var font = _fonts[last];
    var found = false;
    for (var attempt = 0; attempt < 2 && !found; attempt++) {
        var tryTexts = (attempt == 0) ? full : compact;
        for (var i = F_TINY; i <= last && !found; i++) {
            var tryFont = _fonts[i];
            if (dc.getFontHeight(tryFont) * 0.8 > h * 0.10 && i < last) {
                continue; // too tall for these rows
            }
            var tryW = blockColumnWidth(dc, tryFont, y1, y2);
            var ok = true;
            for (var c = 0; c < 4; c++) {
                if (dc.getTextWidthInPixels(tryTexts[c], tryFont) > tryW - pad) {
                    ok = false;
                }
            }
            if (ok) {
                texts = tryTexts;
                font = tryFont;
                found = true;
            }
        }
    }

    // Values line up against the center line: the left column ends at
    // it and the right column starts at it, with the same space each side
    var leftAlign = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
    var rightAlign = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
    dc.setColor(C_WHITE, Graphics.COLOR_TRANSPARENT);
    dc.drawText(cx - pad, y1, font, texts[0], leftAlign);
    dc.drawText(cx + pad, y1, font, texts[1], rightAlign);
    dc.drawText(cx - pad, y2, font, texts[2], leftAlign);
    dc.drawText(cx + pad, y2, font, texts[3], rightAlign);

    var lw = lineWidth(dc);
    dc.setColor(paint(C_GREEN), Graphics.COLOR_TRANSPARENT);
    dc.fillRectangle(cx - lw / 2, y1 - h * 0.045, lw, (y2 - y1) + h * 0.09);
}

// Width available to each of the two columns, measured from the center
// line out to the nearest screen edge of either row
private function blockColumnWidth(dc as Dc, font as Graphics.FontDefinition,
                                  y1 as Float, y2 as Float) as Float {
    var w = dc.getWidth().toFloat();
    var cx = w / 2.0;
    var halfH = dc.getFontHeight(font) * 0.3;
    var colW = w * 0.34;
    var b1 = rowBounds(dc, y1, halfH);
    var b2 = rowBounds(dc, y2, halfH);
    if (cx - b1[0] < colW) { colW = cx - b1[0]; }
    if (b1[1] - cx < colW) { colW = b1[1] - cx; }
    if (cx - b2[0] < colW) { colW = cx - b2[0]; }
    if (b2[1] - cx < colW) { colW = b2[1] - cx; }
    return colW;
}

// -----------------------------------------------------------------------
// Reports
// One report per screen: title with a line under it, then one row per
// line. Numbers/letters sit in a column on the left, separated from the
// labels by a vertical line. Uses the largest font where every row fits
// inside the screen shape.
// -----------------------------------------------------------------------
private function drawReport(dc as Dc, index as Number) as Void {
    var rows = Reports.rows(index);     // key, label, key, label, ...
    var n = rows.size() / 2;
    var w = dc.getWidth().toFloat();
    var h = dc.getHeight().toFloat();
    var availH = h * 0.90;
    var last = _fonts.size() - 1;
    var units = n + 1.3;                // title, a little space for its line, then the rows

    for (var i = 0; i <= last; i++) {
        var font = _fonts[i];
        var fh = dc.getFontHeight(font);

        // Rows are all caps (nothing hangs below the line), so they can
        // sit a little closer together than the full font height.
        var step = fh * 0.95;
        if (step * units > availH) {
            step = availH / units;
        }
        if (step < fh * 0.72 && i < last) {
            continue; // rows would overlap, try a smaller font
        }

        var top = (h - step * units) / 2.0;
        var halfH = fh * 0.3;
        var gap = fh * 0.7;             // space between the two columns, split by the line

        // Width of the number/letter column and of the widest label
        var keyW = 0;
        var labelW = 0;
        for (var k = 0; k < n; k++) {
            var kw = dc.getTextWidthInPixels(rows[k * 2], font);
            var lw = dc.getTextWidthInPixels(rows[k * 2 + 1], font);
            if (kw > keyW) { keyW = kw; }
            if (lw > labelW) { labelW = lw; }
        }

        // Range of x positions for the left edge of the block that keeps
        // every row on the screen
        var minLeft = 0.0;
        var maxLeft = w;
        for (var m = 0; m < n; m++) {
            var b = rowBounds(dc, top + step * (m + 1.8), halfH);
            var room = b[1] - (keyW + gap + dc.getTextWidthInPixels(rows[m * 2 + 1], font));
            if (b[0] > minLeft) { minLeft = b[0]; }
            if (room < maxLeft) { maxLeft = room; }
        }

        // Title row: full title if it fits, short one otherwise
        var titleY = top + step * 0.5;
        var tb = rowBounds(dc, titleY, halfH);
        var title = Reports.title(index);
        if (dc.getTextWidthInPixels(title, font) > tb[1] - tb[0]) {
            title = Reports.shortTitle(index);
        }
        var titleFits = dc.getTextWidthInPixels(title, font) <= tb[1] - tb[0];

        if (i < last && (!titleFits || minLeft > maxLeft)) {
            continue; // too wide, try a smaller font
        }

        // Center the block, then nudge it if a row would leave the screen
        var x = (w - (keyW + gap + labelW)) / 2.0;
        if (x > maxLeft) { x = maxLeft; }
        if (x < minLeft) { x = minLeft; }

        var thick = lineWidth(dc);
        var titleX = (tb[0] + tb[1]) / 2.0;

        // Title and the line under it
        dc.setColor(paint(C_GREEN), Graphics.COLOR_TRANSPARENT);
        drawCentered(dc, titleX, titleY, font, title);
        var ruleLen = w * 0.36;
        if (ruleLen > tb[1] - tb[0]) { ruleLen = tb[1] - tb[0]; }
        dc.fillRectangle(titleX - ruleLen / 2.0, top + step * 1.1, ruleLen, thick);

        // Vertical line between the two columns
        dc.fillRectangle(x + keyW + gap / 2.0, top + step * 1.3, thick, step * n);

        for (var r = 0; r < n; r++) {
            var y = top + step * (r + 1.8);
            dc.setColor(paint(C_GREEN), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + keyW, y, font, rows[r * 2],
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(C_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + keyW + gap, y, font, rows[r * 2 + 1],
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        return;
    }
}

// -----------------------------------------------------------------------
// Layout helpers
// -----------------------------------------------------------------------

// Draws text centered in a horizontal band at yFrac of the screen height,
// stepping down from startFont until it fits both the band height and the
// screen width at that height.
private function drawRow(dc as Dc, text as String, color as Graphics.ColorType,
                         yFrac as Float, slotFrac as Float, startFont as Number) as Void {
    var y = dc.getHeight() * yFrac;
    var slotH = dc.getHeight() * slotFrac;
    var last = _fonts.size() - 1;

    for (var i = startFont; i <= last; i++) {
        var font = _fonts[i];
        var fh = dc.getFontHeight(font);
        if (fh * 0.8 > slotH && i < last) {
            continue; // too tall for this row
        }
        var b = rowBounds(dc, y, fh * 0.3);
        if (i == last || dc.getTextWidthInPixels(text, font) <= b[1] - b[0]) {
            dc.setColor(paint(color), Graphics.COLOR_TRANSPARENT);
            drawCentered(dc, (b[0] + b[1]) / 2.0, y, font, text);
            return;
        }
    }
}

// Usable [left, right] x-range for a band of text centered at y that
// reaches halfH above and below y. Accounts for round screens, the
// Instinct's cut corners, and its corner window.
private function rowBounds(dc as Dc, y as Float, halfH as Float) as Array<Float> {
    var w = dc.getWidth().toFloat();
    var h = dc.getHeight().toFloat();
    var halfW = w / 2.0;
    var margin = w * 0.03;

    if (_shape == System.SCREEN_SHAPE_ROUND) {
        // Chord width at the band edge furthest from the center
        var dy = y - h / 2.0;
        if (dy < 0) { dy = -dy; }
        dy += halfH;
        var r = w / 2.0;
        halfW = (dy < r) ? Math.sqrt(r * r - dy * dy).toFloat() : 0.0;
        margin = w * 0.02;
    } else if (_shape == System.SCREEN_SHAPE_SEMI_OCTAGON) {
        // Square with cut corners
        var top = y - halfH;
        var bottom = h - (y + halfH);
        var d = (top < bottom) ? top : bottom;
        if (d < 0) { d = 0.0; }
        var octHalf = w * 0.207 + d;
        if (octHalf < halfW) { halfW = octHalf; }
    }

    var left = w / 2.0 - halfW + margin;
    var right = w / 2.0 + halfW - margin;

    // Keep text clear of the page dots on the right edge, and by the same
    // amount on the left so centered text stays centered
    var dotR = dotRadius(dc);
    var dotsHalf = dotR * (2 * Reports.COUNT + 1);
    if (y + halfH > h / 2.0 - dotsHalf && y - halfH < h / 2.0 + dotsHalf) {
        var clear = dotInset(dc) + dotR + margin;
        if (left < clear) { left = clear; }
        if (right > w - clear) { right = w - clear; }
    }

    // Keep text out of the Instinct corner window
    var sub = _sub;
    if (sub != null && y - halfH < sub.y + sub.height && y + halfH > sub.y) {
        var limit = sub.x - margin;
        if (right > limit) { right = limit; }
    }
    if (right < left) { right = left; }
    return [left, right] as Array<Float>;
}

private function drawCentered(dc as Dc, x as Numeric, y as Numeric,
                              font as Graphics.FontDefinition, text as String) as Void {
    dc.drawText(x, y, font, text,
        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
}

// Colors become white on black-and-white screens so nothing disappears
private function paint(color as Graphics.ColorType) as Graphics.ColorType {
    return _mono ? C_WHITE : color;
}

private function mgrsColor() as Graphics.ColorType {
    if (_gpsQuality == Position.QUALITY_GOOD) {
        return C_GREEN;
    } else if (_gpsQuality == Position.QUALITY_USABLE) {
        return C_YELLOW;
    } else if (_gpsQuality == Position.QUALITY_POOR) {
        return C_ORANGE;
    }
    return C_RED;
}

private function julianDay(now as Time.Moment, utc as Gregorian.Info) as Number {
    var startOfYear = Gregorian.moment({
        :year   => utc.year,
        :month  => 1,
        :day    => 1,
        :hour   => 0,
        :minute => 0,
        :second => 0
    });
    return ((now.value() - startOfYear.value()) / 86400).toNumber() + 1;
}
}
