# CommonDeployment.ps1
PowerShell to simplify SharePoint deployment operations

By default works with all wsp's in currect folder.

To limit operation by specific solution, use -Solution parameter
PowerShell's auto-suggest file names suported: .\mysolution.wsp

Example of output:

![Image of Yaktocat](https://github.com/gdbd/CommonDeployment.ps1/raw/master/asset/cmdp-watch-update.PNG)


Common scenarios:

All solutions in current dirtectory for default web app:
`.\commondeployment.ps1 `

Watching for solutions changes and update:
`.\commondeployment.ps1 -Watch`

Watching for solution changes then update and restart timer:
`.\commondeployment.ps1 -Watch -Solution .\mysolution.wsp -RestartTimer`

Install/reinstall example:
`.\commondeployment.ps1 -Url:"http://site" -Solution:"mysolution.wsp" -RestartTimer`

Retract and delete:
`.\commondeployment.ps1 -Url:"http://site" -Uninstall`

Re-Deploy all solutions in current dirtectory:
`.\commondeployment.ps1 -Url:"http://site"`

Re-deploy and re-activate all features:
`.\commondeployment.ps1 -Url:"http://site" -Solution:"mysolution.wsp" -Reativate`

Update all solutions in current folder:
`. .\commondeployment.ps1 -Update`

Update solution (through Update-SPSolution):
`. .\commondeployment.ps1 -Update -Solution .\mysolution.wsp`

Update can perform deploy if not deployed yet:
`. .\commondeployment.ps1 -Update -Url "http://site"`

Import defined functions, (see script source for reference):
`. .\commondeployment.ps1 -Import`

and more..
