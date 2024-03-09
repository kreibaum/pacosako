//! Wraps cryptographic functions.

use aes_gcm::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    Aes256Gcm,
    Key, // Or `Aes128Gcm`
    Nonce,
};
use base64::Engine;

use crate::ServerError;

use super::SessionId;

/// Encrypts a string using a secret key. This secret key should come from configuration.
///
/// This is used for session keys and to store discord access tokens when the user
/// has not yet been created in the database.
pub fn encrypt_string(data: &str, secret_key: &str) -> Result<String, ServerError> {
    let secret_key = decode_base64(secret_key)?;
    let key = Key::<Aes256Gcm>::from_slice(&secret_key);
    let cipher = Aes256Gcm::new(key);
    let nonce = Aes256Gcm::generate_nonce(&mut OsRng); // 96-bits; unique per message

    let encrypted = cipher.encrypt(&nonce, data.as_bytes())?;

    Ok(merge_nonce(&nonce, &encrypted))
}

/// Decrypts a session key using a secret key. This secret key should come from configuration.
pub fn decrypt_session_key(
    session_key: &str,
    secret_key: &str,
) -> Result<SessionId, anyhow::Error> {
    // Split into nonce and encrypted
    let (nonce, encrypted) = split_nonce(session_key)?;

    // Decode nonce and encrypted
    let nonce = Nonce::from_slice(&nonce);
    let encrypted: &[u8] = &encrypted;

    // Decrypt
    let secret_key = decode_base64(secret_key)?;
    let key = Key::<Aes256Gcm>::from_slice(&secret_key);
    let cipher = Aes256Gcm::new(key);
    let decrypted = cipher.decrypt(nonce, encrypted)?;

    Ok(SessionId(String::from_utf8(decrypted)?))
}

fn encode_base64(bytes: &[u8]) -> String {
    base64::prelude::BASE64_STANDARD.encode(bytes)
}

fn decode_base64(bytes: &str) -> Result<Vec<u8>, ServerError> {
    Ok(base64::prelude::BASE64_STANDARD.decode(bytes)?)
}

fn merge_nonce(nonce: &[u8], payload: &[u8]) -> String {
    format!("{}:{}", encode_base64(nonce), encode_base64(payload))
}

fn split_nonce(combined: &str) -> Result<(Vec<u8>, Vec<u8>), anyhow::Error> {
    let mut split = combined.split(':');
    let Some(nonce) = split.next() else {
        anyhow::bail!("No nonce")
    };
    let Some(payload) = split.next() else {
        anyhow::bail!("No payload")
    };
    Ok((decode_base64(nonce)?, decode_base64(payload)?))
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    /// Randomly generate a uuid, encrypt it, then decrypt it.
    /// If the decrypted value is the same as the original, then the encryption/decryption works.
    /// This is repeated 100 times.
    #[test]
    fn encrypt_decrypt() {
        for _ in 0..100 {
            let session_key = Uuid::new_v4().to_string();
            let secret_key = "0B25jpNtswUWdkemdxU3B8Fvnm46ISgrawzinUpvLLQ=";

            let encrypted = super::encrypt_string(&session_key, secret_key).unwrap();
            let decrypted = super::decrypt_session_key(&encrypted, secret_key).unwrap();

            println!("session_key: {:?}", session_key);
            println!("encrypted: {}", encrypted);

            assert_eq!(session_key, decrypted.0);
        }
    }

    // Randomly generate a nonce & payload, merge them, then split them.
    // If the split values are the same as the original, then the merge/split works.
    #[test]
    fn merge_split() {
        for _ in 0..100 {
            // Create two random byte vectors.
            let nonce: Vec<u8> = rand::random::<[u8; 13]>().to_vec();
            let payload = rand::random::<[u8; 29]>().to_vec();

            let merged = super::merge_nonce(&nonce, &payload);
            let (split_nonce, split_payload) = super::split_nonce(&merged).unwrap();

            assert_eq!(nonce, split_nonce);
            assert_eq!(payload, split_payload);
        }
    }
}
