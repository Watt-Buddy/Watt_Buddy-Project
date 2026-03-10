const LOCAL_URL = 'http://localhost:4000/api/esp32/data';
const LAN_URL = 'http://192.168.184.49:4000/api/esp32/data';

const testData = {
  voltage: 2.9,
  current: 0.0,
  power: 0.0,
  energy: 2.1715,
  relay1: 1,
  relay2: 1,
  dominantRelay: 0,
  dominantPower: 0.0,
  userId: '11'
};

async function postJson(url, payload, timeoutMs = 5000) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal
    });

    const raw = await response.text();
    let data = raw;
    try {
      data = JSON.parse(raw);
    } catch (_) {
      // Keep plain text response if not JSON.
    }

    return { ok: response.ok, status: response.status, data };
  } finally {
    clearTimeout(timeout);
  }
}

async function testEndpoint() {
  try {
    console.log('Testing localhost...');
    const localResponse = await postJson(LOCAL_URL, testData);
    if (localResponse.ok) {
      console.log('✅ Localhost POST success:', localResponse.data);
    } else {
      console.error(`❌ Localhost POST failed: HTTP ${localResponse.status}`, localResponse.data);
    }
  } catch (error) {
    if (error.name === 'AbortError') {
      console.error('❌ Localhost failed: Request timed out');
    } else {
      console.error('❌ Localhost failed:', error.message);
    }
  }

  try {
    console.log('\nTesting with local IP...');
    const ipResponse = await postJson(LAN_URL, testData);
    if (ipResponse.ok) {
      console.log('✅ Local IP POST success:', ipResponse.data);
    } else {
      console.error(`❌ Local IP POST failed: HTTP ${ipResponse.status}`, ipResponse.data);
    }
  } catch (error) {
    if (error.name === 'AbortError') {
      console.log('🔴 Local IP timed out - network path blocked or server unreachable');
    } else {
      console.log('🔴 Local IP failed:', error.message);
    }
  }
}

testEndpoint();

