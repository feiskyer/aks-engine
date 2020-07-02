$Global:ClusterConfiguration = ConvertFrom-Json ((Get-Content "c:\k\kubeclusterconfig.json" -ErrorAction Stop) | out-string)
$clusterFQDN = $Global:ClusterConfiguration.Kubernetes.ControlPlane.IpAddress
$hostsFile="C:\Windows\System32\drivers\etc\hosts"
$retryDelaySeconds = 15

# TODO: test only, remove it after test
$clusterFQDN = "$clusterFQDN.local"

# Dot-source scripts with functions that are called in this script
. c:\AzureData\k8s\kuberneteswindowsfunctions.ps1

function Get-APIServer-IPAddress
{
    $uri = "http://169.254.169.254/metadata/instance/compute/tags?api-version=2019-03-11&format=text"
    $response = Retry-Command -Command "Invoke-RestMethod" -Args @{Uri=$uri; Method="Get"; ContentType="application/json"; Headers=@{"Metadata"="true"}} -Retries 3 -RetryDelaySeconds 5

    if(!$response) {
        return ""
    }

    foreach ($tag in $response.Split(";"))
    {
        $values = $tag.Split(":")
        if ($values.Length -ne 2)
        {
            return ""
        }

        if ($values[0] -eq "aksAPIServerIPAddress")
        {
            return $values[1]
        }
    }

    return ""
}

while ($true)
{
    $clusterIP = Get-APIServer-IPAddress
    Write-Log "Get current APIServer IP address: $clusterIP"

    if ($clusterIP -eq "") {
        Write-Log "Doesn't find clusterIP from aksAPIServerIPAddress tag, skipping"
        Start-Sleep $retryDelaySeconds
        continue
    }

    $hostsContent=Get-Content -Path $hostsFile -Encoding UTF8
    if ($hostsContent -match "$clusterIP $clusterFQDN") {
        Write-Log "$clusterFQDN has already been set to $clusterIP"
    } else {
        $hostsContent -notmatch "$clusterFQDN" | Out-File $hostsFile -Encoding UTF8
        Add-Content -Path $hostsFile -Value "$clusterIP $clusterFQDN" -Encoding UTF8
        Write-Log "Updated $clusterFQDN to $clusterIP"
    }

    Start-Sleep $retryDelaySeconds
}
