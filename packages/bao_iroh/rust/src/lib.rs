//! BaoCode's link transport for Dart: iroh endpoints, their connections,
//! and the framed streams on them, behind a small C interface.
//!
//! Dart holds integer handles; the objects are kept here. A call that
//! takes time is given a request number, and finishes by calling the
//! callback given to [bi_init] once, on some thread, with that number:
//! `status` [OK] (and `value`, a new handle where there is one, and `data`,
//! JSON or a message's bytes), [ERR] (`data`, what went wrong) or [END]
//! (the thing waited on is gone: `data`, why). `data` is this library's:
//! Dart copies it and gives it back with [bi_free].
//!
//! [bi_init] again (a hot restart) forgets every object, and calls for
//! what the old callback asked never come.

#![allow(clippy::missing_safety_doc)]

mod frame;
mod log;

use std::{
    collections::HashMap,
    net::{Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6},
    panic::AssertUnwindSafe,
    sync::{
        Arc, LazyLock, Mutex, OnceLock,
        atomic::{AtomicI64, Ordering},
    },
    time::Duration,
};

use futures_util::{FutureExt, StreamExt};
use iroh::{
    Endpoint, EndpointAddr, PublicKey, RelayConfig, RelayMap, RelayMode, RelayUrl, SecretKey,
    TransportAddr, Watcher,
    endpoint::{
        BindOpts, Connection, IdleTimeout, QuicTransportConfig, ReadExactError, RecvStream,
        SendStream, VarInt, presets,
    },
};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::sync::{mpsc, watch};

/// Done: `value` and `data` as the call says.
pub const OK: i32 = 0;
/// Failed: `data` says why.
pub const ERR: i32 = 1;
/// What was waited on is gone (closed, finished): `data` says why.
pub const END: i32 = 2;
/// Not an answer: a line for the log (`req` 0).
pub const LOG: i32 = 3;

/// How a call is answered (see the module's doc).
pub type Callback = extern "C" fn(req: i64, status: i32, data: *mut u8, len: usize, value: i64);

#[derive(Clone)]
enum Obj {
    Endpoint(Arc<EndpointObj>),
    Connection(Connection),
    Stream(Arc<StreamObj>),
}

struct EndpointObj {
    endpoint: Endpoint,
    alpn: Vec<u8>,
    /// Connections handshaken, as they come (if it takes them).
    incoming: tokio::sync::Mutex<mpsc::UnboundedReceiver<Connection>>,
}

struct StreamObj {
    /// What is to be written, in the order asked: one task writes it.
    out: mpsc::UnboundedSender<Out>,
    recv: tokio::sync::Mutex<RecvStream>,
    /// Set: a read under way, or asked for, gives up.
    stop_reading: watch::Sender<bool>,
    /// Set: what is not written yet is given up, and the stream reset.
    reset: watch::Sender<bool>,
}

/// A message to write (and the call to answer once written), or the end.
enum Out {
    Message(Vec<u8>, i64, u64),
    Finish(i64, u64),
}

struct Shared {
    generation: u64,
    callback: Option<Callback>,
    objects: HashMap<i64, Obj>,
}

static SHARED: LazyLock<Mutex<Shared>> = LazyLock::new(|| {
    Mutex::new(Shared {
        generation: 0,
        callback: None,
        objects: HashMap::new(),
    })
});

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

fn shared() -> std::sync::MutexGuard<'static, Shared> {
    SHARED.lock().unwrap_or_else(|e| e.into_inner())
}

fn runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("bao-iroh")
            .enable_all()
            .build()
            .expect("a tokio runtime")
    })
}

fn generation() -> u64 {
    shared().generation
}

/// Hands [data] to Dart, unless the callback it was asked under is gone.
fn deliver(generation: u64, req: i64, status: i32, data: Vec<u8>, value: i64) {
    let callback = {
        let shared = shared();
        if shared.generation != generation {
            return;
        }
        shared.callback
    };
    let Some(callback) = callback else { return };
    let (ptr, len) = leak(data);
    callback(req, status, ptr, len, value);
}

pub(crate) fn log_line(line: String) {
    let generation = generation();
    deliver(generation, 0, LOG, line.into_bytes(), 0);
}

