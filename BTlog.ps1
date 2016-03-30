#Requires –Version 3

Function loadConfig($path)
{
	$global:appSettings = @{}
	$config = [xml](get-content $path)
	foreach ($addNode in $config.configuration.appsettings.add) {
	 if ($addNode.Value.Contains(‘,’)) {
	  # Array case
	  $value = $addNode.Value.Split(‘,’)
	 
	  for ($i = 0; $i -lt $value.length; $i++) { 
		$value[$i] = $value[$i].Trim() 
	  }
	 }
	 else {
	  # Scalar case
	  $value = $addNode.Value
	 }
	 $global:appSettings[$addNode.Key] = $value
	}
}

function execCmd($cmdStr)
{
	$webclient = new-object System.Net.WebClient
	try {
		$response = $webclient.DownloadString("http://$($appSettings["BTnicAddress"])/btnic.cgi?$cmdStr")
		$response = $response | ConvertFrom-JSON
		if ($appSettings["TimestampFormat"]) {
			$timestamp = get-date -f $appSettings["TimestampFormat"]
			$response = @($timestamp) + $response
		}
		return $response
	} catch {
		throw
	}
}

function Get-StartFileTimestamp () {
	if ($appSettings["TimestampFormat"]) {
		return [DateTime]::ParseExact((get-content $appSettings["LogFileName"] -TotalCount 1).split("`t")[0], $appSettings["TimestampFormat"], [CultureInfo]::InvariantCulture)
	} else {
		return (Get-ItemProperty $appSettings["LogFileName"]).CreationTime
	}
}

function Test-LogArchive ($lastResponse) {
	if ((Test-Path $appSettings["LogFileName"]) -And $appSettings["NewLogFileTimeout"] -And ((Get-Date) - $lastResponse -gt [TimeSpan]$appSettings["NewLogFileTimeout"])) {
		$startTimeStamp = Get-StartFileTimestamp
		Move-Item -Path $appSettings["LogFileName"] -Destination ($appSettings["ArchiveLogPath"] + $startTimestamp.ToString($appSettings["ArchiveLogFileName"]))
	}
}

loadConfig BTlog.config
if (Test-Path $appSettings["LogFileName"]) {
	$lastResponse = (Get-ItemProperty $appSettings["LogFileName"]).LastWriteTime
} else {
	$lastResponse = Get-Date
}
Test-LogArchive ($lastResponse)

while ($true) {
	$appSettings["LogItems"] | ForEach-Object {
		try {
			$response = execCmd -cmdStr $_
			if ($response) {
				[string]::join("`t", $response) | out-file -append -encoding ASCII $appSettings["LogFileName"]
				$lastResponse = Get-Date
			}
		} catch {
			Test-LogArchive ($lastResponse)
		}
	}
	if ($appSettings["LogInterval"]) {
		Start-Sleep -s $appSettings["LogInterval"]
	}
}
