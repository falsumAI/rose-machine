# RoseMachine

Project ROSE / FalsumAI — Environment Bootstrap Engine  
Author: Gregg Anthony Haynes  
Date: 2025-11-20 (America/Denver)

RoseMachine is the **one-shot environment builder** for the entire Project ROSE architecture.  
Running the bootstrap script creates a complete local workspace:

- repos/
- logs/
- receipts/
- bundles/
- docs/
- licenses/

It automatically:

✔ Clones the core ROSE repositories  
✔ Harvests all LICENSE and PDF documentation  
✔ Generates a cryptographic RoseReceipt  
✔ Bundles the full workspace for archival or transfer  
✔ Outputs artifacts to the Desktop for easy access

## How to Run

Open PowerShell 7 and run:

pwsh -File "C:\Users\Gregg\Desktop\rose-machine\RoseMachine_bootstrap.ps1"