fn leak(data: Vec<u8>) -> (*mut u8, usize) {
    if data.is_empty() {
        return (std::ptr::null_mut(), 0);
    }
    let boxed = data.into_boxed_slice();
    let len = boxed.len();
    (Box::into_raw(boxed) as *mut u8, len)
}

/// How a call ends, when not done.
enum Fail {
    Err(String),
    End(String),
}

type Done = Result<(Vec<u8>, i64), Fail>;

/// Runs [work] for [req]; its outcome goes to Dart.
fn spawn<F>(req: i64, work: F)
where
    F: Future<Output = Done> + Send + 'static,
{
    let generation = generation();
    runtime().spawn(async move {
        match AssertUnwindSafe(work).catch_unwind().await {
            Ok(done) => answer(generation, req, done),
            Err(_) => deliver(generation, req, ERR, b"panicked".to_vec(), 0),
        }
    });
}

/// Keeps [obj], if asked for under the callback there is now.
fn keep(generation: u64, obj: Obj) -> Option<i64> {
    let mut shared = shared();
    if shared.generation != generation {
        return None;
    }
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    shared.objects.insert(handle, obj);
    Some(handle)
}

fn get(handle: i64) -> Option<Obj> {
    shared().objects.get(&handle).cloned()
}

fn endpoint_of(handle: i64) -> Result<Arc<EndpointObj>, Fail> {
    match get(handle) {
        Some(Obj::Endpoint(endpoint)) => Ok(endpoint),
        _ => Err(Fail::End("no such endpoint".into())),
    }
}

fn connection_of(handle: i64) -> Result<Connection, Fail> {
    match get(handle) {
        Some(Obj::Connection(connection)) => Ok(connection),
        _ => Err(Fail::End("no such connection".into())),
    }
}

fn stream_of(handle: i64) -> Result<Arc<StreamObj>, Fail> {
    match get(handle) {
        Some(Obj::Stream(stream)) => Ok(stream),
        _ => Err(Fail::End("no such stream".into())),
    }
}

unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(ptr, len) }
    }
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn unhex32(text: &str) -> Result<[u8; 32], Fail> {
    let text = text.trim();
    if text.len() != 64 {
        return Err(Fail::Err(format!("not a key: {text}")));
    }
    let mut out = [0u8; 32];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&text[i * 2..i * 2 + 2], 16)
            .map_err(|_| Fail::Err(format!("not a key: {text}")))?;
    }
    Ok(out)
}

fn json_bytes(value: Value) -> Vec<u8> {
    serde_json::to_vec(&value).unwrap_or_default()
}

fn err<E: std::fmt::Display>(e: E) -> Fail {
    Fail::Err(e.to_string())
}

// --- Setup ----------------------------------------------------------------------

/// Takes [callback] for every answer from now on; what was kept before is
/// let go (its endpoints closed). 0.
#[unsafe(no_mangle)]
pub extern "C" fn bi_init(callback: Callback) -> i32 {
    log::install();
    let old = {
        let mut shared = shared();
        shared.generation += 1;
        shared.callback = Some(callback);
        std::mem::take(&mut shared.objects)
    };
    for obj in old.into_values() {
        if let Obj::Endpoint(endpoint) = obj {
            runtime().spawn(async move { endpoint.endpoint.close().await });
        }
    }
    0
}

/// Gives back what a callback was given.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bi_free(data: *mut u8, len: usize) {
    if data.is_null() || len == 0 {
        return;
    }
    drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, len)) });
}

/// Forgets [handle]: an endpoint or a connection is closed; a stream's read
/// under way ends, and what is not finished of it is let go.
#[unsafe(no_mangle)]
pub extern "C" fn bi_release(handle: i64) {
    let obj = shared().objects.remove(&handle);
    match obj {
        Some(Obj::Endpoint(endpoint)) => {
            runtime().spawn(async move { endpoint.endpoint.close().await });
        }
        // Calls still under way keep it: closed, it is let go with them.
        Some(Obj::Connection(connection)) => connection.close(VarInt::from_u32(0), b"released"),
        // Written to the end, then finished: only the reading stops.
        Some(Obj::Stream(stream)) => {
            stream.stop_reading.send_replace(true);
        }
        None => {}
    }
}

