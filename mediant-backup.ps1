<#
.SYNOPSIS
    This script is used for backing up the ini files for AudioCodes SBCs.
.DESCRIPTION
    This script is used for backing up the ini files for AudioCodes SBCs. This is done through the provided REST API.
    All call parameters are mandatory. By default, the last 10 ini file versions are retained and the oldest ones are automatically deleted.
    The variable $maxFilesToKeep can be adjusted for individual needs.
    The specified backup directory must exist before execution.
.PARAMETER hostname
    Specifies the SBC for backup (ip address or FQDN)
.PARAMETER username
    SBC user account for API access
.PARAMETER password
    Password for API access
.PARAMETER backuppath
    Path to directory where the ini file should be saved
.EXAMPLE
    .\mediant-backup.ps1 -hostname 10.0.0.1 -username Admin -password 'Admin' -backuppath 'D:\Backup\'
.NOTES
    Written by Andreas Pramhaas, andreas.pramhaas@atos.net
    
    Version History:
    ----------------   
    V1.0 (30. Aug 2023)
        Initial version  
#>
param
(
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$hostname,
	
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$username,
	
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[String]$password,
	
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$backuppath
)

$currentDateTime = Get-Date -Format "yyyyMMdd_HHmm"
$credentials = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+':'+$password))
$url = "https://"+$hostname+"/api/v1/files/ini"
$backupfile = $hostname+"_"+$currentDateTime+".ini"
$fullPath = [System.IO.Path]::Combine($backuppath, $backupfile)
$maxFilesToKeep = 10

# Disable SSL verification for Powershell <6.1
# https://stackoverflow.com/questions/36456104/invoke-restmethod-ignore-self-signed-certs
if (-not("dummy" -as [type])) {
    add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}
"@
}
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()

# Set connection to TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

try 
{
    # Create a web request with basic authentication
    $request = Invoke-WebRequest -Uri $url -Method Get -Headers @{ 'Authorization' = 'Basic ' + $credentials} -ErrorVariable webError -ErrorAction Stop

    # Check if the request was successful
    if ($request.StatusCode -eq 200)
    {
        # Save the response content to a file
        $request.Content | Set-Content -Path $fullPath -Encoding Byte
		
		# delete old backup files that excess the $maxFilesToKeep value
		$filesToDelete = Get-ChildItem -Path $backuppath -Filter "$hostname*.ini" | Sort-Object LastWriteTime -Descending
        $excessFileCount = $filesToDelete.Count - $maxFilesToKeep
        if ($excessFileCount -gt 0)
        {            
            $filesToDelete[-$excessFileCount..-1] | ForEach-Object {Remove-Item $_.FullName -Force}
        }
    } 
    else 
    {
        Write-Host "Backup has failed with an error status of $($request.StatusCode)"
        Write-Host "Error description: $($webError.Exception.Message)"
    }
}
catch 
{
    Write-Host "An error occurred during the backup process: $_"
}
