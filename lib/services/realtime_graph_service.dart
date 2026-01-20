import 'api_service.dart';

class RealtimeGraphService {
  // 📊 Get live graph data via HTTP
  static Future<List<Map<String, dynamic>>?> getLiveGraphData(
    String userId, {
    int minutes = 60,
  }) async {
    try {
      final data = await ApiService.get(
        '/graph/live/$userId?minutes=$minutes',
      );

      if (data['success'] == true && data['graphData'] != null) {
        return List<Map<String, dynamic>>.from(data['graphData']);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching live graph: $e');
      return null;
    }
  }

  // Get comparison data (today vs yesterday vs week ago)
  static Future<Map<String, dynamic>?> getComparisonData(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/graph/comparison/$userId',
      );

      if (data['success'] == true) {
        return {
          'today': data['today'] ?? [],
          'yesterday': data['yesterday'] ?? [],
          'weekAgo': data['weekAgo'] ?? [],
        };
      }
      return null;
    } catch (e) {
      print('❌ Error fetching comparison: $e');
      return null;
    }
  }

  // Format time series data for graph display
  static List<Map<String, dynamic>> formatForChart(
    List<Map<String, dynamic>> rawData,
  ) {
    return rawData.map((point) {
      return {
        'time': point['timestamp']?.toString().split('T')[1] ?? '00:00',
        'power': (point['power'] ?? 0).toDouble(),
        'voltage': (point['voltage'] ?? 0).toDouble(),
        'current': (point['current'] ?? 0).toDouble(),
        'timestamp': point['timestamp'],
      };
    }).toList();
  }

  // Calculate statistics from data points
  static Map<String, double> calculateStats(
    List<Map<String, dynamic>> data,
  ) {
    if (data.isEmpty) {
      return {
        'avg': 0,
        'max': 0,
        'min': 0,
        'current': 0,
      };
    }

    final powers = data.map((p) => (p['power'] ?? 0).toDouble()).toList();
    final avg = powers.reduce((a, b) => a + b) / powers.length;
    final max = powers.reduce((a, b) => a > b ? a : b);
    final min = powers.reduce((a, b) => a < b ? a : b);
    final current = powers.last;

    return {
      'avg': avg,
      'max': max,
      'min': min,
      'current': current,
    };
  }
}
