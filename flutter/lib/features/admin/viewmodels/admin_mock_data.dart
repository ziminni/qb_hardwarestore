import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';

class AdminMockData {
  const AdminMockData._();

  static const users = [
    User(
      id: 1,
      username: 'admin',
      email: 'admin@queenbuilders.local',
      fullName: 'System Administrator',
      role: Role(id: 1, name: 'admin', displayName: 'Administrator'),
    ),
    User(
      id: 2,
      username: 'maria.santos',
      email: 'maria.santos@queenbuilders.local',
      fullName: 'Maria Santos',
      role: Role(id: 2, name: 'inventory', displayName: 'Inventory Staff'),
    ),
    User(
      id: 3,
      username: 'angela.cruz',
      email: 'angela.cruz@queenbuilders.local',
      fullName: 'Angela Cruz',
      role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
      isActive: false,
    ),
  ];

  static const requisitions = [
    ['REQ-1048', 'Site A', 'Maria Santos', '12 items', 'Pending'],
    ['REQ-1047', 'Site B', 'Joshua Reyes', '8 items', 'Approved'],
    ['REQ-1046', 'Main Store', 'Angela Cruz', '4 items', 'Released'],
  ];

  static const auditLogs = [
    ['10:42 AM', 'Maria Santos', 'LOGIN', 'Signed in at POS Terminal 02'],
    ['10:18 AM', 'Joshua Reyes', 'STOCK_UPDATE', 'Updated PVC Pipe stock'],
    ['9:47 AM', 'Administrator', 'USER_UPDATE', 'Changed staff account role'],
  ];

  static const reportTypes = [
    'Sales summary',
    'Inventory valuation',
    'Stock movement',
    'Requisition history',
  ];

  static const storeName = 'Queen Builders';
  static const storeEmail = 'admin@queenbuilders.local';
  static const storePhone = '+63 900 000 0000';
}
