import 'dart:convert';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:path/path.dart' as path;
import '../util.dart';
import '../screenserver.dart' as ss;
import 'package:hex/hex.dart';
import 'package:intl/intl.dart';
import 'processors.dart';

final requestRegex = RegExp("^\\/[\\+-]?[A-Za-z0-9]{1,${ss.config.nameSize}}(\\.png)?(\\/[a-fA-F0-9]{32})?\$");
final keyRegex = RegExp(r"[a-fA-F0-9]{32}");
final dateFormat = new DateFormat('dd.MM.yyyy HH:mm:ss');

void onRequest(HttpRequest req) async {
  print("Request (${req.connectionInfo.remoteAddress.address}): ${req.uri.path}");

  if (req.uri.path == "") {
    req.response
      ..redirect(Uri.parse("/index"), status: HttpStatus.movedTemporarily)
      ..close();
    return;
  }

  if (req.uri.path == "/index") return handleIndex(req);
  if (req.uri.path == "/upload") return handleUpload(req);

  var uripath = req.uri.path;

  if (requestRegex.firstMatch(uripath) != null) {
    String name = req.uri.pathSegments.first;
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
      req.response.headers.set("Content-Type", "image/png");
      await file.openRead().pipe(req.response);
      req.response.close();
      return;
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
  var name = file.path.substring(0, file.path.length - 4).split("/").last;
  var dbimage = ss.DatabaseImage();

  if (name.contains("/") || name.contains("\\")) throw new Exception("path err critical");

  file.writeAsBytes(data);

  dbimage.name = name;
  dbimage.owner = user.name;
  dbimage.uploader = processorName;
  dbimage.key = new BsonBinary.from(nextBytes(16));
  dbimage.creationDate = DateTime.now().toUtc();
  dbimage.size = data.length;
  dbimage.save(true);

  jsonResponse(req, HttpStatus.ok, makeInfoMap(dbimage, file.path.split("/").last));
}

void handleAction(RequestAction action, HttpRequest req, String fileName, File file, bool exists) async {
  if (req.uri.pathSegments.length != 2) return errorResponse(req, HttpStatus.notFound, "File not found");

  var binkey = new BsonBinary.from(HEX.decode(req.uri.pathSegments[1]));
  var dbimage = await ss.DatabaseImage.load("key", binkey);

  if (dbimage.name + ".png" != fileName) return errorResponse(req, HttpStatus.forbidden, "Invalid key");

  if (exists && dbimage == null && action == RequestAction.INFO)
    return errorResponse(req, HttpStatus.notFound, "No information available");
  else if (dbimage == null) return errorResponse(req, HttpStatus.notFound, "File not found");

  if (action == RequestAction.DELETE) {
    file.deleteSync();
    dbimage
      ..deletionDate = DateTime.now().toUtc()
      ..save(false);

    return jsonResponse(req, HttpStatus.ok, {"info": "Picture with id ${dbimage.name} was deleted"});
  }

  if (action == RequestAction.INFO) {
    return jsonResponse(req, HttpStatus.ok, makeInfoMap(dbimage, fileName));
  }
}

Map<String, dynamic> makeInfoMap(ss.DatabaseImage dbimage, String fileName) {
  return {
    "name": dbimage.name,
    "file": fileName,
    "owner": dbimage.owner,
    "size": dbimage.size,
    "sizeKb": "${dbimage.size / 1000} KB",
    "key": HEX.encode(dbimage.key.byteList),
    "uploader": dbimage.uploader,
    "creationDate": dateFormat.format(dbimage.creationDate.toLocal()),
    "deletionDate": dbimage.deletionDate == null ? null : dateFormat.format(dbimage.deletionDate.toLocal()),
  };
}

void handleIndex(HttpRequest req) {
  req.response
    ..write("Pong")
    ..close();
}

void jsonResponse(HttpRequest req, int status, Map<String, dynamic> map) {
  req.response
    ..statusCode = status
    ..headers.set("Content-Type", "application/json")
    ..write(jsonEncode(map))
    ..close();
  jsonEncode(map);
}

void errorResponse(HttpRequest req, int status, String error) {
  jsonResponse(req, status, {"error": error});
}

enum RequestAction { VIEW, INFO, DELETE }

RequestAction getAction(String s) {
  if (s.startsWith("+")) return RequestAction.INFO;
  if (s.startsWith("-")) return RequestAction.DELETE;
  return RequestAction.VIEW;
}
