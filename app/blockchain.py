"""
blockchain.py — Web3.py wrapper for DHRSS (3 contracts).
PatientRegistry → registration
AccessControl   → consent + emergency
HealthRecords   → records
"""

import json
import os
from datetime import datetime
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

PROVIDER_URL  = os.getenv("WEB3_PROVIDER_URL", "http://127.0.0.1:7545")
CHAIN_ID      = int(os.getenv("CHAIN_ID", "1337"))
GAS_LIMIT     = 300_000
GAS_PRICE_GWEI = 20

REGISTRY_ADDR       = os.getenv("PATIENT_REGISTRY_ADDRESS", "")
ACCESS_CONTROL_ADDR = os.getenv("ACCESS_CONTROL_ADDRESS", "")
HEALTH_RECORDS_ADDR = os.getenv("HEALTH_RECORDS_ADDRESS", "")

ABI_DIR = os.path.join(os.path.dirname(__file__), "..", "contracts", "abi")


class BlockchainClient:
    def __init__(self):
        self.w3 = Web3(Web3.HTTPProvider(PROVIDER_URL))
        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to node at {PROVIDER_URL}")

        with open(os.path.join(ABI_DIR, "PatientRegistry.json")) as f:
            registry_abi = json.load(f)
        with open(os.path.join(ABI_DIR, "AccessControl.json")) as f:
            access_abi = json.load(f)
        with open(os.path.join(ABI_DIR, "HealthRecords.json")) as f:
            records_abi = json.load(f)

        self.registry = self.w3.eth.contract(
            address=Web3.to_checksum_address(REGISTRY_ADDR), abi=registry_abi)
        self.access = self.w3.eth.contract(
            address=Web3.to_checksum_address(ACCESS_CONTROL_ADDR), abi=access_abi)
        self.records = self.w3.eth.contract(
            address=Web3.to_checksum_address(HEALTH_RECORDS_ADDR), abi=records_abi)

    def _send_tx(self, fn, sender: str, private_key: str) -> dict:
        nonce = self.w3.eth.get_transaction_count(Web3.to_checksum_address(sender))
        tx = fn.build_transaction({
            "from":     Web3.to_checksum_address(sender),
            "nonce":    nonce,
            "gas":      GAS_LIMIT,
            "gasPrice": self.w3.to_wei(GAS_PRICE_GWEI, "gwei"),
            "chainId":  CHAIN_ID,
        })
        signed  = self.w3.eth.account.sign_transaction(tx, private_key)
        tx_hash = self.w3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        return {
            "tx_hash": receipt.transactionHash.hex(),
            "status":  "success" if receipt.status == 1 else "failed",
            "block":   receipt.blockNumber,
        }

    @staticmethod
    def _fmt_records(raw: list) -> list:
        return [
            {
                "ipfs_hash":   r[1],
                "timestamp":   datetime.utcfromtimestamp(int(r[3])).strftime("%Y-%m-%d %H:%M UTC"),
                "added_by":    r[4],
                "record_type": str(r[5]),
            }
            for r in raw
        ]

    # ── Registration (PatientRegistry) ───────────────────────────────

    def register_patient(self, account: str, private_key: str) -> dict:
        fn = self.registry.functions.registerPatient()
        return self._send_tx(fn, account, private_key)

    def register_doctor(self, doctor_address: str, admin_account: str, admin_key: str) -> dict:
        fn = self.registry.functions.registerDoctor(Web3.to_checksum_address(doctor_address))
        return self._send_tx(fn, admin_account, admin_key)

    def register_emergency(self, person_address: str, admin_account: str, admin_key: str) -> dict:
        fn = self.registry.functions.registerEmergencyPersonnel(Web3.to_checksum_address(person_address))
        return self._send_tx(fn, admin_account, admin_key)

    def is_doctor(self, address: str) -> bool:
        return self.registry.functions.doctors(Web3.to_checksum_address(address)).call()

    def is_patient(self, address: str) -> bool:
        return self.registry.functions.registeredPatients(Web3.to_checksum_address(address)).call()

    def is_emergency(self, address: str) -> bool:
        return self.registry.functions.emergencyPersonnel(Web3.to_checksum_address(address)).call()

    def get_admin(self) -> str:
        return self.registry.functions.admin().call()

    # ── Records (HealthRecords) ───────────────────────────────────────

    def add_record(self, patient: str, ipfs_hash: str, record_type: str,
                   caller: str, private_key: str) -> dict:
        record_type_map = {
            "Lab Result": 3,
            "Prescription": 1,
            "Consultation Notes": 0,
            "Imaging": 2,
            "Vaccination": 0,
        }
        fn = self.records.functions.addRecord(
            Web3.to_checksum_address(patient),
            ipfs_hash,
            bytes(32),
            int(record_type_map.get(record_type, 0)),
        )
        return self._send_tx(fn, caller, private_key)

    def get_records(self, patient: str, caller: str) -> list:
        raw = self.records.functions.getRecords(
            Web3.to_checksum_address(patient)
        ).call({"from": Web3.to_checksum_address(caller)})
        return self._fmt_records(raw)

    def get_record_count(self, patient: str) -> int:
        return self.records.functions.getRecordCount(
            Web3.to_checksum_address(patient)
        ).call()

    # ── Consent (AccessControl) ───────────────────────────────────────

    def grant_consent(self, doctor: str, duration_seconds: int,
                      patient: str, private_key: str) -> dict:
        fn = self.access.functions.grantConsent(
            Web3.to_checksum_address(doctor), duration_seconds)
        return self._send_tx(fn, patient, private_key)

    def revoke_consent(self, doctor: str, patient: str, private_key: str) -> dict:
        fn = self.access.functions.revokeConsent(Web3.to_checksum_address(doctor))
        return self._send_tx(fn, patient, private_key)

    def has_valid_consent(self, patient: str, doctor: str) -> bool:
        return self.access.functions.hasValidConsent(
            Web3.to_checksum_address(patient),
            Web3.to_checksum_address(doctor),
        ).call()

    def get_consent_expiry(self, patient: str, doctor: str):
        ts = self.access.functions.getConsentExpiry(
            Web3.to_checksum_address(patient),
            Web3.to_checksum_address(doctor),
        ).call()
        if ts == 0:
            return None
        return datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M UTC")

    # ── Emergency (AccessControl) ─────────────────────────────────────

    def emergency_access(self, patient: str, reason: str,
                         caller: str, private_key: str) -> dict:
        fn = self.access.functions.emergencyAccess(
            Web3.to_checksum_address(patient), reason)
        return self._send_tx(fn, caller, private_key)

    def get_emergency_log(self, admin_account: str) -> list:
        count = self.access.functions.totalEmergencyEvents().call()
        raw = []
        for i in range(1, count + 1):
            raw.append(self.access.functions.emergencyEvents(i).call())
        return [
            {
                "accessor":  entry[1],
                "patient":   entry[2],
                "timestamp": datetime.utcfromtimestamp(int(entry[3])).strftime("%Y-%m-%d %H:%M UTC"),
                "reason":    entry[5],
            }
            for entry in raw
        ]