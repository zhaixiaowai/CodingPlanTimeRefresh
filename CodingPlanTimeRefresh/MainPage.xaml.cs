using System.Text;
using CodingPlanTimeRefresh.Resources.Strings;

namespace CodingPlanTimeRefresh;

public partial class MainPage : ContentPage
{
    private AppConfig _config;
    private bool _loading = true;
    private bool _isBusy = false;
    private bool _collapsed = false;
    private int _selectedLanguageIndex = 0;
    private IDispatcherTimer _timer;
    private IDispatcherTimer _usageTimer;

    private static readonly (int Hour, int Minute)[] TriggerTimes = [(1, 0), (7, 0), (13, 0), (19, 0)];

    public MainPage()
    {
        InitializeComponent();
        _config = App.Config;

        TopMostCheck.IsChecked = _config.IsAlwaysOnTop;
        ApiUrlEntry.Text = _config.ApiUrl;
        ApiKeyEntry.Text = _config.ApiKey;
        ModelEntry.Text = _config.Model;

        _selectedLanguageIndex = (_config.Language ?? "auto") switch { "zh" => 1, "en" => 2, _ => 0 };
        UpdateLanguageButtons();

        _loading = false;

        var pg = new PointerGestureRecognizer();
        pg.PointerEnteredCommand = new Command(() => CollapseShape.Fill = Color.FromArgb("#CCCCCC"));
        pg.PointerExitedCommand = new Command(() => CollapseShape.Fill = Color.FromArgb("#666666"));
        CollapseGrid.GestureRecognizers.Add(pg);

        _timer = Dispatcher.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(6);
        _timer.Tick += OnTimerTick;
        _timer.Start();

        _usageTimer = Dispatcher.CreateTimer();
        _usageTimer.Interval = TimeSpan.FromSeconds(60);
        _usageTimer.Tick += OnUsageTimerTick;
        _usageTimer.Start();

        _ = QueryUsageAsync();

        UpdateNextTriggerLabel();

        if (_config.IsCollapsed)
        {
            _collapsed = true;
            BottomBar.IsVisible = false;
            CollapseShape.Points = new PointCollection { new(0, 10), new(16, 10), new(8, 0) };
        }

        if (string.IsNullOrWhiteSpace(_config.ApiUrl) || string.IsNullOrWhiteSpace(_config.ApiKey))
            ConfigSection.IsVisible = true;
    }

    private void OnTopMostLabelTapped(object? sender, TappedEventArgs e)
    {
        TopMostCheck.IsChecked = !TopMostCheck.IsChecked;
    }

    private void OnTopMostChanged(object? sender, CheckedChangedEventArgs e)
    {
        if (_loading) return;

        _config.IsAlwaysOnTop = e.Value;
        App.ApplyAlwaysOnTop(e.Value);
        ConfigService.Save(_config);
    }

    private void OnToggleCollapse(object? sender, EventArgs e)
    {
        try
        {
            _collapsed = !_collapsed;
            BottomBar.IsVisible = !_collapsed;
            CollapseShape.Points = _collapsed
                ? new PointCollection { new(0, 10), new(16, 10), new(8, 0) }
                : new PointCollection { new(0, 0), new(16, 0), new(8, 10) };
            if (_collapsed)
                ResizeCollapsed();
            else
                App.ResizeWindow(ConfigService.ExpandedHeight);
            _config.IsCollapsed = _collapsed;
            ConfigService.Save(_config);
        }
        catch (Exception ex)
        {
            LogService.Append(ex.ToString());
            throw;
        }
    }

    private void ResizeCollapsed()
    {
        App.ResizeWindow(WeeklyRow.IsVisible
            ? ConfigService.CollapsedHeightWithWeekly
            : ConfigService.CollapsedHeight);
    }

    private void OnToggleConfig(object? sender, TappedEventArgs e)
    {
        ResultSection.IsVisible = false;
        ApiUrlEntry.Text = _config.ApiUrl;
        ApiKeyEntry.Text = _config.ApiKey;
        ModelEntry.Text = _config.Model;
        _selectedLanguageIndex = (_config.Language ?? "auto") switch { "zh" => 1, "en" => 2, _ => 0 };
        UpdateLanguageButtons();
        ConfigSection.IsVisible = true;
    }

