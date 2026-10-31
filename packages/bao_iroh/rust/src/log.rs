//! iroh's warnings and errors, handed to Dart (the app's events log): the
//! same line once a minute at most.

use std::{
    collections::HashMap,
    fmt::Write as _,
    sync::{Mutex, Once},
    time::{Duration, Instant},
};

use tracing::{Event, Subscriber, field::Field};
use tracing_subscriber::{
    Layer, filter::LevelFilter, layer::Context, prelude::*, registry::Registry,
};

static INSTALL: Once = Once::new();

/// Installs the subscriber, once a process.
pub fn install() {
    INSTALL.call_once(|| {
        let subscriber = Registry::default().with(DartLayer.with_filter(LevelFilter::WARN));
        let _ = tracing::subscriber::set_global_default(subscriber);
    });
}

struct DartLayer;

impl<S: Subscriber> Layer<S> for DartLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let meta = event.metadata();
        let mut line = format!("{} {}:", meta.level(), meta.target());
        event.record(&mut Visitor(&mut line));
        if once_a_minute(&line) {
            crate::log_line(line);
        }
    }
}

struct Visitor<'a>(&'a mut String);

impl tracing::field::Visit for Visitor<'_> {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            let _ = write!(self.0, " {value:?}");
        } else {
            let _ = write!(self.0, " {}={value:?}", field.name());
        }
    }

    fn record_str(&mut self, field: &Field, value: &str) {
        if field.name() == "message" {
            let _ = write!(self.0, " {value}");
        } else {
            let _ = write!(self.0, " {}={value}", field.name());
        }
    }
}

/// Whether [line] was not told in the last minute (a relay that cannot be
/// reached says so on every retry).
fn once_a_minute(line: &str) -> bool {
    static SEEN: Mutex<Option<HashMap<String, Instant>>> = Mutex::new(None);
    let mut seen = SEEN.lock().unwrap_or_else(|e| e.into_inner());
    let seen = seen.get_or_insert_with(HashMap::new);
    let now = Instant::now();
    if seen.len() > 256 {
        seen.retain(|_, at| now.duration_since(*at) < Duration::from_secs(60));
    }
    match seen.get(line) {
        Some(at) if now.duration_since(*at) < Duration::from_secs(60) => false,
        _ => {
            seen.insert(line.to_string(), now);
            true
        }
    }
}
