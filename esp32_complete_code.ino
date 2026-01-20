#include <WiFi.h>
#include <HTTPClient.h>
#include <SPIFFS.h>
#include <ArduinoJson.h>
#include <WebServer.h>

// ============ PIN CONFIGURATION ============
#define ACS712_PIN A0        // ACS712-5A current sensor (analog pin)
#define ZMPT101B_PIN A1      // ZMPT101B voltage sensor (analog pin)
#define RELAY_PIN 12         // Relay control pin
#define TEMP_SENSOR_PIN 34   // Temperature sensor (analog pin)

// ============ SENSOR CALIBRATION ============
// ACS712-5A: 185 mV/A (2.5V at 0A)
const float ACS712_SENSITIVITY = 0.185;  // mV/A
const float ACS712_ZERO_VOLTAGE = 2.5;   // Volts at 0A

// ZMPT101B: 185 mV/V (sensitivity)
const float ZMPT101B_SENSITIVITY = 0.00445;  // V/mV
const float ZMPT101B_MIDPOINT = 512.0;       // ADC midpoint for 10-bit

// ============ WiFi Configuration ============
const char* ssid = "realme C31";
const char* password = "anjaah@123";

// ============ Backend Server ============
const char* serverUrl = "http://10.168.130.214:4000/api/esp32/data";
const char* anomalyCheckUrl = "http://10.168.130.214:4000/api/anomaly/check";
const char* relayStatusUrl = "http://10.168.130.214:4000/api/relay/status";

// ============ Timeout ============
const int REQUEST_TIMEOUT = 60000;

// ============ Global Variables ============
int CURRENT_USER_ID = 0;
const char* USER_ID_FILE = "/user_id.txt";

// ============ Relay State ============
bool relayState = false;
bool anomalyDetected = false;

// ============ WebServer ============
WebServer server(80);

// ============ Sensor Data Structure ============
struct SensorData {
  float voltage;
  float current;
  float power;
  float energy;
  float pf;        // Power Factor
  float frequency;
  float temperature;
  bool isAnomaly;
  String anomalyType;
};

SensorData currentSensorData;

// ============ SETUP ============
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n\n🔌 ESP32 Energy Monitor with Sensors Starting...");
  
  // Initialize pins
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);  // Relay off by default
  
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
  server.on("/relay/on", HTTP_POST, handleRelayOn);
  server.on("/relay/off", HTTP_POST, handleRelayOff);
  server.on("/relay/status", HTTP_GET, handleRelayStatus);
  server.on("/sensors", HTTP_GET, handleGetSensors);
  server.onNotFound(handleNotFound);

  server.begin();
  Serial.println("✅ WebServer started on port 80");
}

// ============ WEB SERVER HANDLERS ============

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
    
    String response = "{\"success\": true, \"userId\": " + String(userId) + ", \"message\": \"User ID received\"}";
    server.send(200, "application/json", response);
  } else {
    Serial.println("❌ Invalid user ID received");
    server.send(400, "application/json", "{\"success\": false, \"error\": \"Invalid userId\"}");
  }
}

void handleHealth() {
  String response = "{";
  response += "\"status\": \"online\",";
  response += "\"currentUser\": " + String(CURRENT_USER_ID) + ",";
  response += "\"ip\": \"" + WiFi.localIP().toString() + "\",";
  response += "\"signal\": " + String(WiFi.RSSI()) + ",";
  response += "\"relayState\": " + String(relayState ? "true" : "false");
  response += "}";
  
  server.send(200, "application/json", response);
}

void handleRelayOn() {
  if (CURRENT_USER_ID == 0) {
    server.send(401, "application/json", "{\"success\": false, \"error\": \"No user logged in\"}");
    return;
  }

  digitalWrite(RELAY_PIN, HIGH);
  relayState = true;
  
  Serial.println("🔌 Relay turned ON via API");
  server.send(200, "application/json", "{\"success\": true, \"message\": \"Relay turned ON\"}");
}

void handleRelayOff() {
  if (CURRENT_USER_ID == 0) {
    server.send(401, "application/json", "{\"success\": false, \"error\": \"No user logged in\"}");
    return;
  }

  digitalWrite(RELAY_PIN, LOW);
  relayState = false;
  
  Serial.println("⚫ Relay turned OFF via API");
  server.send(200, "application/json", "{\"success\": true, \"message\": \"Relay turned OFF\"}");
}

void handleRelayStatus() {
  String response = "{\"relayState\": " + String(relayState ? "true" : "false") + "}";
  server.send(200, "application/json", response);
}

void handleGetSensors() {
  String response = "{";
  response += "\"voltage\": " + String(currentSensorData.voltage, 2) + ",";
  response += "\"current\": " + String(currentSensorData.current, 3) + ",";
  response += "\"power\": " + String(currentSensorData.power, 2) + ",";
  response += "\"frequency\": " + String(currentSensorData.frequency, 1) + ",";
  response += "\"temperature\": " + String(currentSensorData.temperature, 1);
  response += "}";
  
  server.send(200, "application/json", response);
}

