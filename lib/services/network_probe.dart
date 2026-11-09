import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Predvolený port Codroid websocket servera.
const int kControllerPort = 9000;

/// Overí, či na `[ipAddress]:9000` počúva Codroid controller.
///
/// Pôvodná implementácia používala `dart:io` `Socket.connect`, čo na webe
/// neexistuje. WebSocket spojenie sa dá otvoriť všade rovnako, takže tento
/// helper funguje na Androide, iOS, desktope aj v prehliadači.
Future<bool> pingController(
  String ipAddress, {
  int port = kControllerPort,
  Duration timeout = const Duration(milliseconds: 1500),
}) async {
  if (ipAddress.trim().isEmpty) return false;

  WebSocketChannel? channel;
  try {
    channel = WebSocketChannel.connect(Uri.parse('ws://$ipAddress:$port'));
    await channel.ready.timeout(timeout);
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      await channel?.sink.close();
    } catch (_) {
      // Spojenie sa nepodarilo vytvoriť – nie je čo zatvárať.
    }
  }
}
