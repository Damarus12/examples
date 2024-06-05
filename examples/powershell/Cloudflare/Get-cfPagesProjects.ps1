$projectName = $($env:BUILD_REPOSITORY_NAME.tolower().replace(".", "-"))
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer __workerspagestoken__")

try {

    $response = Invoke-RestMethod 'https://api.cloudflare.com/client/v4/accounts/accountId/pages/projects' -Method 'GET' -Headers $headers
}
catch {
    # Default to using the project name if the API call fails
    Write-Host "##vso[task.setvariable variable=pagesProjectName;isOutput=true]$projectName"
    return
}

if ($response.result.name -notcontains $projectName) {
    Write-Host "project not found"
    Write-Host "Creating Pages Project"
    #=================================================
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", "application/json")
    $headers.Add("Authorization", "Bearer __workerspagestoken__")
    $body = @{
        "build_config"      = @{
            "build_command"   = "npm run build"
            "destination_dir" = "build"
            "root_dir"        = "/"
        }
        "name"              = $projectName  
        "production_branch" = "main"
    } | ConvertTo-Json
    write-host $body
    $response = Invoke-RestMethod 'https://api.cloudflare.com/client/v4/accounts/accountId/pages/projects' -Method 'POST' -Headers $headers -Body $body
    $response | ConvertTo-Json
} 

Write-Host "##vso[task.setvariable variable=pagesProjectName;isOutput=true]$projectName"