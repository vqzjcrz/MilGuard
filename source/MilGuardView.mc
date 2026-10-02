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
        _clockTime = System.getClockTime();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), 500, true);
        _timer = timer;
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        Sensor.enableSensorEvents(method(:onSensor));
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
        }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        Sensor.enableSensorEvents(null);
    }

    function onTick() as Void {
        _clockTime = System.getClockTime();
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
        WatchUi.requestUpdate();
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
    // Row positions are fractions of screen height (same as the original
    // Fenix 8 layout). Second number = vertical space the row may use.
    // -----------------------------------------------------------------------
    function onUpdate(dc as Dc) as Void {
        dc.setColor(C_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        drawBattery(dc);

        var t = _clockTime;
        drawRow(dc, t.hour.format("%02d") + ":" + t.min.format("%02d") + "L",
                C_WHITE, 0.175, 0.14, F_MEDIUM);

        drawMgrs(dc);
        drawAlt(dc);
        drawZuluJulian(dc);
        drawRow(dc, azimuthText(), C_WHITE, 0.90, 0.10, F_XTINY);
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

        var sub = _sub;
        if (sub != null) {
            // Instinct: put the battery inside the corner window
            var text = level.format("%d") + "%";
            var last = _fonts.size() - 1;
            var font = _fonts[last];
            for (var i = 2; i <= last; i++) {
                if (dc.getTextWidthInPixels(text, _fonts[i]) <= sub.width * 0.8) {
                    font = _fonts[i];
                    break;
                }
            }
            dc.setColor(paint(color), Graphics.COLOR_TRANSPARENT);
            drawCentered(dc, sub.x + sub.width / 2.0, sub.y + sub.height / 2.0, font, text);
        } else {
            drawRow(dc, "B: " + level.format("%d") + "%", color, 0.06, 0.10, F_TINY);
        }
    }

    private function drawMgrs(dc as Dc) as Void {
        var color = mgrsColor();
        var nl = _mgrsString.find("\n");
        if (nl == null) {
            // "Waiting for GPS"
            drawRow(dc, _mgrsString, color, 0.4375, 0.30, F_LARGE);
            return;
        }
        var idx = nl as Number;
        var top = _mgrsString.substring(0, idx) as String;                          // "14R NV"
        var coords = _mgrsString.substring(idx + 1, _mgrsString.length()) as String; // "38140 72680"
        drawRow(dc, top, color, 0.35, 0.17, F_LARGE);
        drawRow(dc, coords, color, 0.525, 0.17, F_LARGE);
    }

    private function drawAlt(dc as Dc) as Void {
        var text = "Alt: N/A";
        var alt = _altitude;
        if (alt != null) {
            if (alt >= 1000.0) {
                text = "Alt: " + (alt / 1000.0).format("%.2f") + "km";
            } else {
                text = "Alt: " + alt.format("%.1f") + "m";
            }
        }
        // Black-and-white screens can't show GPS quality by color, so spell it out
        if (_mono && _gpsQuality != Position.QUALITY_NOT_AVAILABLE) {
            text += (_gpsQuality == Position.QUALITY_GOOD) ? "  GPS GOOD" : "  GPS FAIR";
        }
        drawRow(dc, text, mgrsColor(), 0.70, 0.10, F_XTINY);
    }

    private function drawZuluJulian(dc as Dc) as Void {
        var now = Time.now();
        var utc = Gregorian.utcInfo(now, Time.FORMAT_SHORT);
        var zulu = utc.hour.format("%02d") + ":" + utc.min.format("%02d") + ":" + utc.sec.format("%02d");
        var jd = julianDay(now, utc).format("%03d");

        var font = Graphics.FONT_XTINY;
        var y = dc.getHeight() * 0.80;
        var b = rowBounds(dc, y, dc.getFontHeight(font) * 0.3);
        var sepW = dc.getTextWidthInPixels(" | ", font);
        var half = ((b[1] - b[0]) - sepW) / 2.0;

        // Full labels if they fit, short ones on narrow screens
        var leftText = "Z: " + zulu;
        var rightText = "Julian: " + jd;
        if (dc.getTextWidthInPixels(leftText, font) > half
                || dc.getTextWidthInPixels(rightText, font) > half) {
            leftText = zulu + "Z";
            rightText = "J" + jd;
        }

        dc.setColor(C_WHITE, Graphics.COLOR_TRANSPARENT);
        drawCentered(dc, b[1] - half / 2.0, y, font, leftText);
        drawCentered(dc, b[0] + half / 2.0, y, font, rightText);
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

    private function azimuthText() as String {
        var hd = _heading;
        return (hd != null) ? "AZ: " + hd.format("%.0f") + "°" : "AZ: N/A";
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
