# WUShowHideToolAlt

## Why I Created This Project

### Background:
Maintaining a Windows system often involves repetitive tasks that can be tedious and time-consuming. I noticed that Windows annoyingly installs outdated GPU drivers through Windows Update, which has negatively impacted system performance and stability.

### The Problem:
**Windows Update** has a habit of installing ***older or unwanted GPU drivers***, which can sometimes lead to compatibility issues, crashes, or performance degradation.

---

## Overview

This script performs a series of maintenance tasks on a Windows system, including cleaning up temporary files, disabling Delivery Optimization, and hiding old GPU drivers from Windows Update. The script performs the following actions:

1. **Administrative Privileges Check**: Ensures the script is running as Administrator, auto-relaunching with elevated permissions if needed.
2. **Driver Search Configuration**: Disables automatic driver fetching from Windows Update (`SearchOrderConfig = 0`).
3. **User Guidance Before Proceeding**: Prompts the user to manually pause Windows Update to prevent interference.
4. **Optional Disk Cleanup**: Offers to run Disk Cleanup (`cleanmgr`) with selected cleanup categories like Delivery Optimization, Error Reports, Temporary Files, and Update Cleanup.
5. **Delivery Optimization Disable**: Temporarily disables the Delivery Optimization service (`DoSvc`) to stop unwanted background updates.
6. **Safe Mode Cleanup**:
    - Configures the system to reboot into Safe Mode.
    - Performs Windows Update folder reset (`SoftwareDistribution`, `catroot2`).
    - Optionally deletes older reset folders.
    - Displays detailed **DDU (Display Driver Uninstaller)** instructions for safe GPU driver removal.
7. **PostCleanup Stage**:
    - Automatically runs after reboot (via `RunOnce` entry).
    - Restores normal boot mode and Delivery Optimization.
    - Re-enables essential services.
    - Creates a persistent GPU hiding script and task.
8. **Permanent GPU Driver Hiding Script**:
    - Saves `C:\HideOldGPUDriversFromWU.ps1`.
    - Uses the `PSWindowsUpdate` module to detect and hide all GPU-related updates from Windows Update.
    - Sets a **system-level scheduled task** (`HideGPUDriversFromWU`) to run this script automatically at every logon.
9. **System Health Verification (Optional)**:
    - Offers to run full **DISM** and **SFC** scans for system integrity after cleanup.
    - Includes retry logic for both commands to ensure reliable execution.
10. **Final Cleanup**:
    - Removes temporary cleanup scripts, logs, and flags.
    - Restores system boot and cleanup environment to normal.

---

## Script Components

### 1. Administrative Privileges Check
Automatically detects if PowerShell is running with elevated permissions.  
If not, it restarts itself as Administrator using `Start-Process -Verb RunAs`.

### 2. Driver Update Control
Modifies Windows Registry (`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching`) to prevent Windows from automatically installing drivers via Windows Update.

### 3. Disk Cleanup (Optional)
Configures specific `cleanmgr` cleanup profiles and removes unnecessary files like Delivery Optimization data, temporary setup files, and update leftovers.

### 4. Delivery Optimization Service
Disables the `DoSvc` service to prevent unwanted background driver downloads during cleanup and Safe Mode operations.  
Later restored in the PostCleanup phase.

### 5. Safe Mode Cleanup
Automatically schedules the system to boot into Safe Mode (Minimal).  
Performs secure Windows Update folder resets and allows the user to delete old backup folders.  
Displays step-by-step DDU instructions for GPU driver removal.

### 6. PostCleanup Stage
Runs automatically after reboot.  
Restores the system’s normal boot state, cleans flags, restarts services, and runs the GPU hiding automation setup.

### 7. GPU Driver Hiding Automation
Creates a persistent script `C:\HideOldGPUDriversFromWU.ps1` that hides all GPU-related updates using the `PSWindowsUpdate` module.  
A scheduled task `HideGPUDriversFromWU` ensures this script runs at every logon under SYSTEM privileges.

