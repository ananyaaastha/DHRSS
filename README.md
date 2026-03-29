# 🏥 DHRSS — Decentralised Healthcare Record Sharing System

A blockchain-based platform for secure, patient-owned medical records built with **Solidity**, **Web3.py**, and **Flask**.

---

## ✨ Features

| Feature | Description |
|---|---|
| 📋 **Patient Records** | Upload encrypted records (IPFS hashes) linked to your wallet |
| ⏱️ **Auto-Expiry Consent** | Grant time-limited access to doctors — automatically revokes on-chain when expired |
| 🚨 **Emergency Override** | Authorised emergency personnel can access records; every override is permanently logged |
| 👨‍⚕️ **Doctor Access Control** | Admin-verified doctors can only view/add records when patient consent is active |

---

## 🏗️ Tech Stack

- **Smart Contract** — Solidity `^0.8.19`
- **Blockchain Interaction** — Web3.py `6.x`
- **Backend** — Python / Flask `3.x`
- **Frontend** — Bootstrap 5 + Vanilla JS
- **Storage** — IPFS (records stored as CID hashes on-chain)
- **Local Dev Node** — Hardhat / Ganache

---

## 📁 Project Structure

```
DHRSS/
├── contracts/
│   ├── HealthRecords.sol       # Smart contract
│   └── abi/
│       └── HealthRecords.json  # Compiled ABI
├── app/
│   ├── __init__.py             # Flask app factory
│   ├── blockchain.py           # Web3.py client wrapper
│   ├── routes.py               # Flask REST API routes
│   ├── templates/              # Jinja2 HTML templates
│   │   ├── base.html
│   │   ├── index.html
│   │   ├── patient_dashboard.html
│   │   ├── doctor_dashboard.html
│   │   └── admin_dashboard.html
│   └── static/
│       └── style.css
├── deploy.py                   # Contract deployment script
├── run.py                      # Flask entry point
├── requirements.txt
└── .env.example
```

---

## 🚀 Quick Start

### 1. Clone & install dependencies

```bash
git clone https://github.com/YOUR_USERNAME/DHRSS.git
cd DHRSS
pip install -r requirements.txt
```

### 2. Start a local blockchain node

Using **Hardhat** (recommended):
```bash
npx hardhat node
```

Or using **Ganache**:
```bash
ganache --port 8545
```

### 3. Configure environment

```bash
cp .env.example .env
# Edit .env with your deployer address & private key from the local node
```

### 4. Deploy the smart contract

```bash
python deploy.py
```

Copy the printed `CONTRACT_ADDRESS` into your `.env` file.

### 5. Run the Flask app

```bash
python run.py
```

Open **http://localhost:5000** in your browser.

---

## 📡 API Reference

All endpoints accept/return JSON. POST to:

| Endpoint | Description |
|---|---|
| `POST /api/register/patient` | Register a patient wallet |
| `POST /api/register/doctor` | Admin registers a doctor |
| `POST /api/register/emergency` | Admin registers emergency personnel |
| `POST /api/records/add` | Add a health record (IPFS hash) |
| `POST /api/records/get` | Retrieve records (access-controlled) |
| `POST /api/consent/grant` | Grant time-limited doctor consent |
| `POST /api/consent/revoke` | Immediately revoke consent |
| `POST /api/consent/check` | Check if consent is active |
| `POST /api/emergency/access` | Trigger emergency override |
| `POST /api/emergency/log` | Admin view of all emergency accesses |
| `POST /api/check/role` | Look up roles for an address |

---

## 🔐 Smart Contract Design

### Auto-Expiry Consent

```solidity
function grantConsent(address _doctor, uint256 _durationSec) external {
    consents[msg.sender][_doctor] = ConsentGrant({
        expiryTime: block.timestamp + _durationSec,
        active: true
    });
}
```

Consent is checked at the time of access — if `block.timestamp >= expiryTime`, access is denied automatically with no additional transaction needed.

### Emergency Override + Audit Trail

```solidity
function emergencyAccess(address _patient, string calldata _reason) external {
    require(emergencyPersonnel[msg.sender], "Not emergency personnel");
    emergencyLog.push(EmergencyAccess({
        accessor: msg.sender,
        patient: _patient,
        timestamp: block.timestamp,
        reason: _reason
    }));
    emit EmergencyOverride(msg.sender, _patient, _reason);
}
```

Every emergency access is immutably stored on-chain and emits an event for off-chain monitoring.

---

## 🌐 Deploying to Testnet (Sepolia)

1. Get Sepolia ETH from a faucet (e.g. [sepoliafaucet.com](https://sepoliafaucet.com))
2. Update `.env`:
   ```
   WEB3_PROVIDER_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
   CHAIN_ID=11155111
   ```
3. Run `python deploy.py`

---

## ⚠️ Security Notes

- Private keys are **never stored** server-side — users sign transactions client-side in the UI
- All record content is encrypted and stored on IPFS; only the CID hash lives on-chain
- Emergency overrides are permanently auditable — cannot be deleted from the blockchain
- For production use: implement MetaMask/WalletConnect instead of raw private key input

---

## 📄 Licence

MIT — see [LICENSE](LICENSE)

---

*Built as part of IFB452 Blockchain Technology — QUT*
