import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hex/hex.dart';
import 'package:intl/intl.dart';

final logTimeFormat = new DateFormat('[dd.MM HH:mm:ss]');
final String chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
final List<int> pngMagicNumber = HEX.decode("89504e470d0a1a0a");
final Random random = Random.secure();

List<int> nextBytes(int len) {
  var data = <int>[];

  for (var i = 0; i < len; i++)
    data.add(random.nextInt(256));
  return data;
}

String nextChars(int len) {
  var buffer = new StringBuffer();

  for (var i = 0; i < len; i++)
    buffer.write(chars[random.nextInt(chars.length)]);
  return buffer.toString();
}

bool listEquals<T>(List<int> a, List<int> b) {
  if (a == null || b == null || a.length != b.length)
    return false;

  for (var i = 0; i < a.length; i++)
    if (a[i] != b[i]) return false;

  return true;
}

Future<List<T>> streamToList<T>(Stream<T> stream) async {
  List<T> list = [];
  await stream.forEach((t) => list.add(t));
  return list;
}

bool isPNGSimple(List<int> data) {
  if (data.length < pngMagicNumber.length) return false;
  return listEquals(data.sublist(0, pngMagicNumber.length), pngMagicNumber);
}

class CloudflareApiCall {
  String endpoint, key, mail, zone;
  dynamic body = {};

  Future<Map<String, dynamic>> call() async {
    endpoint = endpoint.replaceAll(":zone:", zone);

    final req = await HttpClient().postUrl(Uri.parse(endpoint))
      ..headers.set("X-Auth-Key", key)
      ..headers.set("X-Auth-Email", mail)
      ..write(jsonEncode(body));
    final resp = await req.close();

    dynamic jsonData;

    await resp
        .transform(utf8.decoder)
        .transform(json.decoder)
        .forEach((obj) => jsonData = obj);

    if (jsonData == null)
      print("Unable to read Cloudflare response. Status: ${resp.statusCode}");

    if (!(jsonData is Map<String, dynamic>))
      return null;

    return jsonData;
  }

}