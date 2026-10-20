#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Install', 'Remove')]
    [string]$Action = 'Install',

    [string]$PolicyFile = (Join-Path $PSScriptRoot 'managed-search-engines.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This installer requires Windows.'
}

$source = Get-Content -LiteralPath $PolicyFile -Raw
if (-not $source.TrimStart().StartsWith('[')) {
    throw 'The policy file must contain a JSON array.'
}
$policy = @($source | ConvertFrom-Json)
if ($policy.Count -lt 2 -or
    $null -eq $policy[0] -or
    $policy[0].PSObject.Properties.Name -notcontains 'allow_search_engine_discovery' -or
    $policy[0].allow_search_engine_discovery -isnot [bool] -or
    -not $policy[0].allow_search_engine_discovery) {
    throw 'The first policy entry must enable allow_search_engine_discovery.'
}

$engines = @($policy | Select-Object -Skip 1)
if ($engines.Count -gt 100) {
    throw 'Edge supports at most 100 search engines.'
}
$keywords = @{}
$defaultCount = 0
foreach ($engine in $engines) {
    foreach ($field in 'name', 'keyword', 'search_url') {
        if ($null -eq $engine -or
            $engine.PSObject.Properties.Name -notcontains $field -or
            $engine.$field -isnot [string] -or
            [string]::IsNullOrWhiteSpace($engine.$field)) {
            throw "Each engine needs a nonempty string '$field'."
        }
    }
    if ($engine.keyword -match '\s' -or $keywords.ContainsKey($engine.keyword)) {
        throw "Duplicate or whitespace-containing keyword: '$($engine.keyword)'."
    }
    $keywords[$engine.keyword] = $true
    $url = $null
    if (-not [uri]::TryCreate($engine.search_url, [UriKind]::Absolute, [ref]$url) -or
        $url.Scheme -ne 'https' -or
        ([regex]::Matches($engine.search_url, '\{searchTerms\}')).Count -ne 1 -or
        $engine.search_url.Contains('%s')) {
        throw "Engine '$($engine.name)' needs an HTTPS URL with exactly one {searchTerms} placeholder and no %s."
    }
    if ($engine.PSObject.Properties.Name -contains 'is_default') {
        if ($engine.is_default -isnot [bool]) {
            throw "Engine '$($engine.name)' has a non-boolean is_default."
        }
        if ($engine.is_default) {
            $defaultCount++
        }
    }
}
if ($defaultCount -ne 1) {
    throw 'Exactly one engine must have is_default set to true.'
}

$json = ConvertTo-Json -InputObject $policy -Depth 10 -Compress
$path = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge\Recommended'
$valueName = 'ManagedSearchEngines'
$current = $null
if (Test-Path -LiteralPath $path) {
    $properties = Get-ItemProperty -LiteralPath $path
    if ($properties.PSObject.Properties.Name -contains $valueName) {
        $current = $properties.$valueName
    }
}

if ($Action -eq 'Remove') {
    if ($null -eq $current) {
        Write-Output 'No current-user recommended ManagedSearchEngines value is installed.'
        return
    }
    if ($current -cne $json) {
        throw 'The installed policy differs from this file. Refusing to remove a policy this POC cannot identify. Use the original policy file with -PolicyFile.'
    }
    if ($PSCmdlet.ShouldProcess("$path\$valueName", 'Remove this POC policy value')) {
        Remove-ItemProperty -LiteralPath $path -Name $valueName
        Write-Output 'Policy value removed. Fully exit and restart Edge; browser-retained preferences may remain.'
    }
    return
}

# Do not overwrite or compete with existing search policies.
foreach ($otherPath in @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended',
    'HKCU:\SOFTWARE\Policies\Microsoft\Edge',
    $path
)) {
    if (-not (Test-Path -LiteralPath $otherPath)) {
        continue
    }
    $properties = Get-ItemProperty -LiteralPath $otherPath
    foreach ($name in 'ManagedSearchEngines', 'DefaultSearchProviderSearchURL') {
        if ($properties.PSObject.Properties.Name -notcontains $name) {
            continue
        }
        if ($otherPath -eq $path -and $name -eq $valueName -and $current -ceq $json) {
            continue
        }
        throw "Existing $name at $otherPath. Refusing to replace or compete with it. Check edge://policy and contact your administrator if managed."
    }
}

if ($null -ne $current) {
    Write-Output 'This exact policy value is already installed. Restart Edge and verify it at edge://policy.'
    return
}

$defaultEngine = $engines | Where-Object { $_.PSObject.Properties.Name -contains 'is_default' -and $_.is_default }
Write-Warning "This recommends '$($defaultEngine.name)' as the default and adds $($engines.Count) engines. It applies to eligible profiles for this Windows user, not just the active profile."
if ($PSCmdlet.ShouldProcess("$path\$valueName", 'Install current-user recommended search engines (REG_SZ)')) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $path -Name $valueName -Value $json -PropertyType String | Out-Null
    $installed = Get-ItemProperty -LiteralPath $path -Name $valueName
    if ($installed.$valueName -cne $json) {
        throw 'Registry verification failed: the policy value does not match.'
    }
    Write-Output 'Policy value installed. Fully exit and restart Edge, then verify ManagedSearchEngines at edge://policy. Browser acceptance is not yet verified.'
}
