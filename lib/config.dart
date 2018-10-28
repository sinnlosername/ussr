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

  @optionalConfiguration
  String workDir = "";

  @optionalConfiguration
  String dataDir = "data"; //Subdirectory of homeDir

  @optionalConfiguration
  String mongoUrl = "mongodb://localhost:27017/ussr";

  @optionalConfiguration
  int sizeLimit = 1024 * 1024 * 3;

  @optionalConfiguration
  List<String> hosts = [];

  @optionalConfiguration
  int nameSize = 4;

  @optionalConfiguration
  bool cloudflare = false;

  @optionalConfiguration
  String cloudflareMail = "";

  @optionalConfiguration
  String cloudflareKey = "";

  @optionalConfiguration
  String cloudflareZone = "";

  @optionalConfiguration
  String cloudflareCacheEndpoint = "https://api.cloudflare.com/client/v4/zones/:zone:/purge_cache";

  @optionalConfiguration
  String imageCacheHeader = "public, max-age=15, s-maxage=3600";
}
