import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// OS-level toast (real notification on Android, overlay elsewhere). Replaces
/// SnackBar per spec §4. Uses OS defaults so it reads on both themes.
void showToast(BuildContext context, String message) {
  Fluttertoast.showToast(
    msg: message,
    toastLength: Toast.LENGTH_SHORT,
    gravity: ToastGravity.BOTTOM,
    timeInSecForIosWeb: 2,
  );
}
