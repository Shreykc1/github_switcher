# Switch-GitAccount.ps1
# Robust GitHub account switcher for Windows + Git Credential Manager
# - Clears GitHub credentials from Windows Credential Manager (Generic Credentials)
# - Unsets then sets global git user.name / user.email based on selection
# - Tries to trigger re-auth by running `git fetch --all` (only if inside a repo)

# ---- CONFIGURE YOUR EMAILS HERE ----
$Profiles = @{
  "shrey-regular" = @{
      user  = "shreykc1"
      email = "shreykc1@gmail.com"   # ← change to your personal GitHub email
  }
  "shrey-office"  = @{
      user  = "shrey-resta"
      email = "shrey.chandpa@restaverse.com"    # ← change to your office GitHub email
  }
}

function Select-Account {
    Write-Host "====================================="
    Write-Host "     GitHub Account Switcher"
    Write-Host "====================================="
    Write-Host "1) shrey-regular"
    Write-Host "2) shrey-office"
    Write-Host "====================================="
    $choice = Read-Host "Select account (1 or 2)"
    switch ($choice) {
        "1" { return "shrey-regular" }
        "2" { return "shrey-office" }
        default {
            Write-Warning "Invalid selection. Exiting..."
            exit 1
        }
    }
}

function Remove-GitHubCreds {
    Write-Host "`nRemoving saved GitHub credentials from Windows Credential Manager..."
    # Enumerate all stored credentials via cmdkey and capture only the Target lines
    $targets = @(cmdkey /list 2>$null | Select-String -Pattern '^\s*Target:\s*(.+)$' | ForEach-Object {
        ($_.Matches[0].Groups[1].Value).Trim()
    })

    if (-not $targets -or $targets.Count -eq 0) {
        Write-Host "No stored credentials found." -ForegroundColor Yellow
        return
    }

    # Match anything obviously used by Git Credential Manager for GitHub
    $gitTargets = $targets | Where-Object {
        $_ -match '(?i)\bgit[:@]' -or $_ -match '(?i)github\.com'
    }

    if (-not $gitTargets -or $gitTargets.Count -eq 0) {
        Write-Host "No GitHub-related credentials found." -ForegroundColor Yellow
    } else {
        foreach ($t in $gitTargets) {
            Write-Host "Deleting credential: $t"
            cmdkey /delete:$t | Out-Null
        }
    }

    # Extra sweep: known common target names created by GCM (old/new)
    $common = @(
        'git:https://github.com',
        'git:github.com',
        'LegacyGeneric:target=git:https://github.com'
    )
    foreach ($t in $common) {
        cmdkey /delete:$t 2>$null | Out-Null
    }
}

function Ensure-GitPresent {
    $gitVersion = (& git --version 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $gitVersion) {
        Write-Error "Git is not available on PATH. Install Git for Windows and try again."
        exit 1
    }
}

function Set-GlobalGitIdentity([string]$name, [string]$email) {
    Write-Host "`nClearing old global git user.name and user.email..."
    git config --global --unset user.name 2>$null
    git config --global --unset user.email 2>$null

    Write-Host "Setting new global identity:"
    Write-Host "  user.name  = $name"
    Write-Host "  user.email = $email"
    git config --global user.name "$name"
    git config --global user.email "$email"

    # (Optional) ensure Windows Credential Manager is used for auth
    # This helps guarantee browser-based login on next network call
    # Will not error if already set.
    git config --global credential.helper manager-core 2>$null
}

function Trigger-Reauth($account) {
    Write-Host "`nForcing GitHub login via browser for $account..."

    # Clear credentials at GCM level too
    echo "protocol=https
host=github.com" | git credential-manager-core erase 2>$null

    # Pick repo URL based on account
    switch ($account) {
        "shrey-regular" { 
            $testRepo = "https://github.com/shrey-resta/website-draft"  # 🔹 replace with real repo
        }
        "shrey-office" {
            $testRepo = "https://github.com/Restaverse-Codespace/react-mobile-app.git"    # 🔹 replace with real repo
        }
        default {
            $testRepo = "https://github.com/github/gitignore.git" # fallback (public repo)
        }
    }

    # Force a credentialed call (browser should open if no creds)
    git ls-remote $testRepo | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Browser login prompt should have appeared."
    } else {
        Write-Warning "GitHub auth did not trigger. Try running 'git pull' or 'git push' in a repo."
    }
}



# ---------------- Main ----------------
Ensure-GitPresent
$acct = Select-Account
$profile = $Profiles[$acct]

if (-not $profile) {
    Write-Error "Unknown profile selected. Exiting."
    exit 1
}

Write-Host "`nYou selected: $acct"
Remove-GitHubCreds
Set-GlobalGitIdentity -name $profile.user -email $profile.email
Trigger-Reauth -account $acct

Write-Host "`n-------------------------------------"
Write-Host "✅ Switched to '$acct' globally."
Write-Host "If a browser prompt didn't appear, run 'git fetch --all' inside a repository."
Write-Host "-------------------------------------"
