import 'dart:convert';
import 'dart:io';

import 'screenserver.dart' as ss;
import 'util.dart' as util;
import 'http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';

void start() async {
  while (true) {
    try {
      var line = stdin.readLineSync();
      await _onData(line);
    } catch (e) {
      await _onError(e);
    }
  }
}

void _onData(String line) async {
  var args = (line = line.toLowerCase()).split(" ");

  if (["stop", "quit", "exit", "q"].contains(line))
    return exit(0);

  if (line.startsWith("adduser") && args.length > 1) {
    if (await ss.DatabaseUser.load("name", args[1]) != null)
      return print("User already exists");

    print("Creating user");
    var dbimage = ss.DatabaseUser();

    dbimage.name = args[1];
    dbimage.key = new BsonBinary.from(util.nextBytes(16));
    dbimage.banned = false;
    dbimage.save(true);

    return print("User created");
  }

  if (line.startsWith("swapban") && args.length > 1) {
    var user = await ss.DatabaseUser.load("name", args[1]);

    if (user == null)
      return print("User doesnt exist");

    user.banned = !user.banned;
    user.save(false);

    return print("User is " + (user.banned ? "now banned" : "no longer banned"));
  }

  if (line.startsWith("info") && args.length > 1) {
    var image = await ss.DatabaseImage.load("name", args[1]);


    return print(ss.jsonEncoder.convert(http.makeInfoMap(image, image.name + ".png")));
  }

  print("Unkown command");
}

void _onError(var obj) {
  print("Cli error");
  print(obj);
}