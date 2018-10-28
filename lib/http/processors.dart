import 'dart:async';
import 'dart:io';

import 'multipart.dart';

abstract class UploadProcessor {
  static Map<String, UploadProcessor> map = {
    "sharex": new SharexProcessor(),
    "simple": new SimpleProcessor()
  };

  Future<List<int>> extractData(HttpRequest req);
}

class SharexProcessor extends SimpleProcessor {
  @override
  Future<List<int>> extractData(HttpRequest req) async {
    final boundary = req.headers.contentType.parameters['boundary'];

    if (boundary == null || boundary.isEmpty)
      return null;

    final parser = MultipartFileParser(await super.extractData(req), boundary, 10);

    if (parser.parts.length != 1)
      return null;

    var multipartFile = parser.parts.first;

    if (multipartFile.contentDisposition == null || multipartFile.contentType == null)
      return null; //Headers are wrong

    if (!multipartFile.contentDisposition.contains('name="image"'))
      return null; //Valid name not found

    if (boundary == null)
      return null;

    return multipartFile.data;
  }
}

class SimpleProcessor extends UploadProcessor {
  @override
  Future<List<int>> extractData(HttpRequest req) async {
    var data = <int>[];
    await req.forEach((streamData) => data.addAll(streamData));
    return data;
  }
}