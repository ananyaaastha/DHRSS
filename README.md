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
│   ├── PatientRegistry.sol     # Role registration contract
│   ├── AccessControl.sol       # Consent and emergency access contract
│   ├── HealthRecords.sol       # Record storage contract
│   └── abi/
│       ├── PatientRegistry.json
│       ├── AccessControl.json
│       └── HealthRecords.json
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

## Requirements

Before running the project, make sure you have the following installed:

- Python
- Ganache: <https://trufflesuite.com/ganache>
- Remix IDE: <https://remix.ethereum.org>

---

## 1. Clone the Repository

```bash
git clone https://github.com/ananyaaastha/DHRSS.git
cd DHRSS
```

## 2. Install Python Dependencies

```bash
pip install -r requirements.txt
```

## 3. Start Ganache

1. Open the **Ganache** desktop app.
2. Click **Quickstart Ethereum**.
3. Ganache will create 10 accounts, each with 100 ETH.
4. Check the RPC server at the top of Ganache. It should be:

```text
http://127.0.0.1:7545
```
5. Keep Ganache open while running the project.

## 4. Deploy Smart Contracts in Remix

### 4.1 Open the Contracts

1. Go to <https://remix.ethereum.org>.
2. Open the `contracts` folder.
3. You should see the following Solidity contracts:

- `PatientRegistry.sol`
- `AccessControl.sol`
- `HealthRecords.sol`

### 4.2 Compile the Contracts

1. Go to the **Solidity Compiler** tab.
2. Set the compiler version to:

```text
0.8.19
```

3. Compile each contract file.

### 4.3 Connect Remix to Ganache

1. Go to the **Deploy & Run Transactions** tab.
2. Set **Environment** to:

```text
Custom - External HTTP Provider
```

3. Enter the Ganache RPC URL:

```text
http://127.0.0.1:7545
```

4. Click **OK**.
5. Ganache accounts should now appear in Remix.

### 4.4 Deploy the Contracts

Deploy the contracts in this order:

| Order | Contract | What to Do |
|---|---|---|
| 1 | `PatientRegistry` | Deploy the contract, then copy its contract address. |
| 2 | `AccessControl` | Paste the `PatientRegistry` address into the required field, deploy the contract, then copy its contract address. |
| 3 | `HealthRecords` | Paste the `PatientRegistry` address into the registry address field and the `AccessControl` address into the access control address field, then click **Transact**. |

After deployment, make sure the contract addresses are updated in the Flask application where required, such as in `app.py` or your blockchain configuration file.

## 5. Run the Flask App

```bash
python app.py
```

You should see output similar to:

```text
Running on http://127.0.0.1:5000
```

## 6. Open the Web Interface

Open your browser and go to:

```text
http://127.0.0.1:5000
```

You can access the dashboards using these routes:

| Dashboard | URL |
|---|---|
| Patient Dashboard | `http://127.0.0.1:5000/patient` |
| Doctor Dashboard | `http://127.0.0.1:5000/doctor` |
| Admin Dashboard | `http://127.0.0.1:5000/admin` |

## 7. Get Wallet Addresses and Private Keys from Ganache

To test the application, use the generated accounts from Ganache.

1. Open Ganache.
2. Select an account.
3. Copy the wallet address.
4. Copy the private key.

Recommended account roles:

| Ganache Account | Role |
|---|---|
| Account 0 | Admin |
| Account 1 | Patient |
| Account 2 | Doctor |

> **Important:** These private keys are only for local testing. Do not use real wallet private keys in this project.

## 8. Quick Test Flow

Use the following steps to check that the system is working correctly:

| Step | Action |
|---|---|
| 1 | Register **Account 1** as a patient. |
| 2 | Add a health record using this fake IPFS hash: `QmTzQ1JRkWErjk39mryYw2WVaphAZNAREyMchXzYQ7c15h`. |
| 3 | Fetch the records to verify that the health record was saved. |
| 4 | Grant **Account 2** doctor access through **Manage Consent**. |
| 5 | Fetch the records using **Account 2** as the caller. This should work after access is granted. |
| 6 | Revoke consent and try fetching the records again. This should fail. |

---

## Troubleshooting

| Issue | Fix |
|---|---|
| Web3 is not connected | Make sure Ganache is running before starting Flask. |
| Transaction failed | Check that the correct private key is being used and that the contract addresses are updated in the Flask app. |
| Module not found | Run `pip install -r requirements.txt` again. |
| Port 5000 is already in use | Run the app on another port, for example: `python app.py --port 5001`. |
| Remix cannot connect to Ganache | Make sure Ganache is open and the RPC URL is `http://127.0.0.1:7545`. |
| Contract deployment fails | Check that the compiler version is set to `0.8.19` and that contracts are deployed in the correct order. |

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
