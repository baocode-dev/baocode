//! The messages on a stream: each one `u32` length (big-endian), a flags
//! byte, then the payload, deflated when that is worth it (flag bit 0).

use std::io::{Read, Write};

use flate2::{Compression, read::DeflateDecoder, write::DeflateEncoder};

/// The largest message, as sent (before compression) and as received
/// (after): an 8 MB picture is about 11 MB of base64 in JSON.
pub const MAX_MESSAGE: usize = 32 << 20;

/// Shorter than this is sent as it is: deflate gains little and costs a
/// header.
const COMPRESS_FROM: usize = 1024;

const DEFLATED: u8 = 1;

pub const HEADER: usize = 5;

/// [payload] as a frame, header and all.
pub fn encode(payload: &[u8]) -> Result<Vec<u8>, String> {
    if payload.len() > MAX_MESSAGE {
        return Err(format!(
            "message of {} bytes, over {}",
            payload.len(),
            MAX_MESSAGE
        ));
    }
    let (flags, body) = match deflate(payload) {
        Some(body) => (DEFLATED, body),
        None => (0, payload.to_vec()),
    };
    let mut frame = Vec::with_capacity(HEADER + body.len());
    frame.extend_from_slice(&(body.len() as u32).to_be_bytes());
    frame.push(flags);
    frame.extend_from_slice(&body);
    Ok(frame)
}

/// The length and flags a header says.
pub fn header(bytes: &[u8; HEADER]) -> Result<(usize, u8), String> {
    let len = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as usize;
    if len > MAX_MESSAGE {
        return Err(format!("frame of {len} bytes, over {MAX_MESSAGE}"));
    }
    Ok((len, bytes[4]))
}

/// The payload of a frame's [body], read as its [flags] say.
pub fn decode(flags: u8, body: Vec<u8>) -> Result<Vec<u8>, String> {
    if flags & DEFLATED == 0 {
        return Ok(body);
    }
    let mut out = Vec::with_capacity(body.len() * 4);
    DeflateDecoder::new(&body[..])
        .take(MAX_MESSAGE as u64 + 1)
        .read_to_end(&mut out)
        .map_err(|e| format!("not deflated: {e}"))?;
    if out.len() > MAX_MESSAGE {
        return Err(format!("inflates past {MAX_MESSAGE} bytes"));
    }
    Ok(out)
}

/// [payload] deflated, if it is long enough and comes out shorter.
fn deflate(payload: &[u8]) -> Option<Vec<u8>> {
    if payload.len() < COMPRESS_FROM {
        return None;
    }
    let mut encoder =
        DeflateEncoder::new(Vec::with_capacity(payload.len() / 3), Compression::new(3));
    encoder.write_all(payload).ok()?;
    let body = encoder.finish().ok()?;
    (body.len() + 16 < payload.len()).then_some(body)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round_trip(payload: &[u8]) -> (Vec<u8>, u8) {
        let frame = encode(payload).unwrap();
        let (len, flags) = header(frame[..HEADER].try_into().unwrap()).unwrap();
        assert_eq!(len, frame.len() - HEADER);
        (decode(flags, frame[HEADER..].to_vec()).unwrap(), flags)
    }

    #[test]
    fn short_messages_go_as_they_are() {
        let (out, flags) = round_trip(b"{\"id\":1}");
        assert_eq!(out, b"{\"id\":1}");
        assert_eq!(flags, 0);
    }

    #[test]
    fn long_text_is_deflated() {
        let text = "{\"items\":[".to_string() + &"{\"text\":\"hello world\"},".repeat(500) + "]}";
        let (out, flags) = round_trip(text.as_bytes());
        assert_eq!(out, text.as_bytes());
        assert_eq!(flags, DEFLATED);
    }

    #[test]
    fn random_bytes_are_not() {
        let mut x: u32 = 1;
        let noise: Vec<u8> = (0..4096)
            .map(|_| {
                x ^= x << 13;
                x ^= x >> 17;
                x ^= x << 5;
                x as u8
            })
            .collect();
        let (out, flags) = round_trip(&noise);
        assert_eq!(out, noise);
        assert_eq!(flags, 0);
    }

    #[test]
    fn too_long_is_refused() {
        assert!(encode(&vec![0; MAX_MESSAGE + 1]).is_err());
        let mut bad = [0u8; HEADER];
        bad[..4].copy_from_slice(&((MAX_MESSAGE as u32) + 1).to_be_bytes());
        assert!(header(&bad).is_err());
    }

    #[test]
    fn a_bomb_is_refused() {
        // Deflated zeros: far past the limit once inflated.
        let mut encoder = DeflateEncoder::new(Vec::new(), Compression::best());
        let zeros = vec![0u8; 1 << 20];
        for _ in 0..40 {
            encoder.write_all(&zeros).unwrap();
        }
        let body = encoder.finish().unwrap();
        assert!(decode(DEFLATED, body).is_err());
    }
}
