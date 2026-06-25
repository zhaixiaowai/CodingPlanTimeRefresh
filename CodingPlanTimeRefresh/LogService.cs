namespace CodingPlanTimeRefresh;

public static class LogService
{
    private static readonly string LogDir = GetDataDirectory();
    private static readonly string LogPath = Path.Combine(LogDir, "log.txt");

    public static void Append(string message)
    {
        Directory.CreateDirectory(LogDir);
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}";
        File.AppendAllText(LogPath, line);
    }

    private static string GetDataDirectory()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "CodingPlanTimeRefresh");
    }
}
