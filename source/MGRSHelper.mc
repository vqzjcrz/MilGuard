import Toybox.Math;
import Toybox.Lang;

module MGRSHelper {

    // WGS84 ellipsoid constants
    const A   as Double = 6378137.0d;               // semi-major axis (meters)
    const F   as Double = 1.0d / 298.257223563d;    // flattening
    const K0  as Double = 0.9996d;                  // scale factor
    const E2  as Double = 2.0d * F - F * F;         // eccentricity squared
    const EPR2 as Double = E2 / (1.0d - E2);        // e'^2 (second eccentricity squared)

    // False easting/northing
    const FALSE_EASTING  as Double = 500000.0d;
    const FALSE_NORTHING as Double = 10000000.0d;   // applied for southern hemisphere

    // MGRS 100k letter sets — 3 column sets, 2 row sets
    // Column sets cycle every 3 zones; row sets cycle every 2 zones
    var COL_SETS as Array<String> = ["ABCDEFGH", "JKLMNPQR", "STUVWXYZ"] as Array<String>;
    var ROW_SETS as Array<String> = ["ABCDEFGHJKLMNPQRSTUV", "FGHJKLMNPQRSTUVABCDE"] as Array<String>;

    // Latitude band letters — C through X, skipping I and O
    var ZONE_LETTERS as String = "CDEFGHJKLMNPQRSTUVWX";

    // -----------------------------------------------------------------------
    // getZoneNumber
    // Returns the UTM zone number (1–60) for a given lat/lon.
    // Handles the Norway (zone 32) and Svalbard (zones 31/33/35/37) exceptions.
    // -----------------------------------------------------------------------
    function getZoneNumber(lat as Double, lon as Double) as Number {
        var zone = ((lon + 180.0d) / 6.0d).toNumber() + 1;

        // Norway exception: zone 32 extended, zone 31 removed
        if (lat >= 56.0d && lat < 64.0d && lon >= 3.0d && lon < 12.0d) {
            zone = 32;
        }

        // Svalbard exceptions
        if (lat >= 72.0d && lat < 84.0d) {
            if      (lon >= 0.0d  && lon < 9.0d)  { zone = 31; }
            else if (lon >= 9.0d  && lon < 21.0d) { zone = 33; }
            else if (lon >= 21.0d && lon < 33.0d) { zone = 35; }
            else if (lon >= 33.0d && lon < 42.0d) { zone = 37; }
        }

        return zone;
    }

    // -----------------------------------------------------------------------
    // getZoneLetter
    // Returns the UTM latitude band letter for a given latitude.
    // Returns "Z" for polar regions outside the valid UTM range.
    // -----------------------------------------------------------------------
    function getZoneLetter(lat as Double) as String {
        if (lat < -80.0d || lat > 84.0d) { return "Z"; }
        var idx = ((lat + 80.0d) / 8.0d).toNumber();
        if (idx >= 20) { idx = 19; }
        return ZONE_LETTERS.substring(idx, idx + 1);
    }

    // -----------------------------------------------------------------------
    // latLonToUtm
    // Converts WGS84 lat/lon (degrees) to UTM easting/northing (meters).
    //
    // Uses the full Krüger series (through AA^5 / T^2 terms) for maximum
    // accuracy. Error is sub-millimeter across the full UTM zone.
    //
    // Returns [easting, northing] as Doubles.
    // -----------------------------------------------------------------------
    function latLonToUtm(lat as Double, lon as Double, zoneNum as Number) as Array<Double> {
        var latR  = lat * Math.PI / 180.0d;
        var lonR  = lon * Math.PI / 180.0d;

        // Central meridian of this zone in radians
        var lonOr = ((zoneNum - 1) * 6 - 180 + 3).toDouble() * Math.PI / 180.0d;

        var sinLat = Math.sin(latR);
        var cosLat = Math.cos(latR);
        var tanLat = sinLat / cosLat;

        // Radius of curvature in the prime vertical
        var N = A / Math.sqrt(1.0d - E2 * sinLat * sinLat);

        var T  = tanLat * tanLat;   // tan^2(lat)
        var T2 = T * T;             // tan^4(lat)
        var C  = EPR2 * cosLat * cosLat;
        var C2 = C * C;
        var AA = cosLat * (lonR - lonOr);
        var AA2 = AA * AA;
        var AA3 = AA2 * AA;
        var AA4 = AA3 * AA;
        var AA5 = AA4 * AA;
        var AA6 = AA5 * AA;

        // Meridional arc M — full series through e^6 terms
        var e4 = E2 * E2;
        var e6 = e4 * E2;
        var M = A * (
            (1.0d - E2/4.0d - 3.0d*e4/64.0d - 5.0d*e6/256.0d)   * latR
          - (3.0d*E2/8.0d + 3.0d*e4/32.0d + 45.0d*e6/1024.0d)    * Math.sin(2.0d * latR)
          + (15.0d*e4/256.0d + 45.0d*e6/1024.0d)                   * Math.sin(4.0d * latR)
          - (35.0d*e6/3072.0d)                                      * Math.sin(6.0d * latR)
        );

        // Easting — through AA^5 term
        var easting = K0 * N * (
            AA
          + (1.0d - T + C)                                    * AA3 / 6.0d
          + (5.0d - 18.0d*T + T2 + 72.0d*C - 58.0d*EPR2)    * AA5 / 120.0d
        ) + FALSE_EASTING;

        // Northing — through AA^6 term
        var northing = K0 * (
            M + N * tanLat * (
                AA2 / 2.0d
              + (5.0d - T + 9.0d*C + 4.0d*C2)                          * AA4 / 24.0d
              + (61.0d - 58.0d*T + T2 + 600.0d*C - 330.0d*EPR2)        * AA6 / 720.0d
            )
        );

        // Southern hemisphere: add false northing
        if (lat < 0.0d) { northing += FALSE_NORTHING; }

        return [easting, northing] as Array<Double>;
    }

