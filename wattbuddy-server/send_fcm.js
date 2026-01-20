/*
  Usage:
    - Place your Firebase service account JSON at wattbuddy-server/serviceAccountKey.json
    - Set env var TARGET_TOKEN or pass token/message via CLI

  Example:
    node send_fcm.js --token=DEVICE_TOKEN --title="Hello" --body="Test message"
*/

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Simple CLI args parser (no extra deps required)
const rawArgs = process.argv.slice(2);
const argv = {};
rawArgs.forEach(arg => {
  if (arg.startsWith('--')) {
    const eq = arg.indexOf('=');
    if (eq === -1) {
      argv[arg.slice(2)] = true;
    } else {
      const key = arg.slice(2, eq);
      const val = arg.slice(eq + 1);
      argv[key] = val;
    }
  }
});

const serviceAccountPath = process.env.SERVICE_ACCOUNT_PATH || path.join(__dirname, 'serviceAccountKey.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error('Service account file not found at', serviceAccountPath);
  console.error('Set SERVICE_ACCOUNT_PATH env or place serviceAccountKey.json in wattbuddy-server/');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const token = argv.token || process.env.TARGET_TOKEN;
const title = argv.title || 'WattBuddy';
const body = argv.body || 'You have a new notification';
const data = argv.data ? JSON.parse(argv.data) : {};

if (!token) {
  console.error('No device token specified. Use --token or set TARGET_TOKEN env var.');
  process.exit(1);
}

const message = {
  token: token,
  notification: { title, body },
  data: data,
};

admin.messaging().send(message)
  .then((resp) => {
    console.log('Successfully sent message:', resp);
  })
  .catch((err) => {
    console.error('Error sending message:', err);
  });
