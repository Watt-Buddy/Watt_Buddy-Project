#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <HTTPClient.h>  // ADD THIS FOR RELIABLE HTTP POSTING

/* ============ CONFIGURATION ============ */
const char* ssid = "realme C31";
const char* pass = "anjaah@123";

// (Optional) Static IP configuration - currently unused (DHCP mode)
// IPAddress local_IP(10, 148, 3, 100);    // Example static IP on same subnet as PC (10.148.3.x)
// IPAddress gateway(10, 148, 3, 211);     // From ipconfig: Default Gateway
// IPAddress subnet(255, 255, 255, 0);

#define RELAY1_PIN 23 
#define RELAY2_PIN 19 
#define ACS_PIN 34
#define ZMPT_PIN 35

// Backend server (your PC) IP - from ipconfig: 10.148.3.49
const char* SERVER_IP = "10.185.178.50";
const int SERVER_PORT = 4000;

float Vrms = 0.0, Irms = 0.0, Power = 0.0, energy_kWh = 0.0;
String currentUserId = "8"; // Default fallback ID
WebServer server(80);
unsigned long lastReadingTime = 0, lastServerPostTime = 0;
unsigned long lastSaveTime = 0; 

Preferences preferences; 

// ============ ANOMALY DIAGNOSIS STATE ============
// Threshold used by server as well (approx 2x 75W baseline)
const float ANOMALY_THRESHOLD_W = 150.0;
// Results of last diagnosis
int dominantRelay = 0;          // 0 = unknown/both, 1 or 2 = relay number
float dominantRelayPowerW = 0;  // approximate watts drawn by that relay
unsigned long lastDiagnosisTime = 0;
bool isDiagnosing = false;

/* ============ PRECISION SENSOR LOGIC (UNTOUCHED) ============ */
void calculateSensors() {
  int samples = 600; 
  float sumI2 = 0, sumV2 = 0;
  
  long rMidI = 0, rMidV = 0;
  for(int i=0; i<150; i++) {
    rMidI += analogRead(ACS_PIN);
    rMidV += analogRead(ZMPT_PIN);
  }
  float midI = rMidI / 150.0;
  float midV = rMidV / 150.0;

  // DEBUG: Log the midpoint values
  static unsigned long lastMidDebugTime = 0;
  if (millis() - lastMidDebugTime > 10000) {
    Serial.printf("🔍 MIDPOINT VALUES: midV=%.1f, midI=%.1f\n", midV, midI);
    lastMidDebugTime = millis();
  }

  for (int i = 0; i < samples; i++) {
    int rawIraw = analogRead(ACS_PIN);
    int rawVraw = analogRead(ZMPT_PIN);
    float rawI = rawIraw - midI;
    float rawV = rawVraw - midV;
    sumI2 += (rawI * rawI);
    sumV2 += (rawV * rawV);
    delayMicroseconds(60); 
  }

  // Extra diagnostics when values look suspiciously zero
  if (sumV2 == 0 || sumI2 == 0) {
    Serial.println("⚠️ ADC DIAGNOSTIC: possible wiring/attenuation issue");
    Serial.print("   Sample raw readings (example): ");
    Serial.print(analogRead(ACS_PIN));
    Serial.print(" ");
    Serial.println(analogRead(ZMPT_PIN));
    Serial.print("   midI= "); Serial.print(midI); Serial.print(" midV= "); Serial.println(midV);
  }

  float currentCalc = sqrt(sumI2 / samples) * 0.026; 
  // CORRECTED calibration factor: 0.62 should give ~230V for India AC
  float voltageCalc = sqrt(sumV2 / samples) * 0.62; 

  Irms = (currentCalc < 0.12) ? 0 : currentCalc;
  
  // DEBUG: Print EVERY calculation to diagnose
  static unsigned long lastDebugTime = 0;
  if (millis() - lastDebugTime > 2000) {
    Serial.printf("🔧 SENSOR DEBUG:\n");
    Serial.printf("   sumV2=%.0f, sqrt(sumV2/samples)=%.4f\n", sumV2, sqrt(sumV2 / samples));
    Serial.printf("   voltageCalc=%.2f (before filter)\n", voltageCalc);
    Serial.printf("   Vrms=%.2f (after filter)\n", Vrms);
    Serial.printf("   sumI2=%.0f, currentCalc=%.3f\n", sumI2, currentCalc);
    lastDebugTime = millis();
  }
  
  // REMOVED threshold - accept ANY voltage value
  if (voltageCalc <= 0) {
    Vrms = 0;
  } else {
    Vrms = (Vrms * 0.5) + (voltageCalc * 0.5); 
  }
  
  Power = Vrms * Irms * 0.95;
  if (Power < 1.0) Power = 0;

  if (Power > 0) {
     energy_kWh += (Power / 1000.0) / 3600.0;
  }
}

