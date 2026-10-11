using System.Windows.Media;

namespace DevDeck.Shell;

// What Windows says about its scheme: the app mode, the Windows mode the taskbar follows,
// transparency effects, the accent on Start and the taskbar, and the accent's shades.
public sealed record ThemeInputs(
    bool AppsUseLightTheme,
    bool TransparencyEnabled,
    bool AccentOnTaskbar,
    Color AccentLight2,
    Color AccentDark1,
    Color AccentDark2,
    bool SystemUsesLightTheme = false)
{
    public static ThemeInputs Default { get; } = new(
        false,
        true,
        false,
        Color.FromRgb(0x99, 0xEB, 0xFF),
        Color.FromRgb(0x00, 0x5A, 0x9E),
        Color.FromRgb(0x00, 0x42, 0x75));

    // The card is drawn in the taskbar's material, and the taskbar is light only in the light
    // Windows mode without the accent: with the accent Windows draws it dark, with light text.
    public bool TaskbarIsLight => SystemUsesLightTheme && !AccentOnTaskbar;
}

// Every colour the shell draws, for one scheme. The engine sends meanings; this maps them, and
// nothing else in the shell names a colour that follows the scheme.
public sealed class DeckPalette
{
    // The resource keys a palette fills, the same in both schemes.
    public static readonly IReadOnlyList<string> Keys =
    [
        "TextPrimary", "TextSecondary", "TextTertiary",
        "ToneGood", "ToneAttention", "ToneAlert", "TonePersonal",
        "LinkInfo", "EnvironmentInfo",
        "ControlFill", "ControlHover", "ControlPressed", "ControlStroke", "SeparatorStroke",
        "FocusOuter", "FocusInner", "MenuFill", "MenuHover", "PressedText",
        "ToggleStroke", "ToggleThumb", "ToggleOnFill", "ToggleOnThumb",
        "WindowBackground", "DialogBackground", "SolidCardBackground", "HighlightText",
    ];

    private readonly IReadOnlyDictionary<string, Color> tokens;

    private DeckPalette(
        bool isLight,
        Color cardTint,
        Color accentFill,
        Color accentText,
        IReadOnlyDictionary<string, Color> tokens)
    {
        IsLight = isLight;
        CardTint = cardTint;
        AccentFill = accentFill;
        AccentText = accentText;
        this.tokens = tokens;
    }

    public bool IsLight { get; }

    // The card's surface: the tint over Acrylic, or a solid colour when transparency is off.
    public Color CardTint { get; }

    // A primary button: the accent shade Windows 11 uses for the scheme, with text that reads on it.
    public Color AccentFill { get; }

    public Color AccentText { get; }

    public Color this[string key] => tokens[key];

    public static DeckPalette For(ThemeInputs inputs)
    {
        return inputs.TaskbarIsLight ? Light(inputs) : Dark(inputs);
    }

    public Color Tone(string? tone)
    {
        return tone switch
        {
            "good" => this["ToneGood"],
            "attention" => this["ToneAttention"],
            "alert" => this["ToneAlert"],
            "personal" => this["TonePersonal"],
            _ => this["TextPrimary"],
        };
    }

    // A tinted surface: a badge or a toned button's fill. Neutral is the control fill.
    public Color ToneTint(string? tone)
    {
        if (tone is not ("good" or "attention" or "alert" or "personal"))
        {
            return this["ControlFill"];
        }
        var colour = Tone(tone);
        return Color.FromArgb(IsLight ? (byte)31 : (byte)35, colour.R, colour.G, colour.B);
    }

    // The tray icon follows the taskbar's own mode, which can differ from the apps' mode.
    public static Color TaskbarGlyph(bool lightTaskbar)
    {
        return lightTaskbar ? Color.FromRgb(34, 34, 34) : Color.FromRgb(246, 246, 246);
    }

    // The taskbar's colour as measured on Windows 11: #1C1C1C dark, #EEEEEE light, the accent's
    // second dark shade with the accent shown. With transparency the same colour lies over the
    // blur at the taskbar's opacity.
    public static Color TaskbarColour(ThemeInputs inputs)
    {
        var solid = inputs.AccentOnTaskbar
            ? inputs.AccentDark2
            : inputs.TaskbarIsLight ? Color.FromRgb(0xEE, 0xEE, 0xEE) : Color.FromRgb(0x1C, 0x1C, 0x1C);
        var opacity = !inputs.TransparencyEnabled ? (byte)255 : TaskbarOpacity(inputs);
        return Color.FromArgb(opacity, solid.R, solid.G, solid.B);
    }

    // The taskbar's tint over its Acrylic, worked out on this machine from the wallpaper beneath it:
    // about 92% dark, with or without the accent, and 80% light.
    private static byte TaskbarOpacity(ThemeInputs inputs)
    {
        return inputs.TaskbarIsLight ? (byte)204 : (byte)235;
    }

