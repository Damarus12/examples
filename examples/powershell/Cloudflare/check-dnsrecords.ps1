$dns = gc .\RedactedCompany.io.json | ConvertFrom-Json

$result = @()

foreach ($d in $dns.result) {

    try {
        
        $res = Invoke-WebRequest -Uri $d.name -UseDefaultCredentials -UseBasicParsing -Method Head -TimeoutSec 2 -ErrorAction Stop
        $status = [int]$res.StatusCode
        Write-Host "$($d.name) - $status" -ForegroundColor Green
    }
    catch {
        $status = [int]$_.Exception.Response.StatusCode.value__
        Write-Warning "$($d.name) - $status"
    }
    $result += [PSCustomObject]@{
    
        site   = $d.name
    
        status = $status
    
    }
}