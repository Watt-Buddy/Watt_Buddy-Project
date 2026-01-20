// 📊 FEATURE 3: Live Real-Time Graph with WebSocket
const db = require('../db');

class RealtimeGraphService {
  static userConnections = new Map(); // Store WebSocket connections per user

  // Register user connection
  static registerUserConnection(userId, socket) {
    if (!this.userConnections.has(userId)) {
      this.userConnections.set(userId, []);
    }
    this.userConnections.get(userId).push(socket);
    console.log(`✅ User ${userId} connected to real-time graph. Total: ${this.userConnections.get(userId).length}`);
  }

  // Remove user connection
  static removeUserConnection(userId, socket) {
    const connections = this.userConnections.get(userId);
    if (connections) {
      const index = connections.indexOf(socket);
      if (index > -1) {
        connections.splice(index, 1);
      }
      if (connections.length === 0) {
        this.userConnections.delete(userId);
        console.log(`🔌 User ${userId} disconnected from real-time graph`);
      }
    }
  }

  // Broadcast real-time data to all connected clients for a user
  static broadcastLiveData(userId, data) {
    const connections = this.userConnections.get(userId);
    if (connections && connections.length > 0) {
      connections.forEach(socket => {
        socket.emit('live_data_update', {
          timestamp: new Date().toISOString(),
          ...data
        });
      });
      console.log(`📡 Broadcast live data to ${connections.length} clients for user ${userId}`);
    }
  }

  // Get live data for dashboard
  static async getLiveGraphData(userId, minutes = 60) {
    try {
      const startTime = new Date(Date.now() - minutes * 60 * 1000);

      const result = await db.query(
        `SELECT 
           recorded_at as timestamp,
           power_consumption as power,
           voltage,
           current,
           temperature,
           power_factor
         FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= $2
         ORDER BY recorded_at ASC`,
        [userId, startTime]
      );

      return result.rows;
    } catch (error) {
      console.error('❌ Error fetching live graph data:', error);
      return [];
    }
  }

  // Get comparison data (today vs yesterday vs week ago)
  static async getComparisonData(userId) {
    try {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const yesterday = new Date(today);
      yesterday.setDate(yesterday.getDate() - 1);
      const weekAgo = new Date(today);
      weekAgo.setDate(weekAgo.getDate() - 7);

      const result = await db.query(
        `SELECT 
           DATE(recorded_at) as date,
           EXTRACT(HOUR FROM recorded_at) as hour,
           AVG(power_consumption) as avg_power,
           MAX(power_consumption) as peak_power
         FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= $2
         GROUP BY DATE(recorded_at), EXTRACT(HOUR FROM recorded_at)
         ORDER BY date DESC, hour ASC`,
        [userId, weekAgo]
      );

      const grouped = {
        today: result.rows.filter(r => new Date(r.date).toDateString() === today.toDateString()),
        yesterday: result.rows.filter(r => new Date(r.date).toDateString() === yesterday.toDateString()),
        weekAgo: result.rows.filter(r => Math.abs(new Date(r.date) - weekAgo) < 24 * 60 * 60 * 1000),
      };

      return grouped;
    } catch (error) {
      console.error('❌ Error fetching comparison data:', error);
      throw error;
    }
  }
}

module.exports = RealtimeGraphService;
