// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract PatientRegistry {

    enum Role { None, Patient, Doctor, Pharmacist, Insurer, Emergency, Regulator }

    address public admin;

    mapping(address => bool) public registeredPatients;
    mapping(address => bool) public doctors;
    mapping(address => bool) public pharmacists;
    mapping(address => bool) public insurers;
    mapping(address => bool) public emergencyPersonnel;
    mapping(address => bool) public regulators;

    event PatientRegistered(address indexed patient, uint256 timestamp);
    event ProviderRegistered(address indexed provider, Role role, uint256 timestamp);

    modifier onlyAdmin() {
        require(msg.sender == admin, "DHRSS: caller is not admin");
        _;
    }

    constructor() { admin = msg.sender; }

    function registerPatient() external {
        require(!registeredPatients[msg.sender], "DHRSS: already registered");
        registeredPatients[msg.sender] = true;
        emit PatientRegistered(msg.sender, block.timestamp);
    }

    function registerDoctor(address _doctor) external onlyAdmin {
        require(_doctor != address(0), "DHRSS: zero address");
        require(!doctors[_doctor], "DHRSS: already registered as doctor");
        doctors[_doctor] = true;
        emit ProviderRegistered(_doctor, Role.Doctor, block.timestamp);
    }

    function registerPharmacist(address _pharmacist) external onlyAdmin {
        require(_pharmacist != address(0), "DHRSS: zero address");
        require(!pharmacists[_pharmacist], "DHRSS: already registered as pharmacist");
        pharmacists[_pharmacist] = true;
        emit ProviderRegistered(_pharmacist, Role.Pharmacist, block.timestamp);
    }

    function registerInsurer(address _insurer) external onlyAdmin {
        require(_insurer != address(0), "DHRSS: zero address");
        require(!insurers[_insurer], "DHRSS: already registered as insurer");
        insurers[_insurer] = true;
        emit ProviderRegistered(_insurer, Role.Insurer, block.timestamp);
    }

    function registerEmergencyPersonnel(address _person) external onlyAdmin {
        require(_person != address(0), "DHRSS: zero address");
        require(!emergencyPersonnel[_person], "DHRSS: already registered");
        emergencyPersonnel[_person] = true;
        emit ProviderRegistered(_person, Role.Emergency, block.timestamp);
    }

    function registerRegulator(address _regulator) external onlyAdmin {
        require(_regulator != address(0), "DHRSS: zero address");
        require(!regulators[_regulator], "DHRSS: already registered as regulator");
        regulators[_regulator] = true;
        emit ProviderRegistered(_regulator, Role.Regulator, block.timestamp);
    }

    function isPatient(address _addr) external view returns (bool) { return registeredPatients[_addr]; }
    function isDoctor(address _addr) external view returns (bool) { return doctors[_addr]; }
    function isPharmacist(address _addr) external view returns (bool) { return pharmacists[_addr]; }
    function isInsurer(address _addr) external view returns (bool) { return insurers[_addr]; }
    function isEmergencyPersonnel(address _addr) external view returns (bool) { return emergencyPersonnel[_addr]; }
    function isRegulator(address _addr) external view returns (bool) { return regulators[_addr]; }

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