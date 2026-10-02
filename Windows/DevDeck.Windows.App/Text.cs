using System.Globalization;
using System;
using DevDeck.Windows.Core;

namespace DevDeck.Windows.App;

internal static class Text
{
    private static Localization locale = new(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName);
    internal static string Language => locale.Language;
    internal static Localization Resources => locale;
    internal static void Use(string language) => locale = new(language == "system" ? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName : language);
    internal static string L(string key, params object[] arguments) => locale.Get(key, arguments);
    internal static string LN(string key, int count) => locale.Plural(key, count);
    internal static string Failure(Exception error) => FailureText.For(error, locale);
}
