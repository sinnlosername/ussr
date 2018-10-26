import 'dart:async';
import 'dart:convert';
import 'dart:io';

import "config.dart";
import 'package:mongo_dart/mongo_dart.dart';
import "package:screenserver/http/http.dart";
import "util.dart" as util;
import "cli.dart" as cli;

final JsonEncoder jsonEncoder = new JsonEncoder.withIndent('  ');

ScreenConfig config;
Db db;

void start(bool iscli) async {
  config = ScreenConfig();
  db = new Db(config.mongoUrl);

  Directory.current = config.workDir;

  await db.open().catchError((e) {
    print("Unable to establish a database connection");
    print(e);
    exit(1);
  });

  if (iscli) {
    print("cli online");
    cli.start();
    return;
  }

  HttpServer.bind(config.host, config.port).then((server) {
    server.listen(onRequest, onError: (_, s) {
      print("Error while handling http request");
      print(s);
    });
  }, onError: (e) {
    print("Unable to start http server");
    print(e);
    exit(1);
  });

  print("Ready");
}

File findNextFile() {
  File file;

  while ((file = new File("${config.dataDir}/${util.nextChars(config.nameSize)}.png")).existsSync());
  file.createSync();

  return file;
}

class DatabaseImage {
  String name, owner, processor;
  BsonBinary key;
  DateTime creationDate, deletionDate;
  int size;

  static Future<DatabaseImage> load(String key, dynamic value) async {
    var res = await util.streamToList(db.collection("images").find({key: value}));
    if (res.isEmpty) return null;

    var map = res.first;
    return DatabaseImage()
      ..name = map["name"]
      ..owner = map["owner"]
      ..key = map["key"]
      ..creationDate = map["creationDate"]
      ..deletionDate = map["deleteDate"]
      ..size = map["size"]
      ..processor = map["processor"];
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "owner": owner,
      "key": key,
      "creationDate": creationDate,
      "deletionDate": deletionDate,
      "size": size,
      "processor": processor
    };
  }

  void save(bool insert) async {
    if (!insert)
      db.collection("images").update({"key": key}, toMap());
    else
      db.collection("images").insert(toMap());
  }
}

class DatabaseUser {
  String name;
  BsonBinary key;
  bool banned;

  static Future<DatabaseUser> load(String key, dynamic value) async {
    var res = await util.streamToList(db.collection("users").find({key: value}));
    if (res.isEmpty) return null;

    var map = res.first;
    return DatabaseUser()
      ..name = map["name"]
      ..key = map["key"]
      ..banned = map["banned"];
  }

  Map<String, dynamic> toMap() {
    return {"name": name, "key": key, "banned": banned};
  }

  void save(bool insert) async {
    if (!insert)
      db.collection("users").update({"key": key}, toMap());
    else
      db.collection("users").insert(toMap());
  }
}