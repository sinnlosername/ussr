import 'dart:io';

import 'package:hex/hex.dart';
import 'package:intl/intl.dart';
import "package:logger/default_logger.dart" as log;
import 'package:logger/logger.dart' show Interface;
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
    log.error("Error while handling http request: ${req.uri.toString()}");
    log.error(e);
    log.error(st.toString());
  }
}

void _onRequest(HttpRequest req) async {
  if (req.uri.path == "/" || req.uri.path == "") {
    req.response
      ..redirect(Uri.parse("/index"), status: HttpStatus.movedTemporarily)
      ..close();
    return;
  }

  var logCtx = (log.bind()
    ..string("path", req.uri.path)
    ..string("ip", getRealIP(req))
    ..string("country", getCountry(req))
  ).build();

  logCtx.info("Incoming request");

  if (req.uri.path == "/index")
    return handleIndex(req);

  if (req.uri.path == "/favicon.ico")
    return jsonResponse(req, HttpStatus.notFound, {"error": "No favicon"}, true);

  if (req.uri.path == "/feed")
    return handleUpload(req, logCtx);

  var uripath = req.uri.path;

  if (requestRegex.firstMatch(uripath) != null) {
    String name = req.uri.pathSegments.first;
    String origName = name;
    RequestAction action = getAction(name);

    if (action != RequestAction.VIEW) {
      name = name.substring(1);

      if (req.uri.pathSegments.length <= 1)
        return errorResponse(req, HttpStatus.unauthorized, "Action request without key", logCtx);
    }

    if (!name.endsWith(".png")) name += ".png";

    final Directory dataDir = new Directory("${ss.config.dataDir}");
    final File file = new File("${dataDir.path}/${name}");

    if (!file.existsSync()) {
      if (action == RequestAction.INFO) return await handleAction(action, req, null, null, false, logCtx);

      return errorResponse(req, HttpStatus.notFound, "File not found", logCtx);
    }

    if (!path.isWithin(dataDir.absolute.path, file.absolute.path))
      return errorResponse(req, HttpStatus.badRequest, "Security violation", logCtx);

    if (action == RequestAction.VIEW) {
      req.response
        ..headers.set("Content-Type", "image/png")
        ..headers.set("Cache-Control", ss.config.imageCacheHeader);

      await file.openRead().pipe(req.response);
      req.response.close();


      return logCtx.info("View $origName");
    }

    return await handleAction(action, req, name, file, true, logCtx);
  }

  errorResponse(req, HttpStatus.notFound, "Unhandleable", logCtx);
}

void handleUpload(HttpRequest req, Interface logCtx) async {
  if (req.method != "POST")
    return errorResponse(req, HttpStatus.methodNotAllowed, "This route only accepts POST requests", logCtx);

  if (req.headers.contentLength > ss.config.sizeLimit)
    return errorResponse(req, HttpStatus.badRequest, "Payload too big", logCtx);

  var keyStr = req.headers.value("USSR-Key");
  if (keyStr == null || !keyRegex.hasMatch(keyStr))
    return errorResponse(req, HttpStatus.unauthorized, "Invalid or no key provided", logCtx);

  var user = await ss.DatabaseUser.load("key", new BsonBinary.from(HEX.decode(keyStr)));
  if (user == null) return errorResponse(req, HttpStatus.forbidden, "Invalid key", logCtx);

  if (user.banned) return errorResponse(req, HttpStatus.forbidden, "Your account is banned", logCtx);

  var processorName = req.headers.value("USSR-Processor");
  var processor = UploadProcessor.map[processorName];

  if (processor == null) return errorResponse(req, HttpStatus.badRequest, "Processor not found", logCtx);

  var data = await processor.extractData(req);

  if (data == null)
    return errorResponse(req, 422, "Unable to process image", logCtx);

  if (!isPNGSimple(data))
    return errorResponse(req, HttpStatus.badRequest, "Image must be a png file", logCtx);

  var file = ss.findNextFile();
  var name = file.path
      .substring(0, file.path.length - 4)
      .split("/")
      .last;
  var dbimage = ss.DatabaseImage();

  if (name.contains("/") || name.contains("\\")) throw new Exception("path err critical");

  file.writeAsBytesSync(data);

  optimizePNG(ss.config.optiPngPath, file.absolute.path, logCtx);

  dbimage.name = name;
  dbimage.owner = user.name;
  dbimage.processor = processorName;
  dbimage.key = new BsonBinary.from(nextBytes(16));
  dbimage.creationDate = DateTime.now().toUtc();
  dbimage.size = file.lengthSync();
  dbimage.save(true);

  var saved = (data.length - dbimage.size);
  var savedPerc = (saved * 100 / data.length).round();

  logCtx.info("User ${user.name} uploaded $name (${data.length}B, compressed $savedPerc%) using $processorName");
  return jsonResponse(req, HttpStatus.ok, makeInfoMap(dbimage, file.path.split("/").last));
}

