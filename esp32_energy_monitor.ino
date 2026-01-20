#include <WiFi.h>
#include <HTTPClient.h>
#include <SPIFFS.h>
#include <ArduinoJson.h>
#include <WebServer.h>

// ✅ Sensor Pin Configuration
#define ACS712_PIN 35           // Analog pin for ACS712 current sensor (ADC1_CHANNEL_7)
#define ZMPT101B_PIN 34         // Analog pin for ZMPT101B voltage sensor (ADC1_CHANNEL_6)
#define RELAY_PIN 23            // Digital pin for relay module control
#define TEMP_SENSOR_PIN 33      // Optional: Temperature sensor pin

// ✅ WiFi Configuration
const char* ssid = "realme C31";
const char* password = "anjaah@123";

// ✅ Backend Server
const char* serverUrl = "http://10.168.130.214:4000/api/esp32/data";
const char* anomalyUrl = "http://10.168.130.214:4000/api/anomaly/detect";
const char* relayControlUrl = "http://10.168.130.214:4000/api/relay/control";

// ⏱️ Timeout
const int REQUEST_TIMEOUT = 60000;

// 🔐 Global User ID (dynamically set from app)
int CURRENT_USER_ID = 0;
const char* USER_ID_FILE = "/user_id.txt";

// ✅ WebServer to receive commands from app
WebServer server(80);

// ============ ACS712 CONFIGURATION ============
// ACS712-5A: sensitivity = 185 mV/A (2.5V at 0A)
// ACS712-20A: sensitivity = 100 mV/A
// ACS712-30A: sensitivity = 66 mV/A
const float ACS712_SENSITIVITY = 0.185;  // For ACS712-5A (change based on your module)
const float ACS_ZERO_OFFSET = 2.5;       // 2.5V is zero current (center point)
const int ADC_RESOLUTION = 4095;         // 12-bit ADC
const float ADC_REFERENCE = 3.3;         // ESP32 reference voltage

// ============ ZMPT101B CONFIGURATION ============
// ZMPT101B: Sensitivity = 0.00467V per unit
// Peak voltage = 220V * 1.414 = 311V (for 220V RMS)
const float ZMPT101B_SENSITIVITY = 0.00467;
const float VOLTAGE_MULTIPLIER = 220.0;  // Adjust based on your region (110V or 220V)

// ============ RELAY CONTROL ============
bool RELAY_STATE = false;  // true = ON, false = OFF

// ============ ANOMALY DETECTION ============
float POWER_THRESHOLD = 5000.0;    // Watts - adjust based on your needs
float VOLTAGE_THRESHOLD = 250.0;   // Volts
float CURRENT_THRESHOLD = 20.0;    // Amps
float TEMP_THRESHOLD = 45.0;       // Celsius
bool ANOMALY_DETECTED = false;

// ============ SENSOR READING HISTORY ============
const int HISTORY_SIZE = 10;
float powerHistory[HISTORY_SIZE] = {0};
float voltageHistory[HISTORY_SIZE] = {0};
int historyIndex = 0;

// ============ SETUP ============
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n\n🔌 ESP32 Energy Monitor with Sensors Starting...");
  
  // Initialize pins
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);  // Relay OFF by default
  
  // Configure ADC for better accuracy
  analogSetSamples(8);              // Average of 8 samples
  analogSetClockDiv(1);             // Faster clock
  analogSetAttenuation(ADC_11db);   // Maximum range for 3.3V

  // Initialize SPIFFS
  if (!SPIFFS.begin(true)) {
    Serial.println("❌ SPIFFS Mount Failed");
  } else {
    Serial.println("✅ SPIFFS Mounted");
    loadUserIdFromStorage();
  }

  // Connect to WiFi
  connectToWiFi();

  // Setup WebServer
  setupWebServer();
}

