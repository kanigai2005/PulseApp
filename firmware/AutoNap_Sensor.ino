/*
 * ============================================================
 *  AutoNap ESP32 — ADVANCED Pulse Sensor BLE Firmware (BPM)
 * ============================================================
 *  Builds directly on your working minimal raw-signal test, 
 *  but adds robust, complex stabilization for the BPM:
 *
 *    1. Increased analog smoothing (NUM_READINGS = 8) to
 *       prevent tiny noise from causing "double beats".
 *    2. Outlier Rejection: A Median-Average Filter for BPM.
 *       It stores the last 8 beats, discards the highest 
 *       and lowest anomalies (like a random spike), and
 *       averages the stable middle values.
 *    3. Keeps your working, simple min/max window logic.
 *
 *  BLE Service Name : "AutoNap_Sensor"
 *  Service UUID     : 4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *  Characteristic   : beb5483e-36e1-4688-b7f5-ea07361b26a8
 * ============================================================
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

const int PULSE_PIN = 36;

BLECharacteristic *pCharacteristic = nullptr;
BLEAdvertising    *pAdvertising    = nullptr;
bool deviceConnected    = false;
bool oldDeviceConnected = false;

// ─── Smoothing ───────────────────────────────────────────
const int NUM_READINGS = 8; // Increased from 4 to filter signal noise better
int readings[NUM_READINGS];
int readIndex = 0;
long total = 0;
int smoothed = 0;

// ─── Simple min/max window ───────────────────────────────
const unsigned long WINDOW_MS = 1500;   // rebuild min/max every 1.5s
unsigned long windowStartMs = 0;
int windowMin = 4095;
int windowMax = 0;

int threshold = 2048;

// ─── Beat detection ───────────────────────────────────────
bool beatState = false;
unsigned long lastBeatMs = 0;
float currentBpm = 0.0;

// Buffer increased to 8 to allow for outlier rejection
const int BPM_BUF_SIZE = 8;
float bpmBuffer[BPM_BUF_SIZE];
int bpmBufIndex = 0;
int bpmBufCount = 0;

// ─── Finger detection ──────────────────────────────────────
const int FINGER_ON_THRESHOLD = 200;

// ─── Periodic re-send / timeout ────────────────────────────
unsigned long lastSendMs = 0;
const unsigned long SEND_INTERVAL_MS = 2000;

unsigned long lastDebugMs = 0;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    deviceConnected = true;
    Serial.println(">>> Flutter App Connected!");
  }
  void onDisconnect(BLEServer *pServer) override {
    deviceConnected = false;
    Serial.println(">>> Flutter App Disconnected!");
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Booting advanced stable BPM firmware...");

  for (int i = 0; i < NUM_READINGS; i++) readings[i] = 0;
  for (int i = 0; i < BPM_BUF_SIZE; i++) bpmBuffer[i] = 0;

  BLEDevice::init("AutoNap_Sensor");

  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("0.00");

  pService->start();

  pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising as 'AutoNap_Sensor'. Waiting for phone...");

  windowStartMs = millis();
}

void sendBpm(float bpm) {
  if (!deviceConnected) return;
  char buf[12];
  dtostrf(bpm, 1, 2, buf);
  pCharacteristic->setValue(buf);
  pCharacteristic->notify();
  Serial.print("  >> BLE notify: ");
  Serial.println(buf);
}

// ─── Advanced BPM Outlier Rejection Filter ───────────────
float getStableAverageBpm() {
  if (bpmBufCount == 0) return 0.0;
  
  int count = min(bpmBufCount, BPM_BUF_SIZE);
  float temp[BPM_BUF_SIZE];
  for (int i = 0; i < count; i++) {
    temp[i] = bpmBuffer[i];
  }

  // Bubble sort the array to find the median
  for (int i = 0; i < count - 1; i++) {
    for (int j = 0; j < count - i - 1; j++) {
      if (temp[j] > temp[j + 1]) {
        float t = temp[j];
        temp[j] = temp[j + 1];
        temp[j + 1] = t;
      }
    }
  }

  // If we have enough beats, discard the highest and lowest anomaly
  // and average the stable middle values. This prevents sudden jumps.
  float sum = 0;
  int used = 0;
  int startIdx = (count >= 5) ? 1 : 0;
  int endIdx = (count >= 5) ? count - 1 : count;
  
  for (int i = startIdx; i < endIdx; i++) {
    sum += temp[i];
    used++;
  }
  
  return sum / used;
}

void loop() {
  unsigned long now = millis();

  // ── 1. Read & smooth ──────────────────────────────────
  int raw = analogRead(PULSE_PIN);
  total -= readings[readIndex];
  readings[readIndex] = raw;
  total += raw;
  readIndex = (readIndex + 1) % NUM_READINGS;
  smoothed = total / NUM_READINGS;

  bool fingerDetected = (raw > FINGER_ON_THRESHOLD);

  // ── 2. Track min/max for the current window ───────────
  if (smoothed < windowMin) windowMin = smoothed;
  if (smoothed > windowMax) windowMax = smoothed;

  if (now - windowStartMs >= WINDOW_MS) {
    if (windowMax - windowMin > 15) {
      threshold = (windowMax + windowMin) / 2;
    }
    windowStartMs = now;
    windowMin = smoothed;
    windowMax = smoothed;
  }

  int swing = windowMax - windowMin;

  // ── 3. Beat detection: simple threshold crossing ──────
  if (fingerDetected) {
    if (smoothed > threshold && !beatState) {
      beatState = true;
      unsigned long interval = now - lastBeatMs;

      // debounce >200bpm (300ms) and <40bpm (1500ms limit is implicit by range)
      if (interval > 300 && lastBeatMs > 0) {
        float instantBpm = 60000.0 / interval;
        if (instantBpm >= 40.0 && instantBpm <= 200.0) {
          
          bpmBuffer[bpmBufIndex] = instantBpm;
          bpmBufIndex = (bpmBufIndex + 1) % BPM_BUF_SIZE;
          if (bpmBufCount < BPM_BUF_SIZE) bpmBufCount++;
          
          // Calculate stable BPM using the outlier filter
          currentBpm = getStableAverageBpm();

          Serial.print("Beat! instant=");
          Serial.print(instantBpm, 1);
          Serial.print(" stable_avg=");
          Serial.println(currentBpm, 1);

          sendBpm(currentBpm);
          lastSendMs = now;
        }
      }
      lastBeatMs = now;
    } else if (smoothed < threshold - 10) {
      beatState = false;
    }
  } else {
    beatState = false;
  }

  // ── 4. Timeout & periodic re-send ──────────────────────
  if (currentBpm > 0 && (now - lastBeatMs > 4000)) {
    currentBpm = 0;
    bpmBufCount = 0; // Clear history buffer when finger is off
    sendBpm(0.0);
    lastSendMs = now;
    Serial.println("No heartbeat for 4s, reset to 0");
  } else if (currentBpm > 0 && (now - lastSendMs >= SEND_INTERVAL_MS)) {
    sendBpm(currentBpm);
    lastSendMs = now;
  }

  // ── 5. Debug print once a second ───────────────────────
  if (now - lastDebugMs >= 1000) {
    lastDebugMs = now;
    Serial.print("[DBG] raw="); Serial.print(raw);
    Serial.print(" smooth="); Serial.print(smoothed);
    Serial.print(" thr="); Serial.print(threshold);
    Serial.print(" swing="); Serial.print(swing);
    Serial.print(" finger="); Serial.print(fingerDetected ? "YES" : "NO");
    Serial.print(" bpm="); Serial.print(currentBpm, 1);
    Serial.print(" ble="); Serial.println(deviceConnected ? "CONNECTED" : "waiting");
  }

  // ── 6. BLE reconnection ────────────────────────────────
  if (!deviceConnected && oldDeviceConnected) {
    delay(300);
    pAdvertising->start();
    Serial.println("Restarting advertising...");
    oldDeviceConnected = false;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = true;
  }

  delay(20);  // ~50Hz
}
