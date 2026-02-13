#!/usr/bin/env node

/**
 * Anomaly Alert System Tester
 * Simulates ESP32 data and triggers anomaly detection
 * 
 * Usage: node test_anomaly_alerts.js
 */

const http = require('http');

const SERVER_URL = 'http://localhost:4000';
const USER_ID = 'user123';

// Color codes for console output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

function log(color, ...args) {
  console.log(`${color}${args.join(' ')}${colors.reset}`);
}

/**
 * Send ESP32 data to the backend
 */
async function sendESP32Data(payload) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(payload);

    const options = {
      hostname: 'localhost',
      port: 4000,
      path: '/api/esp32/data',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length,
      },
    };

    const req = http.request(options, (res) => {
      let responseData = '';

      res.on('data', (chunk) => {
        responseData += chunk;
      });

      res.on('end', () => {
        try {
          const parsed = JSON.parse(responseData);
          resolve(parsed);
        } catch (e) {
          resolve({ raw: responseData });
        }
      });
    });

    req.on('error', (e) => {
      reject(e);
    });

    req.write(data);
    req.end();
  });
}

/**
 * Test Scenario 1: Normal Operation
 */
async function testNormalOperation() {
  log(colors.cyan, '\n📊 TEST 1: Normal Operation (50W)');
  log(colors.cyan, '═══════════════════════════════════════');

  const payload = {
    voltage: 230,
    current: 0.22,
    power: 50,
    energy: 5.234,
    relay1: 1,
    relay2: 0,
    userId: USER_ID,
  };

  try {
    const response = await sendESP32Data(payload);
    log(colors.green, '✅ Normal data sent successfully');
    log(colors.blue, `   Power: ${payload.power}W (Below 150W threshold)`);
    log(colors.green, `   DB Write: ${response.dbWrite ? 'YES' : 'NO'}`);
  } catch (error) {
    log(colors.red, '❌ Error:', error.message);
  }
}

/**
 * Test Scenario 2: Anomaly Detection - Socket 1
 */
async function testAnomalySocket1() {
  log(colors.cyan, '\n⚠️  TEST 2: Anomaly Alert - Socket 1 (2850W)');
  log(colors.cyan, '═══════════════════════════════════════');

  const payload = {
    voltage: 230,
    current: 12.4,
    power: 2850,
    energy: 5.235,
    relay1: 1,
    relay2: 0,
    userId: USER_ID,
  };

  try {
    const response = await sendESP32Data(payload);
    log(colors.yellow, '⚠️  Anomaly data sent!');
    log(colors.blue, `   Power: ${payload.power}W (EXCEEDS 150W threshold)`);
    log(colors.red, `   Socket: Socket 1 (relay1 = ${payload.relay1})`);
    log(colors.yellow, '   → Server should emit "anomaly_alert" event');
    log(colors.yellow, '   → Flutter app should show dialog on phone');
  } catch (error) {
    log(colors.red, '❌ Error:', error.message);
  }
}

/**
 * Test Scenario 3: Anomaly Detection - Socket 2
 */
async function testAnomalySocket2() {
  log(colors.cyan, '\n⚠️  TEST 3: Anomaly Alert - Socket 2 (3200W)');
  log(colors.cyan, '═══════════════════════════════════════');

  const payload = {
    voltage: 230,
    current: 13.9,
    power: 3200,
    energy: 5.240,
    relay1: 0,
    relay2: 1,
    userId: USER_ID,
  };

  try {
    const response = await sendESP32Data(payload);
    log(colors.yellow, '⚠️  Anomaly data sent!');
    log(colors.blue, `   Power: ${payload.power}W (EXCEEDS 150W threshold)`);
    log(colors.red, `   Socket: Socket 2 (relay2 = ${payload.relay2})`);
    log(colors.yellow, '   → Server should emit "anomaly_alert" event');
    log(colors.yellow, '   → Flutter app should show dialog on phone');
  } catch (error) {
    log(colors.red, '❌ Error:', error.message);
  }
}

/**
 * Test Scenario 4: Both Sockets Active (Anomaly)
 */