    private static DeckPalette Dark(ThemeInputs inputs)
    {
        var tint = TaskbarColour(inputs);
        return new DeckPalette(false, tint, inputs.AccentLight2, Color.FromArgb(230, 0, 0, 0), new Dictionary<string, Color>
        {
            ["TextPrimary"] = Color.FromArgb(0xF2, 255, 255, 255),
            ["TextSecondary"] = Color.FromArgb(0xA8, 255, 255, 255),
            ["TextTertiary"] = Color.FromArgb(0x6B, 255, 255, 255),
            ["ToneGood"] = Color.FromRgb(0x70, 0xC7, 0x99),
            ["ToneAttention"] = Color.FromRgb(0xF0, 0xC2, 0x6B),
            ["ToneAlert"] = Color.FromRgb(0xE8, 0x84, 0x84),
            ["TonePersonal"] = Color.FromRgb(0xA9, 0x9B, 0xE0),
            ["LinkInfo"] = Color.FromRgb(0x7F, 0xAE, 0xDD),
            ["EnvironmentInfo"] = Color.FromRgb(0xA9, 0x9B, 0xE0),
            ["ControlFill"] = Color.FromArgb(0x0F, 255, 255, 255),
            ["ControlHover"] = Color.FromArgb(0x17, 255, 255, 255),
            ["ControlPressed"] = Color.FromArgb(0x0A, 255, 255, 255),
            ["ControlStroke"] = Color.FromArgb(0x17, 255, 255, 255),
            ["SeparatorStroke"] = Color.FromArgb(0x0D, 255, 255, 255),
            ["FocusOuter"] = Color.FromArgb(0xF2, 255, 255, 255),
            ["FocusInner"] = Color.FromRgb(0x20, 0x20, 0x24),
            ["MenuFill"] = Color.FromArgb(0xFA, 0x2B, 0x2B, 0x2F),
            ["MenuHover"] = Color.FromArgb(0x24, 255, 255, 255),
            ["PressedText"] = Color.FromArgb(0xCC, 255, 255, 255),
            ["ToggleStroke"] = Color.FromArgb(0x73, 255, 255, 255),
            ["ToggleThumb"] = Color.FromArgb(0xCC, 255, 255, 255),
            ["ToggleOnFill"] = inputs.AccentLight2,
            ["ToggleOnThumb"] = Color.FromRgb(0x0B, 0x1A, 0x24),
            ["WindowBackground"] = Color.FromRgb(32, 32, 32),
            ["DialogBackground"] = Color.FromRgb(43, 43, 47),
            ["SolidCardBackground"] = Color.FromRgb(43, 43, 47),
            ["HighlightText"] = Color.FromRgb(0, 0, 0),
        });
    }

    private static DeckPalette Light(ThemeInputs inputs)
    {
        var tint = TaskbarColour(inputs);
        return new DeckPalette(true, tint, inputs.AccentDark1, Color.FromRgb(255, 255, 255), new Dictionary<string, Color>
        {
            ["TextPrimary"] = Color.FromArgb(0xEB, 0, 0, 0),
            ["TextSecondary"] = Color.FromArgb(0xB8, 0, 0, 0),
            ["TextTertiary"] = Color.FromArgb(0x94, 0, 0, 0),
            ["ToneGood"] = Color.FromRgb(0x0F, 0x7B, 0x4A),
            ["ToneAttention"] = Color.FromRgb(0x8A, 0x5A, 0x00),
            ["ToneAlert"] = Color.FromRgb(0xB3, 0x26, 0x1E),
            ["TonePersonal"] = Color.FromRgb(0x5B, 0x3F, 0xAE),
            ["LinkInfo"] = Color.FromRgb(0x0F, 0x5A, 0xA8),
            ["EnvironmentInfo"] = Color.FromRgb(0x5B, 0x3F, 0xAE),
            ["ControlFill"] = Color.FromArgb(0x0F, 0, 0, 0),
            ["ControlHover"] = Color.FromArgb(0x17, 0, 0, 0),
            ["ControlPressed"] = Color.FromArgb(0x0A, 0, 0, 0),
            ["ControlStroke"] = Color.FromArgb(0x21, 0, 0, 0),
            ["SeparatorStroke"] = Color.FromArgb(0x0F, 0, 0, 0),
            ["FocusOuter"] = Color.FromArgb(0xE4, 0, 0, 0),
            ["FocusInner"] = Color.FromRgb(255, 255, 255),
            ["MenuFill"] = Color.FromArgb(0xFA, 0xF9, 0xF9, 0xF9),
            ["MenuHover"] = Color.FromArgb(0x0F, 0, 0, 0),
            ["PressedText"] = Color.FromArgb(0xCC, 0, 0, 0),
            ["ToggleStroke"] = Color.FromArgb(0x9E, 0, 0, 0),
            ["ToggleThumb"] = Color.FromArgb(0xB3, 0, 0, 0),
            ["ToggleOnFill"] = inputs.AccentDark1,
            ["ToggleOnThumb"] = Color.FromRgb(255, 255, 255),
            ["WindowBackground"] = Color.FromRgb(243, 243, 243),
            ["DialogBackground"] = Color.FromRgb(249, 249, 249),
            ["SolidCardBackground"] = Color.FromRgb(243, 243, 243),
            ["HighlightText"] = Color.FromRgb(255, 255, 255),
        });
    }
}