// ============ SETUP WEB SERVER ============
void setupWebServer() {
  server.on("/set-user", HTTP_GET, handleSetUser);
  server.on("/health", HTTP_GET, handleHealth);
  server.on("/relay/toggle", HTTP_GET, handleRelayToggle);
  server.on("/relay/on", HTTP_GET, handleRelayOn);
  server.on("/relay/off", HTTP_GET, handleRelayOff);
  server.on("/relay/status", HTTP_GET, handleRelayStatus);
  server.on("/sensors", HTTP_GET, handleSensorStatus);
  server.onNotFound(handleNotFound);

  server.begin();
  Serial.println("✅ WebServer started on port 80");
}

// ✅ Handle /set-user request
void handleSetUser() {
  String path = server.uri();
  Serial.println("📬 Received request: " + path);

  int lastSlash = path.lastIndexOf('/');
  String userIdStr = path.substring(lastSlash + 1);
  int userId = userIdStr.toInt();

  if (userId > 0) {
    saveUserIdToStorage(userId);
    Serial.print("✅ User ID set via HTTP: ");
    Serial.println(userId);
    
    server.send(200, "application/json", "{\"success\": true, \"userId\": " + String(userId) + "}");
  } else {
    Serial.println("❌ Invalid user ID");
    server.send(400, "application/json", "{\"success\": false, \"error\": \"Invalid userId\"}");
  }
}

// ✅ Handle /relay/toggle
void handleRelayToggle() {
  RELAY_STATE = !RELAY_STATE;
  digitalWrite(RELAY_PIN, RELAY_STATE ? HIGH : LOW);
  
  Serial.print("🔄 Relay toggled to: ");
  Serial.println(RELAY_STATE ? "ON" : "OFF");
  
  String response = "{\"success\": true, \"relayState\": " + String(RELAY_STATE ? "true" : "false") + "}";
  server.send(200, "application/json", response);
}

// ✅ Handle /relay/on
void handleRelayOn() {
  RELAY_STATE = true;
  digitalWrite(RELAY_PIN, HIGH);
  
  Serial.println("🔌 Relay turned ON");
  server.send(200, "application/json", "{\"success\": true, \"relayState\": true}");
}

// ✅ Handle /relay/off
void handleRelayOff() {
  RELAY_STATE = false;
  digitalWrite(RELAY_PIN, LOW);
  
  Serial.println("⚫ Relay turned OFF");
  server.send(200, "application/json", "{\"success\": true, \"relayState\": false}");
}

// ✅ Handle /relay/status
void handleRelayStatus() {
  String response = "{\"relayState\": " + String(RELAY_STATE ? "true" : "false") + "}";
  server.send(200, "application/json", response);
}

// ✅ Handle /sensors - Get current sensor readings
void handleSensorStatus() {
  float current = readCurrentFromACS712();
  float voltage = readVoltageFromZMPT101B();
  float power = voltage * current;
  
  String response = "{";
  response += "\"voltage\": " + String(voltage, 2) + ",";
  response += "\"current\": " + String(current, 2) + ",";
  response += "\"power\": " + String(power, 2) + ",";
  response += "\"pf\": 0.95,";
  response += "\"frequency\": 50.0,";
  response += "\"temperature\": 28.5,";
  response += "\"relayState\": " + String(RELAY_STATE ? "true" : "false");
  response += "}";
  
  server.send(200, "application/json", response);
}

// ✅ Handle 404
void handleNotFound() {
  String message = "404 Not Found\nEndpoints:\n";
  message += "GET /set-user/{userId}\n";
  message += "GET /relay/toggle - Toggle relay\n";
  message += "GET /relay/on - Turn relay ON\n";
  message += "GET /relay/off - Turn relay OFF\n";
  message += "GET /relay/status - Get relay status\n";
  message += "GET /sensors - Get sensor readings\n";
  message += "GET /health - Health check\n";
  
  server.send(404, "text/plain", message);
}

// ============ READ CURRENT FROM ACS712 ============
float readCurrentFromACS712() {
  int rawValue = analogRead(ACS712_PIN);
  
  // Convert raw ADC value to voltage
  float voltage = (rawValue / ADC_RESOLUTION) * ADC_REFERENCE;
  
  // Convert voltage to current (ACS712 formula)
  // Current = (Voltage - Offset) / Sensitivity
  float current = (voltage - ACS_ZERO_OFFSET) / ACS712_SENSITIVITY;
  
  // Remove noise (values very close to 0)
  if (abs(current) < 0.1) {
    current = 0.0;
  }
  
  return abs(current);  // Return absolute value
}

