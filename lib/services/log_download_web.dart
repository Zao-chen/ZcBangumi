import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadLogText(String filename, String text) {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = objectUrl
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(objectUrl));
}
