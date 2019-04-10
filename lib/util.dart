import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hex/hex.dart';
import 'package:intl/intl.dart';
import "package:logger/default_logger.dart" as log;
import 'package:logger/formatters.dart';
import 'package:logger/logger.dart';

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

void optimizePNG(String optimizerPath, String file, logCtx) {
  if (optimizerPath == null || optimizerPath.isEmpty) return;

  try {
    Process.runSync(optimizerPath, ["-o1", "-q", file]);
    logCtx.info("Successfully optimazed PNG using oxipng");
  } catch (ex) {
    logCtx.info("Unable to optimize PNG using oxipng");
  }
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
      log.warning("Unable to read Cloudflare response. Status: ${resp.statusCode}");

    if (!(jsonData is Map<String, dynamic>))
      return null;

    return jsonData;
  }

}

class ConsoleHandler extends Handler {
  Formatter _formatter;

  ConsoleHandler(this._formatter);

  @override
  void call(Record record) {
    print(_formatter.call(record));
  }
}

class FileHandler extends Handler {
  Formatter _formatter;
  IOSink _sink;

  FileHandler(this._formatter, String file) {
    _sink = new File(file).openWrite(mode: FileMode.append);
  }

  @override
  void call(Record record) {
    _sink.writeln(_formatter.call(record));
  }

  @override
  Future<void> close() async {
    await super.close();
    await _sink.flush();
    await _sink.close();
  }
}

class CustomFormatter extends Formatter {
  DateFormat dateFormat = new DateFormat("yy.MM.dd HH:mm:ss");

  @override
  String call(Record record) {
    var fields = record.fields != null ? record.fields.map((f) => "${f.key}:'${f.value}'").join("  ") : "";
    return "[${dateFormat.format(record.time)} ${record.level.name.toUpperCase()}] ${record.message}  $fields";
  }
}
