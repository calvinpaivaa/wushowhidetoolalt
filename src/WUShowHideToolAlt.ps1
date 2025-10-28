# Function to check if the script is running as Administrator
function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if the script is running as Administrator
if (-not (Test-IsAdministrator)) {
    Write-Host "This script needs to be run as an Administrator."
    Write-Host "Trying to restart with elevated privileges..."
    # Use the script path, not the definition
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Delete the SafeMode cleanup flag if it exists (so SafeMode cleanup can run again)
$safeModeFlag = "C:\SafeModeCleanupRan.flag"
if (Test-Path $safeModeFlag) {
    try {
        Remove-Item -Path $safeModeFlag -Force
        Write-Host "Removed existing SafeModeCleanupRan.flag file." -ForegroundColor Yellow
    } catch {
        Write-Host "Warning: Could not remove SafeModeCleanupRan.flag file." -ForegroundColor Red
    }
}


# --- Configure Driver SearchOrderConfig silently ---
try {
    $driverSearchPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
    if (-not (Test-Path $driverSearchPath)) {
        New-Item -Path $driverSearchPath -Force | Out-Null
    }
    # 0 = Never check Windows Update for drivers
    Set-ItemProperty -Path $driverSearchPath -Name "SearchOrderConfig" -Value 0 -Force
} catch {
    # Uncomment for debugging:
    # Write-Host "Failed to set SearchOrderConfig: $($_.Exception.Message)" -ForegroundColor Red
}



# --- Important User Note ---
Write-Host ""
Write-Host "====================== USER NOTE ======================" -ForegroundColor Yellow
Write-Host " Before continuing, please pause Windows Update manually." -ForegroundColor Cyan
Write-Host " Go to Settings > Windows Update and click 'Pause updates'" -ForegroundColor Cyan
Write-Host " (this shows as 'Pause for 1 week')." -ForegroundColor Cyan
Write-Host " This prevents new updates from interfering during cleanup." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host ""
Write-Host "Next steps after reboot:" -ForegroundColor Yellow
Write-Host " - The system will reboot into Safe Mode to perform cleanup." -ForegroundColor Cyan
Write-Host " - After rebooting back to normal Windows, the PostCleanup" -ForegroundColor Cyan
Write-Host "   script will run and show a UAC (Administrator) prompt." -ForegroundColor Cyan
Write-Host ""
Write-Host " - IMPORTANT: When the UAC prompt appears, you must click 'Yes'." -ForegroundColor Green
Write-Host "   (This is required for the PostCleanup script to finish.)" -ForegroundColor Green
Write-Host ""
Write-Host " - If you accidentally close the UAC prompt, you can manually run" -ForegroundColor Red
Write-Host "   'C:\PostCleanupRun.bat' as Administrator to continue the process." -ForegroundColor Red
Write-Host "========================================================" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to continue after pausing updates"


# Define the sageset number and format it with leading zeros
$sagesetNumber = 500
$formattedNumber = $sagesetNumber.ToString("D4")  # Formats the number as four digits
$stateFlagsName = "StateFlags$formattedNumber"

# Define the path to the registry key for VolumeCaches
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"

# Define the list of specific cleanup options to modify
$cleanupOptions = @(
    "Delivery Optimization Files",
    "Device Driver Packages",
    "Temporary Files",
    "Windows Error Reporting Files",
    "Temporary Setup Files",
    "Update Cleanup"
)

# Ask user if they want to run Disk Cleanup
$runCleanup = Read-Host "Do you want to run Disk Cleanup now? (Y/N)"
if ($runCleanup -match '^[Yy]$') {
    # Set the StateFlags DWORD value for the specified sageset number
    foreach ($option in $cleanupOptions) {
        $optionPath = "$regPath\$option"
        if (Test-Path $optionPath) {
            Set-ItemProperty -Path $optionPath -Name $stateFlagsName -Value 2
        } else {
            Write-Host "Registry path not found for option: $option"
        }
    }

    try {
        Start-Process cleanmgr -ArgumentList "/sagerun:$sagesetNumber" -Wait -NoNewWindow
        Write-Host "cleanmgr /sagerun:$sagesetNumber has been executed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to run cleanmgr. Error: $_" -ForegroundColor Red
    }

    # Remove StateFlags after cleanup
    foreach ($option in $cleanupOptions) {
        $optionPath = "$regPath\$option"
        if (Test-Path $optionPath) {
            Remove-ItemProperty -Path $optionPath -Name $stateFlagsName -ErrorAction SilentlyContinue
        }
    }
    Write-Host "StateFlags values for sageset number $sagesetNumber have been removed." -ForegroundColor Cyan
} else {
    Write-Host "Disk Cleanup skipped by user choice." -ForegroundColor Yellow
}

# Disable Delivery Optimization by setting the Start value of the DoSvc service to 4
Write-Host "Disabling Delivery Optimization..."

$deliveryOptimizationServicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc"
if (Test-Path $deliveryOptimizationServicePath) {
    Set-ItemProperty -Path $deliveryOptimizationServicePath -Name "Start" -Value 4
    Write-Host "Delivery Optimization service has been disabled."
} else {
    Write-Host "Delivery Optimization service registry path not found."
}

# Continue with the rest of the script

# Stop related services to avoid conflicts
# $services = @("wuauserv", "bits", "cryptsvc", "msiserver")

# foreach ($service in $services) {
#    try {
#        Stop-Service -Name $service -Force -ErrorAction Stop
#    } catch {
#        Write-Host "Failed to stop service: $service"
#    }
# }

# --- Paths ---
$ps1Path = "C:\SafeModeCleanup.ps1"
$batPath = "C:\SafeModeCleanupRun.bat"
$postCleanupPath = "C:\PostCleanup.ps1"
$postCleanupBatPath = "C:\PostCleanupRun.bat"
$winlogonKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"













# --- Contents of PostCleanup.ps1 ---
$postCleanupContent = @"
# Function to check if running as Administrator
function Test-IsAdministrator {
    `$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    `$principal = New-Object System.Security.Principal.WindowsPrincipal(`$identity)
    return `$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Relaunch with elevation if not already Administrator
if (-not (Test-IsAdministrator)) {
    Write-Host "PostCleanup script needs Administrator privileges. Trying to restart with elevation..." -ForegroundColor Red

    # Use the script file path, not its definition
    `$scriptPath = `$PSCommandPath
    if (-not `$scriptPath) { `$scriptPath = `$MyInvocation.MyCommand.Path }

    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File ``"`$scriptPath``"" -Verb RunAs
    exit
}

# Delete the SafeMode cleanup flag if it exists (so SafeMode cleanup can run again)
`$safeModeFlag = "C:\SafeModeCleanupRan.flag"
if (Test-Path `$safeModeFlag) {
    try {
        Remove-Item -Path `$safeModeFlag -Force
        Write-Host "Removed existing SafeModeCleanupRan.flag file." -ForegroundColor Yellow
    } catch {
        Write-Host "Warning: Could not remove SafeModeCleanupRan.flag file." -ForegroundColor Red
    }
}

Write-Host "Running PostCleanup tasks with Administrator privileges..." -ForegroundColor Green

# Restart the stopped services
`$services = @("wuauserv","bits","cryptsvc","msiserver")
foreach (`$service in `$services) {
    try {
        Start-Service -Name `$service -ErrorAction Stop
        Write-Host "Started service: `$service" -ForegroundColor Green
    } catch {
        Write-Host "Failed to start service: `$service" -ForegroundColor Yellow
    }
}

# Enable Delivery Optimization
`$deliveryOptimizationServicePath = "HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc"
if (Test-Path `$deliveryOptimizationServicePath) {
    Set-ItemProperty -Path `$deliveryOptimizationServicePath -Name "Start" -Value 2
    Write-Host "Delivery Optimization service has been enabled." -ForegroundColor Green
}

# --- Save permanent HideOldGPUDriversFromWU.ps1 script ---
`$scriptPath = "C:\HideOldGPUDriversFromWU.ps1"
`$scriptContent = @'
# Check if running as Administrator
function Test-IsAdministrator {
    `$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    `$principal = New-Object System.Security.Principal.WindowsPrincipal(`$identity)
    return `$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host "This script needs to be run as Administrator."
    Start-Process powershell -ArgumentList "`$(`$MyInvocation.MyCommand.Definition)" -Verb RunAs
    exit
}

`$hideKeywords = @(
    "NVIDIA - Display",
    "Advanced Micro Devices, Inc. - Display",
    "NVIDIA",
    "ATI Technologies Inc. - Display",
    "Display",
    "Intel Corporation - Display",
    "nVidia - Display"
)

if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    try {
        Install-Module -Name PSWindowsUpdate -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Host "Failed to install PSWindowsUpdate module. Exiting script."
        exit
    }
}
Import-Module PSWindowsUpdate

Write-Host "Running HideOldGPUDriversFromWU script..." -ForegroundColor Cyan

`$updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot

if (`$updates) {
    foreach (`$update in `$updates) {
        `$title = `$update.Title
        if (`$hideKeywords | Where-Object { `$title -match `$_ }) {
            Hide-WindowsUpdate -Title `$title -Confirm:`$false
            Write-Host "Hidden update: `$title"
        }
    }
    Write-Host "Old GPU drivers have been successfully hidden." -ForegroundColor Green
} else {
    Write-Host "No old GPU drivers found in Windows Update." -ForegroundColor Cyan
}
'@

Set-Content -Path `$scriptPath -Value `$scriptContent -Force -Encoding UTF8
Write-Host "Created permanent GPU hiding script at `$scriptPath" -ForegroundColor Green

# --- Create scheduled task ---
`$taskName = "HideGPUDriversFromWU"
`$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-ExecutionPolicy Bypass -File "' + `$scriptPath + '" -WindowStyle Hidden')
`$taskTrigger = New-ScheduledTaskTrigger -AtLogon
`$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
`$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName `$taskName ``
    -Description "Hide old GPU drivers from Windows Update" ``
    -Action `$taskAction -Trigger `$taskTrigger -Principal `$taskPrincipal -Settings `$taskSettings -Force

Write-Host "Scheduled task for GPU driver hiding created." -ForegroundColor Cyan

# Run the GPU hiding script once
Start-Process powershell.exe -ArgumentList ('-ExecutionPolicy Bypass -File "' + `$scriptPath + '"') -Wait

# Remove RunOnce entry
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "PostCleanup" -ErrorAction SilentlyContinue

Write-Host "PostCleanup tasks completed successfully!" -ForegroundColor Green
Write-Host "Cleaning up temporary files..." -ForegroundColor Yellow

# Clean up the temporary files
Start-Sleep -Seconds 2
try {
    Remove-Item -Path "C:\PostCleanupRun.bat" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\SafeModeCleanupRun.bat" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\SafeModeCleanup.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\SafeModeCleanupRan.flag" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path `$PSCommandPath -Force -ErrorAction SilentlyContinue
    Write-Host "Temporary SafeModeCleanup scripts and PostCleanup scripts files removed." -ForegroundColor Green
    Write-Host "Old GPU drivers have been successfully hidden from Windows Update." -ForegroundColor Green
} catch {
    Write-Host "Some cleanup files could not be deleted automatically." -ForegroundColor Yellow
}


Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host " Recommended: System Health Check with DISM and SFC" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Would you like to run DISM and SFC scans for system health check?" -ForegroundColor Cyan
Write-Host "This will Run:" -ForegroundColor White
Write-Host "  - DISM.exe /Online /Cleanup-Image /RestoreHealth" -ForegroundColor White
Write-Host "  - sfc /scannow" -ForegroundColor White
Write-Host "  - Takes approximately 15-30 minutes" -ForegroundColor White
Write-Host ""

do {
    `$choice = Read-Host "Run DISM and SFC scans? (y/n)"
    `$choice = `$choice.ToLower()
} while (`$choice -ne "y" -and `$choice -ne "n")

if (`$choice -eq "y") {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " Running DISM and SFC for final system health check..." -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Yellow


    # DISM with retry logic
    `$dismMaxRetries = 2
    `$dismRetryCount = 0
    `$dismSuccess = `$false

    do {
        `$dismRetryCount++
        try {
            Write-Host "Step 2: Running DISM /RestoreHealth (Attempt `$dismRetryCount/`$dismMaxRetries) - this may take some time..." -ForegroundColor Green
            `$dismProcess = Start-Process -FilePath "DISM.exe" -ArgumentList "/Online","/Cleanup-Image","/RestoreHealth" -Wait -NoNewWindow -PassThru -ErrorAction Stop

            if (`$dismProcess.ExitCode -eq 0) {
                Write-Host "DISM completed successfully." -ForegroundColor Cyan
                `$dismSuccess = `$true
            } else {
                throw "DISM exited with code: `$(`$dismProcess.ExitCode)"
            }
        } catch {
            Write-Host "DISM failed (Attempt `$dismRetryCount/`$dismMaxRetries): `$(`$_.Exception.Message)" -ForegroundColor Red
            if (`$dismRetryCount -lt `$dismMaxRetries) {
                Write-Host "Retrying DISM in 5 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
    } while (-not `$dismSuccess -and `$dismRetryCount -lt `$dismMaxRetries)

    if (-not `$dismSuccess) {
        Write-Host "DISM failed after `$dismMaxRetries attempts." -ForegroundColor Red
    }

    # SFC with retry logic
    `$sfcMaxRetries = 2
    `$sfcRetryCount = 0
    `$sfcSuccess = `$false

    do {
        `$sfcRetryCount++
        try {
            Write-Host "Step 3: Running SFC /scannow (Attempt `$sfcRetryCount/`$sfcMaxRetries)..." -ForegroundColor Green
            `$sfcProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow -PassThru -ErrorAction Stop

            if (`$sfcProcess.ExitCode -eq 0) {
                Write-Host "SFC scan completed successfully." -ForegroundColor Cyan
                `$sfcSuccess = `$true
            } else {
                throw "SFC exited with code: `$(`$sfcProcess.ExitCode)"
            }
        } catch {
            Write-Host "SFC failed (Attempt `$sfcRetryCount/`$sfcMaxRetries): `$(`$_.Exception.Message)" -ForegroundColor Red
            if (`$sfcRetryCount -lt `$sfcMaxRetries) {
                Write-Host "Retrying SFC in 5 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5
            }
        }
    } while (-not `$sfcSuccess -and `$sfcRetryCount -lt `$sfcMaxRetries)

    if (-not `$sfcSuccess) {
        Write-Host "SFC failed after `$sfcMaxRetries attempts." -ForegroundColor Red
    }

    Write-Host "============================================================" -ForegroundColor Yellow
    if (`$dismSuccess -and `$sfcSuccess) {
        Write-Host " DISM and SFC checks completed successfully!" -ForegroundColor Green
    } elseif (`$dismSuccess -or `$sfcSuccess) {
        Write-Host " DISM and SFC checks partially completed. Review above messages." -ForegroundColor Yellow
    } else {
        Write-Host " DISM and SFC checks failed. Review above messages for details." -ForegroundColor Red
    }
    Write-Host "============================================================" -ForegroundColor Yellow
} else {
        Write-Host "DISM and SFC skipped by user choice." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " If you want to run DISM or SFC later, use these commands:" -ForegroundColor Cyan
    Write-Host "  DISM.exe /Online /Cleanup-Image /RestoreHealth" -ForegroundColor White
    Write-Host "  sfc /scannow" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Yellow
}

Write-Host "============================================================" -ForegroundColor Yellow
Write-Host " DISM and SFC checks finished. Review above messages for details." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Yellow

Write-Host "All post-cleanup operations completed!" -ForegroundColor Green
Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host " You can now install your GPU drivers." -ForegroundColor Cyan
Write-Host " (NVIDIA / AMD / Intel - whichever is appropriate for your system)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "If you had paused Windows Update earlier," -ForegroundColor Cyan
Write-Host "you can later unpause it from Settings > Windows Update." -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: For Windows Updates to properly download and install," -ForegroundColor Yellow
Write-Host "      it is recommended to restart your system once." -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Enter to exit..."
Read-Host
"@








# --- Contents of PostCleanup.bat ---
$postCleanupBatContent = @"
@echo off
:: Check for admin rights
>nul 2>&1 "%SystemRoot%\system32\cacls.exe" "%SystemRoot%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell.exe -Command "Start-Process '%0' -Verb RunAs"
    exit
)
:: Run the PostCleanup.ps1 script
PowerShell -ExecutionPolicy Bypass -File "C:\PostCleanup.ps1"
"@

# --- Save PostCleanup files ---
Set-Content -Path $postCleanupPath -Value $postCleanupContent -Force -Encoding UTF8
Set-Content -Path $postCleanupBatPath -Value $postCleanupBatContent -Force -Encoding ASCII
Write-Host "Created $postCleanupPath and $postCleanupBatPath" -ForegroundColor Green

# --- Add RunOnce to run the BAT file (which will ensure admin rights) ---
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
    -Name "PostCleanup" -Value $postCleanupBatPath
Write-Host "Added PostCleanupRun.bat to RunOnce registry" -ForegroundColor Green










# --- Contents of SafeModeCleanup.ps1 ---
$ps1Content = @'

# Make this PowerShell window always stay on top
Add-Type -Name WindowAPI -Namespace Win32 -MemberDefinition @"
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);
"@

$HWND_TOPMOST = [IntPtr]::op_Explicit(-1)
$SWP_NOMOVE   = 0x0002
$SWP_NOSIZE   = 0x0001
$SWP_SHOWWINDOW = 0x0040

$handle = (Get-Process -Id $PID).MainWindowHandle
if ($handle -ne [IntPtr]::Zero) {
    [Win32.WindowAPI]::SetWindowPos($handle, $HWND_TOPMOST, 0, 0, 0, 0,
        $SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_SHOWWINDOW) | Out-Null
    Write-Host "PowerShell window is now always on top." -ForegroundColor Cyan
} else {
    Write-Host "Could not get window handle." -ForegroundColor Yellow
}


$flagPath = "C:\SafeModeCleanupRan.flag"
if (Test-Path $flagPath) {
    exit
}
New-Item -Path $flagPath -ItemType File -Force | Out-Null

# Reset boot back to normal (dynamic boot id instead of {current})
$bootId = (bcdedit /enum | Select-String "identifier" | Where-Object {$_ -match "{"}).ToString().Split()[1]
bcdedit /deletevalue $bootId safeboot

# Restore original Userinit (so normal logins work again)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "Userinit" -Value "C:\Windows\system32\userinit.exe,"

Write-Host "Boot mode reset to Normal and Userinit restored." -ForegroundColor Cyan

Start-Sleep -Seconds 1

Write-Host "Resetting Windows Update folders (SoftwareDistribution & catroot2)..." -ForegroundColor Yellow





# Y/N prompt for reset
do {
    Write-Host "`nDo you want to reset SoftwareDistribution and catroot2? (Y/N): " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    $response = $response.ToUpper()
} while ($response -ne "Y" -and $response -ne "N")

if ($response -eq "N") {
    Write-Host "Windows Update folder reset skipped by user." -ForegroundColor Yellow
} else {
    Write-Host "Proceeding with reset (folders will be renamed)..." -ForegroundColor Green

    # Paths
    $softwareDistributionPath = "C:\Windows\SoftwareDistribution"
    $catroot2Path = "C:\Windows\System32\catroot2"

    try {
        # Stop cryptsvc to unlock catroot2
        Write-Host "Stopping Cryptographic Services (cryptsvc)..." -ForegroundColor Yellow
        net stop cryptsvc | Out-Null

        if (Test-Path $softwareDistributionPath) {
            $newName = "$softwareDistributionPath.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Rename-Item -Path $softwareDistributionPath -NewName (Split-Path $newName -Leaf) -Force
            Write-Host "Renamed SoftwareDistribution to $newName" -ForegroundColor Green
        } else {
            Write-Host "SoftwareDistribution folder not found (already reset?)." -ForegroundColor Cyan
        }

        if (Test-Path $catroot2Path) {
            $newName = "$catroot2Path.old_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Rename-Item -Path $catroot2Path -NewName (Split-Path $newName -Leaf) -Force
            Write-Host "Renamed catroot2 to $newName" -ForegroundColor Green
        } else {
            Write-Host "catroot2 folder not found (already reset?)." -ForegroundColor Cyan
        }

        # Optional cleanup of old folders
        do {
            Write-Host "`nDo you want to delete old SoftwareDistribution.old_* and catroot2.old_* folders? (Y/N): " -ForegroundColor Yellow -NoNewline
            $cleanupResponse = Read-Host
            $cleanupResponse = $cleanupResponse.ToUpper()
        } while ($cleanupResponse -ne "Y" -and $cleanupResponse -ne "N")

        if ($cleanupResponse -eq "Y") {
            # Collect old folders into a flat array
            $oldFolders = @()
            $oldFolders += @(Get-ChildItem -Path "C:\Windows" -Directory -Filter "SoftwareDistribution.old_*" -ErrorAction SilentlyContinue)
            $oldFolders += @(Get-ChildItem -Path "C:\Windows\System32" -Directory -Filter "catroot2.old_*" -ErrorAction SilentlyContinue)

            if (-not $oldFolders) {
                Write-Host "No old reset folders found." -ForegroundColor Cyan
            } else {
                foreach ($folder in $oldFolders) {
                    try {
                        Write-Host "`nCleaning: $($folder.FullName)" -ForegroundColor Cyan

                        # Take ownership + grant admins full control
                        takeown /f $folder.FullName /r /d y | Out-Null
                        icacls $folder.FullName /grant administrators:F /t | Out-Null

                        # Retry delete loop
                        $retryCount = 5
                        for ($i = 0; $i -lt $retryCount; $i++) {
                            Get-ChildItem -Path $folder.FullName -Recurse -Force |
                                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                            Start-Sleep -Seconds 2

                            if (-not (Get-ChildItem -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue)) {
                                Write-Host "Deleted contents of $($folder.FullName)" -ForegroundColor Green
                                break
                            } else {
                                Write-Host "Retrying deletion of $($folder.FullName) (Attempt $($i+1)/$retryCount)" -ForegroundColor Yellow
                            }
                        }

                        # Try deleting the empty folder itself
                        Remove-Item -Path $folder.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        if (-not (Test-Path $folder.FullName)) {
                            Write-Host "Removed folder: $($folder.FullName)" -ForegroundColor Green
                        } else {
                            Write-Host "Warning: Could not fully remove $($folder.FullName)" -ForegroundColor Red
                        }

                    } catch {
                        Write-Host "Error cleaning $($folder.FullName): $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        } else {
            Write-Host "Cleanup skipped by user." -ForegroundColor Yellow
        }

    } catch {
        Write-Host "Error while renaming update folders: $($_.Exception.Message)" -ForegroundColor Red
    }
}




# --- DDU Instructions (always shown) ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host " IMPORTANT: Manual Step Required" -ForegroundColor Red
Write-Host "------------------------------------------------------------" -ForegroundColor Yellow
Write-Host " 1. Please run Display Driver Uninstaller (DDU) now." -ForegroundColor Cyan
Write-Host "    In DDU, choose:  'Clean and do NOT restart' " -ForegroundColor Cyan
Write-Host ""
Write-Host " 2. Open the 'Options' menu in DDU and scroll to the end." -ForegroundColor Cyan
Write-Host "    CHECK the box:" -ForegroundColor Cyan
Write-Host "    'Prevent downloads of drivers from Windows Update" -ForegroundColor Cyan
Write-Host "     when Windows searches for a driver for a device'" -ForegroundColor Cyan
Write-Host ""
Write-Host "    (Note: You can later UNCHECK this option if some input" -ForegroundColor DarkYellow
Write-Host "     devices or peripherals fail to get drivers automatically.)" -ForegroundColor DarkYellow
Write-Host ""
Write-Host " After completing these steps, press Enter here to continue." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
[void][System.Console]::ReadLine()

Write-Host "Press Enter to reboot..."
[void][System.Console]::ReadLine()

# Reboot back to normal Windows
Start-Process "shutdown.exe" -ArgumentList "/r /t 0" -WindowStyle Hidden
'@











# --- Contents of SafeModeCleanupRun.bat ---
$batContent = @"
@echo off
if exist "C:\SafeModeCleanupRan.flag" exit /b
start "" /wait powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\SafeModeCleanup.ps1"
"@











# --- Write files ---
Set-Content -Path $ps1Path -Value $ps1Content -Force -Encoding UTF8
Set-Content -Path $batPath -Value $batContent -Force -Encoding ASCII

Write-Host "Created $ps1Path and $batPath" -ForegroundColor Green

# --- Detect boot identifier ---
$bootId = (bcdedit /enum | Select-String "identifier" | Where-Object {$_ -match "{"}).ToString().Split()[1]
Write-Host "Detected boot identifier: $bootId" -ForegroundColor Cyan

# --- Configure Safe Mode Boot ---
Write-Host "Configuring system to boot into Safe Mode (Minimal)..." -ForegroundColor Yellow
bcdedit /set $bootId safeboot minimal

# --- Backup current Userinit ---
$origUserinit = (Get-ItemProperty -Path $winlogonKey -Name Userinit).Userinit
Write-Host "Original Userinit: $origUserinit" -ForegroundColor Cyan

# --- Prepend our BAT to Userinit ---
$newUserinit = "$batPath, $origUserinit"
Set-ItemProperty -Path $winlogonKey -Name Userinit -Value $newUserinit
Write-Host "Userinit modified to include SafeModeCleanup.bat" -ForegroundColor Cyan

# --- Restart into Safe Mode ---
Write-Host "`nSystem will now restart into Safe Mode..." -ForegroundColor Green
Start-Process "shutdown.exe" -ArgumentList "/r /t 0" -WindowStyle Hidden