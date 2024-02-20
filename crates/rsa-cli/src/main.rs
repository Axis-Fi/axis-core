// CLI program to expose the RSA encrypt and decrypt functions for testing against the contract implementations

// Requirements:
// Encrypt a message using RSA-OAEP with the provided public key modulus and seed
// Decrypt a message & seed using RSA-OAEP with the provided private key exponent

// Dependencies
use clap::{error::Result, Parser, Subcommand};
use ethers::{
    types::{Bytes, H256},
    utils::hex,
};
use rsa::{set_seed::SetSeed, sha2::Sha256, BigUint, Oaep, RsaPrivateKey, RsaPublicKey};

// Helper function to convert bytes to a hex-encoded string
fn bytes_to_string(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

// CLI struct and subcommands
#[derive(Parser, Debug)]
#[clap(name = "rsa-cli")]
struct Cli {
    #[clap(subcommand)]
    command: Commands,
}

#[derive(Debug, Subcommand)]
enum Commands {
    #[clap(name = "encrypt")]
    Encrypt {
        #[arg(value_name = "message")]
        message: Bytes,
        #[arg(value_name = "label")]
        label: String,
        #[arg(value_name = "public_exponent")]
        public_exponent: Bytes,
        #[arg(value_name = "modulus")]
        modulus: Bytes,
        #[arg(value_name = "seed")]
        seed: H256,
    },
    Decrypt {
        #[arg(value_name = "ciphertext")]
        ciphertext: Bytes,
        #[arg(value_name = "label")]
        label: String,
        #[arg(value_name = "public_exponent")]
        public_exponent: Bytes,
        #[arg(value_name = "private_exponent")]
        private_exponent: Bytes,
        #[arg(value_name = "modulus")]
        modulus: Bytes,
    },
}

fn main() -> Result<()> {
    let args = Cli::parse();
    match args.command {
        Commands::Encrypt {
            message,
            label,
            public_exponent,
            modulus,
            seed,
        } => {
            // Parse BigUints from Bytes
            let public_exponent = BigUint::from_bytes_be(&public_exponent);
            let modulus = BigUint::from_bytes_be(&modulus);

            // Construct encryption components
            let public_key = RsaPublicKey::new(modulus, public_exponent).unwrap();
            let mut seed_provider = SetSeed::new(seed.as_bytes().to_vec());
            let padding = Oaep::new_with_label::<Sha256, String>(label);

            // Encrypt the message
            let ciphertext = public_key
                .encrypt(&mut seed_provider, padding, &message)
                .unwrap();

            // Convert the ciphertext to a hex-encoded string
            let ciphertext = bytes_to_string(ciphertext.as_slice());

            // Print output to command line
            println!("{}", ciphertext);
        }
        Commands::Decrypt {
            ciphertext,
            label,
            public_exponent,
            private_exponent,
            modulus,
        } => {
            // Parse BigUints from Bytes
            let public_exponent = BigUint::from_bytes_be(&public_exponent);
            let private_exponent = BigUint::from_bytes_be(&private_exponent);
            let modulus = BigUint::from_bytes_be(&modulus);

            // Derive private key from components, we don't have the primes, but it will find them
            let private_key =
                RsaPrivateKey::from_components(modulus, public_exponent, private_exponent, vec![])
                    .unwrap();

            // Configure padding
            let padding = Oaep::new_with_label::<Sha256, String>(label);

            // Decrypt the message and recover the seed
            let (message, seed) = private_key
                .decrypt_seed(padding, ciphertext.to_vec().as_slice())
                .unwrap();

            // Convert the message and seed to a hex-encoded string (abi-encoded since they are both one slot)
            let output = bytes_to_string([message, seed].concat().as_slice());

            // Print output to command line
            println!("{}", output);
        }
    }

    Ok(())
}
