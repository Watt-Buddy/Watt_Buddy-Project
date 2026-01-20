#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <SPIFFS.h>
#include <WebServer.h>
#include <math.h>
#include <time.h>

// ================= PIN CONFIGURATION =================
#define ACS712_PIN 35           // Current sensor → GPIO 35 (ADC1)
#define ZMPT101B_PIN 34         // Voltage sensor → GPIO 34 (ADC1)
#define RELAY_PIN 18            // Relay → GPIO 18
#define STATUS_LED 2            // Status LED

// ================= WIFI =================
const char* ssid = "UNKNOWN";
const char* password = "12345677";
const char* BACKEND_URL = "http://10.168.130.214:4000";

// ================= SERVER =================
WebServer server(80);

// ================= USER TRACKING =================
String LOGGED_IN_USER = "";  // Will be set by backend
String DEVICE_ID = "ESP32_DEVICE_001";

// ================= ADC =================
const int ADC_RESOLUTION = 4095;
const float ADC_REFERENCE = 3.3;

// ================= ACS712 =================
const float ACS712_SENSITIVITY = 0.185;   // V/A (ACS712-5A)
float ACS_ZERO_OFFSET = 2.5;              // Auto-calibrated at boot

// ================= ZMPT101B =================
const float ZMPT101B_SENSITIVITY = 0.00467;
const float VOLTAGE_MULTIPLIER = 220.0;

// ================= RELAY =================
bool RELAY_STATE = false;

// ================= ENERGY TRACKING =================
float totalEnergy = 0;       // kWh
float dailyEnergy = 0;       // kWh
float monthlyEnergy = 0;     // kWh
unsigned long lastReadTime = 0;
const float POWER_TO_ENERGY_FACTOR = 1.0 / 3600000.0;  // Convert mW·ms to kWh

// ================= THRESHOLDS & SAFETY =================
const float OVERVOLTAGE_THRESHOLD = 250.0;
const float UNDERVOLTAGE_THRESHOLD = 180.0;
const float OVERCURRENT_THRESHOLD = 5.0;
const float OVERPOWER_THRESHOLD = 2500.0;

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(RELAY_PIN, OUTPUT);
  pinMode(STATUS_LED, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  digitalWrite(STATUS_LED, LOW);

  analogSetAttenuation(ADC_11db);

  if (!SPIFFS.begin(true)) {
    Serial.println("❌ SPIFFS Mount Failed");
  }

  blinkLED(3, 200);  // 3 blinks to indicate startup

  connectToWiFi();
  calibrateACS712();
  setupWebServer();

  syncTimeWithNTP();
  loadEnergyData();

  Serial.println("✅ ESP32 Energy Monitor Started");
  Serial.print("📡 Backend URL: ");
  Serial.println(BACKEND_URL);
}

// ================= WEB SERVER ENDPOINTS =================
void setupWebServer() {
  // GET: Read all sensors
  server.on("/sensors", HTTP_GET, handleGetSensors);

  // POST: Set relay state
  server.on("/relay/on", HTTP_POST, handleRelayOn);
  server.on("/relay/off", HTTP_POST, handleRelayOff);

  // GET: Get relay status
  server.on("/relay/status", HTTP_GET, handleRelayStatus);

  // POST: Set logged-in user
  server.on("/user/set", HTTP_POST, handleSetUser);

  // GET: Get energy data
  server.on("/energy", HTTP_GET, handleGetEnergy);

  // POST: Reset daily/monthly energy
  server.on("/energy/reset-daily", HTTP_POST, handleResetDaily);
  server.on("/energy/reset-monthly", HTTP_POST, handleResetMonthly);

  // POST: Log sensor data to backend
  server.on("/log/sensor", HTTP_POST, handleLogSensor);

  server.begin();
  Serial.println("✅ Web Server Started");
}