/* ============ NETWORK DIAGNOSTICS ============ */
void checkNetworkDiagnostics() {
  static unsigned long lastDiagTime = 0;
  
  // Only run diagnostics every 30 seconds to avoid flooding logs
  if (millis() - lastDiagTime < 30000) return;
  lastDiagTime = millis();
  
  Serial.println("\n🔍 NETWORK DIAGNOSTICS:");
  Serial.print("   WiFi Status: ");
  
  switch(WiFi.status()) {
    case WL_CONNECTED: 
      Serial.println("✅ Connected");
      Serial.print("   Local IP: ");
      Serial.println(WiFi.localIP());
      Serial.print("   Signal Strength: ");
      Serial.print(WiFi.RSSI());
      Serial.println(" dBm");
      break;
    case WL_DISCONNECTED: Serial.println("❌ Disconnected"); break;
    case WL_CONNECT_FAILED: Serial.println("❌ Connection Failed"); break;
    case WL_NO_SSID_AVAIL: Serial.println("❌ SSID Not Found"); break;
    case WL_IDLE_STATUS: Serial.println("⏳ Idle"); break;
    default: Serial.println("❓ Unknown");
  }
  
  Serial.print("   Target Server: ");
  Serial.print(SERVER_IP);
  Serial.print(":");
  Serial.println(SERVER_PORT);
}

/* ============ SERVER POST (UPDATED: USES HTTPClient FOR RELIABILITY) ============ */
void postData() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("❌ WiFi not connected, skipping POST");
    checkNetworkDiagnostics();  // show reason for lack of connection
    return;
  }

  HTTPClient http;
  
  // Build the complete URL
  String url = "http://" + String(SERVER_IP) + ":" + String(SERVER_PORT) + "/api/esp32/data";
  
  // Build JSON payload (include diagnosis results if available)
  String json = "{\"voltage\":" + String(Vrms, 1) + 
                ",\"current\":" + String(Irms, 3) + 
                ",\"power\":" + String(Power, 2) + 
                ",\"energy\":" + String(energy_kWh, 4) + 
                ",\"relay1\":" + String(digitalRead(RELAY1_PIN) == LOW ? 1 : 0) + 
                ",\"relay2\":" + String(digitalRead(RELAY2_PIN) == LOW ? 1 : 0) + 
                ",\"dominantRelay\":" + String(dominantRelay) +
                ",\"dominantPower\":" + String(dominantRelayPowerW, 1) +
                ",\"userId\":\"" + currentUserId + "\"}"; 

  Serial.print("📤 POST to ");
  Serial.println(url);
  Serial.print("📋 Payload: ");
  Serial.println(json);

  // Set timeouts to prevent hanging
  http.setConnectTimeout(5000);  // 5 second connection timeout
  http.setTimeout(5000);         // 5 second response timeout
  
  if (http.begin(url)) {
    http.addHeader("Content-Type", "application/json");
    http.addHeader("Connection", "close");  // Close connection after request
    
    int httpCode = http.POST(json);
    
    if (httpCode == 200) {
      String response = http.getString();
      Serial.print("✅ POST SUCCESS (Code: ");
      Serial.print(httpCode);
      Serial.print(") Response: ");
      Serial.println(response);
    } else if (httpCode == -1) {
      Serial.println("❌ POST FAILED: Connection timeout or server unreachable");
      Serial.print("   Server: ");
      Serial.print(SERVER_IP);
      Serial.print(":");
      Serial.println(SERVER_PORT);
      checkNetworkDiagnostics();  // Run diagnostics on connection failure
    } else {
      Serial.print("❌ POST FAILED (Code: ");
      Serial.print(httpCode);
      Serial.println(")");
    }
    
    http.end();
  } else {
    Serial.println("❌ Unable to create HTTP connection");
    checkNetworkDiagnostics();
  }
}

