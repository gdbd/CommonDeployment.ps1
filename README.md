# CommonDeployment.ps1
PowerShell to simplify SharePoint deployment operations

Documentation commin soon


Install/reinstall example:

.\commondeployment.ps1 -Url:"http://site" -Solution:"mysolution.wsp" -RestartTimer

All solutions in current dirtectory:
.\commondeployment.ps1 -Url:"http://site"


All solutions in current dirtectory for default web app:
.\commondeployment.ps1 

Import defined functions:

. .\commondeployment.ps1 -Import