    private void OnSaveClicked(object? sender, EventArgs e)
    {
        var oldUrl = _config.ApiUrl;
        var oldKey = _config.ApiKey;

        _config.ApiUrl = ApiUrlEntry.Text ?? "";
        _config.ApiKey = ApiKeyEntry.Text ?? "";
        _config.Model = ModelEntry.Text ?? "";

        var langCode = _selectedLanguageIndex switch { 1 => "zh", 2 => "en", _ => "auto" };
        var langChanged = langCode != (_config.Language ?? "auto");
        _config.Language = langCode;
        ConfigService.Save(_config);
        ConfigSection.IsVisible = false;

        if (langChanged)
        {
            LocalizationService.SetLanguage(langCode);
            RefreshUI();
        }

        if (_config.ApiUrl != oldUrl || _config.ApiKey != oldKey)
            _ = QueryUsageAsync();
    }

    private void OnCancelConfig(object? sender, EventArgs e)
    {
        ConfigSection.IsVisible = false;
    }

    private void OnLangAutoClicked(object? sender, EventArgs e) => SelectLanguage(0);
    private void OnLangZhClicked(object? sender, EventArgs e) => SelectLanguage(1);
    private void OnLangEnClicked(object? sender, EventArgs e) => SelectLanguage(2);

    private void SelectLanguage(int index)
    {
        _selectedLanguageIndex = index;
        UpdateLanguageButtons();
    }

    private void UpdateLanguageButtons()
    {
        LangAutoBtn.BackgroundColor = _selectedLanguageIndex == 0 ? Color.FromArgb("#007ACC") : Color.FromArgb("#3C3C3C");
        LangZhBtn.BackgroundColor = _selectedLanguageIndex == 1 ? Color.FromArgb("#007ACC") : Color.FromArgb("#3C3C3C");
        LangEnBtn.BackgroundColor = _selectedLanguageIndex == 2 ? Color.FromArgb("#007ACC") : Color.FromArgb("#3C3C3C");
    }

    private void RefreshUI()
    {
        TriggerBtn.Text = AppResources.ManualTriggerButton;
        PopupTriggerBtn.Text = AppResources.ManualTriggerPopupButton;
        ResultEditor.Placeholder = AppResources.WaitingPlaceholder;
        ResultHeaderLabel.Text = AppResources.ResultHeader;
        SaveBtn.Text = AppResources.SaveButton;
        CancelBtn.Text = AppResources.CancelButton;
        Token5HText.Text = AppResources.Token5HLabel;
        TokenWeekText.Text = AppResources.TokenWeekLabel;
        MCPMonthText.Text = AppResources.MCPMonthLabel;
        PinText.Text = AppResources.PinLabel;
        LanguageLabelText.Text = AppResources.LanguageLabel;

        LanguageLabelText.Text = AppResources.LanguageLabel;
        LangAutoBtn.Text = AppResources.LanguageAuto;
        LangZhBtn.Text = AppResources.LanguageZh;
        LangEnBtn.Text = AppResources.LanguageEn;
        UpdateLanguageButtons();

        UpdateNextTriggerLabel();
        _ = QueryUsageAsync();
    }

    private void OnCloseResult(object? sender, TappedEventArgs e)
    {
        ResultSection.IsVisible = false;
    }

    private async void OnTimerTick(object? sender, EventArgs e)
    {
        UpdateNextTriggerLabel();

        var now = DateTime.Now;
        foreach (var (h, m) in TriggerTimes)
        {
            var key = $"{now.Date:yyyy-MM-dd} {h:D2}:{m:D2}";
            if (now.Hour == h && now.Minute == m && _config.LastAutoTriggerKey != key)
            {
                _config.LastAutoTriggerKey = key;
                ConfigService.Save(_config);
                for (int attempt = 1; attempt <= 3; attempt++)
                {
                    if (await CallLLMAsync(false)) break;
                    if (attempt < 3) await Task.Delay(5000);
                }
                break;
            }
        }
    }

    private void UpdateNextTriggerLabel()
    {
        var now = DateTime.Now;
        DateTime? next = null;

        foreach (var (h, m) in TriggerTimes)
        {
            var target = now.Date.AddHours(h).AddMinutes(m);
            var key = $"{now.Date:yyyy-MM-dd} {h:D2}:{m:D2}";
            if (target > now || _config.LastAutoTriggerKey != key)
            {
                if (target <= now) target = target.AddDays(1);
                if (next == null || target < next) next = target;
            }
        }

        if (next.HasValue)
        {
            var diff = next.Value - now;
            var totalSeconds = (int)diff.TotalSeconds;
            var minutes = totalSeconds / 60;
            var seconds = totalSeconds % 60;
            NextTriggerLabel.Text = string.Format(AppResources.NextTriggerFormat, next.Value, minutes, seconds);
        }
    }

