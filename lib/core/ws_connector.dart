import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_connector_web.dart'
    if (dart.library.io) 'ws_connector_io.dart'
    as impl;

typedef WebSocketFactory = WebSocketChannel Function(
  Uri uri, {
  Map<String, String>? headers,
});

WebSocketChannel connectWebSocket(Uri uri, {Map<String, String>? headers}) =>
    impl.connectWebSocket(uri, headers: headers);
