"""
blockchain.py — Web3.py wrapper for the HealthRecords smart contract.

All write operations require the caller to supply their private key so
the transaction can be signed locally (no key is ever stored server-side).
"""

import json
import os
from datetime import datetime
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

# ─────────────────────────── Config ─────────────────────────────────

ABI_PATH      = os.path.join(os.path.dirname(__file__), "..", "contracts", "abi", "HealthRecords.json")
PROVIDER_URL  = os.getenv("WEB3_PROVIDER_URL", "http://127.0.0.1:8545")
CONTRACT_ADDR = os.getenv("CONTRACT_ADDRESS", "")
CHAIN_ID      = int(os.getenv("CHAIN_ID", "1337"))   # 1337 = local Hardhat/Ganache
GAS_LIMIT     = 300_000
GAS_PRICE_GWEI = 20


# ─────────────────────────── Client ─────────────────────────────────

class BlockchainClient:
    def __init__(self):
        self.w3 = Web3(Web3.HTTPProvider(PROVIDER_URL))
        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to node at {PROVIDER_URL}")

        with open(ABI_PATH) as f:
            abi = json.load(f)

        self.contract = self.w3.eth.contract(
            address=Web3.to_checksum_address(CONTRACT_ADDR),
            abi=abi,
        )

    # ─────────────── Helpers ─────────────────────────────────────────

    def _send_tx(self, fn, sender: str, private_key: str) -> dict:
        """Build, sign, and broadcast a transaction; return the receipt."""
        nonce = self.w3.eth.get_transaction_count(Web3.to_checksum_address(sender))
        tx = fn.build_transaction({
            "from":     Web3.to_checksum_address(sender),
            "nonce":    nonce,
            "gas":      GAS_LIMIT,
            "gasPrice": self.w3.to_wei(GAS_PRICE_GWEI, "gwei"),
            "chainId":  CHAIN_ID,
        })
        signed  = self.w3.eth.account.sign_transaction(tx, private_key)
        tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        return {
            "tx_hash": receipt.transactionHash.hex(),
            "status":  "success" if receipt.status == 1 else "failed",
            "block":   receipt.blockNumber,
        }

    @staticmethod
    def _fmt_records(raw: list) -> list:
        """Convert raw tuple list from contract into dicts."""
        return [
            {
                "ipfs_hash":   r[0],
                "timestamp":   datetime.utcfromtimestamp(r[1]).strftime("%Y-%m-%d %H:%M UTC"),
                "added_by":    r[2],
                "record_type": r[3],
            }
            for r in raw
        ]

    # ─────────────── Registration ────────────────────────────────────

    def register_patient(self, account: str, private_key: str) -> dict:
        fn = self.contract.functions.registerPatient()
        return self._send_tx(fn, account, private_key)

    def register_doctor(self, doctor_address: str, admin_account: str, admin_key: str) -> dict:
        fn = self.contract.functions.registerDoctor(
            Web3.to_checksum_address(doctor_address)
        )
        return self._send_tx(fn, admin_account, admin_key)

    def register_emergency(self, person_address: str, admin_account: str, admin_key: str) -> dict:
        fn = self.contract.functions.registerEmergencyPersonnel(
            Web3.to_checksum_address(person_address)
        )
        return self._send_tx(fn, admin_account, admin_key)

    # ─────────────── Records ─────────────────────────────────────────

    def add_record(self, patient: str, ipfs_hash: str, record_type: str,
                   caller: str, private_key: str) -> dict:
        fn = self.contract.functions.addRecord(
            Web3.to_checksum_address(patient),
            ipfs_hash,
            record_type,
        )
        return self._send_tx(fn, caller, private_key)

    def get_records(self, patient: str, caller: str) -> list:
        raw = self.contract.functions.getRecords(
            Web3.to_checksum_address(patient)
        ).call({"from": Web3.to_checksum_address(caller)})
        return self._fmt_records(raw)

    def get_record_count(self, patient: str) -> int:
        return self.contract.functions.getRecordCount(
            Web3.to_checksum_address(patient)
        ).call()

    # ─────────────── Consent ─────────────────────────────────────────

    def grant_consent(self, doctor: str, duration_seconds: int,
                      patient: str, private_key: str) -> dict:
        fn = self.contract.functions.grantConsent(
            Web3.to_checksum_address(doctor),
            duration_seconds,
        )
        return self._send_tx(fn, patient, private_key)

    def revoke_consent(self, doctor: str, patient: str, private_key: str) -> dict:
        fn = self.contract.functions.revokeConsent(
            Web3.to_checksum_address(doctor)
        )
        return self._send_tx(fn, patient, private_key)

    def has_valid_consent(self, patient: str, doctor: str) -> bool:
        return self.contract.functions.hasValidConsent(
            Web3.to_checksum_address(patient),
            Web3.to_checksum_address(doctor),
        ).call()

    def get_consent_expiry(self, patient: str, doctor: str):
        ts = self.contract.functions.getConsentExpiry(
            Web3.to_checksum_address(patient),
            Web3.to_checksum_address(doctor),
        ).call()
        if ts == 0:
            return None
        return datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M UTC")

    # ─────────────── Emergency Override ──────────────────────────────

    def emergency_access(self, patient: str, reason: str,
                         caller: str, private_key: str) -> dict:
        fn = self.contract.functions.emergencyAccess(
            Web3.to_checksum_address(patient),
            reason,
        )
        return self._send_tx(fn, caller, private_key)

    def get_emergency_log(self, admin_account: str) -> list:
        raw = self.contract.functions.getEmergencyLog().call(
            {"from": Web3.to_checksum_address(admin_account)}
        )
        return [
            {
                "accessor":  entry[0],
                "patient":   entry[1],
                "timestamp": datetime.utcfromtimestamp(entry[2]).strftime("%Y-%m-%d %H:%M UTC"),
                "reason":    entry[3],
            }
            for entry in raw
        ]

    # ─────────────── Checks ──────────────────────────────────────────

    def is_doctor(self, address: str) -> bool:
        return self.contract.functions.doctors(
            Web3.to_checksum_address(address)
        ).call()

    def is_patient(self, address: str) -> bool:
        return self.contract.functions.registeredPatients(
            Web3.to_checksum_address(address)
        ).call()

    def is_emergency(self, address: str) -> bool:
        return self.contract.functions.emergencyPersonnel(
            Web3.to_checksum_address(address)
        ).call()

    def get_admin(self) -> str:
        return self.contract.functions.admin().call()