async function testBothSocketsAnomaly() {
  log(colors.cyan, '\n⚠️  TEST 4: Anomaly Alert - Both Sockets (4000W)');
  log(colors.cyan, '═══════════════════════════════════════');

  const payload = {
    voltage: 230,
    current: 17.4,
    power: 4000,
    energy: 5.245,
    relay1: 1,
    relay2: 1,
    userId: USER_ID,
  };

  try {
    const response = await sendESP32Data(payload);
    log(colors.yellow, '⚠️  Anomaly data sent!');
    log(colors.blue, `   Power: ${payload.power}W (EXCEEDS 150W threshold)`);
    log(colors.red, `   Socket: Both Sockets (relay1 = 1, relay2 = 1)`);
    log(colors.yellow, '   → Server should emit "anomaly_alert" with "Both Sockets"');
  } catch (error) {
    log(colors.red, '❌ Error:', error.message);
  }
}

/**
 * Test Relay Endpoints
 */
async function testRelayEndpoints() {
  log(colors.cyan, '\n🔌 TEST 5: Relay Control Endpoints');
  log(colors.cyan, '═══════════════════════════════════════');

  const endpoints = [
    { path: '/api/relay/relay1/off', label: 'Turn OFF Socket 1' },
    { path: '/api/relay/relay1/on', label: 'Turn ON Socket 1' },
    { path: '/api/relay/relay2/off', label: 'Turn OFF Socket 2' },
    { path: '/api/relay/relay2/on', label: 'Turn ON Socket 2' },
    { path: '/api/relay/status', label: 'Get Relay Status' },
  ];

  for (const endpoint of endpoints) {
    try {
      const response = await fetch(`${SERVER_URL}${endpoint.path}`);
      const data = await response.json();

      log(colors.green, `✅ ${endpoint.label}`);
      log(colors.blue, `   Response: ${JSON.stringify(data)}`);
    } catch (error) {
      log(colors.red, `❌ ${endpoint.label}: ${error.message}`);
    }
  }
}

/**
 * Check Server Health
 */
async function checkServerHealth() {
  log(colors.cyan, '\n🏥 Server Health Check');
  log(colors.cyan, '═══════════════════════════════════════');

  try {
    const response = await fetch(`${SERVER_URL}/`);
    const text = await response.text();
    log(colors.green, `✅ Server is running`);
    log(colors.blue, `   Response: ${text}`);
  } catch (error) {
    log(colors.red, `❌ Cannot connect to server at ${SERVER_URL}`);
    log(colors.red, `   Error: ${error.message}`);
    log(colors.yellow, '\n   Make sure to start the server first:');
    log(colors.yellow, '   cd wattbuddy-server && npm start');
    process.exit(1);
  }
}

/**
 * Main Test Suite
 */
async function runAllTests() {
  log(colors.cyan, '\n╔════════════════════════════════════════════════════╗');
  log(colors.cyan, '║  🚨 ANOMALY ALERT SYSTEM - TEST SUITE 🚨           ║');
  log(colors.cyan, '╚════════════════════════════════════════════════════╝');

  await checkServerHealth();

  log(colors.yellow, '\n⏳ Running test scenarios...\n');

  // Add small delay between requests
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await testNormalOperation();

  await new Promise((resolve) => setTimeout(resolve, 1000));
  await testAnomalySocket1();

  await new Promise((resolve) => setTimeout(resolve, 1000));
  await testAnomalySocket2();

  await new Promise((resolve) => setTimeout(resolve, 1000));
  await testBothSocketsAnomaly();

  await new Promise((resolve) => setTimeout(resolve, 1000));
  await testRelayEndpoints();

  log(colors.cyan, '\n╔════════════════════════════════════════════════════╗');
  log(colors.cyan, '║  ✅ TEST SUITE COMPLETE ✅                        ║');
  log(colors.cyan, '╚════════════════════════════════════════════════════╝\n');

  log(colors.green, 'Expected Behavior:');
  log(colors.green, '  ✅ Tests 1 & 5: Normal data/relay endpoints work');
  log(colors.yellow, '  ⚠️  Tests 2, 3, 4: Should see "anomaly_alert" events');
  log(colors.yellow, '  📱 Watch your Flutter app screen for alert dialogs!');
  log(colors.yellow, '\n  Hint: Check server console for logs:');
  log(colors.yellow, '        🚨 [ANOMALY ALERT] Socket X - Power: XXXX W');
}

// Run tests
runAllTests().catch((error) => {
  log(colors.red, '❌ Test suite failed:', error.message);
  process.exit(1);
});
