<#
.Synopsis
   Generates an OSV and DLS import script with random passwords for all found users in the OSV export to support enabling SIP Digest Authentication on the OSV switch.
.DESCRIPTION
   Generates an OSV and DLS import script with random passwords for all found users in the OSV export to help enable SIP Digest Authentication.
   To also supply Line- and DSS-Keys on the phones with the SIP user and password, the optional DLS export file needs to be passed to the script with parameter "-dlsexport".
   
   Attention: every run of the script generates new passwords, so always both generated files have to be imported to the OSV and DLS to have a consistent configuration!
.PARAMETER OSVExport
Specifies the OSV Export file (export_all.txt)
.PARAMETER DLSExport
Specifies the DLS Export file (CSV)
.PARAMETER REALM
Specifies the SIP REALM we want to use
.PARAMETER PWLength
Specifies the length of the generated passwords. Default length is 12, minimum 4 and maximum is 20 characters.
.EXAMPLE
   C:\PS> .\osv-da-wizard.ps1 -OSVExport export_all.txt -DLSExport DLS-Export.csv -REALM UNIFY -PWLength 16
   
   Will generate OSV and DLS import file with SIP password and SIP REALM for all found OSV users in the OSV export.
   Additional the DLS import file contains the necessary commands to supply the Line-/DSS keys with the right auhtentication credentials.
   Passwords are generated with a length of 16 characters (default 12).
.EXAMPLE
   C:\PS> .\osv-da-wizard.ps1 -OSVExport export_all.txt -REALM UNIFY
   
   Will generate OSV and DLS import file with SIP password and SIP REALM for all found OSV users in the OSV export.
   Passwords are generated with a default length of 12 characters.
.NOTES
   Written by Andreas Pramhaas, andreas.pramhaas@unify.com
   I take no responsibility for any issues caused by this script ;-)
   
   Version 1.0
   
   Version History:
   ================
   
   V1.0 (20. Jun 2015)
     - Initial Version   
#>
Param
(
    [Parameter(Mandatory=$True)]
    [string]$OSVExport,
    
    [Parameter(Mandatory=$False)]
    [string]$DLSExport,
    
    [Parameter(Mandatory=$True)]
    [string]$REALM,
    
    [Parameter(Mandatory=$False)]
    [ValidateRange(4,20)]
    [int]$PWLength = 12
)

if (!(Test-Path $OSVExport))
{
	Write-Host "OSV export file does not exist or is not readable"
	exit
}

function New-SWRandomPassword {
    <#
    .Synopsis
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .DESCRIPTION
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .EXAMPLE
       New-SWRandomPassword
       C&3SX6Kn

       Will generate one password with a length between 8  and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -MinPasswordLength 8 -MaxPasswordLength 12 -Count 4
       7d&5cnaB
       !Bh776T"Fw
       9"C"RxKcY
       %mtM7#9LQ9h

       Will generate four passwords, each with a length of between 8 and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4 -FirstChar abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString that will start with a letter from 
       the string specified with the parameter FirstChar
    .OUTPUTS
       [String]
    .NOTES
       Written by Simon Wåhlin, blog.simonw.se
       I take no responsibility for any issues caused by this script.
    .FUNCTIONALITY
       Generates random passwords
    .LINK
       http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
   
    #>
    [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
    [OutputType([String])]
    Param
    (
        # Specifies minimum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({$_ -gt 0})]
        [Alias('Min')] 
        [int]$MinPasswordLength = 8,
        
        # Specifies maximum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({
                if($_ -ge $MinPasswordLength){$true}
                else{Throw 'Max value cannot be lesser than min value.'}})]
        [Alias('Max')]
        [int]$MaxPasswordLength = 12,

        # Specifies a fixed password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='FixedLength')]
        [ValidateRange(1,2147483647)]
        [int]$PasswordLength = 8,
        
        # Specifies an array of strings containing charactergroups from which the password will be generated.
        # At least one char from each group (string) will be used.
        [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '23456789'),

        # Specifies a string containing a character group from which the first character in the password will be generated.
        # Useful for systems which requires first char in password to be alphabetic.
        [String] $FirstChar,
        
        # Specifies number of passwords to generate.
        [ValidateRange(1,2147483647)]
        [int]$Count = 1
    )
    Begin {
        Function Get-Seed{
            # Generate a seed for randomization
            $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
            $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
            $Random.GetBytes($RandomBytes)
            [BitConverter]::ToUInt32($RandomBytes, 0)
        }
    }
    Process {
        For($iteration = 1;$iteration -le $Count; $iteration++){
            $Password = @{}
            # Create char arrays containing groups of possible chars
            [char[][]]$CharGroups = $InputStrings

            # Create char array containing all chars
            $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

            # Set password length
            if($PSCmdlet.ParameterSetName -eq 'RandomLength')
            {
                if($MinPasswordLength -eq $MaxPasswordLength) {
                    # If password length is set, use set length
                    $PasswordLength = $MinPasswordLength
                }
                else {
                    # Otherwise randomize password length
                    $PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
                }
            }

            # If FirstChar is defined, randomize first char in password from that string.
            if($PSBoundParameters.ContainsKey('FirstChar')){
                $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
            }
            # Randomize one char from each group
            Foreach($Group in $CharGroups) {
                if($Password.Count -lt $PasswordLength) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed                        
                    }
                    $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                }
            }

            # Fill out with chars from $AllChars
            for($i=$Password.Count;$i -lt $PasswordLength;$i++) {
                $Index = Get-Seed
                While ($Password.ContainsKey($Index)){
                    $Index = Get-Seed                        
                }
                $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
            }
            Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
        }
    }
}

