import 'package:flutter/widgets.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/models/user.dart';

class AuthViewmodel extends ChangeNotifier{
  final AuthRepository repository;

  AuthViewmodel (
    this.repository
  );

  bool isLoading = false;
  User? user;
  String? error;



  Future<void> login(String email, String password) async{
    isLoading = true;
    error = null;

    notifyListeners();

    final result = await repository.login(email, password);

    if (result == null) {
      user = null;
      error = "Invalid email or password";
    } 
    else {
      user = result;
      error = null;
    }

    isLoading = false;

    notifyListeners();
  }
}