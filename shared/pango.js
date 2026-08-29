.pragma library

// Best-effort conversion of the Pango markup produced by
// scripts/weather/get_weather.rb into the HTML subset Qt's Text
// (textFormat: Text.RichText) understands.
function pangoToRich(input) {
    if (!input)
        return "";

    var s = input;

    // <span foreground='#rrggbb' font_family='monospace' size='31000'> -> <font color="#rrggbb" face="monospace">
    s = s.replace(/<span([^>]*)>/gi, function (match, attrs) {
        var fg = attrs.match(/foreground=(['"])(#[0-9a-fA-F]{6})\1/);
        var fam = attrs.match(/font_family=(['"])([^'"]+)\1/);
        var tag = "<font";
        if (fam)
            tag += " face=\"" + fam[2] + "\"";
        if (fg)
            tag += " color=\"" + fg[2] + "\"";
        tag += ">";
        return tag;
    });
    s = s.replace(/<\/span>/gi, "</font>");

    return s;
}