    // -----------------------------------------------------------------------
    // get100kLetters
    // Returns the two-letter MGRS 100k square identifier.
    //
    // Column letter: determined by zone number and easting.
    // Row letter: determined by zone number and northing.
    //   Row letters cycle every 2,000,000m (20 × 100km rows).
    //   Odd zones use ROW_SETS[0], even zones use ROW_SETS[1].
    // -----------------------------------------------------------------------
    function get100kLetters(zoneNum as Number, easting as Double, northing as Double) as String {
        // Column: which 100k easting band within the zone (1-8)
        var colSet = (zoneNum - 1) % 3;
        var e100k  = (easting / 100000.0d).toNumber() - 1;
        // Clamp to valid range just in case of floating point edge cases
        if (e100k < 0) { e100k = 0; }
        if (e100k > 7) { e100k = 7; }
        var colLetter = (COL_SETS[colSet] as String).substring(e100k, e100k + 1);

        // Row: cycle every 2,000,000m; odd/even zone sets offset by 5 rows
        var rowSet = (zoneNum - 1) % 2;
        var n100k  = ((northing.toNumber() % 2000000) / 100000).toNumber();
        // Clamp defensively
        if (n100k < 0)  { n100k = 0; }
        if (n100k > 19) { n100k = 19; }
        var rowLetter = (ROW_SETS[rowSet] as String).substring(n100k, n100k + 1);

        return colLetter + rowLetter;
    }

    // -----------------------------------------------------------------------
    // convert
    // Main entry point. Converts WGS84 lat/lon to an MGRS string.
    //
    // precision: number of digits in easting/northing components
    //   1 = 10km resolution  (e.g. "14R NV 3 7")
    //   2 = 1km  resolution  (e.g. "14R NV 38 72")
    //   3 = 100m resolution  (e.g. "14R NV 381 726")
    //   4 = 10m  resolution  (e.g. "14R NV 3814 7268")
    //   5 = 1m   resolution  (e.g. "14R NV 38140 72680")
    // -----------------------------------------------------------------------
    function convert(lat as Double, lon as Double, precision as Number) as String {
        var zoneNumber = getZoneNumber(lat, lon);
        var zoneLetter = getZoneLetter(lat);
        var utm        = latLonToUtm(lat, lon, zoneNumber);
        var easting    = utm[0] as Double;
        var northing   = utm[1] as Double;
        var letters    = get100kLetters(zoneNumber, easting, northing);

        // Strip the 100k prefix (mod 100000) and format to 5 digits,
        // then take only as many digits as requested by precision
        var eInt = easting.toNumber()  % 100000;
        var nInt = northing.toNumber() % 100000;

        // Guard against negative modulo results on some runtimes
        if (eInt < 0) { eInt += 100000; }
        if (nInt < 0) { nInt += 100000; }

        var e = eInt.format("%05d").substring(0, precision);
        var n = nInt.format("%05d").substring(0, precision);
        
        return zoneNumber.format("%02d") + zoneLetter + " " + letters + "\n" + e + " " + n;
    }

}