$OSVImport = "OSV-Import.txt"
$DLSImport = "DLS-Import.csv"
$PWTable = "User-Passwords.csv"
# Create empty hash table for subscribers
$SubscriberList = @{}

# Extract all E164 subscribers home DNs and add them to the hash table
Get-Content $OSVExport | Select-String "CS_SIP" -Context 0,1 | select -Expand Context | select -Expand PostContext | Select-String 'subscriber' | ForEach-Object {$E164 = $_.Line.Split('"')[1]; $SubscriberList.$E164=0}

foreach ($subscriber in @($SubscriberList.Keys))
{
    $SubscriberList.item($subscriber) = New-SWRandomPassword -PasswordLength $PWLength
}

"# OSV import file" | Out-File -FilePath $OSVImport -Encoding ascii
"FILE VERSION:11.00.01:MP2`n" | Out-File -FilePath $OSVImport -Append -Encoding ascii
"# DLS import file" | Out-File -FilePath $DLSImport -Encoding ascii

foreach ($subscriber in $SubscriberList.Keys)
{   
    # generate OSV MP2 import file
    "UCS" | Out-File -FilePath $OSVImport -Append -Encoding ascii
	"    ,SUBSCRIBERDN=`"${subscriber}`"" | Out-File -FilePath $OSVImport -Append -Encoding ascii
	"    ,IPSEC_UNAME=`"${subscriber}`"" | Out-File -FilePath $OSVImport -Append -Encoding ascii
	"    ,IPSEC_REALM=`"${REALM}`"" | Out-File -FilePath $OSVImport -Append -Encoding ascii
	"    ,IPSEC_PW=`"$($SubscriberList.Item($subscriber))`"" | Out-File -FilePath $OSVImport -Append -Encoding ascii
    "    ,IPSEC_SCHEME=`"digest-authentication`"" | Out-File -FilePath $OSVImport -Append -Encoding ascii
	";;" | Out-File -FilePath $OSVImport -Append -Encoding ascii
    
    # generate DLS CSV import file (devices only)
    "ModifyDevice;${subscriber};user-id=${subscriber};pwd=$($SubscriberList.Item($subscriber));realm=${REALM};" | Out-File -FilePath $DLSImport -Append -Encoding ascii
}

$SubscriberList.getEnumerator() | foreach{ New-Object PSObject -Property @{User=$_.Name; Password=$_.Value} } | Export-Csv $PWTable -Delimiter ";" -NoTypeInformation

Write-Host "Generated files:`n` * ${OSVImport} - Import file with SIP password and SIP REALM for all found OSV users`n` * ${DLSImport} - Import file with SIP password and SIP REALM for all phones based on found users in ${OSVExport}`n` * ${PWTable} - Table with user passwords`n"

if (!([string]::IsNullOrEmpty($DLSExport)))
{
	if (!(Test-Path $DLSExport))
    {
        Write-Host "DLS export file does not exist or is not readable"
		exit
    }
    Get-Content $DLSExport | Select-String ('(?m)^ModifyKey;false;[0-9]+(?:;line|;dss)') | ForEach-Object `
    {
        $Dataset = $_
        $DeviceId = ""
        $KeyFunction = ""
        $KeyLevel = ""
        $KeyModule = ""
        $KeyNumber = ""
        $SipLineUri = ""

        $KeyValues = $_.Line.Split(";")

        For($i=2; $i -lt $KeyValues.Length; $i++)
        {
            $Done = $FALSE;
            
            Switch ($i) 
            {
                2 {$DeviceId = $KeyValues[$i].Trim(); break;}
                3 {$KeyFunction = $KeyValues[$i].Trim(); break;}
                4 {$KeyLevel = $KeyValues[$i].Trim(); break;}
                5 {$KeyModule = $KeyValues[$i].Trim(); break;}
                6 {$KeyNumber = $KeyValues[$i].Trim(); break;}
                default
                {
                    if ($KeyValues[$i].ToString().Trim() -match "line-sip-uri")
                    {
                        $SipLineUri=$KeyValues[$i].ToString().Split("=")[1]
                        $Done = $TRUE;
                    }
                }
            }
            
            if ($Done) 
            {
                if ($SubscriberList.ContainsKey($SipLineUri))
                {
                    "ModifyKey;false;${DeviceId};${KeyFunction};${KeyLevel};${KeyModule};${KeyNumber};line-sip-realm=${REALM};line-sip-user-id=${SipLineUri};line-sip-pwd=$($SubscriberList.Item($SipLineUri));" | Out-File -FilePath $DLSImport -Append -Encoding ascii
                }
                else
                {
                    Write-Host "Info: Phone ${DeviceId}, Key ${KeyNumber} (Level ${KeyLevel}/Module ${KeyModule}) has SIP-Line-URI ${SipLineUri}: User not found in OSV export. Skipping this key..." -ForegroundColor Red
                }
                continue
            }
        }
    }
    Write-Host "${DLSImport} updated with Line-/DSS-Key information!`n"
}