// --- Endpoints --------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BindConfig {
    alpn: String,
    #[serde(default)]
    relays: Vec<String>,
    /// The UDP port wanted (both IPv4 and IPv6); any free one if taken, or 0.
    #[serde(default)]
    port: u16,
    /// Direct connections (UDP); off, only relays (under test).
    #[serde(default = "yes")]
    ip: bool,
    /// Takes connections ([bi_endpoint_accept]).
    #[serde(default)]
    accept: bool,
    #[serde(default = "keep_alive")]
    keep_alive_ms: u64,
    #[serde(default = "idle_timeout")]
    idle_timeout_ms: u64,
}

fn yes() -> bool {
    true
}
fn keep_alive() -> u64 {
    5_000
}
fn idle_timeout() -> u64 {
    20_000
}

/// Binds an endpoint as the 32 bytes at [secret] (an ed25519 key's seed),
/// configured as the JSON at [config] (see [BindConfig]). Answered with
/// its handle, and `{"id"}`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bi_endpoint_bind(
    req: i64,
    secret: *const u8,
    config: *const u8,
    config_len: usize,
) {
    let secret = unsafe { bytes(secret, 32) }.to_vec();
    let config = unsafe { bytes(config, config_len) }.to_vec();
    spawn(req, async move {
        let secret: [u8; 32] = secret.try_into().map_err(|_| Fail::Err("no key".into()))?;
        let config: BindConfig = serde_json::from_slice(&config).map_err(err)?;
        let endpoint = match bind(&secret, &config, config.port).await {
            Ok(endpoint) => endpoint,
            // The port wanted is taken: any other.
            Err(_) if config.port != 0 => bind(&secret, &config, 0).await?,
            Err(e) => return Err(e),
        };
        let (sender, receiver) = mpsc::unbounded_channel();
        if config.accept {
            runtime().spawn(accept_loop(endpoint.clone(), sender));
        }
        if !config.relays.is_empty() {
            runtime().spawn(relay_watchdog(endpoint.clone()));
        }
        let id = hex(endpoint.id().as_bytes());
        let obj = Arc::new(EndpointObj {
            endpoint,
            alpn: config.alpn.into_bytes(),
            incoming: tokio::sync::Mutex::new(receiver),
        });
        let handle = keep(generation(), Obj::Endpoint(obj.clone())).ok_or_else(|| {
            let endpoint = obj.endpoint.clone();
            runtime().spawn(async move { endpoint.close().await });
            Fail::End("restarted".into())
        })?;
        Ok((json_bytes(json!({ "id": id })), handle))
    });
}

async fn bind(secret: &[u8; 32], config: &BindConfig, port: u16) -> Result<Endpoint, Fail> {
    let relays: RelayMap = config
        .relays
        .iter()
        .filter_map(|url| url.parse::<RelayUrl>().ok())
        .collect();
    let relay_mode = if relays.is_empty() {
        RelayMode::Disabled
    } else {
        RelayMode::Custom(relays)
    };
    let idle = IdleTimeout::try_from(Duration::from_millis(config.idle_timeout_ms)).map_err(err)?;
    let transport = QuicTransportConfig::builder()
        .keep_alive_interval(Duration::from_millis(config.keep_alive_ms))
        .max_idle_timeout(Some(idle))
        .build();
    let mut builder = Endpoint::builder(presets::Minimal)
        .secret_key(SecretKey::from_bytes(secret))
        .alpns(vec![config.alpn.clone().into_bytes()])
        .relay_mode(relay_mode)
        .transport_config(transport);
    if !config.ip {
        builder = builder.clear_ip_transports();
    } else if port != 0 {
        builder = builder
            .bind_addr(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, port))
            .map_err(err)?
            // IPv6 may not be there.
            .bind_addr_with_opts(
                SocketAddrV6::new(Ipv6Addr::UNSPECIFIED, port, 0, 0),
                BindOpts::default().set_is_required(false),
            )
            .map_err(err)?;
    }
    builder.bind().await.map_err(err)
}

