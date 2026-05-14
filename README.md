# Chrono Lite

A Flutter velocity-chronograph client that connects over Bluetooth Low Energy to compatible Doppler-radar chronograph devices. Reads BLE advertising packets, decodes velocity, and shows real-time shot data with session stats and history.

![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart)
![License](https://img.shields.io/badge/license-MIT-green)

Compatible hardware (tested): FX Pocket V2 and FX Pocket D1 (MkIII).

---

## Quick Start

```bash
git clone <repo-url>
cd chrono_lite
flutter pub get
flutter run
```

No physical device? Enable demo mode:

```dart
// lib/config/app_config.dart
static const bool kDemoMode = true;
```

---

## What's not in this repo

This is a template — you have to add a few things before publishing your own build:

- **Bundle ID**: ships as `com.example.chronolite`. Change in `android/app/build.gradle`, `ios/Runner.xcodeproj/project.pbxproj`, and the Kotlin package path under `android/app/src/main/kotlin/`.
- **Signing keys**: no Android keystore, no Apple Team ID. Generate your own and wire them up before release.
- **App icon**: placeholder. Replace files under `icon/`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/`, and the Android `mipmap-*` folders, or use `flutter_launcher_icons`.
- **Fonts**: only OFL-licensed fonts (Saira Condensed) and Apache-2.0 (JetBrains Mono). No commercial fonts.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Demo Mode](#demo-mode)
- [BLE Protocol](#ble-protocol)
- [State Management](#state-management)
- [Key Algorithms](#key-algorithms)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Code Style](#code-style)
- [License](#license)

---

## Features

| Feature | Description |
|---------|-------------|
| **Real-time Velocity** | Large display showing FPS or m/s (tap to toggle) |
| **Energy Calculation** | Automatic ft-lbs or Joules from velocity + bullet weight |
| **Session Statistics** | AVG, ES (extreme spread), SD (standard deviation) |
| **Shot History** | Scrollable list with timestamps, auto-saved |
| **Device Support** | FX Pocket V2 and D1 chronographs |
| **Battery & Signal** | Real-time device status in header |
| **Offline Persistence** | Sessions saved locally, viewable in History |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  HomePage   │  │HistoryPage │  │  SessionDetailPage  │  │
│  └──────┬──────┘  └─────────────┘  └─────────────────────┘  │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Widgets (velocity_display, etc.)        │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     State Layer (Provider)                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    AppState                          │    │
│  │  • Device connection state                           │    │
│  │  • Current session & shots                           │    │
│  │  • User preferences (units, weight)                  │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Service Layer                            │
│  ┌──────────────┐  ┌────────────────┐  ┌────────────────┐   │
│  │BroadcastParser│  │SessionStorage │  │EnergyCalculator│   │
│  │ (BLE parsing) │  │ (JSON persist) │  │  (physics)     │   │
│  └──────────────┘  └────────────────┘  └────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Data Layer                               │
│  ┌────────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐  │
│  │BroadcastData│  │  Shot   │  │ Session │  │ChronographDevice│
│  └────────────┘  └─────────┘  └─────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
BLE Advertisement (from device)
         │
         ▼
┌─────────────────────────┐
│ flutter_blue_plus scan  │  Continuous BLE scanning
└───────────┬─────────────┘
            │ manufacturerData[0x0059]
            ▼
┌─────────────────────────┐
│  BroadcastParser.parse  │  Extract velocity, counter, battery
└───────────┬─────────────┘
            │ BroadcastData
            ▼
┌─────────────────────────┐
│ AppState.processBroadcast│  Detect new shot via counter change
└───────────┬─────────────┘
            │ if counter changed
            ▼
┌─────────────────────────┐
│   AppState._recordShot  │  Add to session, auto-save
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   SessionStorage.save   │  Persist to SharedPreferences
└─────────────────────────┘
```

---

## Project Structure

```
lib/
├── main.dart                     # App entry, theme, wakelock
├── config/
│   └── app_config.dart           # Compile-time flags (demo mode)
├── models/
│   ├── broadcast_data.dart       # Parsed BLE packet structure
│   ├── chronograph_device.dart   # Device model with loss detection
│   ├── session.dart              # Session with shots + statistics
│   └── shot.dart                 # Individual velocity measurement
├── pages/
│   ├── home_page.dart            # Main UI + BLE scanning
│   ├── session_detail_page.dart  # View/export saved session
│   └── session_history_page.dart # List of all sessions
├── providers/
│   └── app_state.dart            # Central state (ChangeNotifier)
├── services/
│   ├── broadcast_parser.dart     # BLE packet parsing
│   ├── energy_calculator.dart    # ft-lbs / Joules formulas
│   └── session_storage.dart      # JSON persistence
├── theme/
│   └── app_theme.dart            # Dark theme, colors, typography
├── utils/
│   ├── ble_utils.dart            # Signal strength helpers
│   ├── demo_velocity_generator.dart  # Demo mode shot generator
│   ├── responsive.dart           # Screen size utilities
│   └── unit_converters.dart      # FPS↔m/s, grains↔grams
└── widgets/
    ├── device_status_bar.dart    # Connection status header
    ├── energy_display.dart       # Energy value + weight icon
    ├── shot_list.dart            # Scrollable shot history
    ├── statistics_row.dart       # AVG, ES, SD display
    ├── velocity_display.dart     # Large velocity number
    ├── weight_input.dart         # Bullet weight dialog
    └── common/
        ├── number_input_dialog.dart
        └── stepper_button.dart
```

---

## Getting Started

### Prerequisites

| Requirement | Version |
|-------------|---------|
| Flutter SDK | 3.0.0+ |
| Dart SDK | 3.0.0+ |
| Android Studio | Latest (for Android) |
| Xcode | Latest (for iOS) |

### Installation

```bash
flutter pub get
flutter doctor
flutter run
```

### Building

```bash
# Android APK (release)
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS (requires Mac + Xcode)
cd ios && pod install && cd ..
flutter build ios --release
```

### Platform Permissions

**Android** (`android/app/src/main/AndroidManifest.xml`):
- `BLUETOOTH`, `BLUETOOTH_ADMIN` — Legacy Bluetooth
- `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` — Android 12+
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` — BLE scanning

**iOS** (`ios/Runner/Info.plist`):
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `NSLocationWhenInUseUsageDescription`

---

## Demo Mode

For development without a physical device, enable demo mode:

```dart
// lib/config/app_config.dart
class AppConfig {
  static const bool kDemoMode = true;

  // Velocity configuration (airgun defaults)
  static const int demoMinVelocityFps = 800;
  static const int demoMaxVelocityFps = 950;
  static const double demoStdDevPercent = 1.5;
}
```

When enabled, an amber "Demo" button appears in the bottom action bar. Each tap generates a shot with realistic velocity (800–950 FPS) using a Box-Muller transform for normal distribution (~1.5% SD). Sessions work identically to real device input.

Set `kDemoMode = false` before production builds.

---

## BLE Protocol

> Reverse-engineered from public BLE advertising broadcasts. Not officially documented by the device manufacturer. Reproduced here for interoperability.

Compatible devices broadcast velocity data continuously via BLE advertising packets — no GATT connection required. The app scans and parses manufacturer data.

### Packet Structure

```
Company ID: 0x0059 (Nordic Semiconductor)

Offset  Size  Field                    Encoding
──────────────────────────────────────────────────
0       1     Device type              0x30 = Pocket Chrono
1       1     Data length              —
2-3     2     Major firmware version   Little-endian
4-5     2     Minor firmware version   Little-endian (low byte)
6-9     4     UUID                     V2: 57 65 FD CE
                                       D1: 57 65 FD CD
10      1     Battery percentage       0–100
11-12   2     Shot counter             Big-endian (0–65535)
13-14   2     Velocity (FPS)           Big-endian
15      1     Signal strength          Optional
```

### Shot Detection

New shots are detected by monitoring the shot counter:

```dart
// lib/providers/app_state.dart
final counterDelta = newCounter - _lastShotCounter;
final isWrap = _lastShotCounter >= 65000 && newCounter < 1000;
final isValidShot = counterDelta > 0 || isWrap;

if (isValidShot && velocityFps > 0) {
  _recordShot(velocityFps, previousCounter);
}
```

### Device Loss Detection

Device is considered lost after 3 seconds without broadcasts:

```dart
// lib/models/chronograph_device.dart
bool get isLost => DateTime.now().difference(lastSeen).inSeconds > 3;
```

---

## State Management

The app uses **Provider** with a single `AppState` class (`ChangeNotifier`).

### Key State Properties

```dart
// Device
ChronographDevice? connectedDevice
bool isScanning
bool isConnected
bool isDeviceLost

// Session
Session? currentSession
List<Session> savedSessions
Shot? lastShot
int shotCount

// Statistics
double averageFps
int extremeSpreadFps
double standardDeviationFps

// Preferences (persisted)
double bulletWeightGrains
bool useFps        // false = m/s
bool useFtLbs      // false = Joules
```

### Key Methods

| Method | Description |
|--------|-------------|
| `initialize()` | Load preferences and sessions from storage |
| `processBroadcast()` | Handle BLE advertisement, detect shots |
| `recordShot(fps)` | Manual shot recording (demo mode) |
| `startNewSession()` | Create new session, save previous |
| `setBulletWeight(g)` | Update weight, recalculate energy |
| `toggleVelocityUnit()` | FPS ↔ m/s |
| `toggleEnergyUnit()` | ft-lbs ↔ Joules |

---

## Key Algorithms

### Energy Calculations

```dart
// Foot-pounds (imperial)
double ftLbs = (grains * fps * fps) / 450240.0;

// Joules (metric)
double grams = grains * 0.0648;
double ms = fps * 0.3048;
double joules = (grams * ms * ms) / 2000.0;
```

### Statistics

```dart
// Average
double avg = shots.fold(0, (sum, s) => sum + s.velocityFps) / shots.length;

// Extreme Spread (ES)
int es = maxFps - minFps;

// Standard Deviation (SD) — population formula
double sumSquaredDiff = shots.fold(0.0, (sum, s) => sum + pow(s.velocityFps - avg, 2));
double sd = sqrt(sumSquaredDiff / shots.length);
```

### Demo Velocity Generation

Uses Box-Muller transform for normal distribution:

```dart
// lib/utils/demo_velocity_generator.dart
final u1 = random.nextDouble();
final u2 = random.nextDouble();
final z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
final velocity = meanVelocity + (z * stdDev);
```

---

## Testing

```bash
flutter test
flutter test test/broadcast_parser_test.dart
flutter test --coverage
```

### Test Files

| File | Coverage |
|------|----------|
| `broadcast_parser_test.dart` | BLE packet parsing |
| `device_loss_test.dart` | Connection loss detection |
| `session_storage_test.dart` | Persistence |
| `shot_recording_test.dart` | Shot detection logic |

### Manual Testing Checklist

- [ ] App launches without errors
- [ ] BLE scan finds compatible devices (or demo mode works)
- [ ] Device status bar shows battery/signal
- [ ] "New Session" creates a session
- [ ] Shots record and display correctly
- [ ] Statistics (AVG, ES, SD) calculate correctly
- [ ] Unit toggles work (tap velocity/energy)
- [ ] Weight input saves correctly
- [ ] Sessions persist in History
- [ ] Session details show all shots
- [ ] Sessions can be deleted

---

## Troubleshooting

### BLE not finding devices

1. Check Bluetooth is ON on the phone
2. Check permissions are granted (Settings → Apps → Chrono Lite)
3. **Android 12+**: Ensure both `BLUETOOTH_SCAN` and location permissions granted
4. **iOS**: Ensure Bluetooth permission is "Always" or "While Using"

### Shots not recording

1. Verify device is broadcasting (check with nRF Connect app)
2. Check shot counter is incrementing in broadcasts
3. Ensure velocity > 0 in broadcast packet
4. Session must be active (tap "New Session")

### Build errors

```bash
flutter clean
flutter pub get
flutter run
```

### iOS build issues

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter build ios
```

---

## Code Style

### Naming Conventions

- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables/methods: `camelCase`
- Constants: `camelCase` with descriptive names
- Private members: `_prefixedWithUnderscore`

### Theme Usage

Always use theme colors from `AppColors`:

```dart
import '../theme/app_theme.dart';

Container(
  color: AppColors.surface,
  child: Text(
    'Hello',
    style: TextStyle(color: AppColors.textPrimary),
  ),
)
```

---

## Dependencies

See `pubspec.yaml` for the full, current list.

---

## License

MIT — see [LICENSE](LICENSE).
