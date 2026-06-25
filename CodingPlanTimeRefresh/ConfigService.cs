using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CodingPlanTimeRefresh;

public static class ConfigService
{
    public const double ExpandedWidth = 330;
    public const double ExpandedHeight = 318;
    public const double CollapsedHeight = 120;
    public const double CollapsedHeightWithWeekly = 142;
    private static readonly string ConfigDir = GetDataDirectory();
    private static readonly string ConfigPath = Path.Combine(ConfigDir, "config.dat");

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    // AES-256 key (32 bytes) and IV (16 bytes)
    private static readonly byte[] AesKey = Convert.FromBase64String("Y2RmN2g5azNxUDZ5V0JuTG1SNXZpM3hYN2tybEk4SFg=");
    private static readonly byte[] AesIV = Convert.FromBase64String("UGs0dTl2T3dxWjRuY2xmSA==");

    public static AppConfig Load()
    {
        MigrateFromOldPath();
        if (!File.Exists(ConfigPath))
            return TryLoadLegacyJson();

        try
        {
            var encrypted = File.ReadAllBytes(ConfigPath);
            var json = Decrypt(encrypted);
            return JsonSerializer.Deserialize<AppConfig>(json, JsonOptions) ?? new AppConfig();
        }
        catch
        {
            return TryLoadLegacyJson();
        }
    }

    public static void Save(AppConfig config)
    {
        Directory.CreateDirectory(ConfigDir);
        var json = JsonSerializer.Serialize(config, JsonOptions);
        var encrypted = Encrypt(json);
        File.WriteAllBytes(ConfigPath, encrypted);
    }

    /// <summary>
    /// 兼容旧版明文 config.json，读取后迁移为加密格式
    /// </summary>
    private static AppConfig TryLoadLegacyJson()
    {
        var legacyPath = Path.Combine(ConfigDir, "config.json");
        if (!File.Exists(legacyPath))
            return new AppConfig();

        try
        {
            var json = File.ReadAllText(legacyPath);
            var config = JsonSerializer.Deserialize<AppConfig>(json, JsonOptions) ?? new AppConfig();
            // 迁移为加密格式并删除旧文件
            Save(config);
            File.Delete(legacyPath);
            return config;
        }
        catch
        {
            return new AppConfig();
        }
    }

    /// <summary>
    /// 从旧版 BaseDirectory/data 目录迁移配置到系统 AppData 目录
    /// </summary>
    private static void MigrateFromOldPath()
    {
        if (File.Exists(ConfigPath)) return;
        var oldDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "data");
        var oldPath = Path.Combine(oldDir, "config.dat");
        if (!File.Exists(oldPath)) return;
        try
        {
            Directory.CreateDirectory(ConfigDir);
            File.Copy(oldPath, ConfigPath);
        }
        catch { /* 迁移失败不影响启动 */ }
    }

    private static string GetDataDirectory()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "CodingPlanTimeRefresh");
    }

    private static byte[] Encrypt(string plainText)
    {
        using var aes = Aes.Create();
        aes.Key = AesKey;
        aes.IV = AesIV;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;

        using var ms = new MemoryStream();
        using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
        {
            var bytes = Encoding.UTF8.GetBytes(plainText);
            cs.Write(bytes, 0, bytes.Length);
        }
        return ms.ToArray();
    }

    private static string Decrypt(byte[] cipherText)
    {
        using var aes = Aes.Create();
        aes.Key = AesKey;
        aes.IV = AesIV;
        aes.Mode = CipherMode.CBC;
        aes.Padding = PaddingMode.PKCS7;

        using var ms = new MemoryStream(cipherText);
        using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
        using var sr = new StreamReader(cs, Encoding.UTF8);
        return sr.ReadToEnd();
    }
}
