[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Get-ProjectData() {
    # ================================== Api Query ===================================
    # $apiHostname = "RedactedURL.com"
    $repository = $env:BUILD_REPOSITORY_NAME
    $pipelineName = $env:BUILD_DEFINITIONNAME

    Write-Host "Repository: $repository"
    Write-Host "Pipeline name: $pipelineName"

    $headers = @{}
    $response = Invoke-RestMethod "https://RedactedURL.com/projects?repository=$repository" -Method 'GET' -Headers $headers

    # ================================== Error handling ===================================
    Write-Host "Response: $($response)"
    if ($null -eq $response) {
        Write-Host "##[warning] No project found! Stopping..."
        exit 1
    }
    if ($response.project_name.count -gt 1) {
        Write-Host "Found more than one project..."
        $response = $response | ? { $pipelineName -match $_.project_name }
        Write-Host $response
        if ($response.count -eq 0) {
            Write-Host "##[warning] Could not find a project in OpsCentral that matches $($_.project_name). Stopping..."
            exit 1
        }
        if ($response.count -gt 1) {
            Write-Host "##[warning] Got more than one project! Stopping..."
            exit 1
        }
        if ($response.environment_name -eq "spa") {
            Write-Host "##[warning] SPA project found! Stopping..."
            Write-Host "##[warning] SPA project found! Stopping..."
            Get-ChildItem -filter wrongEnv.txt -Recurse | Get-Content
            exit 1
        }
    }

    Write-Host "Build_SourceBranchName: $($env:BUILD_SOURCEBRANCHNAME)"
    
    # ================================== Set site hostname based on branch ============
    switch ($env:BUILD_SOURCEBRANCHNAME) {
        { $_ -match 'main' } { $siteURL = $response.components.prodUrl; $siteEnv = $response.environment_name }
        { $_ -match 'staging|azurestg' } { $siteURL = $response.components.stgUrl; $siteEnv = 'stg' }
        { $_ -match 'qa|azureqa' } { $siteURL = $response.components.qaUrl; $siteEnv = 'qa' }
        { $_ -match 'dev|azuredev' } { $siteURL = $response.components.devUrl; $siteEnv = 'dev' }
        { $_ -eq 'azure' } { $siteURL = $response.components.prodUrl; $siteEnv = $response.environment_name } # Azure Migration
        Default { Write-Host "##[warning] Deployment environment not clear!"; exit 1 }
    }

    ### Change env for internal nonprod apps
    if ($env:BUILD_SOURCEBRANCHNAME -match 'dev|qa|staging|azuredev|azureqa|azurestg' -and $response.environment_name -eq 'internal' ) {
        $siteEnv = "internalNonProd"
    }
    ###

    # Remap for easily setting pipeline variables
    $data = [PSCustomObject]@{
        url = $siteURL
        env = $siteEnv
    }
    return $data
}

$projectData = Get-ProjectData
if (($projectData.url -eq "" -or $projectData.env -eq "")) {
    Write-Host "##[warning] No project data found! Stopping..."
    Get-ChildItem -filter noProjectFound.txt -Recurse | Get-Content
    exit 1
}
$projectData
# Set variables for pipeline
Write-Host "##vso[task.setvariable variable=siteUrl;isoutput=True]$($projectData.url)"
Write-Host "##vso[task.setvariable variable=siteEnv;isoutput=True]$($projectData.env)"