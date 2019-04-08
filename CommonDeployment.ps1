#version 1.9.1
param (
[switch]$Update,
[switch]$Uninstall,
[string]$Url, 
[string]$Solution, 
[string]$Feature,
[switch]$RestartTimer,
[switch]$Activate,
[switch]$Deactivate,
[switch]$Reactivate,
[switch]$IisReset,
[switch]$Import,
[switch]$Bin,
[switch]$Silent,
[switch]$Warmup,
[string]$ReinstallAssembly
)
#example : .\commondeployment.ps1 -Url:"http://site" -Solution:"mysolution.wsp" -RestartTimer


Add-PSSnapin "microsoft.sharepoint.powershell" -ea 0
Import-Module WebAdministration
$a = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
$a = [System.Reflection.Assembly]::LoadWithPartialName("System.EnterpriseServices")
$dir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent



#region Common deployment functions

function TrimPsName($val){
    if($val -ne ""){
        $val = @($val.TrimStart(".\"))
    }
    return $val
}
function Get-Solutions(){ 
   
    param($nolog = $false)

    $solutions = Get-ChildItem $dir -Filter *.wsp | Select -ExpandProperty Name
      
    if($nolog -eq $false){
        Write-Host "found solutions:" -ForegroundColor:Yellow
        $solutions | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }  
    }    

    if($Solution -ne ""){
        $solutions = @(TrimPsName($Solution))
    }
    return $solutions
}
function Get-SolutionFeatures($solutionName){    
    $solution = Get-SPSolution $solutionName -ErrorAction:SilentlyContinue

    if ($solution -eq $null){		
		Write-Host "not installed:" $solutionName -ForegroundColor:Red
		return
	}	

    $solId = $solution.Id
    $features = Get-SPFeature | where {$_.solutionId -eq $solId}
    return $features
}

function Gac-Install($assemblyName){
	$publish = New-Object System.EnterpriseServices.Internal.Publish

	$currDir = Get-Location

	$fullAsmName = [System.IO.Path]::Combine($currDir,$assemblyName)

	if($fullAsmName.EndsWith(".dll") -eq $false){
		$fullAsmName = $fullAsmName + ".dll"
	}

	if ( -not (Test-Path $fullAsmName -type Leaf) ) {
            throw "The assembly '$fullAsmName' does not exist."
    }

	$publish.GacInstall($fullAsmName)
}
function Gac-Remove($assemblyName){
	$publish = New-Object System.EnterpriseServices.Internal.Publish

	$currDir = Get-Location

	$fullAsmName = [System.IO.Path]::Combine($currDir,$assemblyName)

	if($fullAsmName.EndsWith(".dll") -eq $false){
		$fullAsmName = $fullAsmName + ".dll"
	}

	if ( -not (Test-Path $fullAsmName -type Leaf) ) {
            throw "The assembly '$fullAsmName' does not exist."
    }

	$publish.GacRemove($fullAsmName)
}
function RestartPool($weburl){
	$webApp = [Microsoft.SharePoint.Administration.SPWebApplication]::Lookup($weburl)
	if($webApp -eq $null){
		throw "webapplication not found at: " + $url
	}

	$poolName = $webApp.IisSettings[0].ServerComment
	Restart-WebAppPool -Name $poolName
	Write-Host ("IIS pool recycled: " + $poolName)
}

function Pack-Wsp($sourceDir, $destWSPfilename){

    $sourceDir = TrimPsName($sourceDir)
    $fullSrcPath  = [System.IO.Path]::Combine($dir, $sourceDir)
    $fullDestPath = [System.IO.Path]::Combine($dir, $destWSPfilename)
 
    

	$sourceSolutionDir = [System.IO.DirectoryInfo]$fullSrcPath
 
	$a = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")
	$ctor = $a.GetType("Microsoft.SharePoint.Utilities.Cab.CabinetInfo").GetConstructors("Instance, NonPublic")[0]
 
	$cabInf = $ctor.Invoke($fullDestPath);
 
	$mi = $cabInf.GetType().GetMethods("NonPublic, Instance, DeclaredOnly")
	$mi2 = $null
	foreach( $m in $mi ) {
		if( $m.Name -eq "CompressDirectory" -and $m.GetParameters().Length -eq 4 ) {
			$mi2 = $m;
			break;
		};
	}
 
	$mi2.Invoke($cabInf, @( $sourceSolutionDir.FullName, $true, -1,$null ));
    Write-Host "Created solution: " $fullDestPath -ForegroundColor Green
}

function Count(){
 	begin { $total = 0; }
    process { $total += 1 }
	end { return $total	}
}
function EnableRemoteAdministrator($isEnable){
	$contentService = [Microsoft.SharePoint.Administration.SPWebService]::ContentService
	$contentService.RemoteAdministratorAccessDenied = !$isEnable
	$contentService.Update()
}
function CheckUrl($url){
	$webApp = [Microsoft.SharePoint.Administration.SPWebApplication]::Lookup($url)
	if($webApp -eq $null){
		throw "webapplication not found at: " + $url
	}
}
function IsSingleServer(){
	$c = [Microsoft.SharePoint.Administration.SPFarm]::Local.Servers | Where { 
	($_.Role -eq  [Microsoft.SharePoint.Administration.SPServerRole]::WebFrontEnd) -or
	($_.Role -eq  [Microsoft.SharePoint.Administration.SPServerRole]::Application) -or
    ($_.Role -eq  [Microsoft.SharePoint.Administration.SPServerRole]::SingleServer) -or
	($_.Role -eq  "WebFrontEndWithDistributedCache") -or
	($_.Role -eq  "ApplicationWithSearch") -or
	($_.Role -eq  "SingleServerFarm") -or
	($_.Role -eq  "Custom")	} | Count
	return ($c -eq 1)
}

function ActivateFeature($id, $name, $url){	
	#Enable-SPFeature $name -Confirm:$false -Url:$url -ErrorAction:Stop -Force:$true
	#Write-Host "activated:" $name -ForegroundColor:Green
	# powershell does not show feature receiver exceptions
	Write-Host "activating" $name -ForegroundColor:Yellow -NoNewline
	stsadm.exe -o activatefeature -id $id -url $url  
}
function ActivateFeatures($solution, $url, $feature){

	$name = [System.IO.Path]::GetFileName($solution)

    $featureNames = Get-SolutionFeatures $name

    if($feature -ne ""){
        $featureNames = $featureNames | ?{($_.DisplayName -eq $feature) -or ($_.Id -eq $feature)}
    }

    if($featureNames.Count -eq 0) {
        Write-Host $name "contains no features or specified feature not found"
        return
    }

    foreach($f in $featureNames){   
		ActivateFeature $f.Id $f.DisplayName $url			
	}
}


function DeactivateFeature($id, $name, $url){
	<#$feature = Get-SPFeature -Identity:$name  -ErrorAction:SilentlyContinue -Site:$url
	
	if($feature -eq $null){
		$feature = Get-SPFeature -Identity:$name  -ErrorAction:SilentlyContinue -Web:$url
	}
	
	if ($feature -eq $null){
		Write-Host "not installed or active:" $name -ForegroundColor:Red
		return
	}	
	disable-spfeature $name -Url $url -Force -Confirm:$false -ErrorAction Stop
	Write-Host "deactivated:" $name -ForegroundColor:Green
	#>
	Write-Host "deactivating" $name -ForegroundColor:Yellow -NoNewline
	stsadm.exe -o deactivatefeature -id $id -url $url
}
function DeactivateFeatures($solution, $siteUrl, $feature){

	$name = [System.IO.Path]::GetFileName($solution)

    $featureNames = Get-SolutionFeatures $name

 	if($feature -ne ""){
        $featureNames = $featureNames | ?{($_.DisplayName -eq $feature) -or ($_.Id -eq $feature)}
    }

    if($featureNames.Count -eq 0) {
        Write-Host $name "contains no features or specified feature not found"
        return
    }

    foreach($f in $featureNames){
		DeactivateFeature $f.Id $f.DisplayName $siteUrl
	}
}

function DeploySolution(){

    param($name, $url = $null)
		
	$local = IsSingleServer

    $name = [System.IO.Path]::GetFileName($name)

	write-host -ForegroundColor yellow "deploying" $name -NoNewline

	$solution = Get-SPSolution $name -ErrorAction:Stop
	
	if($solution.Deployed -eq $true){
		Write-Host "already deployed:" $name -ForegroundColor:Red
		return
	}

    if($url -eq $null){
        
        if ($solution.ContainsWebApplicationResource -eq $true){		
		    Install-SPSolution $name -GACDeployment -Local:$local -Confirm:$false -AllWebApplications -Force -ErrorAction:Stop -FullTrustBinDeployment:($Bin -eq $true)
	    }
	    else{
		    Install-SPSolution $name -GACDeployment -Local:$local -Confirm:$false -Force -ErrorAction:Stop -FullTrustBinDeployment:($Bin -eq $true)
	    }

    }
	elseif ($solution.ContainsWebApplicationResource -eq $true){
		
		$webApp = [Microsoft.SharePoint.Administration.SPWebApplication]::Lookup($url)
		
		Install-SPSolution $name -GACDeployment -Local:$local -Confirm:$false -WebApplication:$webApp -Force -ErrorAction:Stop -FullTrustBinDeployment:($Bin -eq $true)
	}
	else{
		Install-SPSolution $name -GACDeployment -Local:$local -Confirm:$false -Force -ErrorAction:Stop -FullTrustBinDeployment:($Bin -eq $true)
	}	
	
	$solution = Get-SPSolution $name -ErrorAction:Stop	

	if ($solution.Deployed -eq $false ) { 
	    $counter = 1 
	    $maximum = 50 
	    $sleeptime = 2 		
	    while( ($solution.JobExists -eq $true ) -and ( $counter -lt $maximum  ) ) { 
	        Write-Host -ForegroundColor yellow "." -NoNewline
	        sleep $sleeptime
	        $counter++ 
		} 
	}	
	Write-Host " ok" -ForegroundColor:Green
}
function DeploySolutions($solutions, $siteUrl){
    foreach($s in $solutions){
        DeploySolution $s $siteUrl
    }
}

function RetractSolution($name, $url){
	$local = IsSingleServer

    $name = [System.IO.Path]::GetFileName($name)

	Write-Host -ForegroundColor yellow "Retracting" $name -NoNewline

	$solution = Get-SPSolution $name -ErrorAction:SilentlyContinue
	
	if ($solution -eq $null){
		Write-Host " not installed, skip" -ForegroundColor:Red
		return
	}	

	if ($solution.Deployed -eq $false){
		#Write-Host "not deployed:" $name -ForegroundColor:Red
		return
	}
			
	if ($solution.ContainsWebApplicationResource)	{	
		$webApp = [Microsoft.SharePoint.Administration.SPWebApplication]::Lookup($url)
		uninstall-spsolution $name -WebApplication:$webApp -Local:$local -Confirm:$false -ErrorAction:Stop
	}
	else{
		uninstall-spsolution $name -Local:$local -Confirm:$false -ErrorAction:Stop
	}
	
	$solution = Get-SPSolution $name -ErrorAction Stop
	
	$counter = 1 
    $maximum = 50 
    $sleeptime = 2 

    while($solution.JobExists -and ($counter -lt $maximum)) { 
        Write-Host -ForegroundColor yellow "." -NoNewline
        sleep $sleeptime
        $counter++ 
    } 
	Write-Host " ok" -ForegroundColor:Green
}
function RetractSolutions($solutions, $url){
	foreach($s in $solutions){
		RetractSolution $s $url
	}
}

function AddSolution($solutionFile){
	
	$name = [System.IO.Path]::GetFileName($solutionFile)
	Write-Host "adding" $name -NoNewline

	$solution = Get-SPSolution $name -ErrorAction:SilentlyContinue
	
	if ($solution -ne $null){
		Write-Host "already exists:" $name -ForegroundColor:Red
		return
	}

	$solution = Add-SPSolution $solutionFile -Confirm:$false -ErrorAction:Stop	
	Write-Host " ok" -ForegroundColor:Green
}
function AddSolutions($solutionFiles){
    foreach($s in $solutionFiles){
        $ss = [System.IO.Path]::Combine($dir,$s)
        AddSolution($ss)
    }
}

function DeleteSolution($name){
	
    $name = [System.IO.Path]::GetFileName($name)
	Write-Host "deleting" $name -ForegroundColor:Green -NoNewline

	$solution = Get-SPSolution $name -ErrorAction:SilentlyContinue
	
	
	if ($solution -eq $null){
		Write-Host " not exist, skip" -ForegroundColor:Red
		return
	}
	
	Remove-SPSolution $name -Force -Confirm:$false -ErrorAction:Stop
	Write-Host " ok" -ForegroundColor:Green
}
function DeleteSolutions($solutions){
    foreach($s in $solutions){
		DeleteSolution $s
	}
}

function Install(){
    AddSolutions($solutions)	
	
    DeploySolutions $solutions $weburl	

	if($Reactivate -eq $true) {
		Write-Host "activate features"
        foreach($s in $solutions){		
		    ActivateFeatures $s $weburl		
        }
	}
}
function Uninstall(){    
    if($Reactivate -eq $true) {
		Write-Host "deactivate features"
        foreach($s in $solutions){
			DeactivateFeatures $s $weburl			
        }	
	}

	RetractSolutions $solutions $weburl		

	DeleteSolutions $solutions	
}

function ConfirmYesNo ([System.String]$caption, [System.String]$message) {
    $yes = new-Object System.Management.Automation.Host.ChoiceDescription "&Yes",""
    $no = new-Object System.Management.Automation.Host.ChoiceDescription "&No",""
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $answer = $host.ui.PromptForChoice($caption, $message, $choices, 1)
    return $answer
}


function RestartService($serviceName){
 
    [array]$servers= Get-SPServer | ? {$_.Role -eq "Application"} 

    foreach ($server in $servers) 
    {      

        $Service = Get-WmiObject -Computer $server.name Win32_Service -Filter "Name='$serviceName'"          

        if ($Service -ne $null) { 
            Write-Host "Restarting service " $serviceName "on server" $server.Name
            $a = $Service.InvokeMethod('StopService',$null)
            Start-Sleep -s 8 
            $a = $service.InvokeMethod('StartService',$null) 
            Start-Sleep -s 5 
            Write-Host -ForegroundColor Green "Service successfully restarted on" $server.Name
        } else {  
            Write-Host -ForegroundColor Red "Could not find service on" $server.Name
        } 

        Write-Host ""
    }
}

function RestartTimer(){
    RestartService "SPTimerV4"
}

function RestartProjectServices(){
    RestartService "ProjectQueueService15"
    RestartService "ProjectEventService15"
    RestartService "ProjectCalcService15"
}

function ResetIis(){
    
    $spServers= Get-SPServer | ? {$_.Role -eq "Application"} 

    foreach ($spServer in $spServers) {             
        Write-Host "Doing IIS Reset in server $spServer" -f Green 
        iisreset $spServer /noforce "\\"$_.Address 
        #iisreset $spServer /status "\\"$_.Address 
    }         
    Write-Host "IIS Reset completed successfully!!" -f Yellow  
    
}

function ResetIssOnDemand(){
    if($IisReset -eq $true){
        ResetIis
    }
}

function RestartTimerOnDemand(){
   if($RestartTimer -eq $true){
        RestartTimer
   }
}

function WarmUp($webUrl) {
	
    function NavigateTo([string] $url) {
	    if ($url.ToUpper().StartsWith("HTTP")) {
		    Write-Host "GET:"  $url -NoNewLine
		    # WebRequest command line
		    try {
			    $wr = Invoke-WebRequest -Uri $url -UseBasicParsing -UseDefaultCredentials -TimeoutSec 360
                try{
			        FetchResources $url $wr.Images
                }
                catch{
                
                }
                try{
		    	    FetchResources $url $wr.Scripts
                }
                catch{
                }
			    Write-Host "."
		    } catch {
			    $httpCode = $_.Exception.Response.StatusCode.Value__
			    if ($httpCode) {
				    Write-Host "   [$httpCode]" -Fore Yellow
			    } else {
				    Write-Host " "
			    }
		    }
	    }
    }

    function FetchResources($baseUrl, $resources) {
	    # Download additional HTTP files
	    [uri]$uri = $baseUrl
	    $rootUrl = $uri.Scheme + "://" + $uri.Authority
	
	    # Loop
	    $counter = 0
	    foreach ($res in $resources) {
		    # Support both abosolute and relative URLs
		    $resUrl  = $res.src
		    if ($resUrl.ToUpper() -contains "HTTP") {
			    $fetchUrl = $res.src
		    } else {
			    if (!$resUrl.StartsWith("/")) {
				    $resUrl = "/" + $resUrl
			    }
			    $fetchUrl = $rootUrl + $resUrl
		    }

		    # Progress
		    Write-Progress -Activity "Opening " -Status $fetchUrl -PercentComplete (($counter/$resources.Count)*100)
		    $counter++
		
		    # Execute
		    $resp = Invoke-WebRequest -UseDefaultCredentials -UseBasicParsing -Uri $fetchUrl -TimeoutSec 120
		    Write-Host "." -NoNewLine
	    }
	    Write-Progress -Activity "Completed" -Completed
    }

    NavigateTo $webUrl
}

function List-Pools(){
    C:\Windows\system32\inetsrv\appcmd.exe list  wp | ? { $_ -match "SharePoint"  }
}

#endregion


if($Update -eq $true){
    Write-Host "Updating solutions" -ForegroundColor Yellow

    $sols = Get-Solutions $true

    foreach($solName in $sols){  
    
        if($Solution -ne ""){
            $n = TrimPsName $Solution
            if($n -ne $solName){
                continue
            }
        }     
       
        $literalPath = [io.path]::Combine($dir, $solName)

        Write-Host ($solName + " ") -NoNewline -ForegroundColor Cyan
        try{
            Update-SPSolution -LiteralPath $literalPath -Identity $solName -GACDeployment -ErrorAction Stop
            Write-Host " Queued" -ForegroundColor Green

            $sleeptime = 2 
            $counter = 1 
	        $maximum = 50 


            $s= Get-SPSolution $solName 

            if($s.JobExists -ne $true){
                write-host "wait job started" -NoNewline
                while(( $s.JobExists -ne $true) -and ( $counter -lt $maximum  ) ) { 
	                Write-Host -ForegroundColor DarkYellow "." -NoNewline
	                sleep $sleeptime
	                $counter++ 
		        }
                Write-Host " ok" -ForegroundColor:Green
            }           
            
            if ($s.JobExists -eq $true ) { 
                write-host  "wait job ends" -NoNewline
	            $counter = 1 
	            $maximum = 50 
	            $sleeptime = 2 		
	            while( ($s.JobExists -eq $true ) -and ( $counter -lt $maximum  ) ) { 
	                Write-Host -ForegroundColor yellow "." -NoNewline
	                sleep $sleeptime
	                $counter++ 
		        } 
                Write-Host " ok" -ForegroundColor:Green
	        }		   

        }
        catch{
            
            if($_.exception.message -match "Cannot find an SPSolution object with Id or Name"){

                try{
                    AddSolution $literalPath
                    DeploySolution $literalPath                   
                    continue 
                }     
                catch{
                    Write-Host ""
                    Write-Host "$($_.exception.message)" -ForegroundColor Red
                }         
            }

            Write-Host ""
            Write-Host "$($_.exception.message)" -ForegroundColor Red
        } 
    }

    RestartTimerOnDemand  

    return

}

if($Import -eq $true){  
	Write-Host "commondeployment functions was imported" -ForegroundColor Yellow
	return
}

if($ReinstallAssembly -ne ""){
	Gac-Remove $ReinstallAssembly
	Gac-Install $ReinstallAssembly
	Write-Host "Assembly updated in GAC"
	if($Url -ne ""){
		RestartPool $Url
	}
	return
}

if($Url -ne ""){
	$weburl = $Url
} else{
    $f = [Microsoft.SharePoint.Administration.SPFarm]::Local

    $ws = $f.Services | ? {$_.TypeName -eq "Microsoft SharePoint Foundation Web Application" }

    $wa = $ws.WebApplications |
     ? {$_.IsAdministrationWebApplication -eq $false} |
     ? {($_.IisSettings[0].SecureBindings.Port -eq 443) -or ($_.IisSettings[0].ServerBindings.Port -eq 80)}
      select -First 1

    $s = $wa.Sites | select -First 1
    $weburl = $s.RootWeb.Url   
  
    if(($Silent -eq $false) -and (ConfirmYesNo("Url parameter not passed. ", "Script will use root web on port 80 or 443: " + $weburl) -eq $false)){
        return
    }
}

CheckUrl($weburl)
Write-Host $weburl.ToUpper() -ForegroundColor:Black -BackgroundColor:White

if($Solution -eq ""){
    $solutions = Get-Solutions
}
else{
    $solutions = @(TrimPsName $Solution)
}

if($Activate -eq $true){
    foreach($s in $solutions){	
        ActivateFeatures $s $weburl $Feature
    }
    RestartTimerOnDemand
    ResetIssOnDemand
    return
}

if($Deactivate -eq $true){
    foreach($s in $solutions){	
        DeactivateFeatures $s $weburl $Feature
    }
    RestartTimerOnDemand
    ResetIssOnDemand
    return
}

if($Reactivate -eq $true){
    foreach($s in $solutions){
        DeactivateFeatures $s $weburl $Feature
        ActivateFeatures $s $weburl	$Feature
    }
    RestartTimerOnDemand
    ResetIssOnDemand
    return
}

if($Uninstall -eq $true){    
    Uninstall
}
else{
	Uninstall
    Install 
}

RestartTimerOnDemand

ResetIssOnDemand

if($Warmup -eq $true){
    WarmUp $Url
}


Write-Host "Completed at:" ([datetime]::Now).ToString()
