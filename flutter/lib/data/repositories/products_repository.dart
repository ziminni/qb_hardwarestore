import 'package:client/data/services/products_service.dart';

/// The repository layer between the inventory store and the products API.
///
/// It exists to keep the map's one-data-path invariant intact —
/// `View → ViewModel → Repository → Service → ApiClient` — so a viewmodel never
/// talks to Dio, and swapping the transport later touches this file rather than
/// every caller. Same shape as [AuthRepository].
class ProductsRepository {
  ProductsRepository(this.service);

  final ProductsService service;

  Future<ProductsSnapshot> loadCatalogue() => service.fetchCatalogue();
}
