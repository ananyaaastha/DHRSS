// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PatientRegistry.sol";

/**
 * @title AccessControl
 * @author Ananya Aastha — N12125547 | IFB452 Blockchain Technology, QUT
 *
 * @notice Contract 2 of 3 — Consent and Emergency Access Management
 *         Manages time-limited consent grants between patients and providers.
 *         Handles emergency override with permanent on-chain logging.
 *         Called by HealthRecords before returning any patient data.
 *
 * @dev NOVEL features vs MedRec (Azaria et al., 2016):
 *   1. Auto-expiry consent — permissions revoke automatically at block.timestamp
 *      No patient action needed — the contract enforces expiry automatically
 *   2. Emergency override with penalty mechanism
 *      Every access is permanently logged. Unjustified access = strike.
 *      Three strikes = automatic suspension from the network.
 *
 * @dev Cross-contract interaction:
 *   This contract calls PatientRegistry to verify roles before
 *   granting or revoking consent and before allowing emergency access.
 */
contract AccessControl {

    // ═══════════════════════════════════════════════════════════════
    //  STRUCTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Stores a time-limited consent grant from patient to provider
    struct ConsentGrant {
        uint256 expiryTime;   // unix timestamp — consent invalid after this
        bool    active;       // false if manually revoked before expiry
    }

    /// @dev NOVEL — every emergency access is permanently stored on-chain
    ///      Records can never be deleted — full immutable audit trail
    struct EmergencyEvent {
        uint256 id;           // unique event identifier
        address accessor;     // emergency personnel who accessed
        address patient;      // patient whose records were accessed
        uint256 timestamp;    // when the access occurred
        uint256 expiresAt;    // 4-hour read token expiry
        string  reason;       // clinical justification — permanently stored
        bool    isReviewed;   // whether admin has reviewed this event
        bool    isJustified;  // admin's ruling on whether access was justified
        string  reviewNote;   // admin's review note
    }

    /// @dev Tracks penalty strikes against emergency personnel
    ///      Three unjustified accesses = automatic suspension
    struct Credential {
        uint256 strikeCount;  // number of unjustified accesses
        bool    isSuspended;  // true if strikeCount >= MAX_STRIKES
    }

    // ═══════════════════════════════════════════════════════════════
    //  STORAGE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Address of the contract deployer — has admin privileges
    address public admin;

    /// @notice Reference to PatientRegistry for cross-contract role verification
    PatientRegistry public registry;

    /// @notice Total number of emergency events ever logged
    uint256 public totalEmergencyEvents;

    /// @notice Emergency access token lasts 4 hours — read-only window
    uint256 public constant EMERGENCY_DURATION = 4 hours;

    /// @notice Three unjustified accesses triggers automatic suspension
    uint256 public constant MAX_STRIKES = 3;

    /// @notice patient => provider => ConsentGrant
    /// @dev NOVEL — auto-expiry checked at call time, no cron job needed
    mapping(address => mapping(address => ConsentGrant)) private consents;

    /// @notice Permanent registry of all emergency events — immutable audit trail
    mapping(uint256 => EmergencyEvent) public emergencyEvents;

    /// @notice patient => list of emergency event IDs affecting them
    mapping(address => uint256[]) public patientEmergencyLog;

    /// @notice Penalty record for each emergency personnel address
    mapping(address => Credential) public credentials;

    // ═══════════════════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Emitted when a patient grants time-limited consent to a provider
    event ConsentGranted(address indexed patient, address indexed provider, uint256 expiryTime);

    /// @notice Emitted when a patient manually revokes consent before expiry
    event ConsentRevoked(address indexed patient, address indexed provider, uint256 timestamp);

    /// @dev NOVEL — patient is immediately alerted on-chain when emergency access occurs
    event PatientAlerted(address indexed patient, address indexed accessor, uint256 eventId, uint256 timestamp);

    /// @notice Emitted when emergency personnel access records without consent
    event EmergencyOverride(address indexed accessor, address indexed patient, uint256 eventId, string reason, uint256 expiresAt);

    /// @notice Emitted when admin reviews an emergency access event
    event AccessReviewed(uint256 indexed eventId, bool isJustified, string note, uint256 timestamp);

    /// @dev NOVEL — emitted when emergency personnel receive a penalty strike
    event ProviderPenalised(address indexed provider, uint256 strikeCount, bool isSuspended, uint256 timestamp);

    // ═══════════════════════════════════════════════════════════════
    //  MODIFIERS
    // ═══════════════════════════════════════════════════════════════

    /// @dev Restricts function to the contract deployer only
    modifier onlyAdmin() {
        require(msg.sender == admin, "DHRSS: caller is not admin");
        _;
    }

    // ═══════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    /// @notice Sets admin and links to the deployed PatientRegistry contract
    /// @param _registryAddress Address of the deployed PatientRegistry contract
    constructor(address _registryAddress) {
        admin    = msg.sender;
        registry = PatientRegistry(_registryAddress);
    }

    // ═══════════════════════════════════════════════════════════════
    //  CONSENT MANAGEMENT — NOVEL: auto-expiry
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice NOVEL — Grant time-limited consent to a provider
     * @dev Calls PatientRegistry to verify caller is a registered patient
     *      and that the provider is a registered doctor/pharmacist/insurer.
     *      Consent auto-expires at block.timestamp >= expiryTime — no patient action needed.
     * @param _provider    Provider wallet address to grant access to
     * @param _durationSec Duration in seconds (e.g. 86400 = 1 day, 3600 = 1 hour)
     */
    function grantConsent(address _provider, uint256 _durationSec) external {
        require(registry.isPatient(msg.sender), "DHRSS: caller is not a registered patient");
        require(_durationSec > 0, "DHRSS: duration must be > 0");
        require(
            registry.isDoctor(_provider)     ||
            registry.isPharmacist(_provider) ||
            registry.isInsurer(_provider),
            "DHRSS: address is not a registered provider"
        );
        uint256 expiry = block.timestamp + _durationSec;
        consents[msg.sender][_provider] = ConsentGrant({ expiryTime: expiry, active: true });
        emit ConsentGranted(msg.sender, _provider, expiry);
    }

    /**
     * @notice Manually revoke a provider's consent before expiry
     * @dev Calls PatientRegistry to verify caller is a registered patient
     * @param _provider Provider wallet address to revoke access from
     */
    function revokeConsent(address _provider) external {
        require(registry.isPatient(msg.sender), "DHRSS: caller is not a registered patient");
        require(consents[msg.sender][_provider].active, "DHRSS: no active consent to revoke");
        consents[msg.sender][_provider].active = false;
        emit ConsentRevoked(msg.sender, _provider, block.timestamp);
    }

    /**
     * @notice Check if a provider currently has valid non-expired consent
     * @dev Called by HealthRecords before returning patient data
     *      NOVEL — checks both active flag AND timestamp expiry
     * @param _patient  Patient wallet address
     * @param _provider Provider wallet address
     * @return true if consent is active and not yet expired
     */
    function hasValidConsent(address _patient, address _provider) external view returns (bool) {
        ConsentGrant storage grant = consents[_patient][_provider];
        return grant.active && block.timestamp < grant.expiryTime;
    }

    /// @notice Returns the expiry timestamp for a provider's consent (0 if none)
    function getConsentExpiry(address _patient, address _provider) external view returns (uint256) {
        ConsentGrant storage grant = consents[_patient][_provider];
        if (!grant.active) return 0;
        return grant.expiryTime;
    }

    // ═══════════════════════════════════════════════════════════════
    //  EMERGENCY OVERRIDE — NOVEL: on-chain alert + penalty mechanism
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice NOVEL — Emergency personnel access records without prior consent
     * @dev Calls PatientRegistry to verify caller is registered emergency personnel
     *      and that the patient is registered. Issues a 4-hour read-only token.
     *      Patient is immediately alerted on-chain via PatientAlerted event.
     *      Every access is permanently logged — records can never be deleted.
     * @param _patient  Patient wallet address whose records are being accessed
     * @param _reason   Clinical justification — stored permanently on-chain
     */
    function emergencyAccess(address _patient, string calldata _reason) external {
        require(registry.isEmergencyPersonnel(msg.sender), "DHRSS: caller is not emergency personnel");
        require(!credentials[msg.sender].isSuspended, "DHRSS: personnel is suspended");
        require(registry.isPatient(_patient), "DHRSS: patient not registered");
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
     * @dev If unjustified, _penalisePersonnel is called automatically.
     *      Three unjustified accesses = automatic suspension.
     * @param _eventId      The emergency event ID to review
     * @param _isJustified  Whether the access was clinically justified
     * @param _note         Reviewer's note explaining the decision
     */
    function reviewAccess(uint256 _eventId, bool _isJustified, string calldata _note) external onlyAdmin {
        require(_eventId > 0 && _eventId <= totalEmergencyEvents, "DHRSS: invalid event ID");
        EmergencyEvent storage e = emergencyEvents[_eventId];
        require(!e.isReviewed, "DHRSS: already reviewed");
        e.isReviewed  = true;
        e.isJustified = _isJustified;
        e.reviewNote  = _note;
        emit AccessReviewed(_eventId, _isJustified, _note, block.timestamp);
        if (!_isJustified) { _penalisePersonnel(e.accessor); }
    }

    /**
     * @notice NOVEL — Internal penalty function
     * @dev Three strikes = automatic suspension from the network
     *      Suspended personnel cannot call emergencyAccess
     * @param _person Address of the emergency personnel to penalise
     */
    function _penalisePersonnel(address _person) internal {
        Credential storage cred = credentials[_person];
        cred.strikeCount++;
        if (cred.strikeCount >= MAX_STRIKES) { cred.isSuspended = true; }
        emit ProviderPenalised(_person, cred.strikeCount, cred.isSuspended, block.timestamp);
    }

    /// @notice Returns total number of emergency events ever logged
    function getEmergencyLogCount() external view returns (uint256) {
        return totalEmergencyEvents;
    }

    /// @notice Returns penalty info for emergency personnel
    function getCredential(address _person) external view returns (uint256 strikeCount, bool isSuspended) {
        return (credentials[_person].strikeCount, credentials[_person].isSuspended);
    }
}