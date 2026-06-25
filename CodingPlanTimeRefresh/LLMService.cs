using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using CodingPlanTimeRefresh.Resources.Strings;

namespace CodingPlanTimeRefresh;

public static class LLMService
{
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(120) };

    public static async Task<string> AskStreamAsync(
        string apiUrl, string apiKey, string model, string question,
        Action<string> onChunk)
    {
        if (string.IsNullOrWhiteSpace(apiUrl))
            throw new Exception(AppResources.ApiUrlNotConfigured);
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new Exception(AppResources.ApiKeyNotConfigured);

        var body = new
        {
            model,
            stream = true,
            messages = new[] { new { role = "user", content = question } },
            temperature = 0.9
        };
        var json = JsonSerializer.Serialize(body);

        using var request = new HttpRequestMessage(HttpMethod.Post, apiUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");

        // Log request
        var reqLog = new StringBuilder();
        reqLog.AppendLine("========== [Request] ==========");
        reqLog.AppendLine($"POST {apiUrl}");
        foreach (var h in request.Headers)
        {
            var val = h.Key.Equals("Authorization", StringComparison.OrdinalIgnoreCase)
                ? "Bearer ***" : string.Join(", ", h.Value);
            reqLog.AppendLine($"{h.Key}: {val}");
        }
        foreach (var h in request.Content.Headers)
            reqLog.AppendLine($"{h.Key}: {string.Join(", ", h.Value)}");
        reqLog.AppendLine();
        reqLog.AppendLine(FormatJson(json));
        LogService.Append(reqLog.ToString());

        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);

        // Log response headers
        var respLog = new StringBuilder();
        respLog.AppendLine($"========== [Response] {(int)response.StatusCode} {response.StatusCode} ==========");
        foreach (var h in response.Headers)
            respLog.AppendLine($"{h.Key}: {string.Join(", ", h.Value)}");
        foreach (var h in response.Content.Headers)
            respLog.AppendLine($"{h.Key}: {string.Join(", ", h.Value)}");

        if (!response.IsSuccessStatusCode)
        {
            var errBody = await response.Content.ReadAsStringAsync();
            respLog.AppendLine();
            respLog.AppendLine(errBody);
            LogService.Append(respLog.ToString());
            throw new Exception(string.Format(AppResources.ApiCallFailedFormat, response.StatusCode, errBody));
        }

        // Read SSE stream
        var fullResult = new StringBuilder();
        using var stream = await response.Content.ReadAsStreamAsync();
        using var reader = new StreamReader(stream);

        string? line;
        while ((line = await reader.ReadLineAsync()) != null)
        {
            if (string.IsNullOrEmpty(line)) continue;
            if (line == "data: [DONE]") break;
            if (!line.StartsWith("data: ")) continue;

            var data = line["data: ".Length..];
            try
            {
                var doc = JsonDocument.Parse(data);
                var delta = doc.RootElement
                    .GetProperty("choices")[0]
                    .GetProperty("delta");
                if (delta.TryGetProperty("content", out var contentEl))
                {
                    var chunk = contentEl.GetString();
                    if (chunk != null)
                    {
                        fullResult.Append(chunk);
                        onChunk(chunk);
                    }
                }
            }
            catch (JsonException)
            {
                // Skip malformed chunks
            }
        }

        respLog.AppendLine();
        respLog.AppendLine(FormatJson(fullResult.ToString()));
        LogService.Append(respLog.ToString());

        return fullResult.ToString();
    }

    public record LimitInfo(int Percentage, long? NextResetTime);

    public record UsageInfo(string? Level, LimitInfo? Mcp, LimitInfo? Hour5, LimitInfo? Weekly);

    public static async Task<UsageInfo?> QueryBigmodelUsagePercentageAsync(string apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey)) return null;

        try
        {
            var url = "https://open.bigmodel.cn/api/monitor/usage/quota/limit";
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("Authorization", apiKey);

            // Log request
            var reqLog = new StringBuilder();
            reqLog.AppendLine("========== [Usage Request] ==========");
            reqLog.AppendLine($"GET {url}");
            foreach (var h in request.Headers)
            {
                var val = h.Key.Equals("Authorization", StringComparison.OrdinalIgnoreCase)
                    ? "***" : string.Join(", ", h.Value);
                reqLog.AppendLine($"{h.Key}: {val}");
            }
            LogService.Append(reqLog.ToString());

            using var response = await _http.SendAsync(request);
            var json = await response.Content.ReadAsStringAsync();

            // Log response
            var respLog = new StringBuilder();
            respLog.AppendLine($"========== [Usage Response] {(int)response.StatusCode} {response.StatusCode} ==========");
            foreach (var h in response.Headers)
                respLog.AppendLine($"{h.Key}: {string.Join(", ", h.Value)}");
            foreach (var h in response.Content.Headers)
                respLog.AppendLine($"{h.Key}: {string.Join(", ", h.Value)}");
            respLog.AppendLine();
            respLog.AppendLine(FormatJson(json));
            LogService.Append(respLog.ToString());

            if (!response.IsSuccessStatusCode) return null;

            var doc = JsonDocument.Parse(json);

            if (!doc.RootElement.TryGetProperty("data", out var data)) return null;
            if (!data.TryGetProperty("limits", out var limits)) return null;

            var level = data.TryGetProperty("level", out var levelEl) ? levelEl.GetString() : null;
            LimitInfo? mcp = null, hour5 = null, weekly = null;

            foreach (var limit in limits.EnumerateArray())
            {
                if (!limit.TryGetProperty("percentage", out var pct)) continue;
                var pctVal = pct.GetInt32();

                long? nextReset = null;
                if (limit.TryGetProperty("nextResetTime", out var nrt))
                    nextReset = nrt.GetInt64();

                var info = new LimitInfo(pctVal, nextReset);

                if (!limit.TryGetProperty("type", out var typeEl)) continue;
                var typeStr = typeEl.GetString();

                if (typeStr == "TIME_LIMIT")
                {
                    mcp = info;
                }
                else if (typeStr == "TOKENS_LIMIT")
                {
                    var unit = limit.TryGetProperty("unit", out var u) ? u.GetInt32() : 0;
                    var number = limit.TryGetProperty("number", out var n) ? n.GetInt32() : 0;
                    if (unit == 3 && number == 5)
                        hour5 = info;
                    else
                        weekly = info;
                }
            }

            return new UsageInfo(level, mcp, hour5, weekly);
        }
        catch
        {
            return null;
        }
    }

    private static readonly JsonSerializerOptions BaseJsonSerializerOptions = new() { WriteIndented = true };
    private static string FormatJson(string json)
    {
        try
        {
            var doc = JsonDocument.Parse(json);
            return JsonSerializer.Serialize(doc, BaseJsonSerializerOptions);
        }
        catch
        {
            return json;
        }
    }
}