// ============ READ VOLTAGE FROM ZMPT101B ============
float readVoltageFromZMPT101B() {
  int rawValue = analogRead(ZMPT101B_PIN);
  
  // Convert raw ADC value to voltage
  float adcVoltage = (rawValue / ADC_RESOLUTION) * ADC_REFERENCE;
  
  // ZMPT101B outputs AC voltage proportional to input
  // Peak voltage = adcVoltage / ZMPT101B_SENSITIVITY
  // RMS voltage = Peak / sqrt(2) * Multiplier
  float rmsVoltage = (adcVoltage / ZMPT101B_SENSITIVITY) / 1.414 * VOLTAGE_MULTIPLIER;
  
  // Ensure reasonable voltage range
  if (rmsVoltage < 0) rmsVoltage = 0;
  if (rmsVoltage > 300) rmsVoltage = 300;  // Cap at 300V
  
  return rmsVoltage;
}

// ============ DETECT ANOMALIES ============
void detectAnomalies(float voltage, float current, float power) {
  bool hasAnomaly = false;
  String anomalyType = "";
  
  if (power > POWER_THRESHOLD) {
    hasAnomaly = true;
    anomalyType = "Over-power detected";
  }
  
  if (voltage > VOLTAGE_THRESHOLD) {
    hasAnomaly = true;
    anomalyType = "Over-voltage detected";
  }
  
  if (current > CURRENT_THRESHOLD) {
    hasAnomaly = true;
    anomalyType = "Over-current detected";
  }
  
  if (hasAnomaly && !ANOMALY_DETECTED) {
    ANOMALY_DETECTED = true;
    Serial.println("\n🚨 ANOMALY DETECTED: " + anomalyType);
    Serial.println("⚠️ Sending anomaly notification to server...");
    
    // Auto-cut off power if anomaly detected
    if (power > POWER_THRESHOLD || current > CURRENT_THRESHOLD) {
      Serial.println("🔌 AUTO-CUTTING OFF RELAY DUE TO ANOMALY!");
      RELAY_STATE = false;
      digitalWrite(RELAY_PIN, LOW);
    }
    
    sendAnomalyAlert(voltage, current, power, anomalyType);
  } else if (!hasAnomaly && ANOMALY_DETECTED) {
    ANOMALY_DETECTED = false;
    Serial.println("✅ Anomaly cleared");
  }
}

// ============ SEND ANOMALY ALERT ============
void sendAnomalyAlert(float voltage, float current, float power, String anomalyType) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("❌ WiFi not connected");
    return;
  }

  WiFiClient client;
  HTTPClient http;

  http.begin(client, anomalyUrl);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(REQUEST_TIMEOUT);

  String payload = "{";
  payload += "\"userId\":" + String(CURRENT_USER_ID) + ",";
  payload += "\"voltage\":" + String(voltage, 2) + ",";
  payload += "\"current\":" + String(current, 2) + ",";
  payload += "\"power\":" + String(power, 2) + ",";
  payload += "\"anomalyType\":\"" + anomalyType + "\",";
  payload += "\"timestamp\":\"" + getCurrentTimestamp() + "\"";
  payload += "}";

  int httpCode = http.POST(payload);

  if (httpCode == 200) {
    Serial.println("✅ Anomaly alert sent successfully");
  } else {
    Serial.print("⚠️ Anomaly alert failed: ");
    Serial.println(httpCode);
  }

  http.end();
}

// ============ CONNECT TO WiFi ============
void connectToWiFi() {
  Serial.println("\n📡 Connecting to WiFi: " + String(ssid));
  WiFi.begin(ssid, password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi Connected!");
    Serial.print("📡 ESP32 IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n❌ WiFi Connection Failed");
  }
}

