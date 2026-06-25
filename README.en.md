English | [中文](README.md)

# Coding Plan Time Refresh

A .NET MAUI desktop utility that periodically calls LLM APIs and displays API usage percentages on the interface. Primarily used to keep the Zhipu BigModel coding plan quota active.

## Preview

| Normal View | Collapsed View |
|:---:|:---:|
| ![Normal View](previews/normal.png) | ![Collapsed View](previews/mini.png) |

| Settings Panel | Trigger Popup |
|:---:|:---:|
| ![Settings Panel](previews/setting.png) | ![Trigger Popup](previews/makeajoke.png) |

## Features

- Scheduled automatic LLM triggering (01:00, 07:00, 13:00, 19:00, checked every 6 seconds)
- Manual LLM trigger
- Streaming display of LLM responses
- Real-time BigModel usage quota display (5H / Weekly / Monthly) — currently supports Zhipu Coding Plan only; other platforms to be added later
- Always-on-top, collapse/expand window
- Encrypted config storage (AES-256-CBC)
- Chinese/English UI switching
- Windows (WinUI 3) and macOS (MacCatalyst) support

## Requirements

- .NET 10.0 SDK
- Windows 10 1809+ or macOS 15.0+

## Build & Run

```bash
# Build (Windows)
dotnet build CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0

# Run (Windows)
dotnet run --project CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0

# Publish (Windows, self-contained)
dotnet publish CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-windows10.0.19041.0 -c Release -r win-x64

# Build (Mac)
dotnet build CodingPlanTimeRefresh/CodingPlanTimeRefresh.csproj -f net10.0-maccatalyst
```

Or use the publish scripts in the project root:

- `publish-win.bat` — Windows self-contained publish with cleanup
- `publish-mac.sh` — macOS publish

## Configuration

On first run, a configuration panel will appear. Fill in:

- **API URL** — OpenAI-compatible chat endpoint (e.g. `https://open.bigmodel.cn/api/paas/v4/chat/completions`)
- **API Key** — Your API key
- **Model** — Model name (default `glm-5.1`)

Configuration is encrypted and stored in `data/config.dat`.

## Project Structure

```
CodingPlanTimeRefresh/
├── App.xaml.cs              # Window lifecycle management
├── MainPage.xaml(cs)        # Main UI and logic
├── LLMService.cs            # LLM calls and usage queries
├── ConfigService.cs         # Encrypted config read/write
├── AppConfig.cs             # Config model
├── LogService.cs            # Logging service
├── Resources/Strings/       # Chinese/English resource files
└── Platforms/               # Platform-specific code
```

## License

[MIT](LICENSE)
