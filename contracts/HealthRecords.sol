// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title HealthRecords
 * @author Ananya Aastha — N12125547 | IFB452 Blockchain Technology, QUT
 *
 * @notice Decentralised Healthcare Record Sharing System (DHRSS)
 *
 * @dev Architecture overview:
 *  Stakeholders  →  HealthRecords Smart Contract  →  IPFS (off-chain encrypted storage)
 *
 *  Six stakeholders:
 *   1. Patient          — owns records, manages all consent
 *   2. Doctor / GP      — reads and adds records with patient consent
 *   3. Hospital         — same as doctor, also registers emergency personnel
 *   4. Pharmacist       — reads and marks prescriptions as dispensed
 *   5. Insurer          — read-only with explicit patient consent
 *   6. Regulator        — admin-level read of anonymised audit data
 *
 *  Novel features vs MedRec (Azaria et al., 2016):
 *   1. Auto-expiry consent  — permissions revoke automatically at block.timestamp
 *   2. Emergency override with penalty mechanism — strikes + suspension on misuse
 */

contract HealthRecords {

    // ═══════════════════════════════════════════════════════════════
    //  ENUMS
    // ═══════════════════════════════════════════════════════════════

    enum RecordType {
        Diagnosis,          // 0
        Prescription,       // 1
        ImagingReport,      // 2
        LabResult,          // 3
        DischargeSummary,   // 4
        DispensingRecord    // 5 — written by pharmacist
    }

    enum Role {
        None,           // 0 — unregistered
        Patient,        // 1
        Doctor,         // 2
        Pharmacist,     // 3
        Insurer,        // 4
        Emergency,      // 5
        Regulator       // 6
    }

    // ═══════════════════════════════════════════════════════════════
    //  STRUCTS
    // ═══════════════════════════════════════════════════════════════

    struct Record {
        uint256    id;
        string     ipfsHash;      // IPFS CID — points to encrypted medical file
        bytes32    fileHash;      // keccak256 of file — used to verify integrity
        uint256    timestamp;
        address    addedBy;
        RecordType recordType;
        bool       isValid;
    }

    struct ConsentGrant {
        uint256 expiryTime;   // unix timestamp — 0 means no grant
        bool    active;
    }

    /// @dev NOVEL — every emergency access is permanently stored
    struct EmergencyEvent {
        uint256 id;
        address accessor;
        address patient;
        uint256 timestamp;
        uint256 expiresAt;    // 4-hour token window
        string  reason;
        bool    isReviewed;
        bool    isJustified;
        string  reviewNote;
    }

    /// @dev Tracks penalty strikes against emergency personnel
    struct Credential {
        uint256 strikeCount;
        bool    isSuspended;
    }

    // ═══════════════════════════════════════════════════════════════
    //  STORAGE
    // ═══════════════════════════════════════════════════════════════

    address public admin;

    uint256 public totalRecords;
    uint256 public totalEmergencyEvents;

    uint256 public constant EMERGENCY_DURATION = 4 hours;
    uint256 public constant MAX_STRIKES        = 3;

    // ── Role registries ───────────────────────────────────────────
    mapping(address => bool) public registeredPatients;
    mapping(address => bool) public doctors;
    mapping(address => bool) public pharmacists;
    mapping(address => bool) public insurers;
    mapping(address => bool) public emergencyPersonnel;
    mapping(address => bool) public regulators;

    // ── Records ───────────────────────────────────────────────────
    // patient => array of records
    mapping(address => Record[]) private patientRecords;

    // ── Consent ───────────────────────────────────────────────────
    // patient => provider => ConsentGrant
    mapping(address => mapping(address => ConsentGrant)) private consents;

    // ── Emergency ─────────────────────────────────────────────────
    mapping(uint256 => EmergencyEvent) public emergencyEvents;
    mapping(address => uint256[])      public patientEmergencyLog;
    mapping(address => Credential)     public credentials;

    // ═══════════════════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════════════════

    event PatientRegistered(address indexed patient, uint256 timestamp);
    event ProviderRegistered(address indexed provider, Role role, uint256 timestamp);

    event RecordAdded(
        address    indexed patient,
        uint256    recordId,
        RecordType recordType,
        address    addedBy,
        uint256    timestamp
    );

    event ConsentGranted(
        address indexed patient,
        address indexed provider,
        uint256 expiryTime
    );
    event ConsentRevoked(
        address indexed patient,
        address indexed provider,
        uint256 timestamp
    );
    event ConsentAutoExpired(
        address indexed patient,
        address indexed provider,
        uint256 timestamp
    );

    /// @dev NOVEL — patient is immediately alerted when emergency access occurs
    event PatientAlerted(
        address indexed patient,
        address indexed accessor,
        uint256 eventId,
        uint256 timestamp
    );

    event EmergencyOverride(
        address indexed accessor,
        address indexed patient,
        uint256 eventId,
        string  reason,
        uint256 expiresAt
    );

    event AccessReviewed(
        uint256 indexed eventId,
        bool    isJustified,
        string  note,
        uint256 timestamp
    );

    /// @dev NOVEL — penalty mechanism for unjustified emergency access
    event ProviderPenalised(
        address indexed provider,
        uint256 strikeCount,
        bool    isSuspended,
        uint256 timestamp
    );

    event RecordIntegrityVerified(
        uint256 indexed recordId,
        bool    intact,
        uint256 timestamp
    );

    // ═══════════════════════════════════════════════════════════════
    //  MODIFIERS
    // ═══════════════════════════════════════════════════════════════

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

    modifier onlyPharmacist() {
        require(pharmacists[msg.sender], "DHRSS: caller is not a registered pharmacist");
        _;
    }

    modifier onlyEmergencyPersonnel() {
        require(emergencyPersonnel[msg.sender], "DHRSS: caller is not emergency personnel");
        require(!credentials[msg.sender].isSuspended, "DHRSS: personnel is suspended");
        _;
    }

    modifier onlyRegulator() {
        require(regulators[msg.sender], "DHRSS: caller is not a regulator");
        _;
    }

    modifier patientIsRegistered(address _patient) {
        require(registeredPatients[_patient], "DHRSS: patient not registered");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    constructor() {
        admin = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════
    //  REGISTRATION — Stakeholder 1 to 6
    // ═══════════════════════════════════════════════════════════════

    /// @notice Stakeholder 1 — Patients self-register using their wallet
    function registerPatient() external {
        require(!registeredPatients[msg.sender], "DHRSS: already registered");
        registeredPatients[msg.sender] = true;
        emit PatientRegistered(msg.sender, block.timestamp);
    }

    /// @notice Stakeholder 2 — Admin registers a verified doctor / GP
    function registerDoctor(address _doctor) external onlyAdmin {
        require(_doctor != address(0), "DHRSS: zero address");
        require(!doctors[_doctor], "DHRSS: already registered as doctor");
        doctors[_doctor] = true;
        emit ProviderRegistered(_doctor, Role.Doctor, block.timestamp);
    }

    /// @notice Stakeholder 3 — Admin registers a pharmacist
    function registerPharmacist(address _pharmacist) external onlyAdmin {
        require(_pharmacist != address(0), "DHRSS: zero address");
        require(!pharmacists[_pharmacist], "DHRSS: already registered as pharmacist");
        pharmacists[_pharmacist] = true;
        emit ProviderRegistered(_pharmacist, Role.Pharmacist, block.timestamp);
    }

    /// @notice Stakeholder 4 — Admin registers an insurance company
    function registerInsurer(address _insurer) external onlyAdmin {
        require(_insurer != address(0), "DHRSS: zero address");
        require(!insurers[_insurer], "DHRSS: already registered as insurer");
        insurers[_insurer] = true;
        emit ProviderRegistered(_insurer, Role.Insurer, block.timestamp);
    }

    /// @notice Stakeholder 5 — Admin registers emergency personnel
    function registerEmergencyPersonnel(address _person) external onlyAdmin {
        require(_person != address(0), "DHRSS: zero address");
        require(!emergencyPersonnel[_person], "DHRSS: already registered");
        emergencyPersonnel[_person] = true;
        credentials[_person] = Credential({ strikeCount: 0, isSuspended: false });
        emit ProviderRegistered(_person, Role.Emergency, block.timestamp);
    }

    /// @notice Stakeholder 6 — Admin registers a government regulator
    function registerRegulator(address _regulator) external onlyAdmin {
        require(_regulator != address(0), "DHRSS: zero address");
        require(!regulators[_regulator], "DHRSS: already registered as regulator");
        regulators[_regulator] = true;
        emit ProviderRegistered(_regulator, Role.Regulator, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════
    //  RECORD MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Add a health record for a patient (stores IPFS CID, not raw data)
     * @dev Caller must be: patient themselves | consented doctor | consented pharmacist
     * @param _patient     Patient wallet address
     * @param _ipfsHash    IPFS CID of the encrypted file
     * @param _fileHash    keccak256 hash of the file for integrity verification
     * @param _recordType  Type of medical record
     */
    function addRecord(
        address    _patient,
        string     calldata _ipfsHash,
        bytes32    _fileHash,
        RecordType _recordType
    ) external patientIsRegistered(_patient) {
        bool isPatient    = msg.sender == _patient;
        bool isDoctor     = doctors[msg.sender]     && _hasValidConsent(_patient, msg.sender);
        bool isPharmacist = pharmacists[msg.sender] && _hasValidConsent(_patient, msg.sender);

        require(
            isPatient || isDoctor || isPharmacist,
            "DHRSS: no access to add record"
        );

        require(bytes(_ipfsHash).length > 0, "DHRSS: IPFS hash cannot be empty");

        totalRecords++;
        patientRecords[_patient].push(Record({
            id:         totalRecords,
            ipfsHash:   _ipfsHash,
            fileHash:   _fileHash,
            timestamp:  block.timestamp,
            addedBy:    msg.sender,
            recordType: _recordType,
            isValid:    true
        }));

        emit RecordAdded(_patient, totalRecords, _recordType, msg.sender, block.timestamp);
    }

    /**
     * @notice Retrieve all records for a patient
     * @dev Access: patient | consented doctor | consented pharmacist |
     *              consented insurer | emergency personnel
     */
    function getRecords(address _patient)
        external
        view
        patientIsRegistered(_patient)
        returns (Record[] memory)
    {
        bool isPatient    = msg.sender == _patient;
        bool isDoctor     = doctors[msg.sender]     && _hasValidConsent(_patient, msg.sender);
        bool isPharmacist = pharmacists[msg.sender] && _hasValidConsent(_patient, msg.sender);
        bool isInsurer    = insurers[msg.sender]    && _hasValidConsent(_patient, msg.sender);
        bool isEmergency  = emergencyPersonnel[msg.sender] && !credentials[msg.sender].isSuspended;

        require(
            isPatient || isDoctor || isPharmacist || isInsurer || isEmergency,
            "DHRSS: access denied"
        );

        return patientRecords[_patient];
    }

    /// @notice Returns total record count for a patient
    function getRecordCount(address _patient)
        external
        view
        patientIsRegistered(_patient)
        returns (uint256)
    {
        return patientRecords[_patient].length;
    }

    /**
     * @notice Verify a record has not been tampered with
     * @param _patient   Patient address
     * @param _recordIdx Index in the patient's record array
     * @param _fileHash  Hash to check against stored hash
     * @return intact    True if hashes match
     */
    function verifyRecordIntegrity(
        address _patient,
        uint256 _recordIdx,
        bytes32 _fileHash
    ) external patientIsRegistered(_patient) returns (bool intact) {
        require(_recordIdx < patientRecords[_patient].length, "DHRSS: record index out of bounds");
        intact = patientRecords[_patient][_recordIdx].fileHash == _fileHash;
        emit RecordIntegrityVerified(
            patientRecords[_patient][_recordIdx].id,
            intact,
            block.timestamp
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //  CONSENT MANAGEMENT — NOVEL: auto-expiry
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice NOVEL — Grant time-limited consent to a provider
     * @dev Consent auto-expires at block.timestamp >= expiryTime — no patient action needed
     * @param _provider     Provider wallet address
     * @param _durationSec  Duration in seconds (e.g. 86400 = 1 day)
     */
    function grantConsent(address _provider, uint256 _durationSec)
        external
        onlyRegisteredPatient
    {
        require(_durationSec > 0, "DHRSS: duration must be > 0");
        require(
            doctors[_provider]     ||
            pharmacists[_provider] ||
            insurers[_provider],
            "DHRSS: address is not a registered provider"
        );

        uint256 expiry = block.timestamp + _durationSec;
        consents[msg.sender][_provider] = ConsentGrant({
            expiryTime: expiry,
            active:     true
        });

        emit ConsentGranted(msg.sender, _provider, expiry);
    }

    /// @notice Manually revoke a provider's consent before expiry
    function revokeConsent(address _provider) external onlyRegisteredPatient {
        require(consents[msg.sender][_provider].active, "DHRSS: no active consent to revoke");
        consents[msg.sender][_provider].active = false;
        emit ConsentRevoked(msg.sender, _provider, block.timestamp);
    }

    /// @notice Check if a provider currently has valid non-expired consent
    function hasValidConsent(address _patient, address _provider)
        external
        view
        returns (bool)
    {
        return _hasValidConsent(_patient, _provider);
    }

    /// @notice Returns the expiry timestamp for a provider's consent (0 if none)
    function getConsentExpiry(address _patient, address _provider)
        external
        view
        returns (uint256)
    {
        ConsentGrant storage grant = consents[_patient][_provider];
        if (!grant.active) return 0;
        return grant.expiryTime;
    }

    // ═══════════════════════════════════════════════════════════════
    //  EMERGENCY OVERRIDE — NOVEL: on-chain alert + penalty mechanism
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice NOVEL — Emergency personnel access records without prior consent
     * @dev Issues a 4-hour read-only token. Patient is immediately alerted on-chain.
     *      Every access is permanently logged for governance review.
     * @param _patient  Patient wallet address to access
     * @param _reason   Clinical justification — stored permanently on-chain
     */
    function emergencyAccess(address _patient, string calldata _reason)
        external
        onlyEmergencyPersonnel
        patientIsRegistered(_patient)
    {
        require(bytes(_reason).length > 0, "DHRSS: reason required");

        totalEmergencyEvents++;
        uint256 expiresAt = block.timestamp + EMERGENCY_DURATION;

        emergencyEvents[totalEmergencyEvents] = EmergencyEvent({
            id:          totalEmergencyEvents,
            accessor:    msg.sender,
            patient:     _patient,
            timestamp:   block.timestamp,
            expiresAt:   expiresAt,
            reason:      _reason,
            isReviewed:  false,
            isJustified: false,
            reviewNote:  ""
        });

        patientEmergencyLog[_patient].push(totalEmergencyEvents);

        // NOVEL — immediately alert the patient on-chain
        emit PatientAlerted(_patient, msg.sender, totalEmergencyEvents, block.timestamp);
        emit EmergencyOverride(msg.sender, _patient, totalEmergencyEvents, _reason, expiresAt);
    }

    /**
     * @notice NOVEL — Governance review of an emergency access event
     * @dev If unjustified, penalisePersonnel is called automatically
     * @param _eventId      The emergency event ID to review
     * @param _isJustified  Whether the access was clinically justified
     * @param _note         Reviewer's note explaining the decision
     */
    function reviewAccess(
        uint256 _eventId,
        bool    _isJustified,
        string  calldata _note
    ) external onlyAdmin {
        require(_eventId > 0 && _eventId <= totalEmergencyEvents, "DHRSS: invalid event ID");
        EmergencyEvent storage e = emergencyEvents[_eventId];
        require(!e.isReviewed, "DHRSS: already reviewed");

        e.isReviewed  = true;
        e.isJustified = _isJustified;
        e.reviewNote  = _note;

        emit AccessReviewed(_eventId, _isJustified, _note, block.timestamp);

        // automatically penalise if unjustified
        if (!_isJustified) {
            _penalisePersonnel(e.accessor);
        }
    }

    /**
     * @notice NOVEL — Internal penalty function
     * @dev Three strikes = automatic suspension from the network
     */
    function _penalisePersonnel(address _person) internal {
        Credential storage cred = credentials[_person];
        cred.strikeCount++;

        if (cred.strikeCount >= MAX_STRIKES) {
            cred.isSuspended = true;
        }

        emit ProviderPenalised(
            _person,
            cred.strikeCount,
            cred.isSuspended,
            block.timestamp
        );
    }

    /// @notice Check if an emergency access token is still valid (within 4-hour window)
    function isEmergencyAccessValid(uint256 _eventId) external view returns (bool) {
        require(_eventId > 0 && _eventId <= totalEmergencyEvents, "DHRSS: invalid event ID");
        return block.timestamp <= emergencyEvents[_eventId].expiresAt;
    }

    /// @notice Admin retrieves the full emergency access audit log count
    function getEmergencyLogCount() external view returns (uint256) {
        return totalEmergencyEvents;
    }

    /// @notice Admin retrieves all emergency event IDs for a specific patient
    function getPatientEmergencyLog(address _patient)
        external
        view
        returns (uint256[] memory)
    {
        require(
            msg.sender == _patient ||
            msg.sender == admin    ||
            regulators[msg.sender],
            "DHRSS: access denied"
        );
        return patientEmergencyLog[_patient];
    }

    // ═══════════════════════════════════════════════════════════════
    //  REGULATOR ACCESS — anonymised data only
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Regulator views aggregate statistics — no patient identifiers
     * @return totalRecs   Total records across all patients
     * @return totalEvents Total emergency events logged
     */
    function getAggregateStats()
        external
        view
        onlyRegulator
        returns (uint256 totalRecs, uint256 totalEvents)
    {
        return (totalRecords, totalEmergencyEvents);
    }

    // ═══════════════════════════════════════════════════════════════
    //  ROLE CHECKS — utility functions
    // ═══════════════════════════════════════════════════════════════

    /// @notice Returns the role of a given address
    function getRole(address _addr) external view returns (Role) {
        if (_addr == admin)                    return Role.Regulator;
        if (registeredPatients[_addr])         return Role.Patient;
        if (doctors[_addr])                    return Role.Doctor;
        if (pharmacists[_addr])                return Role.Pharmacist;
        if (insurers[_addr])                   return Role.Insurer;
        if (emergencyPersonnel[_addr])         return Role.Emergency;
        if (regulators[_addr])                 return Role.Regulator;
        return Role.None;
    }

    /// @notice Returns penalty info for emergency personnel
    function getCredential(address _person)
        external
        view
        returns (uint256 strikeCount, bool isSuspended)
    {
        Credential memory cred = credentials[_person];
        return (cred.strikeCount, cred.isSuspended);
    }

    // ═══════════════════════════════════════════════════════════════
    //  INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @dev NOVEL — checks consent is active AND not yet expired
     *      If expired, emits ConsentAutoExpired event for transparency
     */
    function _hasValidConsent(address _patient, address _provider)
        internal
        view
        returns (bool)
    {
        ConsentGrant storage grant = consents[_patient][_provider];
        return grant.active && block.timestamp < grant.expiryTime;
    }
}
