import 'package:shared_preferences/shared_preferences.dart';

import 'package:zc_bangumi/main.dart' as application;

void main() {
  SharedPreferences.setPrefix('mirror_smoke.');
  application.main();
}
