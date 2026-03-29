// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title HealthRecords
 * @dev Decentralised Healthcare Record Sharing System (DHRSS)
 * Features:
 *  - Patient record management (stored as IPFS hashes)
 *  - Doctor access control
 *  - Smart consent with auto-expiry
 *  - Emergency override mechanism with audit logging
 */
contract HealthRecords {

    // ─────────────────────────── Structs ────────────────────────────

    struct Record {
        string  ipfsHash;       // IPFS CID pointing to encrypted record
        uint256 timestamp;
        address addedBy;
        string  recordType;     // e.g. "Lab Result", "Prescription", "X-Ray"
    }

    struct ConsentGrant {
        uint256 expiryTime;     // unix timestamp; 0 = not granted
        bool    active;
    }

    struct EmergencyAccess {
        address accessor;
        address patient;
        uint256 timestamp;
        string  reason;
    }

    // ─────────────────────────── Storage ────────────────────────────

    address public admin;

    mapping(address => bool)                               public doctors;
    mapping(address => bool)                               public emergencyPersonnel;
    mapping(address => bool)                               public registeredPatients;
    mapping(address => Record[])                           private patientRecords;
    mapping(address => mapping(address => ConsentGrant))   private consents; // patient => doctor => grant

    EmergencyAccess[] public emergencyLog;

    // ─────────────────────────── Events ─────────────────────────────

    event PatientRegistered  (address indexed patient);
    event DoctorRegistered   (address indexed doctor);
    event RecordAdded        (address indexed patient, uint256 recordIndex, string recordType);
    event ConsentGranted     (address indexed patient, address indexed doctor, uint256 expiryTime);
    event ConsentRevoked     (address indexed patient, address indexed doctor);
    event EmergencyOverride  (address indexed accessor, address indexed patient, string reason);

    // ─────────────────────────── Modifiers ──────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == admin, "DHRSS: caller is not admin");
        _;
    }

    modifier onlyRegisteredPatient() {
        require(registeredPatients[msg.sender], "DHRSS: caller is not a registered patient");
        _;
    }

    modifier onlyDoctor() {
        require(doctors[msg.sender], "DHRSS: caller is not a registered doctor");
        _;
    }

    // ─────────────────────────── Constructor ────────────────────────

    constructor() {
        admin = msg.sender;
    }

    // ─────────────────────── Registration ───────────────────────────

    /// @notice Patients self-register using their wallet address
    function registerPatient() external {
        require(!registeredPatients[msg.sender], "DHRSS: already registered");
        registeredPatients[msg.sender] = true;
        emit PatientRegistered(msg.sender);
    }

    /// @notice Admin registers a verified doctor
    function registerDoctor(address _doctor) external onlyAdmin {
        require(_doctor != address(0), "DHRSS: zero address");
        doctors[_doctor] = true;
        emit DoctorRegistered(_doctor);
    }

    /// @notice Admin registers emergency personnel (paramedics, ER doctors)
    function registerEmergencyPersonnel(address _person) external onlyAdmin {
        require(_person != address(0), "DHRSS: zero address");
        emergencyPersonnel[_person] = true;
    }

    // ─────────────────────── Record Management ──────────────────────

    /**
     * @notice Add a health record for a patient (IPFS hash of encrypted data)
     * @dev Caller must be the patient themselves, or a doctor with valid consent
     */
    function addRecord(
        address _patient,
        string  calldata _ipfsHash,
        string  calldata _recordType
    ) external {
        require(registeredPatients[_patient], "DHRSS: patient not registered");
        require(
            msg.sender == _patient ||
            (doctors[msg.sender] && _hasValidConsent(_patient, msg.sender)),
            "DHRSS: no access to add record"
        );

        patientRecords[_patient].push(Record({
            ipfsHash:   _ipfsHash,
            timestamp:  block.timestamp,
            addedBy:    msg.sender,
            recordType: _recordType
        }));

        emit RecordAdded(_patient, patientRecords[_patient].length - 1, _recordType);
    }

    /**
     * @notice Retrieve all records for a patient
     * @dev Accessible by: patient themselves | consented doctor | emergency personnel
     */
    function getRecords(address _patient) external view returns (Record[] memory) {
        require(
            msg.sender == _patient ||
            (doctors[msg.sender] && _hasValidConsent(_patient, msg.sender)) ||
            emergencyPersonnel[msg.sender],
            "DHRSS: access denied"
        );
        return patientRecords[_patient];
    }

    /// @notice Returns total record count for a patient (no access restriction)
    function getRecordCount(address _patient) external view returns (uint256) {
        require(registeredPatients[_patient], "DHRSS: patient not registered");
        return patientRecords[_patient].length;
    }

    // ──────────────────── Consent Management ────────────────────────

    /**
     * @notice Grant a doctor time-limited consent to view/add records
     * @param _doctor      Doctor's wallet address
     * @param _durationSec Consent duration in seconds (e.g. 86400 = 1 day)
     */
    function grantConsent(address _doctor, uint256 _durationSec) external onlyRegisteredPatient {
        require(doctors[_doctor], "DHRSS: address is not a registered doctor");
        require(_durationSec > 0, "DHRSS: duration must be > 0");

        uint256 expiry = block.timestamp + _durationSec;
        consents[msg.sender][_doctor] = ConsentGrant({
            expiryTime: expiry,
            active:     true
        });

        emit ConsentGranted(msg.sender, _doctor, expiry);
    }

    /// @notice Immediately revoke a doctor's consent
    function revokeConsent(address _doctor) external onlyRegisteredPatient {
        require(consents[msg.sender][_doctor].active, "DHRSS: no active consent to revoke");
        consents[msg.sender][_doctor].active = false;
        emit ConsentRevoked(msg.sender, _doctor);
    }

    /// @notice Check if a doctor currently has valid (non-expired, active) consent
    function hasValidConsent(address _patient, address _doctor) external view returns (bool) {
        return _hasValidConsent(_patient, _doctor);
    }

    /// @notice Returns the expiry timestamp for a doctor's consent (0 if none)
    function getConsentExpiry(address _patient, address _doctor) external view returns (uint256) {
        ConsentGrant storage grant = consents[_patient][_doctor];
        if (!grant.active) return 0;
        return grant.expiryTime;
    }

    // ──────────────────── Emergency Override ────────────────────────

    /**
     * @notice Emergency personnel can access any patient's records
     * @dev Every override is permanently logged on-chain for audit purposes
     * @param _patient Patient address to access
     * @param _reason  Reason for emergency override (stored on-chain)
     */
    function emergencyAccess(address _patient, string calldata _reason) external {
        require(emergencyPersonnel[msg.sender], "DHRSS: caller is not emergency personnel");
        require(registeredPatients[_patient], "DHRSS: patient not registered");
        require(bytes(_reason).length > 0, "DHRSS: reason required");

        emergencyLog.push(EmergencyAccess({
            accessor:  msg.sender,
            patient:   _patient,
            timestamp: block.timestamp,
            reason:    _reason
        }));

        emit EmergencyOverride(msg.sender, _patient, _reason);
    }

    /// @notice Admin can retrieve the full emergency access audit log
    function getEmergencyLog() external view onlyAdmin returns (EmergencyAccess[] memory) {
        return emergencyLog;
    }

    /// @notice Returns total number of emergency accesses logged
    function getEmergencyLogCount() external view returns (uint256) {
        return emergencyLog.length;
    }

    // ──────────────────── Internal Helpers ──────────────────────────

    function _hasValidConsent(address _patient, address _doctor) internal view returns (bool) {
        ConsentGrant storage grant = consents[_patient][_doctor];
        return grant.active && block.timestamp < grant.expiryTime;
    }
}
