# Confirm event log source is registered so the application can log events
# ================================== Parameters ==================================
[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $false)]
    [string]$sitePath
)
# logging
Write-Host "Site path: $($sitePath)"
# ================================== Functions ===================================
function SetEventLogSource([string]$sourceName) {
    # $eventLogSource = [System.Diagnostics.EventLog]::SourceExists($sourceName)
    if ([System.Diagnostics.EventLog]::SourceExists($sourceName) -eq $false) {
        [System.Diagnostics.EventLog]::CreateEventSource($sourceName, "Application")
        [System.Diagnostics.EventLog]::CreateEventSource($sourceName, "Security")
        "Event log source created, $($sourceName)"
    }
    # if (!$eventLogSource) {
    #     New-EventLog -LogName Application -Source $sourceName
    #     return "Event log source created, $($sourceName)"
    # }
    return "Event log source exists, $($sourceName)"
}
# ===================================================================================================
if (!$sitePath) {
    Write-Host "No site path provided"
    return
}
$configFiles = Split-Path $sitePath -Parent | Get-ChildItem -Filter web.config -Recurse

foreach ($configFile in $configFiles) {
    $configFileContent = Get-Content $configFile.FullName
    Write-Host "Checking $($configFile.FullName)"

    $match = [regex]::Match($configFileContent, '<eventLog source="([^"]*)"')

    if ($match.Success) {
        $source = $match.Groups[1].Value
        Write-Host "Source: $source"
        SetEventLogSource -sourceName $source
    }
}
