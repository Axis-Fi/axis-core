// CLI program to test ECIES using the ark-bn254 curve implementation against the contract implementations

// Requirements:
// Encrypt a message using our ECIES mechanism on the bn254 (aka alt_bn128) curve
// Decrypt a message using our ECIES mechanism on the bn254 (aka alt_bn128) curve

// Dependencies

use ark_bn254::{Fq as BaseField, Fr as ScalarField, G1Affine as G1};
use ark_ec::{AffineRepr, CurveGroup};
use clap::{error::Result, Parser, Subcommand};
use ethers::{types::U256, utils::hex};
use num_bigint::BigUint;

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
        message: BigUint,
        #[arg(value_name = "public_key_x")]
        public_key_x: BigUint,
        #[arg(value_name = "public_key_y")]
        public_key_y: BigUint,
        #[arg(value_name = "bid_private_key")]
        bid_private_key: BigUint,
        #[arg(value_name = "salt")]
        salt: BigUint,
    },
    Decrypt {
        #[arg(value_name = "ciphertext")]
        ciphertext: BigUint,
        #[arg(value_name = "bid_public_key_x")]
        bid_public_key_x: BigUint,
        #[arg(value_name = "bid_public_key_y")]
        bid_public_key_y: BigUint,
        #[arg(value_name = "private_key")]
        private_key: BigUint,
        #[arg(value_name = "salt")]
        salt: BigUint,
    },
}

fn main() -> Result<()> {
    let args = Cli::parse();
    match args.command {
        Commands::Encrypt {
            message,
            public_key_x,
            public_key_y,
            bid_private_key,
            salt,
        } => {
            // Convert message and salt to U256 types
            let message = U256::from_big_endian(&message.to_bytes_be());
            let salt = U256::from_big_endian(&salt.to_bytes_be());

            // Convert public key coordinates and bid private key to ark-bn254 types
            let x = BaseField::from(public_key_x);
            let y = BaseField::from(public_key_y);
            let bid_private_key = ScalarField::from(bid_private_key);

            // Construct public key from coordinates
            // Will revert if the point is not on the curve
            let public_key = G1::new(x, y);

            // Encrypt the message

            //  Calculate the bid public key using the bid private key
            let bid_public_key = (G1::generator() * bid_private_key).into_affine();

            //  Calculate a shared secret public key using the bid public key and the auction public key
            let shared_secret_public_key = (public_key * bid_private_key).into_affine();

            //  Calculate the symmetric key by taking the keccak256 hash of the x coordinate of shared secret public key and the salt
            let mut shared_secret_bytes = [0u8; 32];
            U256::from_big_endian(&BigUint::from(shared_secret_public_key.x).to_bytes_be())
                .to_big_endian(&mut shared_secret_bytes);
            let mut salt_bytes = [0u8; 32];
            salt.to_big_endian(&mut salt_bytes);
            let symmetric_key = ethers::utils::keccak256(
                [shared_secret_bytes.to_vec(), salt_bytes.to_vec()].concat(),
            );

            //  Encrypt the message by XORing the message with the symmetric key
            let mut message_bytes = [0u8; 32];
            message.to_big_endian(&mut message_bytes);
            let ciphertext = message_bytes
                .iter()
                .zip(symmetric_key.iter())
                .map(|(a, b)| a ^ b)
                .collect::<Vec<u8>>();

            // Combine the ciphertext and the bid public key into a hex-encoded string to return (abi-encoded)
            let mut x_bytes = [0u8; 32];
            U256::from_big_endian(&BigUint::from(bid_public_key.x).to_bytes_be())
                .to_big_endian(&mut x_bytes);

            let mut y_bytes = [0u8; 32];
            U256::from_big_endian(&BigUint::from(bid_public_key.y).to_bytes_be())
                .to_big_endian(&mut y_bytes);

            let output =
                bytes_to_string(&[ciphertext, x_bytes.to_vec(), y_bytes.to_vec()].concat());

            // Print output to command line
            println!("{}", output);
        }
        Commands::Decrypt {
            ciphertext,
            bid_public_key_x,
            bid_public_key_y,
            private_key,
            salt,
        } => {
            // Convert ciphertext and salt to U256
            let ciphertext = U256::from_big_endian(&ciphertext.to_bytes_be());
            let salt = U256::from_big_endian(&salt.to_bytes_be());

            // Convert bid public key coordinates and private key to ark-bn254 types
            let x = BaseField::from(bid_public_key_x);
            let y = BaseField::from(bid_public_key_y);
            let private_key = ScalarField::from(private_key);

            // Construct bid public key from coordinates
            // Will revert if the point is not on the curve
            let bid_public_key = G1::new(x, y);

            // Calculate the shared secret public key using the bid public key and the private key
            let shared_secret_public_key = (bid_public_key * private_key).into_affine();

            // Calculate the symmetric key by taking the keccak256 hash of the x coordinate of shared secret public key and the salt
            let mut shared_secret_bytes = [0u8; 32];
            U256::from_big_endian(&BigUint::from(shared_secret_public_key.x).to_bytes_be())
                .to_big_endian(&mut shared_secret_bytes);
            let mut salt_bytes = [0u8; 32];
            salt.to_big_endian(&mut salt_bytes);
            let symmetric_key = ethers::utils::keccak256(
                [shared_secret_bytes.to_vec(), salt_bytes.to_vec()].concat(),
            );

            // Decrypt the message by XORing the ciphertext with the symmetric key
            let mut ciphertext_bytes = [0u8; 32];
            ciphertext.to_big_endian(&mut ciphertext_bytes);

            let message = ciphertext_bytes
                .iter()
                .zip(symmetric_key.iter())
                .map(|(a, b)| a ^ b)
                .collect::<Vec<u8>>();

            // Convert the message to a hex-encoded string (abi-encoded since it is one slot)
            let output = bytes_to_string(&message);

            // Print output to command line
            println!("{}", output);
        }
    }

    Ok(())
}
