import 'package:client/features/admin/viewmodels/catalogue_lists_viewmodel.dart';

/// The Admin Settings categories & suppliers panel with no server: empty lists,
/// nothing loaded. For tests of the OTHER settings cards.
class OfflineCatalogueLists extends CatalogueListsViewmodel {
  @override
  Future<void> load() async {}
}