// ============ LOAD USER ID FROM STORAGE ============
void loadUserIdFromStorage() {
  if (SPIFFS.exists(USER_ID_FILE)) {
    File file = SPIFFS.open(USER_ID_FILE, "r");
    if (file) {
      String content = file.readString();
      CURRENT_USER_ID = content.toInt();
      file.close();
      Serial.print("✅ Loaded User ID: ");
      Serial.println(CURRENT_USER_ID);
    }
  } else {
    Serial.println("⚠️ No user ID stored yet");
  }
}

// ============ SAVE USER ID TO STORAGE ============
void saveUserIdToStorage(int userId) {
  File file = SPIFFS.open(USER_ID_FILE, "w");
  if (file) {
    file.print(userId);
    file.close();
    CURRENT_USER_ID = userId;
    Serial.print("💾 Saved User ID: ");
    Serial.println(userId);
  }
}

// ============ SEND SENSOR DATA ============
void sendSensorData() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("❌ WiFi Disconnected");
    WiFi.reconnect();
    return;
  }

  if (CURRENT_USER_ID == 0) {
    Serial.println("⚠️ No user ID set");
    return;
  }

  // Read sensors
  float current = readCurrentFromACS712();
  float voltage = readVoltageFromZMPT101B();
  float power = voltage * current;
  float energy = power / 1000.0;  // kWh
  
  // Detect anomalies
  detectAnomalies(voltage, current, power);

  WiFiClient client;
  HTTPClient http;

  http.begin(client, serverUrl);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(REQUEST_TIMEOUT);

  String payload = "{";
  payload += "\"userId\":" + String(CURRENT_USER_ID) + ",";
  payload += "\"voltage\":" + String(voltage, 2) + ",";
  payload += "\"current\":" + String(current, 3) + ",";
  payload += "\"power\":" + String(power, 2) + ",";
  payload += "\"energy\":" + String(energy, 4) + ",";
  payload += "\"pf\":0.95,";
  payload += "\"frequency\":50.0,";
  payload += "\"temperature\":28.5,";
  payload += "\"relayState\":" + String(RELAY_STATE ? "true" : "false") + ",";
  payload += "\"timestamp\":\"" + getCurrentTimestamp() + "\"";
  payload += "}";

  Serial.print("\n📤 Sending data - Voltage: ");
  Serial.print(voltage, 2);
  Serial.print("V, Current: ");
  Serial.print(current, 2);
  Serial.print("A, Power: ");
  Serial.print(power, 2);
  Serial.println("W");

  int httpCode = http.POST(payload);

  if (httpCode == 200) {
    Serial.println("✅ Data sent successfully");
  } else {
    Serial.print("⚠️ HTTP Error: ");
    Serial.println(httpCode);
  }

  http.end();
}

// ============ GET CURRENT TIMESTAMP ============
String getCurrentTimestamp() {
  time_t now = time(nullptr);
  struct tm* timeinfo = localtime(&now);
  char buffer[30];
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", timeinfo);
  return String(buffer);
}

// ============ HEALTH CHECK ============
void handleHealth() {
  float current = readCurrentFromACS712();
  float voltage = readVoltageFromZMPT101B();
  
  String response = "{";
  response += "\"status\": \"online\",";
  response += "\"currentUser\": " + String(CURRENT_USER_ID) + ",";
  response += "\"ip\": \"" + WiFi.localIP().toString() + "\",";
  response += "\"signal\": " + String(WiFi.RSSI()) + ",";
  response += "\"voltage\": " + String(voltage, 2) + ",";
  response += "\"current\": " + String(current, 2) + ",";
  response += "\"relayState\": " + String(RELAY_STATE ? "true" : "false") + "";
  response += "}";
  
  server.send(200, "application/json", response);
}

// ============ MAIN LOOP ============
void loop() {
  // Handle incoming web requests
  server.handleClient();

  // Check WiFi
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("🔌 Reconnecting to WiFi...");
    WiFi.reconnect();
    delay(5000);
  }

  if (CURRENT_USER_ID != 0) {
    Serial.print("👤 Current User: ");
    Serial.println(CURRENT_USER_ID);
  }

  // Send sensor data every 10 seconds
  sendSensorData();

  delay(10000);  // 10 seconds
}