async fn accept_loop(endpoint: Endpoint, sender: mpsc::UnboundedSender<Connection>) {
    while let Some(incoming) = endpoint.accept().await {
        let sender = sender.clone();
        runtime().spawn(async move {
            // One that never finishes its handshake holds up no other.
            if let Ok(Ok(connection)) =
                tokio::time::timeout(Duration::from_secs(20), incoming).await
            {
                let _ = sender.send(connection);
            }
        });
    }
}

/// When the home relay goes away iroh picks another only at its next
/// network report, 20 to 26 s on, and meanwhile no one reaches this end
/// through a relay. (`network_change` does not help: it looks only if the
/// interfaces changed.) A change to the relay map makes it report at once,
/// so the relay down is put in it again: after 3 s down, then less often
/// while it stays down.
async fn relay_watchdog(endpoint: Endpoint) {
    const FIRST: Duration = Duration::from_secs(3);
    let mut home = endpoint.home_relay_status();
    let mut wait = FIRST;
    // When to look again, while down. Status updates (each failed retry
    // has its own error) do not put it off.
    let mut kick: Option<tokio::time::Instant> = None;
    loop {
        let down: Vec<RelayUrl> = {
            let status = home.get();
            if status.iter().any(|s| s.is_connected()) {
                Vec::new()
            } else {
                status.iter().map(|s| s.url().clone()).collect()
            }
        };
        let down = (!down.is_empty()).then_some(down);
        if down.is_none() {
            wait = FIRST;
            kick = None;
        } else if kick.is_none() {
            kick = Some(tokio::time::Instant::now() + wait);
        }
        let at = kick.unwrap_or_else(tokio::time::Instant::now);
        tokio::select! {
            changed = home.updated() => if changed.is_err() { return },
            _ = endpoint.closed() => return,
            _ = tokio::time::sleep_until(at), if kick.is_some() => {
                for url in down.into_iter().flatten() {
                    endpoint.insert_relay(url.clone(), Arc::new(RelayConfig::from(url))).await;
                }
                wait = (wait * 2).min(Duration::from_secs(30));
                kick = None;
            }
        }
    }
}

fn endpoint_info(endpoint: &Endpoint) -> Value {
    let addr = endpoint.addr();
    let home: Vec<Value> = endpoint
        .home_relay_status()
        .get()
        .iter()
        .map(|status| {
            json!({
                "url": status.url().to_string(),
                "connected": status.is_connected(),
                "error": status.last_error().map(|e| e.to_string()),
                "denied": status.auth_denied_reason(),
            })
        })
        .collect();
    json!({
        "id": hex(endpoint.id().as_bytes()),
        "addrs": addr.ip_addrs().map(|a| a.to_string()).collect::<Vec<_>>(),
        "relays": addr.relay_urls().map(|u| u.to_string()).collect::<Vec<_>>(),
        "home": home,
        "bound": endpoint.bound_sockets().iter().map(|a| a.to_string()).collect::<Vec<_>>(),
    })
}

/// Where the endpoint can be reached now: `{"id", "addrs", "relays",
/// "home": [{"url", "connected", "error", "denied"}], "bound"}`.
#[unsafe(no_mangle)]
pub extern "C" fn bi_endpoint_info(req: i64, handle: i64) {
    spawn(req, async move {
        let obj = endpoint_of(handle)?;
        Ok((json_bytes(endpoint_info(&obj.endpoint)), 0))
    });
}

/// As [bi_endpoint_info], once something in it changed (or half a minute
/// went by); [END] once the endpoint is closed.
#[unsafe(no_mangle)]
pub extern "C" fn bi_endpoint_watch(req: i64, handle: i64) {
    spawn(req, async move {
        let obj = endpoint_of(handle)?;
        let endpoint = &obj.endpoint;
        let mut addr = endpoint.watch_addr();
        let mut home = endpoint.home_relay_status();
        tokio::select! {
            _ = addr.updated() => {}
            _ = home.updated() => {}
            _ = tokio::time::sleep(Duration::from_secs(30)) => {}
            _ = endpoint.closed() => return Err(Fail::End("closed".into())),
        }
        Ok((json_bytes(endpoint_info(endpoint)), 0))
    });
}

