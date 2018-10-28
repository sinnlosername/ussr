import 'dart:convert';

import 'package:hex/hex.dart';

class MultipartFile {
  final List<int> sep = HEX.decode("0d0a");
  List<int> _data;
  Map<String, String> _headers = {};

  MultipartFile(this._data) {
    final headerData = <int>[];

    var end = 0;
    var endIndex;
    for (int i = 0; i < _data.length; i++) {
      if (i+1 == _data.length || i > 500) return; //500 => for security reasons
      if (_data[i] == 13 && data[i+1] == 10 && headerData.length > 0) end++;
      if (end > 1) {
        endIndex = i;
        break;
      }
      headerData.add(_data[i]);
    }

    while (endIndex + 1 < _data.length) {
      if (_data[endIndex] == 13 && _data[endIndex + 1] == 10) {
        endIndex += 2;
      } else break;
    }

    final headerStr = utf8.decode(headerData);
    headerStr.split("\x0d\x0a").forEach((line) {
      var keyValue = line.split(":");
      if (keyValue.length != 2) return;

      _headers[keyValue[0]] = keyValue[1].substring(1);
    });

    _data = _data.sublist(endIndex);
    _headers.forEach((a,b ) => print("$a | $b"));
  }


  List<int> get data => _data;
  String get contentDisposition => _headers["Content-Disposition"];
  String get contentType => _headers["Content-Type"];

}

class MultipartFileParser {
  List<MultipartFile> _parts = [];

  MultipartFileParser(List<int> input, String boundaryStr, int limit) {
    List<int> boundary = ascii.encode(boundaryStr);
    List<int> indexes = [];

    int i = 0;
    while ((i = _indexOf(input, boundary, i)) != -1) {
      indexes.add(i);
      i += boundary.length;
    }

    for (int j = 0; j < indexes.length - 1; j++){
      if (j > limit) break;
      _parts.add(MultipartFile(input.sublist(indexes[j] + boundary.length, indexes[j + 1])));
    }
  }

  List<MultipartFile> get parts => _parts;

  int _indexOf(List<int> array, List<int> target, int start) {
    if (target.length == 0) {
      return 0;
    }

    if (start > array.length)
      return -1;

    o:for (int i = start; i < array.length - target.length + 1; i++) {
      for (int j = 0; j < target.length; j++) {
        if (array[i + j] != target[j]) {
          continue o;
        }
      }
      return i;
    }
    return -1;
  }

}