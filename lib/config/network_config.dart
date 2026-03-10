/// Centralized network configuration for WattBuddy
/// Update these values when connecting to different networks or backend servers
class NetworkConfig {
  /// ESP32 device IP address (update when switching networks)
  static const String ESP32_IP = '192.168.137.154';

  /// ESP32 web server port
  static const int ESP32_PORT = 80;

  /// Backend server IP address (update if backend on different machine)
  static const String BACKEND_IP = 'localhost';

  /// Backend server port
  static const int BACKEND_PORT = 4000;

  /// Construct ESP32 base URL
  static String get esp32BaseUrl => 'http://$ESP32_IP:$ESP32_PORT';

  /// Construct backend base URL for API calls
  static String get backendBaseUrl => 'http://$BACKEND_IP:$BACKEND_PORT/api';

  /// Get current configuration summary
  static String getConfigSummary() {
    return '''
ESP32 Configuration:
  IP: $ESP32_IP
  Port: $ESP32_PORT
  URL: $esp32BaseUrl

Backend Configuration:
  IP: $BACKEND_IP
  Port: $BACKEND_PORT
  API Base: $backendBaseUrl
''';
  }
}
