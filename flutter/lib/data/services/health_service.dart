import 'package:client/core/network/api_client.dart';

class HealthService {
  /// Calls GET /api/health/ to verify backend connectivity.
  Future<Map<String, dynamic>> ping() async {
    final response = await ApiClient.instance.get('/api/health/');
    return Map<String, dynamic>.from(response.data as Map);
  }
}