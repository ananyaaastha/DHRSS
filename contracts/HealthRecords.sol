// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PatientRegistry.sol";
import "./AccessControl.sol";

contract HealthRecords {

    enum RecordType { Diagnosis, Prescription, ImagingReport, LabResult, DischargeSummary, DispensingRecord }

    struct Record {
        uint256    id;
        string     ipfsHash;
        bytes32    fileHash;
        uint256    timestamp;
        address    addedBy;
        RecordType recordType;
        bool       isValid;
    }

    address public admin;
    PatientRegistry public registry;
    AccessControl   public accessControl;

    uint256 public totalRecords;
    mapping(address => Record[]) private patientRecords;

    event RecordAdded(address indexed patient, uint256 recordId, RecordType recordType, address addedBy, uint256 timestamp);

    constructor(address _registryAddress, address _accessControlAddress) {
        admin         = msg.sender;
        registry      = PatientRegistry(_registryAddress);
        accessControl = AccessControl(_accessControlAddress);
    }

    function addRecord(address _patient, string calldata _ipfsHash, bytes32 _fileHash, RecordType _recordType) external {
        require(registry.isPatient(_patient), "DHRSS: patient not registered");
        require(bytes(_ipfsHash).length > 0, "DHRSS: IPFS hash cannot be empty");

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

    function getRecords(address _patient) external view returns (Record[] memory) {
        require(registry.isPatient(_patient), "DHRSS: patient not registered");

        bool isPatient    = msg.sender == _patient && registry.isPatient(msg.sender);
        bool isDoctor     = registry.isDoctor(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isPharmacist = registry.isPharmacist(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isInsurer    = registry.isInsurer(msg.sender) && accessControl.hasValidConsent(_patient, msg.sender);
        bool isEmergency  = registry.isEmergencyPersonnel(msg.sender);

        require(isPatient || isDoctor || isPharmacist || isInsurer || isEmergency, "DHRSS: access denied");

        return patientRecords[_patient];
    }

    function getRecordCount(address _patient) external view returns (uint256) {
        require(registry.isPatient(_patient), "DHRSS: patient not registered");
        return patientRecords[_patient].length;
    }
}