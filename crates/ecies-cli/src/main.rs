// CLI program to expose the RSA encrypt and decrypt functions for testing against the contract implementations

// Requirements:
// Encrypt a message using RSA-OAEP with the provided public key modulus and seed
// Decrypt a message & seed using RSA-OAEP with the provided private key exponent

// Dependencies

use ark_bn254::{Fq as BaseField, Fr as ScalarField, G1Affine as G1};
use ark_ec::{AffineRepr, CurveGroup, Group};
use ark_ff::{BigInteger, Field, UniformRand};
use clap::{error::Result, Parser, Subcommand};
use ethers::{
    types::{Bytes, U256},
    utils::hex,
};
use num_bigint::BigUint;
use rand::{thread_rng, Rng};

// Helper function to convert bytes to a hex-encoded string
fn bytes_to_string(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
}

// CLI struct and subcommands
#[derive(Parser, Debug)]
#[clap(name = "ecies-cli")]
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
        #[arg(value_name = "public_key_x")]
        public_key_x: Bytes,
        #[arg(value_name = "public_key_y")]
        public_key_y: Bytes,
        #[arg(value_name = "salt")]
        salt: Bytes,
    },
    Decrypt {
        #[arg(value_name = "ciphertext")]
        ciphertext: Bytes,
        #[arg(value_name = "bid_public_key_x")]
        bid_public_key_x: Bytes,
        #[arg(value_name = "bid_public_key_y")]
        bid_public_key_y: Bytes,
        #[arg(value_name = "private_key")]
        private_key: Bytes,
    },
}

fn main() -> Result<()> {
    let args = Cli::parse();
    match args.command {
        Commands::Encrypt {
            message,
            public_key_x,
            public_key_y,
            salt,
        } => {
            // Parse values from byte strings
            let message = U256::from_big_endian(&message).as_u128();
            let x = BaseField::from(BigUint::from_bytes_be(&public_key_x));
            let y = BaseField::from(BigUint::from_bytes_be(&public_key_y));

            // Construct public key from coordinates
            // Will revert if the point is not on the curve
            let public_key = G1::new(x, y).into_group();

            // Format the message for encryption
            // 1. Generate a random seed to mask the message
            let message_seed: u128 = thread_rng().gen();
            // 2. Mask the message with the seed, allowing for underflows
            let masked_message = message_seed.wrapping_sub(message);
            // 3. Concatenate the seed and the masked message to create the message to encrypt
            let plaintext = [
                message_seed.to_be_bytes().to_vec(),
                masked_message.to_be_bytes().to_vec(),
            ]
            .concat();

            // Encrypt the message
            //  1. Generate a value to serve as the bid private key
            let mut rng = thread_rng();
            let bid_private_key: ScalarField = ScalarField::rand(&mut rng);

            //  2. Calculate the bid public key using the bid private key
            let bid_public_key = G1::generator() * bid_private_key;

            //  3. Calculate a shared secret public key using the bid public key and the auction public key
            let shared_secret_public_key = public_key * bid_private_key;

            //  4. Calculate the symmetric key by taking the keccak256 hash of the x coordinate of shared secret public key and the salt
            let shared_secret = shared_secret_public_key.x.0.to_bytes_be();
            let symmetric_key = ethers::utils::keccak256(&[shared_secret, salt.to_vec()].concat());

            //  5. Encrypt the message by XORing the message with the symmetric key
            let ciphertext = plaintext
                .iter()
                .zip(symmetric_key.iter().cycle())
                .map(|(a, b)| a ^ b)
                .collect::<Vec<u8>>();

            // Combine the ciphertext and the bid public key into a hex-encoded string to return (abi-encoded)
            let output = bytes_to_string(
                &[
                    ciphertext,
                    vec![0x40],
                    bid_public_key.x.0.to_bytes_be(),
                    bid_public_key.y.0.to_bytes_be(),
                ]
                .concat(),
            );

            // Print output to command line
            println!("{}", output);
        }
        Commands::Decrypt {
            ciphertext,
            bid_public_key_x,
            bid_public_key_y,
            private_key,
        } => {
            // // Parse BigUints from Bytes
            // let public_exponent = BigUint::from_bytes_be(&public_exponent);
            // let private_exponent = BigUint::from_bytes_be(&private_exponent);
            // let modulus = BigUint::from_bytes_be(&modulus);

            // // Derive private key from components, we don't have the primes, but it will find them
            // let private_key =
            //     RsaPrivateKey::from_components(modulus, public_exponent, private_exponent, vec![])
            //         .unwrap();

            // // Configure padding
            // let padding = Oaep::new_with_label::<Sha256, String>(label);

            // // Decrypt the message and recover the seed
            // let (message, seed) = private_key
            //     .decrypt_seed(padding, ciphertext.to_vec().as_slice())
            //     .unwrap();

            // // Convert the message and seed to a hex-encoded string (abi-encoded since they are both one slot)
            // let output = bytes_to_string([message, seed].concat().as_slice());

            // // Print output to command line
            // println!("{}", output);
        }
    }

    Ok(())
}
