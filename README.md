# CommonDeployment.ps1
PowerShell to simplify SharePoint deployment operations

By default works with all wsp's in currect folder
To limit operation by specific solution, use -Solution parameter
PowerShell's auto-suggest file names suported: .\mysolution.wsp


Common scenarios:

All solutions in current dirtectory for default web app:
`.\commondeployment.ps1 `

Install/reinstall example:

`.\commondeployment.ps1 -Url:"http://site" -Solution:"mysolution.wsp" -RestartTimer`

Install/reinstall example and reactivate all features:

`.\commondeployment.ps1 -Url:"http://site" -Solution:"mysolution.wsp" -Reativate`

Uninstall:
`.\commondeployment.ps1 -Url:"http://site" -Uninstall

All solutions in current dirtectory:
`.\commondeployment.ps1 -Url:"http://site"`

Import defined functions, (see script source for reference):

`. .\commondeployment.ps1 -Import`

Update solution:
`. .\commondeployment.ps1 -Update -Solution .\mysolution.wsp`

Update all wsp's in current folder:
`. .\commondeployment.ps1 -Update`

And, deploy if not deployed:
`. .\commondeployment.ps1 -Update -Url "http://site"`

and more..