/// The next connection taken (its handshake done): its handle, and
/// `{"remote"}`. [END] once the endpoint is closed.
#[unsafe(no_mangle)]
pub extern "C" fn bi_endpoint_accept(req: i64, handle: i64) {
    spawn(req, async move {
        let obj = endpoint_of(handle)?;
        let connection = obj
            .incoming
            .lock()
            .await
            .recv()
            .await
            .ok_or_else(|| Fail::End("closed".into()))?;
        let remote = hex(connection.remote_id().as_bytes());
        let handle = keep(generation(), Obj::Connection(connection))
            .ok_or_else(|| Fail::End("restarted".into()))?;
        Ok((json_bytes(json!({ "remote": remote })), handle))
    });
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConnectArgs {
    id: String,
    #[serde(default)]
    relays: Vec<String>,
    #[serde(default)]
    addrs: Vec<String>,
    #[serde(default = "connect_timeout")]
    timeout_ms: u64,
}

fn connect_timeout() -> u64 {
    15_000
}

/// Connects to the endpoint the JSON at [args] says: `{"id", "relays",
/// "addrs", "timeoutMs"}`, every relay and address tried at once. Its
/// handle, and `{"remote"}`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bi_endpoint_connect(req: i64, handle: i64, args: *const u8, len: usize) {
    let args = unsafe { bytes(args, len) }.to_vec();
    spawn(req, async move {
        let obj = endpoint_of(handle)?;
        let args: ConnectArgs = serde_json::from_slice(&args).map_err(err)?;
        let id = PublicKey::from_bytes(&unhex32(&args.id)?).map_err(err)?;
        let mut parts = Vec::new();
        for url in &args.relays {
            if let Ok(url) = url.parse::<RelayUrl>() {
                parts.push(TransportAddr::Relay(url));
            }
        }
        for addr in &args.addrs {
            if let Ok(addr) = addr.parse::<SocketAddr>() {
                parts.push(TransportAddr::Ip(addr));
            }
        }
        if parts.is_empty() {
            return Err(Fail::Err("nowhere to reach it".into()));
        }
        let addr = EndpointAddr::from_parts(id, parts);
        let connection = tokio::time::timeout(
            Duration::from_millis(args.timeout_ms),
            obj.endpoint.connect(addr, &obj.alpn),
        )
        .await
        .map_err(|_| Fail::Err("timed out".into()))?
        .map_err(err)?;
        let remote = hex(connection.remote_id().as_bytes());
        let handle = keep(generation(), Obj::Connection(connection))
            .ok_or_else(|| Fail::End("restarted".into()))?;
        Ok((json_bytes(json!({ "remote": remote })), handle))
    });
}

/// The network changed (Wi-Fi to cellular, back from the background):
/// looked at again, paths tried again.
#[unsafe(no_mangle)]
pub extern "C" fn bi_endpoint_network_change(handle: i64) {
    if let Some(Obj::Endpoint(obj)) = get(handle) {
        runtime().spawn(async move { obj.endpoint.network_change().await });
    }
}

/// Closes the endpoint, and every connection on it.
#[unsafe(no_mangle)]
pub extern "C" fn bi_endpoint_close(req: i64, handle: i64) {
    spawn(req, async move {
        let obj = endpoint_of(handle)?;
        obj.endpoint.close().await;
        Ok((Vec::new(), 0))
    });
}

// --- Connections ------------------------------------------------------------------

fn stream_obj(send: SendStream, recv: RecvStream) -> Obj {
    let (out, queue) = mpsc::unbounded_channel();
    let (reset, reset_seen) = watch::channel(false);
    runtime().spawn(write_loop(send, queue, reset_seen));
    Obj::Stream(Arc::new(StreamObj {
        out,
        recv: tokio::sync::Mutex::new(recv),
        stop_reading: watch::channel(false).0,
        reset,
    }))
}

