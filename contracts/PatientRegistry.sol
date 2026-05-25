// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title PatientRegistry
 * @author Ananya Aastha — N12125547 | IFB452 Blockchain Technology, QUT
 *
 * @notice Contract 1 of 3 — Stakeholder Registration
 *         Manages all role assignments for the DHRSS system.
 *         This is the source of truth for identity verification.
 *         AccessControl and HealthRecords call this contract to verify roles
 *         before performing any sensitive operations.
 *
 * @dev Stakeholders:
 *   1. Patient          — self-registers using their wallet
 *   2. Doctor           — registered by admin after credential verification
 *   3. Pharmacist       — registered by admin
 *   4. Insurer          — registered by admin, read-only with patient consent
 *   5. Emergency        — registered by admin, bypass consent in emergencies
 *   6. Regulator        — registered by admin, anonymised audit access only
 */
contract PatientRegistry {

    // ═══════════════════════════════════════════════════════════════
    //  ENUMS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Defines all stakeholder roles in the DHRSS system
    enum Role {
        None,           // 0 — unregistered address
        Patient,        // 1 — self-registered patient
        Doctor,         // 2 — admin-verified medical doctor
        Pharmacist,     // 3 — admin-verified pharmacist
        Insurer,        // 4 — admin-verified insurance company
        Emergency,      // 5 — admin-verified emergency personnel
        Regulator       // 6 — government regulator / admin
    }

    // ═══════════════════════════════════════════════════════════════
    //  STORAGE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Address of the contract deployer — has admin privileges
    address public admin;

    /// @notice Role registries — one mapping per stakeholder type
    mapping(address => bool) public registeredPatients;
    mapping(address => bool) public doctors;
    mapping(address => bool) public pharmacists;
    mapping(address => bool) public insurers;
    mapping(address => bool) public emergencyPersonnel;
    mapping(address => bool) public regulators;

    // ═══════════════════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Emitted when a patient self-registers
    event PatientRegistered(address indexed patient, uint256 timestamp);

    /// @notice Emitted when admin registers any provider role
    event ProviderRegistered(address indexed provider, Role role, uint256 timestamp);

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

    /// @notice Sets the deployer as admin on deployment
    constructor() {
        admin = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════
    //  REGISTRATION — Stakeholders 1 to 6
    // ═══════════════════════════════════════════════════════════════

    /// @notice Stakeholder 1 — Patients self-register using their wallet
    /// @dev No admin approval needed — patients own their registration
    function registerPatient() external {
        require(!registeredPatients[msg.sender], "DHRSS: already registered");
        registeredPatients[msg.sender] = true;
        emit PatientRegistered(msg.sender, block.timestamp);
    }

    /// @notice Stakeholder 2 — Admin registers a verified doctor / GP
    /// @param _doctor Wallet address of the doctor to register
    function registerDoctor(address _doctor) external onlyAdmin {
        require(_doctor != address(0), "DHRSS: zero address");
        require(!doctors[_doctor], "DHRSS: already registered as doctor");
        doctors[_doctor] = true;
        emit ProviderRegistered(_doctor, Role.Doctor, block.timestamp);
    }

    /// @notice Stakeholder 3 — Admin registers a pharmacist
    /// @param _pharmacist Wallet address of the pharmacist to register
    function registerPharmacist(address _pharmacist) external onlyAdmin {
        require(_pharmacist != address(0), "DHRSS: zero address");
        require(!pharmacists[_pharmacist], "DHRSS: already registered as pharmacist");
        pharmacists[_pharmacist] = true;
        emit ProviderRegistered(_pharmacist, Role.Pharmacist, block.timestamp);
    }

    /// @notice Stakeholder 4 — Admin registers an insurance company
    /// @param _insurer Wallet address of the insurer to register
    function registerInsurer(address _insurer) external onlyAdmin {
        require(_insurer != address(0), "DHRSS: zero address");
        require(!insurers[_insurer], "DHRSS: already registered as insurer");
        insurers[_insurer] = true;
        emit ProviderRegistered(_insurer, Role.Insurer, block.timestamp);
    }

    /// @notice Stakeholder 5 — Admin registers emergency personnel
    /// @dev Emergency personnel can bypass consent in genuine emergencies
    /// @param _person Wallet address of the emergency personnel to register
    function registerEmergencyPersonnel(address _person) external onlyAdmin {
        require(_person != address(0), "DHRSS: zero address");
        require(!emergencyPersonnel[_person], "DHRSS: already registered");
        emergencyPersonnel[_person] = true;
        emit ProviderRegistered(_person, Role.Emergency, block.timestamp);
    }

    /// @notice Stakeholder 6 — Admin registers a government regulator
    /// @param _regulator Wallet address of the regulator to register
    function registerRegulator(address _regulator) external onlyAdmin {
        require(_regulator != address(0), "DHRSS: zero address");
        require(!regulators[_regulator], "DHRSS: already registered as regulator");
        regulators[_regulator] = true;
        emit ProviderRegistered(_regulator, Role.Regulator, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════
    //  ROLE CHECKS — called externally by AccessControl and HealthRecords
    // ═══════════════════════════════════════════════════════════════

    /// @notice Check if an address is a registered patient
    function isPatient(address _addr) external view returns (bool) {
        return registeredPatients[_addr];
    }

    /// @notice Check if an address is a registered doctor
    function isDoctor(address _addr) external view returns (bool) {
        return doctors[_addr];
    }

    /// @notice Check if an address is a registered pharmacist
    function isPharmacist(address _addr) external view returns (bool) {
        return pharmacists[_addr];
    }

    /// @notice Check if an address is a registered insurer
    function isInsurer(address _addr) external view returns (bool) {
        return insurers[_addr];
    }

    /// @notice Check if an address is registered emergency personnel
    function isEmergencyPersonnel(address _addr) external view returns (bool) {
        return emergencyPersonnel[_addr];
    }

    /// @notice Check if an address is a registered regulator
    function isRegulator(address _addr) external view returns (bool) {
        return regulators[_addr];
    }

    /// @notice Returns the role enum for any address
    function getRole(address _addr) external view returns (Role) {
        if (_addr == admin)                return Role.Regulator;
        if (registeredPatients[_addr])     return Role.Patient;
        if (doctors[_addr])                return Role.Doctor;
        if (pharmacists[_addr])            return Role.Pharmacist;
        if (insurers[_addr])               return Role.Insurer;
        if (emergencyPersonnel[_addr])     return Role.Emergency;
        if (regulators[_addr])             return Role.Regulator;
        return Role.None;
    }
}