/* ============ SETUP ============ */
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n\n🔧 WattBuddy ESP32 Starting...");

  // Initialize Preferences and load previous energy/user data
  preferences.begin("watt-buddy", false); 
  energy_kWh = preferences.getFloat("energy", 0.0);
  currentUserId = preferences.getString("last_user", "8"); // Load the last saved user ID
  
  Serial.printf("📊 Restored Energy: %.4f kWh\n", energy_kWh);
  Serial.printf("👤 Active User ID: %s\n", currentUserId.c_str());

  pinMode(RELAY1_PIN, OUTPUT);
  pinMode(RELAY2_PIN, OUTPUT);
  
  digitalWrite(RELAY1_PIN, LOW); 
  digitalWrite(RELAY2_PIN, LOW);

  Serial.println("📡 Connecting to WiFi...");
  WiFi.mode(WIFI_STA);

  // Use DHCP for IP assignment (simpler and avoids mismatch with backend PC)
  WiFi.begin(ssid, pass);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) { 
    delay(500); 
    Serial.print("."); 
    attempts++;
  }
  
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("✅ WiFi Connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("❌ WiFi Connection Failed!");
    checkNetworkDiagnostics();

    // retry once using DHCP instead of static IP
    Serial.println("⚠️ Retrying connection with DHCP (no static IP)");
    WiFi.disconnect(true);           // clear previous settings
    WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
    WiFi.begin(ssid, pass);
    attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
      delay(500);
      Serial.print("+");
      attempts++;
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("✅ Connected via DHCP!");
      Serial.print("IP: ");
      Serial.println(WiFi.localIP());
    } else {
      Serial.println("❌ Still unable to connect after DHCP retry");
      checkNetworkDiagnostics();
    }
  }

  // NEW ROUTE: Provisioning endpoint for Flutter app
  server.on("/set-user", HTTP_GET, []() {
    if (server.hasArg("id")) {
      currentUserId = server.arg("id");
      preferences.putString("last_user", currentUserId); // Save to permanent memory
      server.send(200, "text/plain", "User ID Updated to: " + currentUserId);
      Serial.println("👤 Device provisioned for User: " + currentUserId);
    } else {
      server.send(400, "text/plain", "Missing ID parameter");
    }
  });

  server.on("/relay1/on", []() { 
    digitalWrite(RELAY1_PIN, LOW); 
    Serial.printf("🟢 HTTP /relay1/on -> RELAY1_PIN=%d (digitalRead=%d)\n", RELAY1_PIN, digitalRead(RELAY1_PIN));
    server.send(200, "text/plain", "1"); 
  });
  
  server.on("/relay1/off", []() { 
    digitalWrite(RELAY1_PIN, HIGH); 
    Serial.printf("🔴 HTTP /relay1/off -> RELAY1_PIN=%d (digitalRead=%d)\n", RELAY1_PIN, digitalRead(RELAY1_PIN));
    server.send(200, "text/plain", "0"); 
  });
  
  server.on("/relay2/on", []() { 
    digitalWrite(RELAY2_PIN, LOW); 
    Serial.printf("🟢 HTTP /relay2/on -> RELAY2_PIN=%d (digitalRead=%d)\n", RELAY2_PIN, digitalRead(RELAY2_PIN));
    server.send(200, "text/plain", "1"); 
  });
  
  server.on("/relay2/off", []() { 
    digitalWrite(RELAY2_PIN, HIGH); 
    Serial.printf("🔴 HTTP /relay2/off -> RELAY2_PIN=%d (digitalRead=%d)\n", RELAY2_PIN, digitalRead(RELAY2_PIN));
    server.send(200, "text/plain", "0"); 
  });

  // Debug endpoint: confirm what the ESP32 thinks relay states are.
  // Note: in this wiring, LOW means relay ON, HIGH means relay OFF.
  server.on("/relay/status", HTTP_GET, []() {
    const int r1 = (digitalRead(RELAY1_PIN) == LOW) ? 1 : 0;
    const int r2 = (digitalRead(RELAY2_PIN) == LOW) ? 1 : 0;
    String json = "{\"relay1\":" + String(r1) + ",\"relay2\":" + String(r2) + "}";
    server.send(200, "application/json", json);
  });

  server.begin();
  analogReadResolution(12);
  // Ensure ADC attenuation is set for full AC mains range
  analogSetPinAttenuation(ACS_PIN, ADC_11db);
  analogSetPinAttenuation(ZMPT_PIN, ADC_11db);
  
  Serial.println("🚀 ESP32 Ready!");
}

