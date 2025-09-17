# Switch-GitAccount.ps1
# Robust GitHub account switcher for Windows + Git Credential Manager
#
# - Clears GitHub credentials using the modern Git Credential Manager.
# - Unsets then sets the global git user.name and user.email.
# - Directly forces a browser re-authentication prompt after switching.

# ---- PROFILES PERSISTENCE ----
function Get-ConfigPath {
    # Ensures the configuration directory and file path exist.
    $base = Join-Path $env:APPDATA "gitswitch"
    if (-not (Test-Path $base)) {
        New-Item -Path $base -ItemType Directory -Force | Out-Null
    }
    return (Join-Path $base "profiles.json")
}

function Load-Profiles {
    $path = Get-ConfigPath
    if (Test-Path $path) {
        try {
            $json = Get-Content -Raw -Path $path
            # Return a PSCustomObject which works like a hashtable for our purposes.
            return ($json | ConvertFrom-Json -ErrorAction Stop)
        }
        catch {
            Write-Warning "Could not load or parse profiles.json. A new one will be created."
        }
    }
    # Return an empty object if no file exists.
    return [PSCustomObject]@{}
}

function Save-Profiles($profiles) {
    $path = Get-ConfigPath
    ($profiles | ConvertTo-Json -Depth 5) | Set-Content -Path $path -Encoding UTF8
}

# ---- UI: MESSAGES & MENUS ----
function Show-AddAccountsArt {
    $art = @"
`n
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║             No profiles found for Git Switcher             ║
║                                                          ║
║   ➜ Choose 'Add accounts' to create aliases with your    ║
║     Git user.name and user.email.                        ║
║                                                          ║
║   Example:                                               ║
║     Alias : personal                                     ║
║     User  : john-wick                                    ║
║     Email : john-wick@gmail.com                          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
"@
    Write-Host $art -ForegroundColor Cyan
}

function Show-MainMenu {
    Clear-Host
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "     GitHub Account Switcher"
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host " 1) Switch Account"
    Write-Host " 2) Add New Account(s)"
    Write-Host " 3) Exit"
    Write-Host "=====================================" -ForegroundColor Green
    $choice = Read-Host "Select an action (1-3)"
    switch ($choice) {
        "1" { return "change" }
        "2" { return "add" }
        "3" { return "exit" }
        default {
            Write-Warning "Invalid selection."
            return $null
        }
    }
}

# ---- CORE LOGIC ----
function Add-Accounts($profiles) {
    # Convert PSCustomObject to a Hashtable for easier manipulation (.ContainsKey, .Add).
    $profilesHashtable = @{}
    if ($null -ne $profiles) {
        $profiles.psobject.properties | ForEach-Object { $profilesHashtable[$_.Name] = $_.Value }
    }

    do {
        Write-Host "`n-- Add a New Account Profile --" -ForegroundColor Yellow
        $alias = Read-Host "Enter a short Alias (e.g., personal, work)"
        if ([string]::IsNullOrWhiteSpace($alias)) { Write-Warning "Alias cannot be empty."; continue }
        if ($profilesHashtable.ContainsKey($alias)) { Write-Warning "Alias '$alias' already exists."; continue }

        $user = Read-Host "Enter the Git user.name (e.g., john-wick)"
        if ([string]::IsNullOrWhiteSpace($user)) { Write-Warning "user.name cannot be empty."; continue }

        $email = Read-Host "Enter the Git user.email (e.g., john.wick@example.com)"
        if ([string]::IsNullOrWhiteSpace($email)) { Write-Warning "user.email cannot be empty."; continue }

        $profilesHashtable[$alias] = @{ user = $user; email = $email }
        Save-Profiles -profiles $profilesHashtable
        Write-Host "`n✅ Profile '$alias' saved successfully." -ForegroundColor Green

        $again = Read-Host "`nAdd another account? (y/N)"
    } while ($again -match '^(y|yes)$')

    return $profilesHashtable
}

function Select-Account($profiles) {
    $aliases = @($profiles.psobject.properties.Name) | Sort-Object
    if ($aliases.Count -eq 0) {
        Show-AddAccountsArt
        return $null
    }

    Write-Host "`n=====================================" -ForegroundColor Cyan
    Write-Host "          Select Account"
    Write-Host "=====================================" -ForegroundColor Cyan
    for ($i = 0; $i -lt $aliases.Count; $i++) {
        $alias = $aliases[$i]
        $profile = $profiles.$alias
        Write-Host ("{0}) {1}  ({2} <{3}>)" -f ($i + 1), $alias.PadRight(15), $profile.user, $profile.email)
    }
    Write-Host "=====================================" -ForegroundColor Cyan
    $choice = Read-Host "Select an account number (1-$($aliases.Count))"

    # Validate input is a number within the correct range.
    if (($choice -as [int]) -and ([int]$choice -ge 1) -and ([int]$choice -le $aliases.Count)) {
        $idx = [int]$choice - 1
        return $aliases[$idx]
    }
    else {
        Write-Warning "Invalid selection."
        return $null
    }
}

function Ensure-GitPresent {
    & git --version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git is not found in your PATH. Please install Git for Windows and ensure it's accessible."
        exit 1
    }
}

function Set-GlobalGitIdentity([string]$name, [string]$email) {
    Write-Host "`n⚙️  Configuring global git identity..." -ForegroundColor Yellow

    # Unset old values to ensure a clean state.
    git config --global --unset user.name 2>$null
    git config --global --unset user.email 2>$null

    Write-Host "  - Setting user.name  = $name"
    git config --global user.name "$name"
    Write-Host "  - Setting user.email = $email"
    git config --global user.email "$email"

    # Ensure Git Credential Manager is set as the credential helper.
    # 'manager' is the modern and recommended value.
    Write-Host "  - Ensuring credential.helper is 'manager'..."
    git config --global credential.helper manager

    Write-Host "✅ Git identity configured." -ForegroundColor Green
}




# ==============================================================================
# --- Main Execution Block ---
# ==============================================================================

Ensure-GitPresent
$Profiles = Load-Profiles

do {
    $action = Show-MainMenu
    switch ($action) {
        'add' {
            $Profiles = Add-Accounts -profiles $Profiles
            Write-Host "`nReturning to main menu..."
            Start-Sleep -Seconds 2
        }

        'change' {
            if ($null -eq $Profiles -or $Profiles.psobject.properties.Count -eq 0) {
                Show-AddAccountsArt
                Write-Host "`nPlease add an account first."
                Start-Sleep -Seconds 3
                continue # Go back to the start of the loop
            }

            $selectedAlias = Select-Account -profiles $Profiles
            if ($selectedAlias) {
                $profile = $Profiles.$selectedAlias

                Write-Host "`n➡️  Switching to account: '$selectedAlias'" -ForegroundColor Cyan
                Set-GlobalGitIdentity -name $profile.user -email $profile.email

                Write-Host "`n-----------------------------------------------------" -ForegroundColor Green
                Write-Host "✅ Switched to '$selectedAlias'. You are ready to go!"
                Write-Host "-----------------------------------------------------`n"

                # After a successful switch, exit the script.
                $action = 'exit'
                Start-Sleep -Seconds 2
            }
            else {
                Write-Warning "No account selected. Returning to main menu."
                Start-Sleep -Seconds 2
            }
        }
    }
} while ($action -ne 'exit')

Write-Host "`nBye! 👋"
