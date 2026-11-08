# Neurovault

<p align="center">
  <img src="assets/icons/app_icon.png" alt="Neurovault App Icon" width="128" height="128" />
</p>

<p align="center">
  <strong>An advanced, dopamine-aligned life operating system designed for ADHD and neurodivergent minds.</strong><br>
  Built with Flutter, Kotlin, and modern Android architecture to provide friction-free task execution, hierarchical vision planning, and adaptive daily momentum.
</p>

<p align="center">
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
  <a href="#tech-stack"><img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop-green.svg" alt="Platforms"></a>
  <a href="#tech-stack"><img src="https://img.shields.io/badge/Gradle-8.14-02303A.svg?logo=gradle" alt="Gradle"></a>
  <a href="#tech-stack"><img src="https://img.shields.io/badge/Kotlin-2.2.20-7F52FF.svg?logo=kotlin" alt="Kotlin"></a>
  <a href="#build--test"><img src="https://img.shields.io/badge/Tests-70%20passing-brightgreen.svg" alt="Tests"></a>
</p>

---

## Overview

Traditional productivity apps often fail neurodivergent users due to rigid schedules, punitive streaks, and cognitive overload. **Neurovault** reimagines productivity through executive-function-friendly interfaces, non-punitive carryovers, fractional habit scoring, and recursive vision mapping.

---

## Core Features

- **Hierarchical Vision & Milestone Trees:** Break ambitious life goals into manageable, self-calculating sub-milestones with recursive progress roll-ups.
- **Adaptive Daily Focus Engine:** A unified daily dashboard with three fluid views (Category, Routine, Vision) that adapts to your fluctuating energy levels.
- **Net Daily Scoring & Fractional Progression:** Celebrate partial wins with proportional progress (+fraction) and net scoring (+1.0 for wins, non-catastrophic tracking for lapses).
- **Carryover & Resilient Schedules:** Uncompleted tasks carry forward seamlessly across calendar days without breaking streaks or creating guilt.
- **Visual Analytics & 7-Day Rolling Trends:** Powered by `AggregationEngine` and interactive charts (`fl_chart`) to visualize long-term consistency and habit momentum.
- **Local-First Offline Storage & Conflict-Free Sync:** Blazing-fast local persistence via Hive NoSQL storage with multi-account isolation and CRDT-inspired cross-device cloud sync.
- **Privacy-First Architecture:** Operates completely standalone offline with zero mandatory remote tracking or account dependencies.

---

## Screenshots & Demo

<p align="center">
  <img src="assets/icons/1" alt="App Dashboard" width="280"/>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/icons/2" alt="App Dashboard" width="280"/>
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/icons/3" alt="App Dashboard" width="280"/>
</p>

---

## Tech Stack & Architecture

- **UI & Framework:** Flutter 3.x (Dart 3.x) with Material Design 3 and responsive layouts.
- **Android Native Platform:**
  - **Gradle:** 8.14 (with Gradle Wrapper)
  - **Android Gradle Plugin (AGP):** 8.11.1
  - **Kotlin:** 2.2.20
  - **Min SDK:** 21 (Android 5.0 Lollipop)
  - **Target/Compile SDK:** 34 (Android 14)
  - **Java Target:** JDK 17
- **State Management & Architecture:**
  - Riverpod (`flutter_riverpod`) for reactive, unidirectional state flow and dependency injection.
  - Clean Architecture separation: `models/`, `services/`, `providers/`, and `ui/`.
- **Data & Persistence:**
  - Hive & `hive_flutter` for lightweight, encrypted local NoSQL storage.
  - In-memory test fixtures and mock storage for deterministic unit testing.
- **Visualizations:** `fl_chart` for custom 7-day rolling curves and momentum graphs.

---

## Getting Started

### Prerequisites

Ensure you have the following installed on your host machine:

- **Android Studio:** Ladybug (2024.2+) or Koala (2024.1+)
- **JDK:** OpenJDK 17 or Oracle JDK 17
- **Android SDK:** API Level 34
- **Flutter SDK:** 3.24.x or later

### Local Configuration

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/neurovault.git
   cd neurovault
   ```

2. **Configure `local.properties`:**
   Copy the provided template to `android/local.properties`:
   ```bash
   cp android/local.properties.example android/local.properties
   ```
   Open `android/local.properties` and verify your local SDK directories:
   ```properties
   sdk.dir=C\:\\Users\\<username>\\AppData\\Local\\Android\\sdk # or /Users/<username>/Library/Android/sdk on macOS
   flutter.sdk=C\:\\flutter # or /path/to/flutter on macOS/Linux
   ```

3. **Install Dependencies:**
   ```bash
   flutter pub get
   ```

---

## Build & Test

### Run Unit & Widget Tests
Execute the comprehensive test suite (70 automated unit and widget tests):
```bash
flutter test
```

### Build Android APK via Gradle
You can compile the Android application directly using the Gradle wrapper without requiring a global Gradle installation:

```bash
# Navigate to the Android directory
cd android

# Build debug APK
./gradlew assembleDebug

# Run unit tests via Gradle
./gradlew test
```
The compiled debug APK will be located at:
`build/app/outputs/flutter-apk/app-debug.apk`

### Build via Flutter CLI
```bash
# Debug build
flutter run -d android

# Release APK build
flutter build apk --release
```

---

## Release Signing & Security

For security, production release keystores and sensitive credentials are strictly untracked in `.gitignore`.

To sign release builds locally or in your CI/CD pipeline:

1. Copy the keystore template:
   ```bash
   cp android/keystore.properties.example android/keystore.properties
   ```
2. Populate `android/keystore.properties` with your signing configuration:
   ```properties
   storeFile=path/to/release-keystore.jks
   storePassword=your_keystore_password
   keyAlias=your_key_alias
   keyPassword=your_key_password
   ```
3. When `android/keystore.properties` is absent, Gradle automatically falls back to debug keys so contributors can build and test release flavors without failing.

### Environment & Build Configurations

You can inject cloud endpoints and API keys dynamically via Gradle properties or compile-time Dart defines without hardcoding secrets:

```bash
# Via Gradle Property
./gradlew assembleRelease -PAPI_BASE_URL="https://api.yourdomain.com"

# Via Flutter compile-time defines
flutter build apk --release \
  --dart-define=CLOUD_API_ENDPOINT="https://api.yourdomain.com" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="your-client-id.apps.googleusercontent.com"
```

---

## Project Structure

```text
├── android/                  # Android native project and Gradle configuration
│   ├── app/                  # Application module (Manifest, Kotlin sources, Proguard)
│   ├── gradle/               # Gradle wrapper and version catalogs (libs.versions.toml)
│   ├── gradlew / gradlew.bat # Gradle wrapper CLI executables
│   ├── build.gradle.kts      # Root build configuration
│   └── settings.gradle.kts   # Plugin management and module inclusion
├── assets/                   # App icons and graphical assets
├── lib/                      # Core application source code
│   ├── models/               # Domain models (AppUser, NeuroItem)
│   ├── providers/            # Riverpod state providers
│   ├── services/             # Aggregation engine, auth, and cloud sync services
│   └── ui/                   # Screens, widgets, and themes
├── test/                     # Comprehensive unit & widget test suite (70 tests)
├── .gitignore                # Industry-standard Android and Flutter ignore rules
├── LICENSE                   # Open-source MIT License
└── pubspec.yaml              # Flutter dependencies and metadata
```

---

## License

This project licensed under the [MIT License](LICENSE).