/* ============ LOOP ============ */
void loop() {
  server.handleClient();
  
  if (millis() - lastReadingTime > 1000) {
    calculateSensors();
    lastReadingTime = millis();
    Serial.printf("V: %.1f | I: %.3f | P: %.1fW | Total: %.4f kWh | User: %s\n", Vrms, Irms, Power, energy_kWh, currentUserId.c_str());
  }

  if (millis() - lastSaveTime > 300000) {
    preferences.putFloat("energy", energy_kWh);
    lastSaveTime = millis();
    Serial.println("💾 Energy data backed up to flash memory.");
  }

  if (millis() - lastServerPostTime > 5000) {
    postData();
    lastServerPostTime = millis();
  }

  // Run auto-diagnosis when power is abnormally high
  if (!isDiagnosing && Power > ANOMALY_THRESHOLD_W && (millis() - lastDiagnosisTime) > 60000) {
    runAnomalyDiagnosis();
  }
}

// ============ ANOMALY DIAGNOSIS LOGIC ============
void runAnomalyDiagnosis() {
  isDiagnosing = true;
  lastDiagnosisTime = millis();

  float baselineP = Power;
  float pDropR1 = 0;
  float pDropR2 = 0;

  // Probe Relay 1 if currently ON (LOW = ON in this wiring)
  if (digitalRead(RELAY1_PIN) == LOW) {
    Serial.println("🔍 Diagnosis: probing Relay 1...");
    digitalWrite(RELAY1_PIN, HIGH); // turn OFF relay 1
    delay(1500);                    // allow sensors to settle
    calculateSensors();
    float after = Power;
    pDropR1 = baselineP - after;
    Serial.printf("   Relay1 drop ≈ %.1f W\n", pDropR1);
    // Restore Relay 1
    digitalWrite(RELAY1_PIN, LOW);
    delay(500);
    calculateSensors();
    baselineP = Power; // update baseline after restoring
  }

  // Probe Relay 2 if currently ON
  if (digitalRead(RELAY2_PIN) == LOW) {
    Serial.println("🔍 Diagnosis: probing Relay 2...");
    digitalWrite(RELAY2_PIN, HIGH); // turn OFF relay 2
    delay(1500);
    calculateSensors();
    float after = Power;
    pDropR2 = baselineP - after;
    Serial.printf("   Relay2 drop ≈ %.1f W\n", pDropR2);
    // Restore Relay 2
    digitalWrite(RELAY2_PIN, LOW);
    delay(500);
    calculateSensors();
  }

  // Decide dominant relay
  dominantRelay = 0;
  dominantRelayPowerW = 0;
  // Only mark a relay as dominant if:
  //  - its drop is > 5W (ignore noise), AND
  //  - it is clearly higher than the other (at least 1.5x)
  if (pDropR1 > pDropR2 && pDropR1 > 5 && pDropR1 >= pDropR2 * 1.5f) {
    dominantRelay = 1;
    dominantRelayPowerW = pDropR1;
  } else if (pDropR2 > pDropR1 && pDropR2 > 5 && pDropR2 >= pDropR1 * 1.5f) {
    dominantRelay = 2;
    dominantRelayPowerW = pDropR2;
  } else {
    // Both sockets are contributing similarly → treat as general anomaly
    dominantRelay = 0;
    dominantRelayPowerW = 0;
  }

  Serial.printf("🔎 Diagnosis result: dominantRelay=%d, power≈%.1f W\n", dominantRelay, dominantRelayPowerW);

  isDiagnosing = false;
}
