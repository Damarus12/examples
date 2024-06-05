# ================================== Parameters ==================================
[CmdletBinding()]
Param
(
    [Parameter(Mandatory = $true)]
    [string]$siteURL
)
# ================================== Functions ===================================
Import-Module WebAdministration
function Get-v4WebApp([string]$hostname) {
    # Create object to store which components exist. False = create, True = skip
    $data = [PSCustomObject]@{
        apppool          = $false
        components       = [PSCustomObject]@{
            web = [PSCustomObject]@{
                exists = $false
                name   = ""
            }
        }
        folderComponents = [PSCustomObject]@{
            web       = $false
            api       = $false
            auth      = $false
            scheduler = $false
        }
    }
    # Check if app pool exists
    if (Get-ChildItem IIS:\AppPools\ | ? { $_.Name -match $hostname }) {
        $data.apppool = $true
    }
    # Check if site exists
    $website = Get-Website -name $hostname
    if ($website) {
        Write-Host "##vso[task.setvariable variable=webPhysicalPath]$($website.PhysicalPath)" # Set pipeline variable for EventLogSource Task
        $data.components.web.exists = $true
        $data.components.web.name = $website.Name

        # Check if folder structure exists
        if (Test-Path -Path $website.PhysicalPath -ErrorAction SilentlyContinue) {
            $data.folderComponents.web = $true
        }
    }
    # Check if api folder structure exists
    if (Test-Path -Path "D:\sites\$($hostname)\Api" -ErrorAction SilentlyContinue) {
        $data.folderComponents.api = $true
    }
    # Check if auth folder structure exists
    if (Test-Path -Path "D:\sites\$($hostname)\Auth" -ErrorAction SilentlyContinue) {
        $data.folderComponents.auth = $true
    }
    # Check if scheduler folder structure exists
    if (Test-Path -Path "D:\sites\$($hostname)\Scheduler" -ErrorAction SilentlyContinue) {
        $data.folderComponents.scheduler = $true
    }
    
    return $data
        
}
function Set-SubAppHostname([string]$hostname) {
    $data = [PSCustomObject]@{
        rootHostname = ""
        subAppName   = ""
    }

    $data.rootHostname = ($hostname -split '\b(\/\w+)$')[0] -replace '(?:(pl\d{3,7}\-))'
    Write-Host "##[section]root variable: $($data.rootHostname)"
    Write-Host "##vso[task.setvariable variable=rootSite;isoutput=True]$($data.rootHostname)"

    $data.subAppName = ($hostname -split '\b(\/\w+)$')[1] -replace '/'
    Write-Host "##[section]app variable: $($data.subAppName)"
    Write-Host "##vso[task.setvariable variable=subapp;isoutput=True]$($data.subAppName)"

    return $data
}
function Get-v4SubApp([string]$rootHostname, [string]$subAppName) {
    # Create object to store which components exist. False = create, True = skip
    $data = [PSCustomObject]@{
        apppool          = $false
        components       = [PSCustomObject]@{
            subApp = [PSCustomObject]@{
                exists = $false
                name   = ""
            }
            web    = [PSCustomObject]@{
                exists = $false
                name   = ""
            }
        }
        folderComponents = [PSCustomObject]@{
            web  = $false
            api  = $false
            auth = $false
        }
    }
    # Check if app pool exists if hostname != non-prod (non-prod app pools share the root site app pool)
    if ($rootHostname -match 'dev.|qa.|stg.') {
        $data.apppool = $true
    }
    elseif
     (Get-ChildItem IIS:\AppPools\ | ? { $_.Name -eq $subAppName }) {
        $data.apppool = $true
    }
    # Check if app exists
    $subapp = Get-WebApplication -site $rootHostname -name $subAppName
    if ($subapp) {
        Write-Host "##vso[task.setvariable variable=webPhysicalPath]$($subapp.PhysicalPath)" # Set pipeline variable for EventLogSource Task
        $data.components.subApp.exists = $true
        $data.components.subApp.name = $subAppName

        # Check if folder structure exists
        if (Test-Path -Path $subapp.PhysicalPath -ErrorAction SilentlyContinue) {
            $data.folderComponents.web = $true
        }
    }
    Write-Host $data | ConvertFrom-Json
    return $data 
}
function New-v4Site([string]$hostname) {

    Write-Host "Site Components: $($siteComponents | Format-List | Out-String)"
    Write-Host "Hostname: $hostname"

    # Create app pool if it doesn't exist
    if ($siteComponents.apppool -eq $false) {
        "Creating app pool!"
        if ($hostname.Length -gt '64') {
            Write-Host "##[warning] App Pool HOSTNAME IS TOO LONG!"; exit 1
        }
        New-WebAppPool -Name $hostname
    }
    # Create folders if they don't exist - Only create Web Folder for RedactedCompany..
    if ($hostname -match 'RedactedCompany' -and $hostname -notmatch 'RedactedCompanydashboard') {
        New-Item -Path "S:\sites\$hostname\Web" -ItemType Directory -ErrorAction SilentlyContinue
    }
    else {
        $siteComponents.folderComponents.Psobject.properties | ForEach-Object {
            if ($_.Value -eq $false) {
                New-Item -Path "S:\sites\$hostname\$($_.Name)" -ItemType Directory -ErrorAction SilentlyContinue
            }
        }
    }
    # Create site if it doesn't exist
    if ($siteComponents.components.web.exists -eq $false) {
        New-Website -Name $hostname -PhysicalPath "S:\sites\$hostname\Web" -HostHeader $hostname -IPAddress "*" -SslFlags 2 -Port 443 -Ssl -ApplicationPool $hostname
        Write-Host "##vso[task.setvariable variable=webPhysicalPath]$("S:\sites\$hostname\Web")" # Set pipeline variable for EventLogSource Task

    
        Set-ItemProperty "IIS:\Sites\$hostname" -Name applicationDefaults.preloadEnabled -Value True
        Write-Host "##[section]New Website created"

        ### @TODO: Safe to remove this section after Azure Migration Project is Complete
        ################################################################################
        # if ($hostname -match 'RedactedCompany') {
        #     $testBinding = "RedactedCompany.az.ebbo.com" 
        #     New-WebBinding -Name $hostname -HostHeader $testBinding -Protocol https -Port 443 -IPAddress * -SslFlags 2 -ErrorAction silentlycontinue
        #     Write-Host "##[section]Azure test Binding: $testBinding"
        # }
        # else {
        #     Write-Host "No longer adding .az.ebbo.com binding for $hostname"
        #     # $testBinding = $hostname.Split(".")[0] + ".az.ebbo.com" 
        #     # New-WebBinding -Name $hostname -HostHeader $testBinding -Protocol https -Port 443 -IPAddress * -SslFlags 2 -ErrorAction silentlycontinue
        #     # Write-Host "##[section]Azure test Binding: $testBinding"
        # }
    }
  
    # =========== Create API / Auth Sub apps if they don't exist. Variables are set in the prior pipeline task. ===========
    Get-WebApp 



    ###############################################################################


    Set-ItemProperty "IIS:\Sites\$hostname" -Name applicationDefaults.preloadEnabled -Value True
}
function New-v4SubApp([string]$rootHostname, [string]$subAppName) {
    Write-Host "Site Components: $($siteComponents | Format-List | Out-String)"
    Write-Host "rootHostname: $rootHostname"
    Write-Host "subAppName: $subAppName"
    
    # Create app pool if it doesn't exist
    if ($siteComponents.apppool -eq $false) {
        "Creating app pool!"
        if ($subAppName.Length -gt '64') {
            Write-Host "##[warning] App Pool HOSTNAME IS TOO LONG!"; exit 1
        }
        New-WebAppPool -Name $subAppName
    }
    # Create folders if they don't exist
    $siteComponents.folderComponents.Psobject.properties | % {
        if ($_.Value -eq $false) {
            New-Item -Path "S:\sites\$rootHostname\$($_.Name)" -ItemType Directory -ErrorAction SilentlyContinue
        }
    }
    # Create ROOT site if it doesn't exist
    if (!(Get-Website -name $rootHostname)) {
        New-v4Site -hostname $rootHostname # Create root site using function
        Write-Host "##[section]Root site created"
    }
    if ($siteComponents.folderComponents.web -eq $false) { New-Item -Path "S:\sites\$rootHostname\$($subAppName)" -ItemType Directory -ErrorAction SilentlyContinue }
    if ($siteComponents.components.subApp.exists -eq $false) {

        # Use Root site app pool if sub app is dev, qa, or stg
        if ($rootHostname -match 'dev.|qa.|stg.') {

            New-WebApplication -name $subAppName -Site $rootHostname -physicalPath "S:\sites\$rootHostname\$subAppName" -ApplicationPool $rootHostname
        }
        else {

            Write-Host "##vso[task.setvariable variable=webPhysicalPath]$("S:\sites\$rootHostname\$subAppName")" # Set pipeline variable for EventLogSource Task
        }
        New-WebApplication -name $subAppName -Site $rootHostname -physicalPath "S:\sites\$rootHostname\$subAppName" -ApplicationPool $subAppName
    }
}
function Get-WebApp() {
    # ===== Create API / Auth Sub apps if they don't exist.
    # $env:[component] is set in a prior pipeline task
    if ($env:api) {
        $component = "api"

        if ($siteURL -match 'dev.|qa.|stg.') { $appPoolName = $siteURL }
        else { $appPoolName = $siteURL + "-$component" }

        if ($siteURL -notmatch 'dev.|qa.|stg.') {
            $poolExists = Get-ChildItem IIS:\AppPools\ | ? { $_.Name -eq $appPoolName }
            if ($poolExists) {
                Write-Host "##[section]$component App Pool already exists"
            }
            else {
                if ($appPoolName.Length -gt '64') {
                    Write-Host "##[warning] App Pool HOSTNAME IS TOO LONG!"; exit 1
                }
                New-WebAppPool -Name $appPoolName
            }
        }
        $appExists = Get-WebApplication -site $siteURL -name $component
        if ($appExists) {
            Write-Host "##[section]App already exists"
        }
        else {
            New-WebApplication -name $component -Site $siteURL -physicalPath "S:\sites\$siteUrl\$component" -ApplicationPool $appPoolName
        }
    }
    if ($env:auth) {
        $component = "auth"

        if ($siteURL -match 'dev.|qa.|stg.') { $appPoolName = $siteURL }
        else { $appPoolName = $siteURL + "-$component" }

        if ($siteURL -notmatch 'dev.|qa.|stg.') {
            $poolExists = Get-ChildItem IIS:\AppPools\ | ? { $_.Name -eq $appPoolName }
            if ($poolExists) {
                Write-Host "##[section]$component App Pool already exists"
            }
            else {
                if ($appPoolName.Length -gt '64') {
                    Write-Host "##[warning] App Pool HOSTNAME IS TOO LONG!"; exit 1
                }
                New-WebAppPool -Name $appPoolName
            }
        }
        $appExists = Get-WebApplication -site $siteURL -name $component
        if ($appExists) {
            Write-Host "##[section]App already exists"
        }
        else {
            New-WebApplication -name $component -Site $siteURL -physicalPath "S:\sites\$siteUrl\$component" -ApplicationPool $appPoolName
        }
    }
    if ($env:scheduler) {
        $component = "scheduler"
        if ($siteURL -match 'dev.|qa.|stg.') { $appPoolName = $siteURL }
        else { $appPoolName = $siteURL + "-$component" }

        if ($siteURL -notmatch 'dev.|qa.|stg.') {
            $poolExists = Get-ChildItem IIS:\AppPools\ | ? { $_.Name -eq $appPoolName }
            if ($poolExists) {
                Write-Host "##[section]$component App Pool already exists"
            }
            else {
                if ($appPoolName.Length -gt '64') {
                    Write-Host "##[warning] App Pool HOSTNAME IS TOO LONG!"; exit 1
                }
                New-WebAppPool -Name $appPoolName
            }
        }
        $appExists = Get-WebApplication -site $siteURL -name $component
        if ($appExists) {
            Write-Host "##[section]App already exists"
        }
        else {
            New-WebApplication -name $component -Site $siteURL -physicalPath "S:\sites\$siteUrl\$component" -ApplicationPool $appPoolName

        }
        # =========== Set Autostart provider for scheduler ===========
        # @TODO: Move up one level during web-app creation after Azure Migration Project is Complete
        $AutoStartProvider = [PSCustomObject]@{
            name = ($siteURL.Split(".")[0]) + $component + "ApplicationPreload" 
            type = "Company.Promo.Scheduler.ApplicationPreload, Company.Promo.Scheduler"
        }
        if (!(Get-ItemProperty "IIS:\Sites\$siteURL\$component\" -name serviceAutoStartEnabled)) {
            Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/serviceAutoStartProviders' -Name '.' -Value @{ name = $AutoStartProvider.name; type = $AutoStartProvider.type } -ErrorAction SilentlyContinue
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.applicationHost/sites/site[@name='$siteURL']/application[@path='/$component']" -Name "serviceAutoStartEnabled" -Value "True" -ErrorAction SilentlyContinue
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "system.applicationHost/sites/site[@name='$siteURL']/application[@path='/$component']" -Name "serviceAutoStartProvider" -Value $AutoStartProvider.name	-ErrorAction SilentlyContinue
            Write-host "##[section]ADDED Autostart provider!"
            Write-Host $AutoStartProvider.name - $AutoStartProvider.type
        }
        write-host "##[section]Autostart exists"
        # =========== Set Autostart provider for scheduler ===========
    }
}
#########################################################################
# Currently not being used as UGC has been moved to Azure Blob Storage
#########################################################################

# function Get-UgcFolders([string]$hostname) { 

#     $UGCPath = "\\redactedstorage.domain.com\ugc\$hostname"

#     $webVirtualDir = Get-WebVirtualDirectory -Site $hostname
#     if ($webVirtualDir.path -notcontains '/content/UGC') {
#         if ([string]::IsNullOrEmpty($hostname)) { Write-Host "##[warning] Site name variable is empty"; exit 1 }
#         else {
#             try {
#                 New-Item -Path $UGCPath -ItemType Directory -ErrorAction Continue
#                 'uploaded', 'converted', 'tmp' | % { New-Item -Path "$UGCPath\image\$_" -ItemType Directory -ErrorAction Continue }
#                 'uploaded', 'converted' | % { New-Item -Path "$UGCPath\other\$_" -ItemType Directory -ErrorAction Continue }
#                 'uploaded', 'converted', 'damaged', 'archive' | % { New-Item -Path "$UGCPath\video\$_" -ItemType Directory -ErrorAction Continue }

#                 New-Item "IIS:\Sites\$($hostname)\Content\UGC" -physicalPath $UGCPath -type VirtualDirectory
#             }
#             catch {
#                 Get-ChildItem -filter ugcError.txt -Recurse | Get-Content # ASCII Error ../../other/ugcError.txt
#             }
      
#             Write-Host "##[section]UGC folders created"
#         }
#     }
#     Write-Host "##[section]Verified UGC folders"
# }

# ================================== Main ===================================

# IF hostname contains a slash, it's a sub application
if ($siteUrl -match '\b(\/\w+)$') {
    Write-Host "##[section]Sub Application"
    $subAppData = Set-SubAppHostname -hostname $siteUrl # Splits hostname into root and sub app names
    $siteComponents = Get-v4SubApp -rootHostname $subAppData.rootHostname -subAppName $subAppData.subAppName
    New-v4SubApp -rootHostname $subAppData.rootHostname -subAppName $subAppData.subAppName
}
else {
    $siteComponents = Get-v4WebApp -hostname $siteURL
    New-v4Site -hostname $siteUrl
}