void handleNotFound() {
  String message = "404 Not Found\n";
  message += "Available endpoints:\n";
  message += "GET /set-user/{userId}\n";
  message += "GET /health\n";
  message += "POST /relay/on\n";
  message += "POST /relay/off\n";
  message += "GET /relay/status\n";
  message += "GET /sensors\n";
  
  server.send(404, "text/plain", message);
}

// ============ READ SENSORS ============

void readSensors() {
  // Read ACS712 (Current Sensor)
  int rawCurrent = analogRead(ACS712_PIN);
  float voltageCurrent = (rawCurrent / 4095.0) * 3.3;  // Convert to voltage (ESP32 is 12-bit, 3.3V)
  float offsetVoltage = voltageCurrent - ACS712_ZERO_VOLTAGE;
  currentSensorData.current = offsetVoltage / ACS712_SENSITIVITY;
  
  // Ensure no negative values
  if (currentSensorData.current < 0.1) {
    currentSensorData.current = 0;
  }

  // Read ZMPT101B (Voltage Sensor)
  int rawVoltage = analogRead(ZMPT101B_PIN);
  float normalizedVoltage = (rawVoltage - ZMPT101B_MIDPOINT) / (ZMPT101B_MIDPOINT);
  currentSensorData.voltage = normalizedVoltage * 230.0;  // Assuming 230V AC standard
  
  if (currentSensorData.voltage < 0) {
    currentSensorData.voltage = -currentSensorData.voltage;
  }

  // Calculate Power (P = V * I)
  currentSensorData.power = currentSensorData.voltage * currentSensorData.current;

  // Read Temperature (using internal sensor or external NTC thermistor)
  int rawTemp = analogRead(TEMP_SENSOR_PIN);
  currentSensorData.temperature = (rawTemp / 4095.0) * 100.0;  // Simplified conversion

  // Calculate Power Factor (assuming PF = 0.95 for inductive load)
  currentSensorData.pf = 0.95;

  // Calculate Frequency (assuming 50 Hz standard)
  currentSensorData.frequency = 50.0;

  // Calculate Energy consumed (for every reading, in kWh)
  currentSensorData.energy = (currentSensorData.power / 1000.0) / 3600.0;  // Convert to kWh per second

  // Detect Anomalies
  detectAnomalies();
}

// ============ ANOMALY DETECTION ============

void detectAnomalies() {
  currentSensorData.isAnomaly = false;
  currentSensorData.anomalyType = "None";

  // Check Overvoltage (> 250V)
  if (currentSensorData.voltage > 250) {
    currentSensorData.isAnomaly = true;
    currentSensorData.anomalyType = "Overvoltage";
    Serial.print("⚠️ OVERVOLTAGE DETECTED: ");
    Serial.println(currentSensorData.voltage);
    triggerAutoShutdown("Overvoltage detected");
  }
  
  // Check Undervoltage (< 180V)
  else if (currentSensorData.voltage < 180) {
    currentSensorData.isAnomaly = true;
    currentSensorData.anomalyType = "Undervoltage";
    Serial.print("⚠️ UNDERVOLTAGE DETECTED: ");
    Serial.println(currentSensorData.voltage);
  }
  
  // Check Overcurrent (> 10A for ACS712-5A)
  else if (currentSensorData.current > 5.0) {
    currentSensorData.isAnomaly = true;
    currentSensorData.anomalyType = "Overcurrent";
    Serial.print("⚠️ OVERCURRENT DETECTED: ");
    Serial.println(currentSensorData.current);
    triggerAutoShutdown("Overcurrent detected");
  }
  
  // Check Overpower (> 2500W)
  else if (currentSensorData.power > 2500) {
    currentSensorData.isAnomaly = true;
    currentSensorData.anomalyType = "Overpower";
    Serial.print("⚠️ OVERPOWER DETECTED: ");
    Serial.println(currentSensorData.power);
    triggerAutoShutdown("Overpower detected");
  }
  
  // Check Overtemperature (> 80°C)
  else if (currentSensorData.temperature > 80) {
    currentSensorData.isAnomaly = true;
    currentSensorData.anomalyType = "Overtemperature";
    Serial.print("⚠️ OVERTEMPERATURE DETECTED: ");
    Serial.println(currentSensorData.temperature);
    triggerAutoShutdown("Overtemperature detected");
  }
}

// ============ AUTO SHUTDOWN ============

void triggerAutoShutdown(String reason) {
  Serial.print("🚨 AUTO SHUTDOWN TRIGGERED: ");
  Serial.println(reason);
  
  digitalWrite(RELAY_PIN, LOW);
  relayState = false;
  anomalyDetected = true;

  // Send alert to server
  sendAnomalyAlert(reason);
}