// ================= SENSOR READ HANDLERS =================
void handleGetSensors() {
  float voltage = readVoltageFromZMPT101B();
  float current = readCurrentFromACS712();
  float power = voltage * current;

  // Safety checks
  if (voltage > OVERVOLTAGE_THRESHOLD || voltage < UNDERVOLTAGE_THRESHOLD) {
    emergencyShutdown("Voltage Anomaly", voltage, current, power);
  }

  if (current > OVERCURRENT_THRESHOLD || power > OVERPOWER_THRESHOLD) {
    emergencyShutdown("Current/Power Anomaly", voltage, current, power);
  }

  // Update energy
  updateEnergyTracking(power);

  // Create JSON response
  StaticJsonDocument<256> doc;
  doc["voltage"] = round(voltage * 100) / 100.0;
  doc["current"] = round(current * 1000) / 1000.0;
  doc["power"] = round(power * 100) / 100.0;
  doc["relay"] = RELAY_STATE;
  doc["totalEnergy"] = round(totalEnergy * 100) / 100.0;
  doc["dailyEnergy"] = round(dailyEnergy * 100) / 100.0;
  doc["monthlyEnergy"] = round(monthlyEnergy * 100) / 100.0;
  doc["user"] = LOGGED_IN_USER;
  doc["timestamp"] = millis();

  String response;
  serializeJson(doc, response);

  server.send(200, "application/json", response);

  // Log to backend asynchronously
  sendSensorDataToBackend(voltage, current, power);
}

// ================= RELAY CONTROL HANDLERS =================
void handleRelayOn() {
  digitalWrite(RELAY_PIN, HIGH);
  RELAY_STATE = true;
  blinkLED(1, 100);
  logRelayStateChange(true);
  server.send(200, "application/json", "{\"success\":true,\"relay\":\"ON\"}");
  Serial.println("🔌 Relay ON");
}

void handleRelayOff() {
  digitalWrite(RELAY_PIN, LOW);
  RELAY_STATE = false;
  logRelayStateChange(false);
  server.send(200, "application/json", "{\"success\":true,\"relay\":\"OFF\"}");
  Serial.println("🔌 Relay OFF");
}

