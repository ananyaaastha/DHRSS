"""
routes.py — Flask route handlers for DHRSS web UI.
"""

from flask import Blueprint, render_template, request, jsonify, flash, redirect, url_for
from .blockchain import BlockchainClient

main = Blueprint("main", __name__)


def _client():
    """Returns a fresh BlockchainClient or raises a user-friendly error."""
    try:
        return BlockchainClient()
    except Exception as e:
        raise RuntimeError(f"Blockchain connection failed: {e}")


# ─────────────────────────── Pages ──────────────────────────────────

@main.route("/")
def index():
    return render_template("index.html")


@main.route("/patient")
def patient_dashboard():
    return render_template("patient_dashboard.html")


@main.route("/doctor")
def doctor_dashboard():
    return render_template("doctor_dashboard.html")


@main.route("/admin")
def admin_dashboard():
    return render_template("admin_dashboard.html")


# ─────────────────────── API: Registration ──────────────────────────

@main.route("/api/register/patient", methods=["POST"])
def api_register_patient():
    data = request.get_json()
    account     = data.get("account")
    private_key = data.get("private_key")
    if not account or not private_key:
        return jsonify({"error": "account and private_key are required"}), 400
    try:
        receipt = _client().register_patient(account, private_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@main.route("/api/register/doctor", methods=["POST"])
def api_register_doctor():
    data = request.get_json()
    doctor_addr = data.get("doctor_address")
    admin_addr  = data.get("admin_account")
    admin_key   = data.get("admin_key")
    if not all([doctor_addr, admin_addr, admin_key]):
        return jsonify({"error": "doctor_address, admin_account, admin_key required"}), 400
    try:
        receipt = _client().register_doctor(doctor_addr, admin_addr, admin_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@main.route("/api/register/emergency", methods=["POST"])
def api_register_emergency():
    data = request.get_json()
    person_addr = data.get("person_address")
    admin_addr  = data.get("admin_account")
    admin_key   = data.get("admin_key")
    if not all([person_addr, admin_addr, admin_key]):
        return jsonify({"error": "person_address, admin_account, admin_key required"}), 400
    try:
        receipt = _client().register_emergency(person_addr, admin_addr, admin_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────── API: Records ───────────────────────────────

@main.route("/api/records/add", methods=["POST"])
def api_add_record():
    data = request.get_json()
    patient     = data.get("patient")
    ipfs_hash   = data.get("ipfs_hash")
    record_type = data.get("record_type")
    caller      = data.get("caller")
    private_key = data.get("private_key")
    if not all([patient, ipfs_hash, record_type, caller, private_key]):
        return jsonify({"error": "Missing required fields"}), 400
    try:
        receipt = _client().add_record(patient, ipfs_hash, record_type, caller, private_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@main.route("/api/records/get", methods=["POST"])
def api_get_records():
    data = request.get_json()
    patient = data.get("patient")
    caller  = data.get("caller")
    if not patient or not caller:
        return jsonify({"error": "patient and caller are required"}), 400
    try:
        records = _client().get_records(patient, caller)
        return jsonify({"success": True, "records": records})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────── API: Consent ───────────────────────────────

@main.route("/api/consent/grant", methods=["POST"])
def api_grant_consent():
    data = request.get_json()
    doctor      = data.get("doctor")
    duration    = data.get("duration_seconds")
    patient     = data.get("patient")
    private_key = data.get("private_key")
    if not all([doctor, duration, patient, private_key]):
        return jsonify({"error": "Missing required fields"}), 400
    try:
        receipt = _client().grant_consent(doctor, int(duration), patient, private_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@main.route("/api/consent/revoke", methods=["POST"])
def api_revoke_consent():
    data = request.get_json()
    doctor      = data.get("doctor")
    patient     = data.get("patient")
    private_key = data.get("private_key")
    if not all([doctor, patient, private_key]):
        return jsonify({"error": "Missing required fields"}), 400
    try:
        receipt = _client().revoke_consent(doctor, patient, private_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@main.route("/api/consent/check", methods=["POST"])
def api_check_consent():
    data    = request.get_json()
    patient = data.get("patient")
    doctor  = data.get("doctor")
    if not patient or not doctor:
        return jsonify({"error": "patient and doctor are required"}), 400
    try:
        client  = _client()
        valid   = client.has_valid_consent(patient, doctor)
        expiry  = client.get_consent_expiry(patient, doctor)
        return jsonify({"success": True, "valid": valid, "expiry": expiry})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────── API: Emergency ─────────────────────────────

@main.route("/api/emergency/access", methods=["POST"])
def api_emergency_access():
    data = request.get_json()
    patient     = data.get("patient")
    reason      = data.get("reason")
    caller      = data.get("caller")
    private_key = data.get("private_key")
    if not all([patient, reason, caller, private_key]):
        return jsonify({"error": "Missing required fields"}), 400
    try:
        receipt = _client().emergency_access(patient, reason, caller, private_key)
        return jsonify({"success": True, "receipt": receipt})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@main.route("/api/emergency/log", methods=["POST"])
def api_emergency_log():
    data = request.get_json()
    admin_account = data.get("admin_account")
    if not admin_account:
        return jsonify({"error": "admin_account is required"}), 400
    try:
        log = _client().get_emergency_log(admin_account)
        return jsonify({"success": True, "log": log})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ─────────────────────── API: Utilities ─────────────────────────────

@main.route("/api/check/role", methods=["POST"])
def api_check_role():
    data    = request.get_json()
    address = data.get("address")
    if not address:
        return jsonify({"error": "address is required"}), 400
    try:
        client = _client()
        return jsonify({
            "success":   True,
            "is_patient":   client.is_patient(address),
            "is_doctor":    client.is_doctor(address),
            "is_emergency": client.is_emergency(address),
            "is_admin":     client.get_admin().lower() == address.lower(),
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500