/// Writes [queue] to [send] in order, each message once deflated (here,
/// not on Dart's thread); finishes the stream once let go of.
async fn write_loop(
    mut send: SendStream,
    mut queue: mpsc::UnboundedReceiver<Out>,
    mut reset: watch::Receiver<bool>,
) {
    loop {
        let next = tokio::select! {
            biased;
            _ = reset.wait_for(|reset| *reset) => {
                let _ = send.reset(VarInt::from_u32(0));
                break;
            }
            next = queue.recv() => next,
        };
        match next {
            None => {
                let _ = send.finish();
                return;
            }
            Some(Out::Message(message, req, generation)) => {
                let written = match frame::encode(&message) {
                    Err(e) => Err(Fail::Err(e)),
                    Ok(frame) => tokio::select! {
                        written = send.write_all(&frame) => written.map_err(|e| Fail::End(e.to_string())),
                        _ = reset.wait_for(|reset| *reset) => Err(Fail::End("reset".into())),
                    },
                };
                answer(generation, req, written.map(|()| (Vec::new(), 0)));
            }
            Some(Out::Finish(req, generation)) => {
                let _ = send.finish();
                answer(generation, req, Ok((Vec::new(), 0)));
            }
        }
    }
    // Reset: what was asked to be written never will be.
    queue.close();
    while let Some(out) = queue.recv().await {
        let (Out::Message(_, req, generation) | Out::Finish(req, generation)) = out;
        answer(generation, req, Err(Fail::End("reset".into())));
    }
}

fn answer(generation: u64, req: i64, done: Done) {
    match done {
        Ok((data, value)) => deliver(generation, req, OK, data, value),
        Err(Fail::Err(message)) => deliver(generation, req, ERR, message.into_bytes(), 0),
        Err(Fail::End(message)) => deliver(generation, req, END, message.into_bytes(), 0),
    }
}

/// A new stream both ways: its handle.
#[unsafe(no_mangle)]
pub extern "C" fn bi_connection_open(req: i64, handle: i64) {
    spawn(req, async move {
        let connection = connection_of(handle)?;
        let (send, recv) = connection
            .open_bi()
            .await
            .map_err(|e| Fail::End(e.to_string()))?;
        let handle = keep(generation(), stream_obj(send, recv))
            .ok_or_else(|| Fail::End("restarted".into()))?;
        Ok((Vec::new(), handle))
    });
}

/// The next stream the other end opened: its handle. [END] once the
/// connection is closed.
#[unsafe(no_mangle)]
pub extern "C" fn bi_connection_accept(req: i64, handle: i64) {
    spawn(req, async move {
        let connection = connection_of(handle)?;
        let (send, recv) = connection
            .accept_bi()
            .await
            .map_err(|e| Fail::End(e.to_string()))?;
        let handle = keep(generation(), stream_obj(send, recv))
            .ok_or_else(|| Fail::End("restarted".into()))?;
        Ok((Vec::new(), handle))
    });
}

fn connection_info(connection: &Connection) -> Value {
    let paths = connection.paths();
    let mut list = Vec::new();
    let mut selected = Value::Null;
    for path in paths.iter() {
        let addr = match path.remote_addr() {
            TransportAddr::Ip(addr) => addr.to_string(),
            TransportAddr::Relay(url) => url.to_string(),
            other => format!("{other:?}"),
        };
        let item = json!({
            "kind": if path.is_relay() { "relay" } else { "ip" },
            "addr": addr,
            "selected": path.is_selected(),
            "rttMs": path.rtt().as_millis() as u64,
        });
        if path.is_selected() {
            selected = item.clone();
        }
        list.push(item);
    }
    json!({
        "remote": hex(connection.remote_id().as_bytes()),
        "paths": list,
        "selected": selected,
        "closed": connection.close_reason().map(|r| r.to_string()),
    })
}

/// Its paths now: `{"remote", "paths": [{"kind": "ip"|"relay", "addr",
/// "selected", "rttMs"}], "selected", "closed"}`.
#[unsafe(no_mangle)]
pub extern "C" fn bi_connection_info(req: i64, handle: i64) {
    spawn(req, async move {
        let connection = connection_of(handle)?;
        Ok((json_bytes(connection_info(&connection)), 0))
    });
}

