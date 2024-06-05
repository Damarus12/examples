$pipelines = az pipelines list --name "HAProxy*" --organization https://dev.azure.com/company --project DevOps | ConvertFrom-Json
$count = 0
$pipelines.foreach({
    Write-Host "Running pipeline: $($_.name)"
    az pipelines run --id $_.id --organization https://dev.azure.com/company --project DevOps | Out-Null
    $count++
    if($count -ge 3){
        Write-Host "Giving time for other pipelines to finish"
        Start-Sleep 90
        $count = 0
    }
})
