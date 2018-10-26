import 'dart:io';

import "package:ussr/cli.dart" as cli;
import 'package:ussr/screenserver.dart' as screenserver;

main(List<String> arguments) async {
  bool isCli = !arguments.isEmpty && arguments.elementAt(0) == "cli";

  await screenserver.start(isCli);

  if (isCli) {
    await cli.executeCli(arguments.sublist(1).join(" "));
    exit(0);
  }
}