### 8. DISM and SFC Health Checks
Offers to run `DISM.exe /Online /Cleanup-Image /RestoreHealth` and `sfc /scannow` after cleanup.  
If chosen, it performs both scans with retry logic to ensure system integrity.

---

## Prerequisites

- Windows 10 / 11 with PowerShell
- Administrator privileges
- Internet connection (for module installation and update retrieval)
- `PSWindowsUpdate` PowerShell module (installed automatically if missing)
- **Display Driver Uninstaller (DDU)** for safe GPU cleanup
    - Download from: [Official DDU Page (Wagnardsoft)](https://www.wagnardsoft.com/)

---

## How to Use

1. **Download Instructions for the Script:**
   
   - **From the Releases Section:**
        - Navigate to the [Releases](https://github.com/hexagonal717/wushowhidetoolalt/releases) page of the repository.
        - Download the latest release.
        - Extract the ZIP file to access the `WUShowHideToolAlt`.
    - **To download as a ZIP file:**
        - On the main repository page, click the **Code** button and select **Download ZIP**.
        - Extract the ZIP file to access the `WUShowHideToolAlt`.
    - **To clone using Git:**
        - Open Git Bash or a terminal.
        - Run the following command:
          ```bash
          git clone https://github.com/hexagonal717/wushowhidetoolalt
          ```
        - This will clone the entire repository to your local machine, and you can access the `WUShowHideToolAlt`.

2. **Ensure an Internet Connection:**
    - The script depends on Windows Update to retrieve the old drivers from the server so that it can block the old drivers.

3. **Pause Windows Update:**
    - Go to Settings > Windows Update > Pause (pause for 1 week).

4. **Run the `run_this.bat` file**:
    - Locate the `run_this.bat` file in the directory where you extracted or cloned the repository.
    - Double-click the `run_this.bat` file to execute it. This file will run the PowerShell script with the necessary permissions.
    - If Windows SmartScreen appears, warning you that the file might be unsafe, follow these steps to bypass it:
       - Click on **More info**.
       - Then click **Run anyway**.
       - The script will then execute with the necessary permissions.
5. **Install `PSWindowsUpdate` Module:**
    - If prompted, type `Y` and press enter.

6. **Let the Script Run:**
    - The script will perform its tasks automatically and create a scheduled task for future automatic executions.
    - The script will take around 4-5 minutes to finish executing. Be patient.

7. **Important! Run DDU (Display Driver Uninstaller):**
    - Follow the instructions in the video below:
      `(Do the DDU safe mode method.)`
        - [How to download and use DDU (Display Driver Uninstaller)](https://youtu.be/1XlwirtWs_c?si=aw5g3N4NUi8TGURM&t=142)

8. **Download and Install the Appropriate GPU Driver After Reboot:**
    - Download the latest GPU driver from the respective links:
        - **AMD**: [AMD Drivers](https://www.amd.com/en/support/download/drivers.html)
            - ***Also download Chipset drivers along with GPU drivers for AMD.***
        - **Nvidia**: [Nvidia Drivers](https://www.nvidia.com/download/index.aspx)
        - **Intel**: [Intel Drivers](https://www.intel.com/content/www/us/en/download-center/home.html)

9. **Enable / Resume Windows Update back in Settings**

10. **Verify the Task and Script:**
    - If everything is done correctly, there will be a `HideOldGPUDriversFromWU.ps1` file in the ***root of your C: Drive*** and a task named `HideOldGPUDriversFromWU` in ***Task Scheduler***.

    ### `HideOldGPUDriversFromWU.ps1` file in C: Drive:
    ![WUShowHideToolAlt Banner](./guide-assets/c-drive.png)

    ### `HideOldGPUDriversFromWU` task in Task Scheduler:
    ![WUShowHideToolAlt Banner](./guide-assets/task-scheduler.png)

    - ### Caution:
        - Do not move the `HideOldGPUDriversFromWU.ps1` file placed in the root of C: Drive. It is essential for the Task Scheduler for the automation of the script.

---

## License
This project is licensed under the MIT License - see the LICENSE file for details.
