[string]$pipelineName = "name*" # Use * for wildcard
[string]$Project = "ProjectName"
[string]$branch = "instance/dev"

$pipelines = az pipelines list --name $pipelineName --organization https://dev.azure.com/company --project $Project | ConvertFrom-Json
$count = 0
$pipelines.foreach({
    Write-Host "Running pipeline: $($_.name)"
    az pipelines run --id $_.id --organization https://dev.azure.com/company --project $Project --branch $branch | Out-Null
    $count++
    if($count -ge 4){
        Write-Host "Giving time for other pipelines to finish"
        Start-Sleep 90
        $count = 0
    }
})
