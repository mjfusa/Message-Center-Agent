# get subscription
#az account list
$azure_subscription="9b66a533-8bc7-4ca0-9c70-27ae3afa3377"
# Create service Principal
$sp_output=az ad sp create-for-rbac --name "CopilotAgentDeploy" --role Contributor --scopes /subscriptions/$azure_subscription | ConvertFrom-Json
# Print the service principal ID
$sp_appId=$($sp_output.appId)
Write-Output "Service Principal ID: $sp_output.appId"
# TeamsAppInstallation.ReadWriteForUser.All == 74ef0291-ca83-4d02-8c7e-d2391e6a444f
# TeamsApp.ReadWrite.All == eb6b3d76-ed75-4be6-ac36-158d04c0a555
az ad app permission add --id $sp_appId --api 00000003-0000-0000-c000-000000000000 --api-permissions 74ef0291-ca83-4d02-8c7e-d2391e6a444f=Role
az ad app permission grant --id $sp_appId --api 00000003-0000-0000-c000-000000000000   --scope Role
az ad app permission add --id $sp_appId --api 00000003-0000-0000-c000-000000000000 --api-permissions eb6b3d76-ed75-4be6-ac36-158d04c0a555=Role
az ad app permission grant --id $sp_appId --api 00000003-0000-0000-c000-000000000000   --scope Role

# read permissions
$sp_output
