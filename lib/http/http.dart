import 'dart:io';

import 'package:hex/hex.dart';
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:path/path.dart' as path;

import '../screenserver.dart' as ss;
import '../util.dart';
import 'processors.dart';

final requestRegex = RegExp("^\\/[\\+-]?[A-Za-z0-9]{1,${ss.config.nameSize}}(\\.png)?(\\/[a-fA-F0-9]{32})?\$");
final keyRegex = RegExp(r"[a-fA-F0-9]{32}");
final dateFormat = new DateFormat('dd.MM.yyyy HH:mm:ss');

void onRequest(HttpRequest req) async {
  try {
    await _onRequest(req);
  } catch (e, st) {
    print("Error while handling http request: ${req.uri.toString()}");
    print(e);
    print(st.toString());
  }
}

void _onRequest(HttpRequest req) async {
  if (req.uri.path == "/" || req.uri.path == "") {
    req.response
      ..redirect(Uri.parse("/index"), status: HttpStatus.movedTemporarily)
      ..close();
    return;
  }

  print("Request (${logTime()} ${getRealIP(req)}): ${req.uri.path}");

  if (req.uri.path == "/index")
    return handleIndex(req);

  if (req.uri.path == "/favicon.ico")
    return jsonResponse(req, HttpStatus.notFound, {"error": "No favicon"}, true);

  if (req.uri.path == "/feed")
    return handleUpload(req);

  var uripath = req.uri.path;

  if (requestRegex.firstMatch(uripath) != null) {
    String name = req.uri.pathSegments.first;
    String origName = name;
    RequestAction action = getAction(name);

    if (action != RequestAction.VIEW) {
      name = name.substring(1);

      if (req.uri.pathSegments.length <= 1)
        return errorResponse(req, HttpStatus.unauthorized, "Action request without key");
    }

    if (!name.endsWith(".png")) name += ".png";

    final Directory dataDir = new Directory("${ss.config.dataDir}");
    final File file = new File("${dataDir.path}/${name}");

    if (!file.existsSync()) {
      if (action == RequestAction.INFO) return await handleAction(action, req, null, null, false);

      return errorResponse(req, HttpStatus.notFound, "File not found");
    }

    if (!path.isWithin(dataDir.absolute.path, file.absolute.path))
      return errorResponse(req, HttpStatus.badRequest, "Security violation");

    if (action == RequestAction.VIEW) {
      req.response
        ..headers.set("Content-Type", "image/png")
        ..headers.set("Cache-Control", ss.config.imageCacheHeader);

      await file.openRead().pipe(req.response);
      req.response.close();

      return print("Request (${logTime()} ${getRealIP(req)}) - View: $origName");
    }

    return await handleAction(action, req, name, file, true);
  }

  errorResponse(req, HttpStatus.notFound, "Unhandleable");
}

void handleUpload(HttpRequest req) async {
  if (req.method != "POST")
    return errorResponse(req, HttpStatus.methodNotAllowed, "This route only accepts POST requests");

  if (req.headers.contentLength > ss.config.sizeLimit)
    return errorResponse(req, HttpStatus.badRequest, "Payload too big");

  var keyStr = req.headers.value("USSR-Key");
  if (keyStr == null || !keyRegex.hasMatch(keyStr))
    return errorResponse(req, HttpStatus.unauthorized, "Invalid or no key provided");

  var user = await ss.DatabaseUser.load("key", new BsonBinary.from(HEX.decode(keyStr)));
  if (user == null) return errorResponse(req, HttpStatus.forbidden, "Invalid key");

  if (user.banned) return errorResponse(req, HttpStatus.forbidden, "Your account is banned");

  var processorName = req.headers.value("USSR-Processor");
  var processor = UploadProcessor.map[processorName];

  if (processor == null) return errorResponse(req, HttpStatus.badRequest, "Processor not found");

  var data = await processor.extractData(req);

  if (data == null)
    return errorResponse(req, 422, "Unable to process image");

  if (!isPNGSimple(data))
    return errorResponse(req, HttpStatus.badRequest, "Image must be a png file");

  var file = ss.findNextFile();
  var name = file.path
      .substring(0, file.path.length - 4)
      .split("/")
      .last;
  var dbimage = ss.DatabaseImage();

  if (name.contains("/") || name.contains("\\")) throw new Exception("path err critical");

  file.writeAsBytes(data);

  dbimage.name = name;
  dbimage.owner = user.name;
  dbimage.processor = processorName;
  dbimage.key = new BsonBinary.from(nextBytes(16));
  dbimage.creationDate = DateTime.now().toUtc();
  dbimage.size = data.length;
  dbimage.save(true);

  print("Request (${logTime()} ${getRealIP(req)}) - User '${user.name}' uploaded '$name' (${data
      .length}B) using '$processorName'");
  return jsonResponse(req, HttpStatus.ok, makeInfoMap(dbimage, file.path
      .split("/")
      .last));
}

