/// The C interface of rust/src/lib.rs, built by hook/build.dart. Every
/// call returns at once; one that takes time answers through the callback
/// given to [biInit] (see iroh.dart).
@DefaultAsset('package:bao_iroh/src/ffi.dart')
library;

import 'dart:ffi';

/// The callback's `status`: done, failed, gone, a log line.
const biOk = 0, biErr = 1, biEnd = 2, biLog = 3;

typedef BiCallback =
    Void Function(Int64 req, Int32 status, Pointer<Uint8> data, Size len, Int64 value);

@Native<Int32 Function(Pointer<NativeFunction<BiCallback>>)>(
  symbol: 'bi_init',
  isLeaf: true,
)
external int biInit(Pointer<NativeFunction<BiCallback>> callback);

@Native<Void Function(Pointer<Uint8>, Size)>(symbol: 'bi_free', isLeaf: true)
external void biFree(Pointer<Uint8> data, int len);

@Native<Void Function(Int64)>(symbol: 'bi_release', isLeaf: true)
external void biRelease(int handle);

@Native<Void Function(Int64, Pointer<Uint8>, Pointer<Uint8>, Size)>(
  symbol: 'bi_endpoint_bind',
  isLeaf: true,
)
external void biEndpointBind(
  int req,
  Pointer<Uint8> secret,
  Pointer<Uint8> config,
  int len,
);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_endpoint_info', isLeaf: true)
external void biEndpointInfo(int req, int handle);

@Native<Void Function(Int64, Int64, Int64)>(symbol: 'bi_endpoint_watch', isLeaf: true)
external void biEndpointWatch(int req, int handle, int seen);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_endpoint_accept', isLeaf: true)
external void biEndpointAccept(int req, int handle);

@Native<Void Function(Int64, Int64, Pointer<Uint8>, Size)>(
  symbol: 'bi_endpoint_connect',
  isLeaf: true,
)
external void biEndpointConnect(
  int req,
  int handle,
  Pointer<Uint8> args,
  int len,
);

@Native<Void Function(Int64)>(
  symbol: 'bi_endpoint_network_change',
  isLeaf: true,
)
external void biEndpointNetworkChange(int handle);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_endpoint_close', isLeaf: true)
external void biEndpointClose(int req, int handle);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_connection_open', isLeaf: true)
external void biConnectionOpen(int req, int handle);

@Native<Void Function(Int64, Int64)>(
  symbol: 'bi_connection_accept',
  isLeaf: true,
)
external void biConnectionAccept(int req, int handle);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_connection_info', isLeaf: true)
external void biConnectionInfo(int req, int handle);

@Native<Void Function(Int64, Int64)>(
  symbol: 'bi_connection_watch',
  isLeaf: true,
)
external void biConnectionWatch(int req, int handle);

@Native<Void Function(Int64, Int64)>(
  symbol: 'bi_connection_closed',
  isLeaf: true,
)
external void biConnectionClosed(int req, int handle);

@Native<Void Function(Int64, Uint32)>(
  symbol: 'bi_connection_close',
  isLeaf: true,
)
external void biConnectionClose(int handle, int code);

@Native<Void Function(Int64, Int64, Pointer<Uint8>, Size)>(
  symbol: 'bi_stream_send',
  isLeaf: true,
)
external void biStreamSend(int req, int handle, Pointer<Uint8> data, int len);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_stream_recv', isLeaf: true)
external void biStreamRecv(int req, int handle);

@Native<Void Function(Int64, Int64)>(symbol: 'bi_stream_finish', isLeaf: true)
external void biStreamFinish(int req, int handle);

@Native<Void Function(Int64)>(symbol: 'bi_stream_reset', isLeaf: true)
external void biStreamReset(int handle);
