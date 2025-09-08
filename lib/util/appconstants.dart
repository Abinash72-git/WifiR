import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'WifiR';

  //API URL Constants
  // static const String BASE_URL = 'https://new.dev-healthplanner.xyz/api/'; //Dev
  static const String BASE_URL = 'https://fulupostore.tsitcloud.com/';
  static const String baseUrlImg = 'https://fulupostore.tsitcloud.com/';
  //static const String baseUrlImg = 'https://fulupo.selfietoons.com/';

  // static final String BASE_URL = AppConfig.instance.baseUrl;
  static final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  static Map<String, String> headers = {
    //"X-API-KEY": "OpalIndiaKeysinUse",
    'Charset': 'utf-8',
    'Accept': 'application/json',
  };
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();

  static const String token = 'token';

 static const String register='is_registered';
}