void handleRelayStatus() {
  float voltage = readVoltageFromZMPT101B();
  float current = readCurrentFromACS712();
  float power = voltage * current;

  StaticJsonDocument<256> doc;
  doc["relay"] = RELAY_STATE;
  doc["voltage"] = round(voltage * 100) / 100.0;
  doc["current"] = round(current * 1000) / 1000.0;
  doc["power"] = round(power * 100) / 100.0;
  doc["user"] = LOGGED_IN_USER;

  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

// ================= USER MANAGEMENT =================
void handleSetUser() {
  if (server.hasArg("userId")) {
    LOGGED_IN_USER = server.arg("userId");
    server.send(200, "application/json", "{\"success\":true,\"user\":\"" + LOGGED_IN_USER + "\"}");
    Serial.print("👤 User Set: ");
    Serial.println(LOGGED_IN_USER);
  } else {
    server.send(400, "application/json", "{\"error\":\"userId required\"}");
  }
}

// ================= ENERGY HANDLERS =================
void handleGetEnergy() {
  StaticJsonDocument<256> doc;
  doc["totalEnergy"] = round(totalEnergy * 100) / 100.0;
  doc["dailyEnergy"] = round(dailyEnergy * 100) / 100.0;
  doc["monthlyEnergy"] = round(monthlyEnergy * 100) / 100.0;

  String response;
  serializeJson(doc, response);
  server.send(200, "application/json", response);
}

void handleResetDaily() {
  dailyEnergy = 0;
  saveEnergyData();
  server.send(200, "application/json", "{\"success\":true,\"message\":\"Daily energy reset\"}");
  Serial.println("🔄 Daily Energy Reset");
}

void handleResetMonthly() {
  monthlyEnergy = 0;
  dailyEnergy = 0;
  saveEnergyData();
  server.send(200, "application/json", "{\"success\":true,\"message\":\"Monthly energy reset\"}");
  Serial.println("🔄 Monthly Energy Reset");
}

void handleLogSensor() {
  // This endpoint receives sensor data from backend confirmation
  server.send(200, "application/json", "{\"success\":true}");
}

// ================= BACKEND COMMUNICATION =================
void sendSensorDataToBackend(float voltage, float current, float power) {
  if (WiFi.status() != WL_CONNECTED || LOGGED_IN_USER == "") {
    return;
  }

  HTTPClient http;
  String url = String(BACKEND_URL) + "/api/sensor-data/log";

  StaticJsonDocument<256> doc;
  doc["userId"] = LOGGED_IN_USER;
  doc["deviceId"] = DEVICE_ID;
  doc["voltage"] = round(voltage * 100) / 100.0;
  doc["current"] = round(current * 1000) / 1000.0;
  doc["power"] = round(power * 100) / 100.0;
  doc["relay"] = RELAY_STATE;
  doc["dailyEnergy"] = round(dailyEnergy * 100) / 100.0;
  doc["monthlyEnergy"] = round(monthlyEnergy * 100) / 100.0;
  doc["timestamp"] = time(nullptr);

  String payload;
  serializeJson(doc, payload);

  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  int httpCode = http.POST(payload);

  if (httpCode > 0) {
    if (httpCode == HTTP_CODE_OK) {
      Serial.println("📤 Sensor data sent to backend");
    } else {
      Serial.print("⚠️ Backend response: ");
      Serial.println(httpCode);
    }
  } else {
    Serial.print("❌ HTTP error: ");
    Serial.println(http.errorToString(httpCode).c_str());
  }

  http.end();
}

void logRelayStateChange(bool state) {
  if (WiFi.status() != WL_CONNECTED || LOGGED_IN_USER == "") {
    return;
  }

  HTTPClient http;
  String url = String(BACKEND_URL) + "/api/relay/state-change";

  StaticJsonDocument<128> doc;
  doc["userId"] = LOGGED_IN_USER;
  doc["deviceId"] = DEVICE_ID;
  doc["relayNumber"] = 1;
  doc["state"] = state ? "ON" : "OFF";
  doc["timestamp"] = time(nullptr);

  String payload;
  serializeJson(doc, payload);

  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.POST(payload);
  http.end();

  Serial.println("📤 Relay state logged to backend");
}

// ================= ENERGY TRACKING =================
void updateEnergyTracking(float powerW) {
  unsigned long currentTime = millis();

  if (lastReadTime > 0) {
    unsigned long timeDiffMs = currentTime - lastReadTime;
    float energyMwh = powerW * timeDiffMs;  // mW·ms
    float energyKwh = energyMwh * POWER_TO_ENERGY_FACTOR;

    totalEnergy += energyKwh;
    dailyEnergy += energyKwh;
    monthlyEnergy += energyKwh;
  }

  lastReadTime = currentTime;
}

void saveEnergyData() {
  StaticJsonDocument<128> doc;
  doc["totalEnergy"] = totalEnergy;
  doc["dailyEnergy"] = dailyEnergy;
  doc["monthlyEnergy"] = monthlyEnergy;

  File file = SPIFFS.open("/energy.json", "w");
  serializeJson(doc, file);
  file.close();

  Serial.println("💾 Energy data saved to SPIFFS");
}

void loadEnergyData() {
  if (!SPIFFS.exists("/energy.json")) {
    return;
  }

  File file = SPIFFS.open("/energy.json", "r");
  StaticJsonDocument<128> doc;
  deserializeJson(doc, file);
  file.close();

  totalEnergy = doc["totalEnergy"] | 0.0;
  dailyEnergy = doc["dailyEnergy"] | 0.0;
  monthlyEnergy = doc["monthlyEnergy"] | 0.0;

  Serial.println("📂 Energy data loaded from SPIFFS");
}

// ================= SAFETY & EMERGENCY =================
void emergencyShutdown(const char* reason, float voltage, float current, float power) {
  digitalWrite(RELAY_PIN, LOW);
  RELAY_STATE = false;

  Serial.print("🚨 EMERGENCY SHUTDOWN: ");
  Serial.println(reason);

  blinkLED(5, 100);  // Fast blinks for emergency

  // Log anomaly to backend
  if (WiFi.status() == WL_CONNECTED && LOGGED_IN_USER != "") {
    HTTPClient http;
    String url = String(BACKEND_URL) + "/api/anomalies/log";

    StaticJsonDocument<256> doc;
    doc["userId"] = LOGGED_IN_USER;
    doc["deviceId"] = DEVICE_ID;
    doc["anomalyType"] = reason;
    doc["voltage"] = voltage;
    doc["current"] = current;
    doc["power"] = power;
    doc["autoShutdown"] = true;
    doc["timestamp"] = time(nullptr);

    String payload;
    serializeJson(doc, payload);

    http.begin(url);
    http.addHeader("Content-Type", "application/json");
    http.POST(payload);
    http.end();
  }
}

// ================= ACS712 AUTO-CALIBRATION =================
void calibrateACS712() {
  float sum = 0;
  const int samples = 1000;

  Serial.println("🔧 Calibrating ACS712 (NO LOAD)...");
  blinkLED(2, 150);
  delay(2000);

  for (int i = 0; i < samples; i++) {
    sum += analogRead(ACS712_PIN);
    delay(2);
  }

  ACS_ZERO_OFFSET = (sum / samples) * (ADC_REFERENCE / ADC_RESOLUTION);

  Serial.print("✅ ACS712 Zero Offset = ");
  Serial.println(ACS_ZERO_OFFSET, 3);
}

// ================= CURRENT READING (RMS) =================
float readCurrentFromACS712() {
  const int samples = 500;
  float sumSq = 0;

  for (int i = 0; i < samples; i++) {
    int raw = analogRead(ACS712_PIN);
    float voltage = (raw / (float)ADC_RESOLUTION) * ADC_REFERENCE;
    float current = (voltage - ACS_ZERO_OFFSET) / ACS712_SENSITIVITY;
    sumSq += current * current;
    delayMicroseconds(200);
  }

  float rmsCurrent = sqrt(sumSq / samples);
  if (rmsCurrent < 0.05) rmsCurrent = 0;  // Filter noise
  return rmsCurrent;
}

// ================= VOLTAGE READING (RMS) =================
float readVoltageFromZMPT101B() {
  const int samples = 500;
  float sumSq = 0;

  for (int i = 0; i < samples; i++) {
    int raw = analogRead(ZMPT101B_PIN);
    float adcV = (raw / (float)ADC_RESOLUTION) * ADC_REFERENCE;
    float voltage = adcV / ZMPT101B_SENSITIVITY;
    sumSq += voltage * voltage;
    delayMicroseconds(200);
  }

  float rmsVoltage = sqrt(sumSq / samples) / 1.414;
  rmsVoltage *= VOLTAGE_MULTIPLIER;

  if (rmsVoltage < 10) rmsVoltage = 0;
  if (rmsVoltage > 300) rmsVoltage = 300;  // Clip max voltage

  return rmsVoltage;
}

// ================= WIFI CONNECTION =================
void connectToWiFi() {
  Serial.print("📡 Connecting to WiFi: ");
  Serial.println(ssid);

  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
    blinkLED(1, 50);
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi Connected");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
    digitalWrite(STATUS_LED, HIGH);  // LED on when connected
  } else {
    Serial.println("\n❌ WiFi Connection Failed");
  }
}

