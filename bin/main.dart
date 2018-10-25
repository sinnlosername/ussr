import 'package:screenserver/screenserver.dart' as screenserver;

main(List<String> arguments) {
  screenserver.start(arguments.contains("cli"));
}