// ============ SEND SENSOR DATA ============

void sendSensorData() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("❌ WiFi Disconnected - Reconnecting...");
    WiFi.reconnect();
    return;
  }

  if (CURRENT_USER_ID == 0) {
    Serial.println("⚠️ No user ID set! Waiting for app to log in...");
    return;
  }

  WiFiClient client;
  HTTPClient http;

  http.begin(client, serverUrl);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(REQUEST_TIMEOUT);

  String payload = "{";
  payload += "\"userId\":" + String(CURRENT_USER_ID) + ",";
  payload += "\"voltage\":" + String(currentSensorData.voltage, 2) + ",";
  payload += "\"current\":" + String(currentSensorData.current, 3) + ",";
  payload += "\"power\":" + String(currentSensorData.power, 2) + ",";
  payload += "\"energy\":" + String(currentSensorData.energy, 6) + ",";
  payload += "\"pf\":" + String(currentSensorData.pf, 2) + ",";
  payload += "\"frequency\":" + String(currentSensorData.frequency, 1) + ",";
  payload += "\"temperature\":" + String(currentSensorData.temperature, 1) + ",";
  payload += "\"isAnomaly\":" + String(currentSensorData.isAnomaly ? "true" : "false") + ",";
  payload += "\"anomalyType\":\"" + currentSensorData.anomalyType + "\",";
  payload += "\"relayState\":" + String(relayState ? "true" : "false") + ",";
  payload += "\"timestamp\":\"" + getCurrentTimestamp() + "\"";
  payload += "}";

  Serial.print("\n📤 Payload for User ");
  Serial.print(CURRENT_USER_ID);
  Serial.print(": ");
  Serial.println(payload);

  int httpCode = http.POST(payload);

  Serial.print("📤 HTTP Response Code: ");
  Serial.println(httpCode);

  if (httpCode == 200) {
    Serial.println("✅ Data stored successfully!");
    String response = http.getString();
    Serial.println("📥 Server Response: " + response);
  } else if (httpCode > 0) {
    Serial.print("⚠️ Unexpected status: ");
    Serial.println(httpCode);
    Serial.println(http.getString());
  } else {
    Serial.print("❌ Request failed: ");
    Serial.println(http.errorToString(httpCode).c_str());
  }

  http.end();
}

// ============ SEND ANOMALY ALERT ============

void sendAnomalyAlert(String reason) {
  if (WiFi.status() != WL_CONNECTED) return;

  WiFiClient client;
  HTTPClient http;

  http.begin(client, anomalyCheckUrl);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(REQUEST_TIMEOUT);

  String payload = "{";
  payload += "\"userId\":" + String(CURRENT_USER_ID) + ",";
  payload += "\"voltage\":" + String(currentSensorData.voltage, 2) + ",";
  payload += "\"current\":" + String(currentSensorData.current, 3) + ",";
  payload += "\"power\":" + String(currentSensorData.power, 2) + ",";
  payload += "\"anomalyType\":\"" + currentSensorData.anomalyType + "\",";
  payload += "\"reason\":\"" + reason + "\"";
  payload += "}";

  Serial.println("🚨 Sending anomaly alert to server...");
  http.POST(payload);
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
    Serial.println("\n❌ WiFi Connection Failed - Retrying...");
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
      Serial.print("✅ Loaded User ID from storage: ");
      Serial.println(CURRENT_USER_ID);
    }
  } else {
    Serial.println("⚠️ No user ID stored yet. Waiting for app to set it...");
  }
}

// ============ SAVE USER ID TO STORAGE ============

void saveUserIdToStorage(int userId) {
  File file = SPIFFS.open(USER_ID_FILE, "w");
  if (file) {
    file.print(userId);
    file.close();
    CURRENT_USER_ID = userId;
    Serial.print("💾 Saved User ID to storage: ");
    Serial.println(userId);
  }
}

// ============ GET CURRENT TIMESTAMP ============

String getCurrentTimestamp() {
  time_t now = time(nullptr);
  struct tm* timeinfo = localtime(&now);
  char buffer[30];
  strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", timeinfo);
  return String(buffer);
}

// ============ MAIN LOOP ============

void loop() {
  // Handle incoming web requests
  server.handleClient();

  // Check WiFi connection
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("🔌 Reconnecting to WiFi...");
    WiFi.reconnect();
    delay(5000);
  }

  // Display current user
  if (CURRENT_USER_ID != 0) {
    Serial.print("👤 Current User: ");
    Serial.println(CURRENT_USER_ID);
  }

  // Read sensors
  readSensors();

  // Send sensor data every 10 seconds
  sendSensorData();

  // Delay before next reading
  delay(10000);  // 10 seconds
}
