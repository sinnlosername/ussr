import 'dart:async';
import 'dart:io';

import 'package:mime/mime.dart';

abstract class UploadProcessor {
  static Map<String, UploadProcessor> map = {
    "sharex": new SharexProcessor(),
    "simple": new SimpleProcessor()
  };

  Future<List<int>> extractData(HttpRequest req);
}

class SharexProcessor extends UploadProcessor {
  @override
  Future<List<int>> extractData(HttpRequest req) async {
    String boundary = req.headers.contentType.parameters['boundary'];

    if (boundary == null)
      return null;

    final parts = await req.transform(new MimeMultipartTransformer(boundary));
    final first = await parts.firstWhere((part) => true, orElse: null);

    if (first == null)
      return null;

    final data = <int>[];

    first.forEach((streamData) => data.addAll(streamData));

    return data;
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