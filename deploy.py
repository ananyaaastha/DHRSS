"""
deploy.py — Compile and deploy the HealthRecords contract.

Requirements:
  pip install web3 py-solc-x python-dotenv

Usage:
  1. Start a local Hardhat/Ganache node
  2. Copy .env.example to .env and fill in values
  3. python deploy.py
"""

import json
import os
from dotenv import load_dotenv
from web3 import Web3
from solcx import compile_standard, install_solc

load_dotenv()

SOLC_VERSION  = "0.8.19"
CONTRACT_FILE = "contracts/HealthRecords.sol"
ABI_OUTPUT    = "contracts/abi/HealthRecords.json"
PROVIDER_URL  = os.getenv("WEB3_PROVIDER_URL", "http://127.0.0.1:8545")
DEPLOYER_ADDR = os.getenv("DEPLOYER_ADDRESS")
DEPLOYER_KEY  = os.getenv("DEPLOYER_PRIVATE_KEY")
CHAIN_ID      = int(os.getenv("CHAIN_ID", "1337"))


def main():
    print(f"[1/5] Installing solc {SOLC_VERSION}...")
    install_solc(SOLC_VERSION)

    print("[2/5] Reading contract source...")
    with open(CONTRACT_FILE) as f:
        source = f.read()

    print("[3/5] Compiling contract...")
    compiled = compile_standard(
        {
            "language": "Solidity",
            "sources": {
                "HealthRecords.sol": {"content": source}
            },
            "settings": {
                "outputSelection": {
                    "*": {"*": ["abi", "evm.bytecode"]}
                }
            },
        },
        solc_version=SOLC_VERSION,
    )

    contract_data = compiled["contracts"]["HealthRecords.sol"]["HealthRecords"]
    abi      = contract_data["abi"]
    bytecode = contract_data["evm"]["bytecode"]["object"]

    # Save ABI
    with open(ABI_OUTPUT, "w") as f:
        json.dump(abi, f, indent=2)
    print(f"    ABI saved to {ABI_OUTPUT}")

    print("[4/5] Connecting to node...")
    w3 = Web3(Web3.HTTPProvider(PROVIDER_URL))
    assert w3.is_connected(), f"Cannot connect to {PROVIDER_URL}"
    print(f"    Connected. Chain ID: {w3.eth.chain_id}")

    print("[5/5] Deploying contract...")
    contract = w3.eth.contract(abi=abi, bytecode=bytecode)
    nonce = w3.eth.get_transaction_count(DEPLOYER_ADDR)

    tx = contract.constructor().build_transaction({
        "from":     DEPLOYER_ADDR,
        "nonce":    nonce,
        "gas":      3_000_000,
        "gasPrice": w3.to_wei("20", "gwei"),
        "chainId":  CHAIN_ID,
    })

    signed  = w3.eth.account.sign_transaction(tx, DEPLOYER_KEY)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)

    address = receipt.contractAddress
    print(f"\n✅  Contract deployed at: {address}")
    print(f"    Tx hash:              {tx_hash.hex()}")
    print(f"    Block:                {receipt.blockNumber}")
    print(f"\nAdd this to your .env file:\n  CONTRACT_ADDRESS={address}")


if __name__ == "__main__":
    main()
