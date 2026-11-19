import 'package:client/core/network/api_client.dart';
import 'package:dio/dio.dart';

/// Raised when the Admin dashboard cannot be read. [message] is safe to show.
class AdminDashboardException implements Exception {
  const AdminDashboardException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One section of the dashboard as the server sent it, with typed readers.
///
/// Money arrives as strings ("1234.50"), counts as ints (the API convention).
class DashboardSection {
  const DashboardSection(this._json);

  final Map<String, dynamic> _json;

  int count(String key) {
    final value = _json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  double money(String key) {
    final value = _json[key];
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String text(String key) => _json[key]?.toString() ?? '';

  bool flag(String key) => _json[key] == true;

  List<Map<String, dynamic>> rows(String key) => [
    for (final row in (_json[key] as List<dynamic>? ?? const []))
      if (row is Map<String, dynamic>) row,
  ];

  Map<String, dynamic> map(String key) =>
      (_json[key] as Map<String, dynamic>?) ?? const {};
}

/// One tab's figures and when the server computed them.
class DashboardSectionRead {
  const DashboardSectionRead({required this.asOf, required this.section});

  final DateTime? asOf;
  final DashboardSection section;
}

/// `GET /api/v1/reports/admin-dashboard/?section=<name>` (Admin only).
///
/// One read per tab, so a slow section never holds up the others.
class AdminDashboardService {
  AdminDashboardService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const path = '/api/v1/reports/admin-dashboard/';

  /// [name] is one of system, sales, inventory, bodega, finance.
  Future<DashboardSectionRead> fetchSection(String name) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        path,
        queryParameters: {'section': name},
      );
      final data = response.data;
      if (data == null) throw const FormatException('Empty answer.');
      final section = data[name];
      if (section is! Map<String, dynamic>) {
        throw FormatException('The dashboard has no "$name" section.');
      }
      return DashboardSectionRead(
        asOf: DateTime.tryParse('${data['as_of'] ?? ''}'),
        section: DashboardSection(section),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) {
        throw const AdminDashboardException(
          'Only an Admin can open this dashboard.',
        );
      }
      if (error.response == null) {
        throw const AdminDashboardException(
          'Cannot connect to the BuildPro server.',
        );
      }
      throw const AdminDashboardException('The dashboard could not be read.');
    } on FormatException catch (error) {
      throw AdminDashboardException(
        'The dashboard could not be read (${error.message}).',
      );
    }
  }
}
