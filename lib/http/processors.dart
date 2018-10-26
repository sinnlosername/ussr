import 'dart:async';
import 'dart:io';

import 'package:mime/mime.dart';
import '../util.dart' as util;

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

    List<MimeMultipart> parts = await util.streamToList(req.transform(new MimeMultipartTransformer(boundary)));
    if (parts.isEmpty) return null;

    List<List<int>> files = await util.streamToList(parts.first);
    if (files.isEmpty) return null;

    return files.first;
  }
}

class SimpleProcessor extends UploadProcessor {
  @override
  Future<List<int>> extractData(HttpRequest req) async {
    return await req.first;
  }
}