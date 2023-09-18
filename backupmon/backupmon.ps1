param
(
    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [string]$config
)

# Function to send an email report
function Send-EmailReport {
    param (
        [string]$subject,
        [string]$body
    )

    $smtp = New-Object Net.Mail.SmtpClient($smtpServer)
    $message = New-Object Net.Mail.MailMessage
    $message.From = $emailSender
    $message.To.Add($notificationEmail)
    $message.Subject = $subject
    $message.Body = $body
    $smtp.Send($message)
}

# Function to get the size of a backup (file or directory)
function Get-BackupSize {
    param (
        [string]$path
    )

    if (Test-Path $path -PathType Leaf) {
        return (Get-Item $path).Length
    }
    elseif (Test-Path $path -PathType Container) {
        return (Get-ChildItem $path -Recurse | Measure-Object -Property Length -Sum).Sum
    }
    else {
        return 0
    }
}

# Function to calculate the median of an array of numbers
function Get-Median {
    param (
        [long[]]$numbers
    )

    $count = $numbers.Count
    $sortedNumbers = $numbers | Sort-Object

    if ($count % 2 -eq 0) {
        # If the count is even, take the average of the middle two numbers
        $middle1 = $sortedNumbers[($count / 2) - 1]
        $middle2 = $sortedNumbers[$count / 2]
        $median = ($middle1 + $middle2) / 2
    }
    else {
        # If the count is odd, simply take the middle number
        $median = $sortedNumbers[$count / 2]
    }

    return $median
}

# Read config file
if (Test-Path $config) {
    $configFileContents = Get-Content $config | ForEach-Object {
        $_.Trim()
    }

    # Define default values
    $minBackupSets = 5
    $emailSender = "backup-monitor@yourdomain.com"
    $notificationEmail = "your@email.com"
    # Control if a mail is sent. Valid values: off, alarm, always
    $notifyType = "off"
    $smtpServer = "smtp.yourmailserver.com"
    $backupPaths = @()

    foreach ($line in $configFileContents) {
        if ($line -match "^\s*(\w+)\s*=\s*(.+)") {
            $variableName = $matches[1]
            $variableValue = $matches[2]
            
            # Set the variable based on the name
            Set-Variable -Name $variableName -Value $variableValue
        }
        elseif (Test-Path $line -PathType Container) {
            # If the line is a valid path, add it to the paths array
            $backupPaths += $line
        }
    }

    # Display the read or default values
    Write-Host "Backup monitor started. These values where read from the config file. If not specified a default value was used."    
    Write-Host "minBackupSets: $minBackupSets"
    Write-Host "emailSender: $emailSender"
    Write-Host "notificationEmail: $notificationEmail"
    Write-Host "smtpServer: $smtpServer"
    Write-Host "notifyType: $notifyType"
    Write-Host "Paths:"
    $backupPaths | ForEach-Object {
        Write-Host $_
    }
}
else {
    Write-Host "Specified config file \"$config\" does not exist."
    exit 1
}

# Initialize variables for tracking backups
$failedBackups = @()
$currentDate = Get-Date

Write-Host "Start backup check at $currentDate"
# Loop through each backup path
foreach ($path in $backupPaths) {
    if (Test-Path $path) {
        Write-Host "Checking path: ${path}"

        # Get a list of backup files and directories sorted by create time
        $backupItems = Get-ChildItem -Path $path | Sort-Object CreationTime

        # Ensure a minimum of $minBackupSets backup sets
        if ($backupItems.Count -lt $minBackupSets) {
            # If there is a backup that is not older than 25 hours it's probably a fresh start and ignore
            if ($backupItems.Count -gt 0) {
                if (($currentDate - $backupItems[-1].CreationTime).TotalSeconds -ge 90000) {                    
                    $failedBackups += "${path}: Less than $minBackupSets backup sets found."
                    continue                    
                }
                else {
                    Write-Host "${path}: less than $minBackupSets found, but ignoring as last backup is from within 25 hours"
                    continue
                }
            }
            else {
                $failedBackups += "${path}: Less than $minBackupSets backup sets found."
                continue          
            }
        }

        # Determine the pattern frequency based on timestamps 
        # Calculate the differences between timestamps
        $differences = @()
        for ($i = 0; $i -lt ($backupItems.Count - 1); $i++) {
            $diff = ($backupItems[$i + 1].CreationTime - $backupItems[$i].CreationTime).TotalSeconds
            $differences += $diff
        }
        
        # Calculate the median of the differences
        $medianDateDiff = Get-Median -numbers $differences

        # Check if the difference between the last backup timestamp and now is below the calculated median with a 5% discrepancy allowed        
        $differenceToCheck = ($currentDate - $backupItems[-1].CreationTime).TotalSeconds
        # Define the allowable discrepancy (5%)
        $allowableDiscrepancy = $medianDateDiff * 1.05
        if ($differenceToCheck -gt $allowableDiscrepancy) {
            $failedBackups += "${path}: More time than usual has passed since the last backup (calculated based on creation time)."
        }

        # Check if the latest backup size is reasonable based on previous backups
        $backupSizes = @()
        for ($i = 0; $i -lt ($backupItems.Count - 1); $i++) {
            $backupSizes += Get-BackupSize $backupItems[$i].FullName
        }

        # Calculate the median of all previous backup sizes
        $medianSize = Get-Median -numbers $backupSizes
        $lastBackupSize = Get-BackupSize $backupItems[-1].FullName
        # Define the allowable discrepancy (5%)
        $allowableDiscrepancy = $medianSize * 0.05
        if ($lastBackupSize -lt $allowableDiscrepancy) {
            $failedBackups += "${path}: Last backup is more than 5% smaller than usual based on the previous backups."
        }       
    }
    else {
        $failedBackups += "${path}: Path not found."
    }
}

# Generate a summary report
$reportBody = "Backup monitor summary report - ${currentDate}`n"
$reportBody += "===============================================`n"

$reportBody += "Checked backup paths:`n"
foreach ($path in $backupPaths) {
    $reportBody += "$path`n"
}

$reportBody += "`nALARMS:`n"
if ($failedBackups.Count -eq 0) {
    $reportBody += "No failed backups`n"
}
else {
    foreach ($failedBackup in $failedBackups) {
        $reportBody += "$failedBackup`n"
    }
}

# Send the summary report via email
if ($notificationEmail -ne "your@email.com" -And $smtpServer -ne "smtp.yourmailserver.com" -And $notifyType -ne "off") {
    Write-Host "Send e-mail with summary to $notificationEmail"
    if ($failedBackups.Count -eq 0 -And $notifyType -eq "always") {
        Send-EmailReport -subject "Backup monitor summary" -body $reportBody
    }
    if ($failedBackups.Count -gt 0 -And $notifyType -eq "alarm") {
        Send-EmailReport -subject "Backup monitor summary with ALARMs" -body $reportBody
    }
}

Write-Host "`n$reportBody"