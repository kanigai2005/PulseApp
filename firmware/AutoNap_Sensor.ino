#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- Bluetooth UUIDs (Must match your Flutter App) ---
#define SERVICE_UUID           "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// --- Hardware Pins ---
const int PulseWire = 36;       // Grey wire on VP (ADC1_CH0)
const int LED_PIN = 2;          // Onboard Blue LED

// --- BLE Globals ---
BLECharacteristic *pCharacteristic = nullptr;
BLEAdvertising *pAdvertising = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// --- Signal Processing Variables ---
const int numReadings = 10;
int readings[numReadings];      // Circular buffer for moving average
int readIndex = 0;
int total = 0;
int average = 0;

// --- Adaptive Heartbeat Detection Variables ---
int peak = 2048;                // Tracks the signal peak (max value)
int valley = 2048;              // Tracks the signal valley (min value)
int threshold = 2150;           // Dynamic midpoint between peak and valley
unsigned long lastBeatTime = 0;
float bpm = 0;
bool beatDetected = false;

// --- LED Blinking state ---
unsigned long lastLedToggle = 0;
bool ledState = false;

// BLE Server Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
      deviceConnected = true;
      Serial.println(">>> App Connected!");
    }
    void onDisconnect(BLEServer* pServer) override {
      deviceConnected = false;
      Serial.println(">>> App Disconnected!");
    }
};

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  
  // Initialize smoothing array
  for (int i = 0; i < numReadings; i++) readings[i] = 0;

  // Initialize BLE Device
  BLEDevice::init("AutoNap_Sensor");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();

  // Start BLE Advertising
  pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // functions that help with iPhone connections issues
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("AutoNap Hardware Ready. Waiting for App connection...");
}

void loop() {
  unsigned long currentMillis = millis();

  // --- Smoothing Filter (Moving Average) ---
  total = total - readings[readIndex];
  readings[readIndex] = analogRead(PulseWire);
  total = total + readings[readIndex];
  readIndex = (readIndex + 1) % numReadings;
  average = total / numReadings;

  // --- Adaptive Threshold Calibration (Runs continuously) ---
  // Every 2 seconds, decay peak and valley slightly to adapt to long-term signal changes
  static unsigned long lastCalibrationTime = 0;
  if (currentMillis - lastCalibrationTime > 2000) {
    threshold = (peak + valley) / 2; // Midpoint threshold
    
    // Decay values toward current average to adapt to positional shifts
    peak = (peak * 3 + average) / 4;
    valley = (valley * 3 + average) / 4;
    
    lastCalibrationTime = currentMillis;
  }

  // Dynamically update peak and valley for current signal bounds
  if (average > peak) {
    peak = average;
  }
  if (average < valley && average > 100) { // filter out zero or disconnected ground noise
    valley = average;
  }

  // Update dynamic threshold
  threshold = (peak + valley) / 2;

  // --- Heartbeat Detection (Crossing the threshold) ---
  if (average > threshold && !beatDetected) {
    // Check if enough time has passed since last beat (Debounce)
    if (currentMillis - lastBeatTime > 300) { 
      beatDetected = true;
      digitalWrite(LED_PIN, HIGH); // Light up LED on heartbeat
      
      bpm = 60000.0 / (currentMillis - lastBeatTime);
      lastBeatTime = currentMillis;
      
      // Filter out unrealistic BPM spikes (45 to 180 BPM)
      if (bpm >= 45.0 && bpm <= 180.0) {
        Serial.print("♥ Heartbeat! BPM: ");
        Serial.print(bpm);
        Serial.print(" | Signal Peak: ");
        Serial.print(peak);
        Serial.print(" Valley: ");
        Serial.print(valley);
        Serial.print(" Threshold: ");
        Serial.println(threshold);
        
        // Notify Flutter App via BLE
        if (deviceConnected) {
          char str[10];
          dtostrf(bpm, 1, 2, str); // Convert float to string
          pCharacteristic->setValue(str);
          pCharacteristic->notify();
        }
      }
    }
  }

  // Reset beat detection when signal falls below threshold (with hysteresis margin)
  if (average < (threshold - 50) && beatDetected) {
    beatDetected = false;
    digitalWrite(LED_PIN, LOW); // Turn off LED
  }

  // --- BLE Connection Visual Indicators ---
  if (!deviceConnected) {
    // Fast blink when disconnected/advertising (every 300ms)
    if (currentMillis - lastLedToggle > 300) {
      ledState = !ledState;
      digitalWrite(LED_PIN, ledState ? HIGH : LOW);
      lastLedToggle = currentMillis;
    }
  } else {
    // When connected, stay off and only blink HIGH during active heartbeat detection
    if (!beatDetected) {
      digitalWrite(LED_PIN, LOW);
    }
  }

  // Handle disconnected advertising restart
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // give the bluetooth stack the chance to get ready
    pAdvertising->start();
    Serial.println("Restarting advertising...");
    oldDeviceConnected = deviceConnected;
  }
  
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  delay(20); // 50Hz sample rate for smooth tracking
}
