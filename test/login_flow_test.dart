import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
void main(){test('authentication state keys can be restored',() async {SharedPreferences.setMockInitialValues({'remux_server_url':'https://media.example.com','remux_access_token':'token','remux_user_id':'user'});final p=await SharedPreferences.getInstance();expect(p.getString('remux_server_url'),'https://media.example.com');expect(p.getString('remux_access_token'),'token');expect(p.getString('remux_user_id'),'user');});}
