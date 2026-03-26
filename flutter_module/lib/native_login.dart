import 'package:flutter/services.dart';

class NativeLogin {
  static const MethodChannel _channel = MethodChannel("pos/native");

  static Future<void> openLogin() async {
    await _channel.invokeMethod("openLogin");
  }
}