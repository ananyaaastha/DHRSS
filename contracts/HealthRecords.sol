// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PatientRegistry.sol";
import "./AccessControl.sol";

/**
 * @title HealthRecords
 * @author Ananya Aastha — N12125547 | IFB452 Blockchain Technology, QUT
 *
 * @notice Contract 3 of 3 — Health Record Storage and Retrieval
 *         Stores IPFS hashes of encrypted medical records on-chain.
 *         Raw medical data is stored off-chain on IPFS — only the CID
 *         and a keccak256 integrity hash are stored on-chain.
 *
 * @dev Cross-contract interactions:
 *   This contract calls PatientRegistry to verify stakeholder roles.
 *   This contract calls AccessControl to verify consent before returning data.
 *   This demonstrates direct smart contract interaction as required by the spec.
 *
 * @dev Architecture:
 *   PatientRegistry  ←── HealthRecords ──→  AccessControl
 *        ↑                                        ↑
 *   role checks                          consent checks
 */
contract HealthRecords {

    // ═══════════════════════════════════════════════════════════════
    //  ENUMS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Defines the type of medical record being stored
    enum RecordType {
        Diagnosis,          // 0 — clinical diagnosis
        Prescription,       // 1 — medication prescription
        ImagingReport,      // 2 — X-ray, MRI, CT scan reports
        LabResult,          // 3 — blood tests, pathology results
        DischargeSummary,   // 4 — hospital discharge summary
        DispensingRecord    // 5 — pharmacist dispensing record
    }

    // ═══════════════════════════════════════════════════════════════
    //  STRUCTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Represents a single health record stored on-chain
    /// @dev Only the IPFS hash is stored — raw data lives off-chain
    struct Record {
        uint256    id;          // unique record identifier
        string     ipfsHash;    // IPFS CID pointing to encrypted file
        bytes32    fileHash;    // keccak256 of file — for integrity verification
        uint256    timestamp;   // when the record was added
        address    addedBy;     // who added the record
        RecordType recordType;  // type of medical record
        bool       isValid;     // false if record has been invalidated
    }

    // ═══════════════════════════════════════════════════════════════
    //  STORAGE
    // ═══════════════════════════════════════════════════════════════

    /// @notice Address of the contract deployer — has admin privileges
    address public admin;

    /// @notice Reference to PatientRegistry for cross-contract role verification
    PatientRegistry public registry;

    /// @notice Reference to AccessControl for cross-contract consent verification
    AccessControl public accessControl;

    /// @notice Total number of records ever added across all patients
    uint256 public totalRecords;

    /// @notice patient address => array of their health records
    mapping(address => Record[]) private patientRecords;

    // ═══════════════════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Emitted when a new health record is added for a patient
    event RecordAdded(
        address    indexed patient,
        uint256    recordId,
        RecordType recordType,
        address    addedBy,
        uint256    timestamp
    );

    // ═══════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Links this contract to the other two deployed contracts
     * @param _registryAddress      Address of the deployed PatientRegistry contract
     * @param _accessControlAddress Address of the deployed AccessControl contract
     */
    constructor(address _registryAddress, address _accessControlAddress) {
        admin         = msg.sender;
        registry      = PatientRegistry(_registryAddress);
        accessControl = AccessControl(_accessControlAddress);
    }

    // ═══════════════════════════════════════════════════════════════
    //  RECORD MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    /**
     * @notice Add a health record for a patient
     * @dev Calls PatientRegistry to verify patient is registered.
     *      Calls AccessControl to verify consent for doctors and pharmacists.
     *      Only the IPFS hash is stored — raw data lives off-chain on IPFS.
     * @param _patient     Patient wallet address
     * @param _ipfsHash    IPFS CID of the encrypted medical file
     * @param _fileHash    keccak256 hash of the file for integrity verification
     * @param _recordType  Type of medical record being added
     */
    function addRecord(
        address    _patient,
        string     calldata _ipfsHash,
        bytes32    _fileHash,
        RecordType _recordType
    ) external {
        require(registry.isPatient(_patient), "DHRSS: patient not registered");
        require(bytes(_ipfsHash).length > 0, "DHRSS: IPFS hash cannot be empty");

        // Cross-contract calls to verify access rights
        bool isPatient    = msg.sender == _patient && registry.isPatient(msg.sender);
        bool isDoctor     = registry.isDoctor(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isPharmacist = registry.isPharmacist(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);

        require(isPatient || isDoctor || isPharmacist, "DHRSS: no access to add record");

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
     * @notice Retrieve all health records for a patient
     * @dev Calls PatientRegistry to verify roles.
     *      Calls AccessControl to verify consent for doctors/pharmacists/insurers.
     *      Emergency personnel can access without consent — audit log in AccessControl.
     * @param _patient Patient wallet address whose records to retrieve
     * @return Array of Record structs belonging to the patient
     */
    function getRecords(address _patient) external view returns (Record[] memory) {
        require(registry.isPatient(_patient), "DHRSS: patient not registered");

        // Cross-contract calls to verify access rights
        bool isPatient    = msg.sender == _patient && registry.isPatient(msg.sender);
        bool isDoctor     = registry.isDoctor(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isPharmacist = registry.isPharmacist(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isInsurer    = registry.isInsurer(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isEmergency  = registry.isEmergencyPersonnel(msg.sender);

        require(
            isPatient || isDoctor || isPharmacist || isInsurer || isEmergency,
            "DHRSS: access denied"
        );

        return patientRecords[_patient];
    }

    /**
     * @notice Returns the total number of records for a patient
     * @param _patient Patient wallet address
     * @return Number of records stored for this patient
     */
    function getRecordCount(address _patient) external view returns (uint256) {
        require(registry.isPatient(_patient), "DHRSS: patient not registered");
        return patientRecords[_patient].length;
    }
}