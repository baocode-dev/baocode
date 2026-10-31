# bao_iroh

A thin Dart binding for [iroh](https://github.com/n0-computer/iroh): QUIC
connections dialled by public key, direct where the network lets two ends
meet, through a relay where it does not. Desktop and phone both use it for
the link between them (see `docs/mobile-link.md`).

- `rust/` — the Rust side, a C interface (`bi_*`) over an iroh endpoint.
  Messages are framed (u32 length + flags) and deflated when it pays.
- `hook/build.dart` — builds the library for the target being built
  (Dart native assets, `native_toolchain_rust`); needs `rustup`.
- `lib/` — `IrohEndpoint`, `IrohConnection`, `IrohStream`.

No n0 services are used: relays are the ones handed to `IrohEndpoint.bind`.

Tests run against real endpoints on loopback:

```sh
flutter test   # first run builds the Rust library (a few minutes)
cd rust && cargo test
```
