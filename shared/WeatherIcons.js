.pragma library

// WMO weather-code -> glyph/description table. Glyph codepoints come from
// "Symbols Nerd Font Mono" (the same font stack the whole bar already uses),
// verified against ~/.config/waybar/scripts/weather/weather_icons.json so
// they're known to render correctly in this environment. Kept as codepoints
// (not literal characters) since several sit outside the BMP.
var CODES = {
    0: { day: 0xf0599, night: 0xf0594, desc: "Clear sky" },
    1: { day: 0xf0599, night: 0xf0594, desc: "Mainly clear" },
    2: { day: 0xf0595, night: 0xf0f31, desc: "Partly cloudy" },
    3: { day: 0xf0595, night: 0xf0f31, desc: "Overcast" },
    45: { day: 0xf0591, night: 0xf0591, desc: "Fog" },
    48: { day: 0xe313, night: 0xf0591, desc: "Depositing rime fog" },
    51: { day: 0xef1e, night: 0xef1b, desc: "Light drizzle" },
    53: { day: 0xef1e, night: 0xef1b, desc: "Moderate drizzle" },
    55: { day: 0xef1e, night: 0xef1b, desc: "Dense drizzle" },
    56: { day: 0xe306, night: 0xe323, desc: "Light freezing drizzle" },
    57: { day: 0xfb7d, night: 0xfb7d, desc: "Dense freezing drizzle" },
    61: { day: 0xef1e, night: 0xef1b, desc: "Slight rain" },
    63: { day: 0xf0597, night: 0xf0597, desc: "Moderate rain" },
    65: { day: 0xf0596, night: 0xf0596, desc: "Heavy rain" },
    66: { day: 0xf0f35, night: 0xf067f, desc: "Light freezing rain" },
    67: { day: 0xf067f, night: 0xf067f, desc: "Heavy freezing rain" },
    71: { day: 0xf0f34, night: 0xe361, desc: "Slight snow fall" },
    73: { day: 0xf0f34, night: 0xe361, desc: "Moderate snow fall" },
    75: { day: 0xf0f36, night: 0xf0f36, desc: "Heavy snow fall" },
    77: { day: 0xf0598, night: 0xf0598, desc: "Snow grains" },
    80: { day: 0xef1e, night: 0xef1b, desc: "Slight rain showers" },
    81: { day: 0xef1d, night: 0xef1d, desc: "Moderate rain showers" },
    82: { day: 0xef1d, night: 0xef1d, desc: "Violent rain showers" },
    85: { day: 0xe365, night: 0xe367, desc: "Slight snow showers" },
    86: { day: 0xe365, night: 0xe367, desc: "Heavy snow showers" },
    95: { day: 0xe365, night: 0xe367, desc: "Thunderstorm" },
    96: { day: 0xe365, night: 0xe367, desc: "Thunderstorm with slight hail" },
    99: { day: 0xe365, night: 0xe367, desc: "Thunderstorm with heavy hail" }
};

// A few extra glyphs used around the popup (also verified against
// ~/.config/waybar/scripts/weather/ui_icons.json).
var GLYPHS = {
    sunrise: 0xe343,
    sunset: 0xf059a,
    precipLow: 0xee8e,
    precipHigh: 0xf043
};

function iconFor(code, isDay) {
    var entry = CODES[code];
    if (!entry)
        return "?";
    return String.fromCodePoint(isDay ? entry.day : entry.night);
}

function descriptionFor(code) {
    var entry = CODES[code];
    return entry ? entry.desc : "Unknown";
}

function glyph(name) {
    var cp = GLYPHS[name];
    return cp ? String.fromCodePoint(cp) : "";
}
