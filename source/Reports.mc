import Toybox.Lang;

// Report formats shown on the pages after the main screen.
// Text is all caps and kept short so a whole report fits on one screen.
module Reports {

    const COUNT = 3;

    function title(index as Number) as String {
        if (index == 0) { return "9-LINE MEDEVAC"; }
        if (index == 1) { return "SALUTE"; }
        return "LACE";
    }

    // Used when the full title is too wide for the top of the screen
    function shortTitle(index as Number) as String {
        if (index == 0) { return "9-LINE"; }
        return title(index);
    }

    // Flat list of pairs: line number or letter, then its label
    function rows(index as Number) as Array<String> {
        if (index == 0) {
            return [
                "1", "LOCATION",
                "2", "FREQ/CALL SIGN",
                "3", "# BY PRECEDENCE",
                "4", "SPECIAL EQUIP",
                "5", "# BY TYPE",
                "6", "SITE SECURITY",
                "7", "SITE MARKING",
                "8", "NATION/STATUS",
                "9", "CBRN"
            ] as Array<String>;
        }
        if (index == 1) {
            return [
                "S", "SIZE",
                "A", "ACTIVITY",
                "L", "LOCATION",
                "U", "UNIT/UNIFORM",
                "T", "TIME",
                "E", "EQUIPMENT"
            ] as Array<String>;
        }
        return [
            "L", "LIQUID",
            "A", "AMMO",
            "C", "CASUALTIES",
            "E", "EQUIPMENT"
        ] as Array<String>;
    }
}
