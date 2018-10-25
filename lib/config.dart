import 'dart:io';

import 'package:safe_config/safe_config.dart';

class ScreenConfig extends Configuration {
  factory ScreenConfig() {
    final File file = new File("config.yml");

    if (!file.existsSync()) {
      file.createSync();
      print("Config file created, please configure it and restart the server");
      exit(0);
    }

    try {
      return ScreenConfig._internal(file);
    } catch (e) {
      print("Unable to read config.yml");
      exit(1);
      throw e; //Need to return/throw something
    }
  }

  ScreenConfig._internal(File file) : super.fromFile(file);

  String host = "127.0.0.1";
  int port = 8075;

  String workDir = "/my/file/home";

  @optionalConfiguration
  String dataDir = "data"; //Subdirectory of homeDir

  @optionalConfiguration
  String mongoUrl = "mongodb://localhost:27017/screenserver";

  @optionalConfiguration
  int sizeLimit = 1024 * 1024 * 3;

  int nameSize = 4;
}