void handleAction(RequestAction action, HttpRequest req, String fileName, File file, bool exists) async {
  if (req.uri.pathSegments.length != 2) return errorResponse(req, HttpStatus.notFound, "File not found");

  var binkey = new BsonBinary.from(HEX.decode(req.uri.pathSegments[1]));
  var dbimage = await ss.DatabaseImage.load("key", binkey);

  if (dbimage.name + ".png" != fileName) return errorResponse(req, HttpStatus.forbidden, "Invalid key");

  if (exists && dbimage == null && action == RequestAction.INFO)
    return errorResponse(req, HttpStatus.notFound, "No information available");
  else if (dbimage == null)
    return errorResponse(req, HttpStatus.notFound, "File not found");

  if (action == RequestAction.DELETE) {
    file.delete();
    dbimage
      ..deletionDate = DateTime.now().toUtc()
      ..save(false);

    _clearCache(req, dbimage.name);

    print("Request (${logTime()} ${getRealIP(req)}) - Deleted: ${dbimage.name}");
    return jsonResponse(req, HttpStatus.ok, {"info": "Picture with id ${dbimage.name} was deleted"});
  }

  if (action == RequestAction.INFO) {
    print("Request (${logTime()} ${getRealIP(req)}) - Info: ${dbimage.name}");
    return jsonResponse(req, HttpStatus.ok, makeInfoMap(dbimage, fileName));
  }
}

void _clearCache(HttpRequest req, String name) async {
  if (!ss.config.cloudflare) return;

  final cfapi = CloudflareApiCall()
    ..endpoint = ss.config.cloudflareCacheEndpoint
    ..key = ss.config.cloudflareKey
    ..mail = ss.config.cloudflareMail
    ..zone = ss.config.cloudflareZone
    ..body = [
      "${req.uri.scheme}://${req.uri.host}/$name",
      "${req.uri.scheme}://${req.uri.host}/$name.png"
    ];

  final result = await cfapi.call();

  if (result == null)
    return;

  if (result["success"] == null || !result["success"])
    return print("Request (${logTime()} ${getRealIP(req)}) - Purge error, resp: ${ss.jsonEncoder.convert(result)}");

  print("Request (${logTime()} ${getRealIP(req)}) - Cache for $name purged successfully");
}

Map<String, dynamic> makeInfoMap(ss.DatabaseImage dbimage, String fileName) {
  return {
    "name": dbimage.name,
    "file": fileName,
    "owner": dbimage.owner,
    "size": dbimage.size,
    "sizeKB": "${dbimage.size / 1000}",
    "key": HEX.encode(dbimage.key.byteList),
    "processor": dbimage.processor,
    "creationDate": dateFormat.format(dbimage.creationDate.toLocal()),
    "deletionDate": dbimage.deletionDate == null ? null : dateFormat.format(dbimage.deletionDate.toLocal()),
  };
}

String getRealIP(HttpRequest req) {
  String ip = req.connectionInfo?.remoteAddress?.address;

  ip = ip == null ? "unresolvable" : ip;
  ip = req.headers.value("X-Forward-For") != null ? req.headers.value("X-Forward-For") : ip;
  ip = req.headers.value("X-Real-IP") != null ? req.headers.value("X-Real-IP") : ip;
  ip = req.headers.value("CF-Connecting-IP") != null ? req.headers.value("CF-Connecting-IP") : ip;

  return ip;
}

void handleIndex(HttpRequest req) {
  return jsonResponse(req, HttpStatus.ok, {
    "name": "USSR",
    "fullName": "Universal Screenshot Share Router",
    "author": "Florian",
    "contributers": "Steven (https://github.com/StevenKGER)",
    "message": "Welcome! You can view images at /<name> and upload images at /feed (requires a valid key)",
    "disclaimer": "Every user is responsible for their uploaded pictures",
    "api": {
      "/feed": {
        "description": "Feed the server with an image",
        "method": "POST",
        "required_headers": {
          "USSR-Key": {
            "description": "A valid api key",
            "format": "hex (32 chars)"
          },
          "USSR-Processor": {
            "description": "The processor which should be used for the body",
            "values": ["sharex"]
          }
        },
        "body": "Must contain a format which is handleable by the selected processor"
      },
      "/<name>": {
        "method": "GET",
        "description": "View an image",
        "parameters": {
          "name": {
            "description": "Name of the image",
            "format": "alphanumeric"
          }
        }
      },
      "/+<name>/<key>": {
        "method": "GET",
        "description": "Get metadata of the image",
        "parameters": {
          "name": {
            "description": "Name of the image",
            "format": "alphanumeric"
          },
          "key": {
            "description": "A valid image authorization key",
            "format": "hex (32 chars)"
          }
        }
      },
      "/-<name>/<key>": {
        "method": "GET",
        "description": "Delete an image",
        "parameters": {
          "name": {
            "description": "Name of the image",
            "format": "alphanumeric"
          },
          "key": {
            "description": "A valid image authorization key",
            "format": "hex (32 chars)"
          }
        }
      }
    }
  }, true);
}

void jsonResponse(HttpRequest req, int status, Map<String, dynamic> map, [cache = false]) {
  req.response
    ..statusCode = status
    ..headers.set("Content-Type", "application/json")
    ..headers.set("Cache-Control", "no-store")
    ..write(ss.jsonEncoder.convert(map))
    ..flush().whenComplete(() => req.response.close());
}

void errorResponse(HttpRequest req, int status, String error) {
  print("Request (${logTime()} ${getRealIP(req)}) - Error: $error");
  jsonResponse(req, status, {"error": error});
}

enum RequestAction { VIEW, INFO, DELETE }

RequestAction getAction(String s) {
  if (s.startsWith("+")) return RequestAction.INFO;
  if (s.startsWith("-")) return RequestAction.DELETE;
  return RequestAction.VIEW;
}
