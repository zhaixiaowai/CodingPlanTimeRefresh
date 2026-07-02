English | [中文](README.md)

# Coding Plan Time Refresh

A Flutter desktop utility that periodically calls LLM APIs and displays multi-vendor API usage percentages as a resident desktop widget. Primarily used to keep the Zhipu BigModel coding plan quota active. Migrated from the former .NET MAUI edition.

## Preview

| Main View | Settings Panel |
|:---:|:---:|
| ![Main View](previews/normal.png) | ![Settings Panel](previews/setting.png) |

## Features

- Scheduled automatic LLM keep-alive: trigger hours are customizable in Settings (default 01:00, 07:00, 13:00, 19:00, checked every 6 seconds; 3 retries with 5s interval on failure; uncheck all to disable)
- Real-time multi-vendor usage quota display (Zhipu 5H / Weekly / Monthly; Volcengine Ark), resident on desktop
- Always-on-top window
- Encrypted config storage (AES-256-CBC), backward compatible with the former MAUI edition
- Chinese/English UI switching
- Windows and macOS support

## Supported Providers

- **Zhipu BigModel** (bigmodel.cn): queries usage quota via HTTP.
- **Volcengine Ark** (ark.cn-beijing.volces.com): queries usage via Access Key / Secret Access Key.

## Volcengine Ark Usage Prerequisites

Volcengine Ark usage querying uses long-lived Volcengine **Access Key / Secret Access Key** (OpenAPI V4 signing) — no local tooling and no login required:

1. Create an Access Key / Secret Access Key pair in the Volcengine console → Key Management (IAM).
2. In the app's Settings, when you add or edit a config whose API URL contains `ark.cn-beijing.volces.com`, two extra fields — **Access Key** / **Secret Access Key** — appear; fill them in.

If unconfigured or the AK/SK is invalid, the Volcengine Ark usage frame shows the corresponding error (e.g. "Access Key / Secret Access Key not configured", "AK/SK invalid or no permission").

## Requirements

- Flutter stable (with desktop support)
- Windows 10+ or macOS

## Build & Run

Source lives under `codingplan_refresh/`.

```bash
cd codingplan_refresh

# Run (Windows)
flutter run -d windows

# Publish (Windows)
flutter build windows --release

# Publish (macOS)
flutter build macos --release
```

## Configuration

- Main view gear icon → Settings: manage multiple model configs (long-press drag to reorder, add, delete, edit), and pick the daily auto-trigger hours in "Trigger Hours" (0-23, default 1/7/13/19; uncheck all to disable scheduled keep-alive).
- Each config fills in: Name, API URL, API Key, Model (Zhipu: model name like `glm-5.1`; Volcengine: endpoint id like `ep-xxx`). Volcengine configs additionally require Access Key / Secret Access Key (usage query only).
- Provider is auto-detected from the API URL.
- Config is encrypted and backward compatible with the former MAUI edition's `config.dat` (AES-256-CBC, same key/IV, auto-migrated).

## Project Structure

```
codingplan_refresh/
├── lib/
│   ├── main.dart              # Entry: window/single-instance/config/i18n init
│   ├── models/                # AppConfig, UsageInfo
│   ├── services/              # config/log/llm/scheduler/i18n/usage providers
│   ├── platform/              # window control, single instance
│   ├── ui/                    # main page and widgets
│   └── utils/                 # AES, SSE, signing
├── test/                      # unit tests
├── windows/ macos/            # platform projects
└── pubspec.yaml
```

## License

[MIT](LICENSE)
