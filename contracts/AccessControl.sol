// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PatientRegistry.sol";

contract AccessControl {

    struct ConsentGrant { uint256 expiryTime; bool active; }

    struct EmergencyEvent {
        uint256 id;
        address accessor;
        address patient;
        uint256 timestamp;
        uint256 expiresAt;
        string  reason;
        bool    isReviewed;
        bool    isJustified;
        string  reviewNote;
    }

    struct Credential { uint256 strikeCount; bool isSuspended; }

    address public admin;
    PatientRegistry public registry;

    uint256 public totalEmergencyEvents;
    uint256 public constant EMERGENCY_DURATION = 4 hours;
    uint256 public constant MAX_STRIKES = 3;

    mapping(address => mapping(address => ConsentGrant)) private consents;
    mapping(uint256 => EmergencyEvent) public emergencyEvents;
    mapping(address => uint256[]) public patientEmergencyLog;
    mapping(address => Credential) public credentials;

    event ConsentGranted(address indexed patient, address indexed provider, uint256 expiryTime);
    event ConsentRevoked(address indexed patient, address indexed provider, uint256 timestamp);
    event PatientAlerted(address indexed patient, address indexed accessor, uint256 eventId, uint256 timestamp);
    event EmergencyOverride(address indexed accessor, address indexed patient, uint256 eventId, string reason, uint256 expiresAt);
    event AccessReviewed(uint256 indexed eventId, bool isJustified, string note, uint256 timestamp);
    event ProviderPenalised(address indexed provider, uint256 strikeCount, bool isSuspended, uint256 timestamp);

    modifier onlyAdmin() {
        require(msg.sender == admin, "DHRSS: caller is not admin");
        _;
    }

    constructor(address _registryAddress) {
        admin    = msg.sender;
        registry = PatientRegistry(_registryAddress);
    }

    function grantConsent(address _provider, uint256 _durationSec) external {
        require(registry.isPatient(msg.sender), "DHRSS: caller is not a registered patient");
        require(_durationSec > 0, "DHRSS: duration must be > 0");
        require(
            registry.isDoctor(_provider) ||
            registry.isPharmacist(_provider) ||
            registry.isInsurer(_provider),
            "DHRSS: address is not a registered provider"
        );
        uint256 expiry = block.timestamp + _durationSec;
        consents[msg.sender][_provider] = ConsentGrant({ expiryTime: expiry, active: true });
        emit ConsentGranted(msg.sender, _provider, expiry);
    }

    function revokeConsent(address _provider) external {
        require(registry.isPatient(msg.sender), "DHRSS: caller is not a registered patient");
        require(consents[msg.sender][_provider].active, "DHRSS: no active consent to revoke");
        consents[msg.sender][_provider].active = false;
        emit ConsentRevoked(msg.sender, _provider, block.timestamp);
    }

    function hasValidConsent(address _patient, address _provider) external view returns (bool) {
        ConsentGrant storage grant = consents[_patient][_provider];
        return grant.active && block.timestamp < grant.expiryTime;
    }

    function getConsentExpiry(address _patient, address _provider) external view returns (uint256) {
        ConsentGrant storage grant = consents[_patient][_provider];
        if (!grant.active) return 0;
        return grant.expiryTime;
    }

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
        emit PatientAlerted(_patient, msg.sender, totalEmergencyEvents, block.timestamp);
        emit EmergencyOverride(msg.sender, _patient, totalEmergencyEvents, _reason, expiresAt);
    }

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

    function _penalisePersonnel(address _person) internal {
        Credential storage cred = credentials[_person];
        cred.strikeCount++;
        if (cred.strikeCount >= MAX_STRIKES) { cred.isSuspended = true; }
        emit ProviderPenalised(_person, cred.strikeCount, cred.isSuspended, block.timestamp);
    }

    function getEmergencyLogCount() external view returns (uint256) { return totalEmergencyEvents; }

    function getCredential(address _person) external view returns (uint256 strikeCount, bool isSuspended) {
        return (credentials[_person].strikeCount, credentials[_person].isSuspended);
    }
}