    private void OnOpenResult(object? sender, EventArgs e)
    {
        ConfigSection.IsVisible = false;
        ResultSection.IsVisible = true;
    }

    private async void OnManualTrigger(object? sender, EventArgs e)
    {
        await CallLLMAsync(true);
    }

    private async Task<bool> CallLLMAsync(bool isManual)
    {
        if (_isBusy) return false;
        _isBusy = true;
        TriggerBtn.IsEnabled = false;
        PopupTriggerBtn.IsEnabled = false;
        ResultEditor.Text = AppResources.LoadingText;

        try
        {
            var model = string.IsNullOrWhiteSpace(_config.Model) ? "glm-5.1" : _config.Model;
            var prompt = $"{AppResources.JokePrompt}\nseed={Random.Shared.Next(10000)}";
            var sb = new StringBuilder();
            await LLMService.AskStreamAsync(
                _config.ApiUrl, _config.ApiKey, model, prompt,
                chunk =>
                {
                    sb.Append(chunk);
                    var text = sb.ToString();
                    MainThread.BeginInvokeOnMainThread(() =>
                    {
                        if (ResultEditor.Text == AppResources.LoadingText) ResultEditor.Text = "";
                        ResultEditor.Text = text;
                    });
                });
            ResultHeaderLabel.Text = string.Format(AppResources.ResultTimestampFormat, DateTime.Now);
            return true;
        }
        catch (Exception ex)
        {
            if (!isManual)
            {
                _config.LastAutoTriggerKey = "";
                ConfigService.Save(_config);
            }
            ResultEditor.Text = string.Format(AppResources.ErrorMessageFormat, ex.Message);
            LogService.Append($"[Error] {ex.Message}");
            return false;
        }
        finally
        {
            _isBusy = false;
            TriggerBtn.IsEnabled = true;
            PopupTriggerBtn.IsEnabled = true;
        }
    }

    private async void OnUsageTimerTick(object? sender, EventArgs e)
    {
        await QueryUsageAsync();
    }

    private static Color PctColor(int pct) => pct switch
    {
        >= 80 => Colors.Red,
        >= 50 => Color.FromArgb("#FF8C00"),
        _ => Color.FromArgb("#007ACC")
    };

    private static string ResetText(long? nextReset)
    {
        if (!nextReset.HasValue) return "";
        var dt = DateTime.UnixEpoch.AddMilliseconds(nextReset.Value).ToLocalTime();
        var format = dt.Date == DateTime.Today ? AppResources.ResetTextToday : AppResources.ResetTextOther;
        return string.Format(format, dt);
    }

    private void UpdateLimitRow(Label pctLabel, Label resetLabel, LLMService.LimitInfo? info, bool hideIfNull = false)
    {
        if (info == null)
        {
            pctLabel.Text = "";
            resetLabel.Text = "";
            if (hideIfNull)
            {
                WeeklyRow.IsVisible = false;
                if (_collapsed) ResizeCollapsed();
            }
            return;
        }
        if (hideIfNull)
        {
            WeeklyRow.IsVisible = true;
            if (_collapsed) ResizeCollapsed();
        }
        pctLabel.Text = $"{info.Percentage}%";
        pctLabel.TextColor = PctColor(info.Percentage);
        resetLabel.Text = ResetText(info.NextResetTime);
    }

    private async Task QueryUsageAsync()
    {
        if (string.IsNullOrWhiteSpace(_config.ApiUrl) || string.IsNullOrWhiteSpace(_config.ApiKey))
            return;

        LLMService.UsageInfo? usage;
        if (_config.ApiUrl.Contains("bigmodel.cn"))
            usage = await LLMService.QueryBigmodelUsagePercentageAsync(_config.ApiKey);
        else
            return;

        if (usage == null) return;

        MainThread.BeginInvokeOnMainThread(() =>
        {
            UpdateLimitRow(McpPctLabel, McpResetLabel, usage.Mcp);
            UpdateLimitRow(Hour5PctLabel, Hour5ResetLabel, usage.Hour5);
            UpdateLimitRow(WeeklyPctLabel, WeeklyResetLabel, usage.Weekly, hideIfNull: true);

            if (App.MainWindow != null)
            {
                var levelText = string.IsNullOrWhiteSpace(usage.Level) ? "" : $" {char.ToUpper(usage.Level[0])}{usage.Level[1..]}";
                var primaryPct = usage.Hour5?.Percentage ?? usage.Mcp?.Percentage ?? 0;
                App.MainWindow.Title = string.Format(AppResources.WindowTitleFormat, primaryPct, levelText.Trim());
            }
        });
    }
}
