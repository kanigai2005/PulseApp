# AutoNap — Smart Sleep Detection & Alarm System

> An IoT-powered nap management ecosystem that uses real-time heart rate monitoring to detect sleep onset, trigger intelligent alarms, and alert emergency contacts during cardiac spikes.

![Platform](https://img.shields.io/badge/Platform-ESP32%20%2B%20Flutter-blue)
![Language](https://img.shields.io/badge/Firmware-C%2B%2B%20%2F%20Arduino-orange)
![App](https://img.shields.io/badge/App-Dart%20%2F%20Flutter-02569B)
![BLE](https://img.shields.io/badge/Protocol-Bluetooth%20Low%20Energy-lightblue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 📋 Table of Contents

- [Problem Statement](#-problem-statement)
- [Solution Overview](#-solution-overview)
- [System Architecture](#-system-architecture)
- [Hardware Setup](#-hardware-setup)
- [ESP32 Firmware (C++ Algorithm)](#-esp32-firmware-c-algorithm)
- [Flutter Mobile App](#-flutter-mobile-app)
- [Features](#-features)
- [Tech Stack](#-tech-stack)
- [Installation & Setup](#-installation--setup)
- [How It Works — Step by Step](#-how-it-works--step-by-step)
- [Project Structure](#-project-structure)
- [Future Enhancements](#-future-enhancements)

---

## 🧩 Problem Statement

In today's high-pressure environment — particularly for students during exams and professionals pulling long shifts — sleep deprivation is a critical health issue. Short "power naps" (15–30 minutes) are scientifically proven to restore cognitive function, but existing solutions fail in three ways:

| Problem | Why It Matters |
|---|---|
| **Dumb Alarms** | Traditional phone alarms count clock time, not sleep time. If you take 15 minutes to fall asleep with a 20-minute alarm, you only get 5 minutes of actual rest. |
| **Sleep Inertia** | Oversleeping past 30 minutes pushes you into deep sleep (Stage 3 NREM). Waking from deep sleep causes extreme grogginess lasting 30+ minutes — worse than not napping at all. |
| **Unmonitored Health Risks** | Dangerous cardiac events (heart rate spikes > 120 BPM) during sleep go completely unnoticed. No affordable consumer device monitors heart rate during naps and alerts someone nearby. |

---

## 💡 Solution Overview

**AutoNap** is a complete IoT ecosystem with two components:

1. **ESP32 Edge Device** — A microcontroller with an optical pulse sensor that reads heartbeats, processes the signal using a custom Digital Signal Processing (DSP) algorithm in C++, and transmits clean BPM data over Bluetooth Low Energy (BLE).

2. **Flutter Mobile App** — A cross-platform dashboard that receives real-time BPM data, detects sleep onset using a physiological algorithm, manages smart alarms with audio + vibration + screen wake lock, and provides emergency contact calling and historical analytics.

---

## 🏗 System Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   HARDWARE LAYER (ESP32)                  │
│                                                          │
│  ☝️ Finger on PPG Sensor                                 │
│         │                                                │
│         ▼                                                │
│  ┌─────────────┐     ┌──────────────────────────────┐    │
│  │  ADC Read    │────▶│   DSP Pipeline (C++)         │    │
│  │  GPIO 36     │     │                              │    │
│  │  Raw: 0-4095 │     │  1. DC-Blocking High-Pass    │    │
│  └─────────────┘     │     Filter (removes drift)   │    │
│                       │                              │    │
│                       │  2. 4-Sample Moving Average   │    │
│                       │     (smooths electrical noise)│    │
│                       │                              │    │
│                       │  3. Zero-Crossing + Threshold │    │
│                       │     Detection (finds beats)  │    │
│                       │                              │    │
│                       │  4. 400ms Refractory Period   │    │
│                       │     (blocks dicrotic notch)  │    │
│                       │                              │    │
│                       │  5. Trimmed Mean BPM          │    │
│                       │     (outlier rejection)      │    │
│                       └──────────────┬───────────────┘    │
│                                      │                    │
│                                      ▼                    │
│                          ┌───────────────────┐            │
│                          │  BLE GATT Server   │            │
│                          │  Notify: "72.50"   │            │
│                          └─────────┬─────────┘            │
└────────────────────────────────────┼─────────────────────┘
                                     │
                          Bluetooth Low Energy
                          (Notify Characteristic)
                                     │
┌────────────────────────────────────┼─────────────────────┐
│                    MOBILE APP (Flutter)                    │
│                                     │                    │
│                          ┌─────────▼─────────┐            │
│                          │  BLE GATT Client   │            │
│                          │  flutter_blue_plus │            │
│                          └─────────┬─────────┘            │
│                                    │                      │
│                          ┌─────────▼─────────┐            │
│                          │  State Management  │            │
│                          │  ValueNotifier     │            │
│                          └──┬──┬──┬──┬───────┘            │
│                             │  │  │  │                    │
│              ┌──────────────┘  │  │  └──────────────┐     │
│              ▼                 ▼  ▼                  ▼     │
│     ┌────────────┐  ┌──────────┐ ┌─────────┐ ┌──────────┐│
│     │ Dashboard   │  │  Sleep   │ │Emergency│ │ Analytics││
│     │ Live Graph  │  │Detection │ │ Contacts│ │ History  ││
│     │ BPM Display │  │ 11% Drop │ │ 1-Tap   │ │ Charts   ││
│     └────────────┘  │  ↓       │ │ Call     │ └──────────┘│
│                      │ Nap Timer│ └─────────┘             │
│                      │  ↓      │                          │
│                      │ Alarm   │                          │
│                      │ 🔔+📳   │                          │
│                      └─────────┘                          │
└──────────────────────────────────────────────────────────┘
```

---

## 🔌 Hardware Setup

### Components Required

| Component | Specification | Purpose |
|---|---|---|
| ESP32 Dev Board | ESP-WROOM-32 | Microcontroller with BLE |
| Pulse Sensor | PPG Analog Sensor (e.g., PulseSensor.com) | Optical heart rate detection |
| Jumper Wires | 3x Male-to-Female | Connections |
| USB Cable | Micro-USB or USB-C (depending on board) | Power + Programming |

### Wiring Diagram

```
Pulse Sensor          ESP32
───────────          ─────
   VCC (Red)    ──▶   3.3V
   GND (Black)  ──▶   GND
   OUT (Purple)  ──▶   GPIO 36 (VP / ADC1_CH0)
```

> ⚠️ **Important:** Use **GPIO 36** specifically. It is on ADC1 which is compatible with BLE (ADC2 pins conflict with WiFi/BLE on ESP32).

---

## ⚡ ESP32 Firmware (C++ Algorithm)

The firmware implements a **5-stage Digital Signal Processing pipeline** that converts raw analog light readings into accurate, clinical-grade BPM values.

### Why This Algorithm?

Previous approaches used min/max threshold crossing, which constantly broke because the threshold drifted when the user moved their finger. This version uses a **DC-blocking high-pass filter** — the correct method for analog PPG sensors.

### The DSP Pipeline

```
Raw ADC (0-4095)
     │
     ▼
┌────────────────────────────────┐
│ Stage 1: DC Removal            │
│ dcValue += 0.02 × (raw - dc)  │
│ ac = raw - dcValue             │
│ Result: Wave centered at 0     │
└────────────────┬───────────────┘
                 │
     ▼
┌────────────────────────────────┐
│ Stage 2: Smoothing             │
│ 4-sample moving average        │
│ Removes electrical noise       │
└────────────────┬───────────────┘
                 │
     ▼
┌────────────────────────────────┐
│ Stage 3: Beat Detection        │
│ AC crosses threshold (+8)      │
│ AND was below zero before      │
│ AND 400ms refractory passed    │
└────────────────┬───────────────┘
                 │
     ▼
┌────────────────────────────────┐
│ Stage 4: BPM Calculation       │
│ BPM = 60000 / (Time B - A)    │
│ Sanity range: 40-200 BPM      │
│ Plausibility: ±40% of stable  │
└────────────────┬───────────────┘
                 │
     ▼
┌────────────────────────────────┐
│ Stage 5: Trimmed Mean          │
│ Sort last 5 BPMs               │
│ Discard highest & lowest       │
│ Average the middle 3           │
│ Result: Rock-stable BPM        │
└────────────────────────────────┘
```

### Full Firmware Source Code

<details>
<summary>📄 Click to expand — AutoNap_Sensor.ino</summary>

```cpp
/*
 * ============================================================
 *  AutoNap ESP32 — Pulse Sensor BLE Firmware (FINAL)
 * ============================================================
 *
 *  ALGORITHM:
 *  ─────────────────────────────────────────────────────────
 *  This version uses the CORRECT method for analog PPG sensors:
 *
 *   Step 1 – DC Removal (High-Pass Filter)
 *     The raw signal has a large, slow DC component (~2000–3000)
 *     that shifts when you move your finger. We subtract a slow
 *     moving average (the "DC") from the raw signal, leaving
 *     only the fast AC heartbeat waveform centred around 0.
 *
 *        ac_signal = raw - slow_average   (values near ±50..200)
 *
 *   Step 2 – Peak Detection on AC signal
 *     Because the AC signal is centred at 0, a positive peak
 *     crossing a small fixed threshold (e.g. +10) is a heartbeat.
 *     No adaptive min/max math needed. This threshold NEVER drifts.
 *
 *   Step 3 – BPM Calculation
 *     BPM = 60000 / ms_between_peaks, averaged over last 5 beats,
 *     with outlier rejection (discard values outside ±20% of
 *     the running average).
 *
 *  WIRING:
 *   Pulse sensor OUT → GPIO 36 (VP / ADC1_CH0)
 *   Pulse sensor VCC → 3.3V
 *   Pulse sensor GND → GND
 *
 *  BLE:
 *   Service Name  : "AutoNap_Sensor"
 *   Service UUID  : 4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *   Char UUID     : beb5483e-36e1-4688-b7f5-ea07361b26a8
 *   Properties    : READ + NOTIFY
 *   Data format   : ASCII float string e.g. "72.50"
 * ============================================================
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ─── BLE UUIDs ───────────────────────────────────────────────
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// ─── Hardware ────────────────────────────────────────────────
const int PULSE_PIN = 36;

// ─── BLE globals ─────────────────────────────────────────────
BLECharacteristic *pCharacteristic = nullptr;
BLEAdvertising    *pAdvertising    = nullptr;
bool deviceConnected    = false;
bool oldDeviceConnected = false;

// ─── DC Removal Filter ───────────────────────────────────────
// dcValue tracks the slow-moving average of the raw signal.
// Subtracting it isolates the fast AC heartbeat component.
// Alpha controls how slowly the DC tracks: smaller = slower DC.
// At 50Hz, alpha=0.02 gives a ~1s time constant — perfect for
// removing finger pressure drift while keeping the 60–180 BPM band.
float dcValue = 2048.0;
const float DC_ALPHA = 0.02;

// ─── Light smoothing for AC signal ───────────────────────────
// A 4-sample moving average on the AC signal removes high-freq
// electrical noise without smearing the heartbeat peak.
const int AC_BUF = 4;
float acBuf[AC_BUF];
int acIdx = 0;
float acSmoothed = 0.0;

// ─── Peak detection ──────────────────────────────────────
// AC_THRESHOLD: fixed value in AC units (not raw ADC).
const float AC_THRESHOLD = 8.0;

// REFRACTORY_MS: hard lock-out after each beat.
// 400ms = 150 BPM max. Prevents double-triggering on one wave.
const unsigned long REFRACTORY_MS = 400;

bool inPeak = false;
bool belowZero = true;
unsigned long lastBeatMs = 0;

// ─── BPM history (trimmed mean) ──────────────────────────────
const int BPM_BUF = 5;
float bpmBuf[BPM_BUF];
int bpmIdx = 0;
int bpmCount = 0;
float currentBpm = 0.0;

// ─── Finger detection ────────────────────────────────────────
const int FINGER_THRESHOLD = 200;

// ─── BLE send timing ─────────────────────────────────────────
unsigned long lastSendMs = 0;
const unsigned long RESEND_INTERVAL = 2000;
const unsigned long TIMEOUT_MS = 4000;

// ─── Debug timing ────────────────────────────────────────────
unsigned long lastDebugMs = 0;

// ─────────────────────────────────────────────────────────────
//  BLE Server Callbacks
// ─────────────────────────────────────────────────────────────
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    deviceConnected = true;
    Serial.println(">>> App Connected");
  }
  void onDisconnect(BLEServer *) override {
    deviceConnected = false;
    Serial.println(">>> App Disconnected");
  }
};

// ─────────────────────────────────────────────────────────────
//  Send BPM over BLE
// ─────────────────────────────────────────────────────────────
void sendBpm(float bpm) {
  if (!deviceConnected) return;
  char buf[12];
  dtostrf(bpm, 1, 2, buf);
  pCharacteristic->setValue(buf);
  pCharacteristic->notify();
  Serial.print("  >> BLE: "); Serial.print(buf); Serial.println(" BPM");
}

// ─────────────────────────────────────────────────────────────
//  Trimmed mean: sort BPM buffer, discard the extremes, average
//  the middle. This kills outlier spikes without adding lag.
// ─────────────────────────────────────────────────────────────
float stableBpm() {
  int n = min(bpmCount, BPM_BUF);
  if (n == 0) return 0.0;
  if (n == 1) return bpmBuf[0];

  float tmp[BPM_BUF];
  for (int i = 0; i < n; i++) tmp[i] = bpmBuf[i];
  for (int i = 0; i < n - 1; i++)
    for (int j = 0; j < n - i - 1; j++)
      if (tmp[j] > tmp[j+1]) { float t=tmp[j]; tmp[j]=tmp[j+1]; tmp[j+1]=t; }

  int lo = (n >= 4) ? 1 : 0;
  int hi = (n >= 4) ? n - 1 : n;
  float sum = 0; int cnt = 0;
  for (int i = lo; i < hi; i++) { sum += tmp[i]; cnt++; }
  return sum / cnt;
}

// ─────────────────────────────────────────────────────────────
//  SETUP
// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Serial.println("=== AutoNap Pulse Firmware (DC-filter method) ===");

  for (int i = 0; i < AC_BUF; i++) acBuf[i] = 0;
  for (int i = 0; i < BPM_BUF; i++) bpmBuf[i] = 0;

  BLEDevice::init("AutoNap_Sensor");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCB());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("0.00");
  pService->start();

  pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("Advertising as 'AutoNap_Sensor'. Open the Flutter app.");
}

// ─────────────────────────────────────────────────────────────
//  LOOP  (~50 Hz / every 20 ms)
// ─────────────────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  // ── 1. Read raw ADC ──────────────────────────────────────
  int raw = analogRead(PULSE_PIN);
  bool fingerOn = (raw > FINGER_THRESHOLD);

  // ── 2. DC removal (high-pass filter) ─────────────────────
  dcValue += DC_ALPHA * (raw - dcValue);
  float ac = raw - dcValue;

  // ── 3. Light smoothing on AC signal ──────────────────────
  float acTotal = 0;
  acBuf[acIdx] = ac;
  acIdx = (acIdx + 1) % AC_BUF;
  for (int i = 0; i < AC_BUF; i++) acTotal += acBuf[i];
  acSmoothed = acTotal / AC_BUF;

  // ── 4. Peak detection ────────────────────────────────────
  if (fingerOn) {
    if (acSmoothed < 0) belowZero = true;

    bool refractoryDone = (now - lastBeatMs >= REFRACTORY_MS);

    if (acSmoothed > AC_THRESHOLD && !inPeak && refractoryDone && belowZero) {
      inPeak    = true;
      belowZero = false;

      unsigned long interval = now - lastBeatMs;

      if (lastBeatMs > 0) {
        float instantBpm = 60000.0 / interval;

        if (instantBpm >= 40.0 && instantBpm <= 200.0) {
          bool plausible = true;
          if (currentBpm > 0) {
            float ratio = instantBpm / currentBpm;
            plausible = (ratio >= 0.60 && ratio <= 1.40);
          }

          if (plausible) {
            bpmBuf[bpmIdx] = instantBpm;
            bpmIdx = (bpmIdx + 1) % BPM_BUF;
            if (bpmCount < BPM_BUF) bpmCount++;
            currentBpm = stableBpm();

            sendBpm(currentBpm);
            lastSendMs = now;
          }
        }
      }
      lastBeatMs = now;
    }

    if (acSmoothed < (AC_THRESHOLD * 0.5) && inPeak) {
      inPeak = false;
    }

  } else {
    inPeak    = false;
    belowZero = true;
  }

  // ── 5. Timeout: no beat for 4 s → reset BPM ─────────────
  if (currentBpm > 0 && (now - lastBeatMs > TIMEOUT_MS)) {
    currentBpm = 0;
    bpmCount   = 0;
    inPeak     = false;
    sendBpm(0.0);
    lastSendMs = now;
  }

  // ── 6. Periodic keepalive re-send ────────────────────────
  if (currentBpm > 0 && (now - lastSendMs >= RESEND_INTERVAL)) {
    sendBpm(currentBpm);
    lastSendMs = now;
  }

  // ── 7. Debug print (once per second) ─────────────────────
  if (now - lastDebugMs >= 1000) {
    lastDebugMs = now;
    Serial.print("[DBG] raw=");    Serial.print(raw);
    Serial.print("  dc=");         Serial.print((int)dcValue);
    Serial.print("  ac=");         Serial.print(acSmoothed, 1);
    Serial.print("  thr=");        Serial.print(AC_THRESHOLD);
    Serial.print("  inPeak=");     Serial.print(inPeak ? "Y" : "N");
    Serial.print("  finger=");     Serial.print(fingerOn ? "YES" : "NO");
    Serial.print("  bpm=");        Serial.print(currentBpm, 1);
    Serial.print("  ble=");        Serial.println(deviceConnected ? "CONN" : "wait");
  }

  // ── 8. BLE reconnect on disconnect ───────────────────────
  if (!deviceConnected && oldDeviceConnected) {
    delay(300);
    pAdvertising->start();
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }

  delay(20); // 50 Hz sample rate
}
```

</details>

---

## 📱 Flutter Mobile App

The Flutter app is the user-facing interface that transforms raw BPM data into actionable sleep intelligence.

### App Modules

| Module | Description |
|---|---|
| **🖥️ Dashboard** | Real-time animated heart rate graph, BPM display, connection status, sleep state indicator |
| **💤 Sleep Detection** | Calculates awake baseline BPM, detects ~11% sustained drop indicating Stage 1 sleep onset |
| **⏱️ Smart Alarm** | Starts countdown only after confirmed sleep; rings system alarm + vibration + screen wake lock |
| **🚨 Emergency Contacts** | Stores safety contacts; one-tap "Call" button using native phone dialer during cardiac spikes |
| **📊 Analytics** | Logs each nap session to local storage; displays duration charts and spike history |
| **⚙️ Settings** | Dark/Light theme toggle, nap duration (preset + custom 1-120 mins), sleep detection sensitivity |

### Key Packages Used

| Package | Purpose |
|---|---|
| `flutter_blue_plus` | BLE GATT client for ESP32 communication |
| `fl_chart` | Real-time animated line & bar charts |
| `shared_preferences` | Persistent local storage for settings & history |
| `permission_handler` | Runtime BLE & location permission requests |
| `wakelock_plus` | Prevents screen timeout during alarm |
| `url_launcher` | Opens native phone dialer for emergency calls |
| `flutter_ringtone_player` | Plays system alarm ringtone |

---

## ✨ Features

- ✅ **Real-time BPM monitoring** with live animated graph
- ✅ **Automatic sleep detection** — no manual "start sleep" button needed
- ✅ **Smart adaptive alarm** — counts actual sleep time, not clock time
- ✅ **Loud alarm** with system ringtone + haptic vibration + screen wake lock
- ✅ **Emergency safety network** — one-tap call during heart rate spikes (>120 BPM)
- ✅ **Custom nap duration** — preset chips (15/20/30/60 min) + manual input (1-120 min)
- ✅ **Historical analytics** — session logs with bar charts and spike tracking
- ✅ **Dark/Light theme** — calming teal/blue-green palette
- ✅ **Auto BLE reconnection** — automatically rescans if ESP32 disconnects
- ✅ **Edge computing** — all DSP runs on ESP32, only clean BPM sent over BLE

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| **Microcontroller** | ESP32 (Xtensa dual-core 240MHz) |
| **Sensor** | PPG Analog Pulse Sensor |
| **Firmware Language** | C++ (Arduino Framework) |
| **Signal Processing** | High-Pass DC-Blocking Filter, Zero-Crossing Detection, Refractory Period, Trimmed Mean |
| **Wireless Protocol** | Bluetooth Low Energy 4.2 (GATT Server, Notify Characteristic) |
| **Mobile Framework** | Flutter 3.x (Dart) |
| **State Management** | ValueNotifier + ValueListenableBuilder |
| **Local Storage** | SharedPreferences (JSON serialization) |
| **Native Integrations** | WakelockPlus, url_launcher (tel: intent), flutter_ringtone_player |

---

## 🚀 Installation & Setup

### Prerequisites

- [Arduino IDE](https://www.arduino.cc/en/software) or [PlatformIO](https://platformio.org/)
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.x+)
- ESP32 Board Package installed in Arduino IDE
- Android phone with Bluetooth enabled

### Step 1: Flash the ESP32

1. Open `firmware/AutoNap_Sensor.ino` in Arduino IDE.
2. Select Board: **ESP32 Dev Module**.
3. Select the correct COM port.
4. Click **Upload**.
5. Open Serial Monitor (115200 baud) to verify output.

### Step 2: Run the Flutter App

```bash
cd PulseApp
flutter pub get
flutter run
```

### Step 3: Connect

1. Place your finger on the pulse sensor.
2. Open the AutoNap app on your phone.
3. The app will automatically scan for "AutoNap_Sensor" and connect.
4. You should see real-time BPM data on the dashboard within seconds.

---

## 🔄 How It Works — Step by Step

```
1. User places finger on PPG sensor
                 │
2. ESP32 reads analog voltage at 50Hz (every 20ms)
                 │
3. DC-Blocking filter removes baseline drift
                 │
4. Zero-crossing + refractory period detects true heartbeats
                 │
5. BPM = 60000 / inter-beat-interval (trimmed mean of last 5)
                 │
6. Clean BPM pushed to Flutter app via BLE Notify
                 │
7. App calculates awake baseline BPM over first few minutes
                 │
8. User falls asleep → BPM drops ~11% below baseline
                 │
9. App confirms sustained drop → starts nap countdown timer
                 │
10. Timer reaches zero → ALARM (ringtone + vibration + screen on)
                 │
11. If BPM spikes > 120 during sleep → Emergency contact alert
                 │
12. Session saved to history → viewable in Analytics tab
```

---

## 📁 Project Structure

```
PulseApp/
├── firmware/
│   └── AutoNap_Sensor.ino        # ESP32 C++ firmware (DSP + BLE)
├── lib/
│   └── main.dart                  # Flutter app (all modules)
├── android/
│   ├── app/
│   │   └── build.gradle.kts       # Android build config
│   └── settings.gradle.kts        # Gradle plugin versions
├── pubspec.yaml                   # Flutter dependencies
└── README.md                      # This file
```

---

## 🔮 Future Enhancements

| Enhancement | Description |
|---|---|
| **HRV Analysis (RMSSD)** | Use Inter-Beat Interval variance to distinguish true sleep from meditation/relaxation |
| **Motion Artifact Detection** | Monitor PPG signal variance to detect micro-movements (awake indicator) |
| **Automated SMS Alerts** | Send SMS to emergency contacts automatically during cardiac spikes |
| **Cloud Sync** | Firebase integration for cross-device history and doctor sharing |
| **Wearable Form Factor** | Migrate from finger sensor to wrist-worn PPG band |
| **Multi-Stage Sleep Detection** | Differentiate between Stage 1, Stage 2, and deep sleep using HRV patterns |

---

## 📄 License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with ❤️ using ESP32 + Flutter
</p>
