using System.Globalization;

namespace CodingPlanTimeRefresh;

public static class LocalizationService
{
    public static string CurrentLanguage { get; private set; } = "zh";

    public static void Initialize(string? savedLanguage)
    {
        string lang;
        if (!string.IsNullOrEmpty(savedLanguage) && savedLanguage != "auto")
        {
            lang = savedLanguage;
        }
        else
        {
            lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "en" ? "en" : "zh";
        }

        ApplyCulture(lang);
    }

    public static string SetLanguage(string lang)
    {
        if (lang == "auto")
        {
            lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "en" ? "en" : "zh";
        }
        ApplyCulture(lang);
        return lang;
    }

    private static void ApplyCulture(string lang)
    {
        CurrentLanguage = lang;
        var culture = new CultureInfo(lang == "en" ? "en" : "zh-CN");
        CultureInfo.CurrentUICulture = culture;
        CultureInfo.CurrentCulture = culture;
        Resources.Strings.AppResources.Culture = culture;
    }
}