void handleAction(RequestAction action, HttpRequest req, String fileName, File file, bool exists, Interface logCtx) async {
  if (req.uri.pathSegments.length != 2) return errorResponse(req, HttpStatus.notFound, "File not found", logCtx);

  var binkey = new BsonBinary.from(HEX.decode(req.uri.pathSegments[1]));
  var dbimage = await ss.DatabaseImage.load("key", binkey);

  if (dbimage.name + ".png" != fileName) return errorResponse(req, HttpStatus.forbidden, "Invalid key", logCtx);

  if (exists && dbimage == null && action == RequestAction.INFO)
    return errorResponse(req, HttpStatus.notFound, "No information available", logCtx);
  else if (dbimage == null)
    return errorResponse(req, HttpStatus.notFound, "File not found", logCtx);

  if (action == RequestAction.DELETE) {
    file.delete();
    dbimage
      ..deletionDate = DateTime.now().toUtc()
      ..save(false);

    _clearCache(req, dbimage.name, logCtx);

    logCtx.info("Deleted ${dbimage.name}");
    return jsonResponse(req, HttpStatus.ok, {"info": "Picture with id ${dbimage.name} was deleted"});
  }

  if (action == RequestAction.INFO) {
    logCtx.info("Requested info of ${dbimage.name}");
    return jsonResponse(req, HttpStatus.ok, makeInfoMap(dbimage, fileName));
  }
}

void _clearCache(HttpRequest req, String name, Interface logCtx) async {
  if (!ss.config.cloudflare) return;

  final files = <String>[];

  ss.config.hosts.forEach((host) {
    files.add("$host/$name");
    files.add("$host/$name.png");
  });

  final cfapi = CloudflareApiCall()
    ..endpoint = ss.config.cloudflareCacheEndpoint
    ..key = ss.config.cloudflareKey
    ..mail = ss.config.cloudflareMail
    ..zone = ss.config.cloudflareZone
    ..body = {"files": files};

  final result = await cfapi.call();

  if (result == null)
    return;

  if (result["success"] == null || !result["success"])
    return logCtx.warning("Purge error, resp: ${ss.jsonEncoder.convert(result)}");

  logCtx.info("Cace for $name purged successfully");
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

void errorResponse(HttpRequest req, int status, String error, Interface logCtx) {
  logCtx.info("Returning error: $error");
  jsonResponse(req, status, {"error": error});
}

enum RequestAction { VIEW, INFO, DELETE }

RequestAction getAction(String s) {
  if (s.startsWith("+")) return RequestAction.INFO;
  if (s.startsWith("-")) return RequestAction.DELETE;
  return RequestAction.VIEW;
}

String getRealIP(HttpRequest req) {
  String ip = req.connectionInfo?.remoteAddress?.address;

  ip = ip == null ? "unresolvable" : ip;
  ip = req.headers.value("X-Forward-For") != null ? req.headers.value("X-Forward-For") : ip;
  ip = req.headers.value("X-Real-IP") != null ? req.headers.value("X-Real-IP") : ip;
  ip = req.headers.value("CF-Connecting-IP") != null ? req.headers.value("CF-Connecting-IP") : ip;

  return ip;
}

String getCountry(HttpRequest req) {
  final countryHeader = req.headers.value("CF-IPCountry");
  return countryHeader == null ? "" : " $countryHeader";
}
