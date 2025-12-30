const admin = require('firebase-admin');
const pool = require('../db');
const path = require('path');
const fs = require('fs');

/**
 * PushNotificationService - Handle FCM push notifications
 * Sends real-time alerts to users mobile devices
 */
class PushNotificationService {
  static isInitialized = false;

  /**
   * Initialize Firebase Admin SDK
   */
  static initialize() {
    if (this.isInitialized) {
      return true;
    }

    try {
      const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT || 
        path.join(__dirname, '..', 'serviceAccountKey.json');

      if (!fs.existsSync(serviceAccountPath)) {
        console.warn(' Firebase service account file not found. Push notifications disabled.');
        console.warn('   Place serviceAccountKey.json in wattbuddy-server/ to enable push notifications');
        return false;
      }

      const serviceAccount = require(serviceAccountPath);

      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });

      this.isInitialized = true;
      console.log(' Firebase Admin SDK initialized for push notifications');
      return true;
    } catch (error) {
      console.error(' Failed to initialize Firebase Admin SDK:', error.message);
      return false;
    }
  }

  /**
   * Send anomaly alert push notification
   * @param {number} userId - User ID
   * @param {object} anomalyData - Anomaly detection data
   */
  static async sendAnomalyAlert(userId, anomalyData) {
    try {
      if (!this.isInitialized) {
        const initialized = this.initialize();
        if (!initialized) {
          console.log(' Push notifications not available - Firebase not initialized');
          return { success: false, error: 'Firebase not initialized' };
        }
      }

      // Get user FCM token and notification preferences
      const userQuery = await pool.query(
        'SELECT fcm_token, mobile_number, notification_preferences FROM users WHERE id = $1',
        [userId]
      );

      if (userQuery.rows.length === 0) {
        console.log(` User ${userId} not found`);
        return { success: false, error: 'User not found' };
      }

      const user = userQuery.rows[0];

      if (!user.fcm_token) {
        console.log(` User ${userId} has no FCM token registered`);
        return { success: false, error: 'No FCM token' };
      }

      // Check if user wants anomaly alerts
      const preferences = user.notification_preferences || {};
      if (preferences.anomaly_alerts === false) {
        console.log(` User ${userId} has disabled anomaly alerts`);
        return { success: false, error: 'Anomaly alerts disabled' };
      }

      // Prepare notification message
      const { currentPower, threshold, anomalySocket, message } = anomalyData;

      const notification = {
        title: ' Power Spike Alert',
        body: message || `High power usage detected: ${Math.round(currentPower)}W (threshold: ${Math.round(threshold)}W)`,
      };

      const data = {
        type: 'anomaly_alert',
        userId: userId.toString(),
        power: currentPower.toString(),
        threshold: threshold.toString(),
        socket: anomalySocket || 'Unknown',
        timestamp: new Date().toISOString(),
      };

      // Send FCM message
      const fcmMessage = {
        token: user.fcm_token,
        notification: notification,
        data: data,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'anomaly_alerts',
            priority: 'high',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
      };

      const response = await admin.messaging().send(fcmMessage);

      // Log notification
      await pool.query(
        `INSERT INTO push_notification_log 
         (user_id, fcm_token, notification_type, title, body, data, status) 
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, user.fcm_token, 'anomaly_alert', notification.title, notification.body, JSON.stringify(data), 'sent']
      );

      console.log(` Anomaly alert sent to user ${userId} (FCM response: ${response})`);

      return {
        success: true,
        messageId: response,
        userMobile: user.mobile_number,
      };
    } catch (error) {
      console.error(` Failed to send anomaly alert to user ${userId}:`, error);

      // Log failed notification
      try {
        await pool.query(
          `INSERT INTO push_notification_log 
           (user_id, fcm_token, notification_type, title, body, data, status, error_message) 
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
          [
            userId,
            'unknown',
            'anomaly_alert',
            ' Power Spike Alert',
            'Failed to send',
            JSON.stringify(anomalyData),
            'failed',
            error.message,
          ]
        );
      } catch (logError) {
        console.error('Failed to log notification error:', logError);
      }

      return { success: false, error: error.message };
    }
  }

  /**
   * Send emergency alert (very high power / system critical)
   * @param {number} userId - User ID
   * @param {object} alertData - Emergency alert data
   */
  static async sendEmergencyAlert(userId, alertData) {
    try {
      if (!this.isInitialized) {
        this.initialize();
      }

      const userQuery = await pool.query(
        'SELECT fcm_token, notification_preferences FROM users WHERE id = $1',
        [userId]
      );

      if (userQuery.rows.length === 0 || !userQuery.rows[0].fcm_token) {
        return { success: false, error: 'No FCM token' };
      }

      const user = userQuery.rows[0];
      const preferences = user.notification_preferences || {};

      if (preferences.emergency_alerts === false) {
        return { success: false, error: 'Emergency alerts disabled' };
      }

      const notification = {
        title: ' EMERGENCY: Critical Power Alert',
        body: alertData.message || 'Critical power usage detected! Immediate action required.',
      };

      const data = {
        type: 'emergency_alert',
        userId: userId.toString(),
        severity: 'critical',
        ...alertData,
        timestamp: new Date().toISOString(),
      };

      const fcmMessage = {
        token: user.fcm_token,
        notification: notification,
        data: data,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'emergency_alerts',
            priority: 'max',
            visibility: 'public',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              'content-available': 1,
            },
          },
        },
      };

      const response = await admin.messaging().send(fcmMessage);

      await pool.query(
        `INSERT INTO push_notification_log 
         (user_id, fcm_token, notification_type, title, body, data, status) 
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [userId, user.fcm_token, 'emergency_alert', notification.title, notification.body, JSON.stringify(data), 'sent']
      );

      console.log(` Emergency alert sent to user ${userId}`);

      return { success: true, messageId: response };
    } catch (error) {
      console.error(` Failed to send emergency alert:`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Update user FCM token
   * @param {number} userId - User ID
   * @param {string} fcmToken - FCM token from mobile device
   */
  static async updateFCMToken(userId, fcmToken) {
    try {
      await pool.query(
        'UPDATE users SET fcm_token = $1 WHERE id = $2',
        [fcmToken, userId]
      );

      console.log(` FCM token updated for user ${userId}`);
      return { success: true };
    } catch (error) {
      console.error(` Failed to update FCM token:`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Update user mobile number
   * @param {number} userId - User ID
   * @param {string} mobileNumber - Mobile number (for future SMS)
   */
  static async updateMobileNumber(userId, mobileNumber) {
    try {
      await pool.query(
        'UPDATE users SET mobile_number = $1 WHERE id = $2',
        [mobileNumber, userId]
      );

      console.log(` Mobile number updated for user ${userId}`);
      return { success: true };
    } catch (error) {
      console.error(` Failed to update mobile number:`, error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Get notification history for a user
   * @param {number} userId - User ID
   * @param {number} limit - Number of recent notifications to fetch
   */
  static async getNotificationHistory(userId, limit = 20) {
    try {
      const result = await pool.query(
        `SELECT notification_type, title, body, data, status, sent_at 
         FROM push_notification_log 
         WHERE user_id = $1 
         ORDER BY sent_at DESC 
         LIMIT $2`,
        [userId, limit]
      );

      return { success: true, notifications: result.rows };
    } catch (error) {
      console.error(' Failed to fetch notification history:', error);
      return { success: false, error: error.message };
    }
  }
}

module.exports = PushNotificationService;