/// As [bi_connection_info], once a path opened, closed or was chosen (or
/// ten seconds went by, for the round trip's time); [END] once closed.
#[unsafe(no_mangle)]
pub extern "C" fn bi_connection_watch(req: i64, handle: i64) {
    spawn(req, async move {
        let connection = connection_of(handle)?;
        let mut events = connection.path_events();
        tokio::select! {
            _ = events.next() => {}
            _ = tokio::time::sleep(Duration::from_secs(10)) => {}
            reason = connection.closed() => return Err(Fail::End(reason.to_string())),
        }
        Ok((json_bytes(connection_info(&connection)), 0))
    });
}

/// Once the connection is closed, by either end or by its going quiet:
/// why, as [OK]'s data.
#[unsafe(no_mangle)]
pub extern "C" fn bi_connection_closed(req: i64, handle: i64) {
    spawn(req, async move {
        let connection = connection_of(handle)?;
        let reason = connection.closed().await;
        Ok((reason.to_string().into_bytes(), 0))
    });
}

/// Closes it now, with [code].
#[unsafe(no_mangle)]
pub extern "C" fn bi_connection_close(handle: i64, code: u32) {
    if let Some(Obj::Connection(connection)) = get(handle) {
        connection.close(VarInt::from_u32(code), b"");
    }
}

// --- Streams ----------------------------------------------------------------------

/// Sends the [len] bytes at [data] as one message, after those asked for
/// before; done once written.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bi_stream_send(req: i64, handle: i64, data: *const u8, len: usize) {
    let generation = generation();
    let message = unsafe { bytes(data, len) }.to_vec();
    match stream_of(handle) {
        Ok(stream) => {
            if let Err(mpsc::error::SendError(Out::Message(_, req, generation))) =
                stream.out.send(Out::Message(message, req, generation))
            {
                answer(generation, req, Err(Fail::End("reset".into())));
            }
        }
        Err(fail) => answer(generation, req, Err(fail)),
    }
}

/// The next message: [OK] with its bytes; [END] once the other end
/// finished (or reset) the stream.
#[unsafe(no_mangle)]
pub extern "C" fn bi_stream_recv(req: i64, handle: i64) {
    spawn(req, async move {
        let stream = stream_of(handle)?;
        let mut recv = stream.recv.lock().await;
        let read = async {
            let mut header = [0u8; frame::HEADER];
            match recv.read_exact(&mut header).await {
                Ok(()) => {}
                Err(ReadExactError::FinishedEarly(0)) => return Err(Fail::End("finished".into())),
                Err(ReadExactError::FinishedEarly(_)) => {
                    return Err(Fail::Err("finished in a message".into()));
                }
                Err(ReadExactError::ReadError(e)) => return Err(Fail::End(e.to_string())),
            }
            let (len, flags) = frame::header(&header).map_err(Fail::Err)?;
            let mut body = vec![0u8; len];
            recv.read_exact(&mut body).await.map_err(|e| match e {
                ReadExactError::ReadError(e) => Fail::End(e.to_string()),
                other => Fail::Err(other.to_string()),
            })?;
            frame::decode(flags, body).map_err(Fail::Err)
        };
        let mut stop = stream.stop_reading.subscribe();
        if *stop.borrow_and_update() {
            return Err(Fail::End("reset".into()));
        }
        tokio::select! {
            message = read => Ok((message?, 0)),
            _ = stop.wait_for(|stop| *stop) => Err(Fail::End("reset".into())),
        }
    });
}

/// No more from this end, once what was asked before is written: the other
/// gets [END] once it read the rest.
#[unsafe(no_mangle)]
pub extern "C" fn bi_stream_finish(req: i64, handle: i64) {
    let generation = generation();
    match stream_of(handle) {
        Ok(stream) => {
            if stream.out.send(Out::Finish(req, generation)).is_err() {
                answer(generation, req, Ok((Vec::new(), 0)));
            }
        }
        Err(fail) => answer(generation, req, Err(fail)),
    }
}

/// Gives the stream up both ways, at once: a read under way ends, and what
/// is not written yet never is.
#[unsafe(no_mangle)]
pub extern "C" fn bi_stream_reset(handle: i64) {
    let Ok(stream) = stream_of(handle) else {
        return;
    };
    stream.stop_reading.send_replace(true);
    stream.reset.send_replace(true);
    runtime().spawn(async move {
        let _ = stream.recv.lock().await.stop(VarInt::from_u32(0));
    });
}
