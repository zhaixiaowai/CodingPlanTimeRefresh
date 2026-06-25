namespace CodingPlanTimeRefresh;

public class AppConfig
{
    public bool IsAlwaysOnTop { get; set; } = false;
    public string ApiUrl { get; set; } = "";
    public string ApiKey { get; set; } = "";
    public string Model { get; set; } = "glm-5.1";
    public string LastAutoTriggerKey { get; set; } = "";
    public bool IsCollapsed { get; set; } = false;
    public string? Language { get; set; }
}
