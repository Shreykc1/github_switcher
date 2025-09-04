# Switch-GitAccount.ps1
# Dynamic GitHub Account Switcher
# - Store accounts in accounts.json
# - Add new accounts interactively
# - Switch between stored accounts (clears creds + forces browser login)

$AccountsFile = Join-Path $env:USERPROFILE ".git-accounts.json"


# Load or initialize accounts
if (Test-Path $AccountsFile) {
    $Profiles = Get-Content $AccountsFile | ConvertFrom-Json
} else {
    $Profiles = @{}
}

function Save-Profiles {
    $Profiles | ConvertTo-Json | Set-Content $AccountsFile
}

function Show-MainMenu {
    Write-Host "====================================="
    Write-Host "     GitHub Account Switcher"
    Write-Host "====================================="
    Write-Host "1) Add a new account"
    Write-Host "2) Switch accounts"
    Write-Host "====================================="
    return (Read-Host "Choose an option (1 or 2)")
}

function Add-Account {
    $alias = Read-Host "Enter an alias for this account (e.g. work, personal)"
    if ($Profiles.$alias) {
        Write-Warning "Alias '$alias' already exists. Use another name."
        return
    }

    $username = Read-Host "Enter GitHub username"
    $email = Read-Host "Enter GitHub email"

    $Profiles | Add-Member -NotePropertyName $alias -NotePropertyValue @{ user=$username; email=$email } -Force
    Save-Profiles
    Write-Host "✅ Account '$alias' added successfully."
}

function Select-Account {
    if (-not $Profiles.Keys.Count) {
        Write-Warning "No accounts found. Add an account first."
        return $null
    }

    Write-Host "`nAvailable accounts:"
    $i = 1
    foreach ($key in $Profiles.Keys) {
        Write-Host "$i) $key"
        $i++
    }

    $choice = Read-Host "Select account number"
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $Profiles.Keys.Count) {
        Write-Warning "Invalid choice."
        return $null
    }

    return ($Profiles.Keys)[$index]
}

function Remove-GitHubCreds {
    Write-Host "`nRemoving saved GitHub credentials from Windows Credential Manager..."
    $targets = @(cmdkey /list 2>$null | Select-String -Pattern '^\s*Target:\s*(.+)$' | ForEach-Object {
        ($_.Matches[0].Groups[1].Value).Trim()
    })

    $gitTargets = $targets | Where-Object {
        $_ -match '(?i)\bgit[:@]' -or $_ -match '(?i)github\.com'
    }

    foreach ($t in $gitTargets) {
        Write-Host "Deleting credential: $t"
        cmdkey /delete:$t | Out-Null
    }

    $common = @(
        'git:https://github.com',
        'git:github.com',
        'LegacyGeneric:target=git:https://github.com'
    )
    foreach ($t in $common) {
        cmdkey /delete:$t 2>$null | Out-Null
    }
}

function Set-GlobalGitIdentity([string]$name, [string]$email) {
    git config --global --unset user.name 2>$null
    git config --global --unset user.email 2>$null

    git config --global user.name "$name"
    git config --global user.email "$email"
    git config --global credential.helper manager-core 2>$null

    Write-Host "✅ Git identity set to: $name <$email>"
}

function Trigger-Reauth {
    echo "protocol=https
host=github.com" | git credential-manager-core erase 2>$null

    # Use a well-known repo to force login
    $testRepo = "https://github.com/github/gitignore.git"
    git ls-remote $testRepo | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Browser login should have opened (if creds were missing)."
    } else {
        Write-Warning "Could not trigger login. Run 'git fetch --all' or 'git pull' in a repo."
    }
}

# ---------------- Main ----------------
$mainChoice = Show-MainMenu
switch ($mainChoice) {
    "1" { Add-Account }
    "2" {
        $acct = Select-Account
        if ($acct) {
            $profile = $Profiles.$acct
            Write-Host "`nSwitching to account '$acct'..."
            Remove-GitHubCreds
            Set-GlobalGitIdentity -name $profile.user -email $profile.email
            Trigger-Reauth
        }
    }
    default { Write-Warning "Invalid choice." }
}