// ================= NTP TIME SYNC =================
void syncTimeWithNTP() {
  configTime(5.5 * 3600, 0, "pool.ntp.org");  // IST (UTC+5:30)
  Serial.println("⏰ Syncing time with NTP...");
  time_t now = time(nullptr);
  int attempts = 0;
  while (now < 24 * 3600 && attempts < 20) {
    delay(500);
    now = time(nullptr);
    attempts++;
  }
  Serial.print("✅ Time synced: ");
  Serial.println(ctime(&now));
}

// ================= LED BLINK HELPER =================
void blinkLED(int count, int duration) {
  for (int i = 0; i < count; i++) {
    digitalWrite(STATUS_LED, HIGH);
    delay(duration);
    digitalWrite(STATUS_LED, LOW);
    delay(duration);
  }
}

// ================= MAIN LOOP =================
void loop() {
  server.handleClient();

  // Every 10 seconds, read and display sensors
  static unsigned long lastDisplay = 0;
  if (millis() - lastDisplay > 10000) {
    lastDisplay = millis();

    float voltage = readVoltageFromZMPT101B();
    float current = readCurrentFromACS712();
    float power = voltage * current;

    Serial.print("⚡ V: ");
    Serial.print(voltage, 2);
    Serial.print("V | I: ");
    Serial.print(current, 3);
    Serial.print("A | P: ");
    Serial.print(power, 2);
    Serial.print("W | Daily: ");
    Serial.print(dailyEnergy, 2);
    Serial.print(" kWh | User: ");
    Serial.println(LOGGED_IN_USER);
  }

  // Every 5 minutes, save energy data
  static unsigned long lastSave = 0;
  if (millis() - lastSave > 300000) {
    lastSave = millis();
    saveEnergyData();
  }

  delay(100);
}
