targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix used for resource names')
param namePrefix string

@description('Container image for the Roadmap MCP server')
param roadmapImage string

@description('External ingress target port for the app')
param roadmapTargetPort int = 8081

@description('Minimum replicas (0 enables scale-to-zero)')
@minValue(0)
param minReplicas int = 0

@description('Maximum replicas')
@minValue(1)
param maxReplicas int = 5

@description('Log Analytics workspace SKU')
param logAnalyticsSku string = 'PerGB2018'

@description('Enable zone redundancy for the Container Apps managed environment (only supported in some regions)')
param zoneRedundant bool = false

@description('Optional override for the Azure Container Registry login server. If empty, derived from roadmapImage.')
param acrLoginServer string = ''

@description('If true, use system-assigned managed identity to pull from ACR. If false, use ACR admin credentials (bootstrap mode).')
param acrUseManagedIdentity bool = false

var logAnalyticsName = '${namePrefix}-law'
var appInsightsName = '${namePrefix}-appi'
var acaEnvName = '${namePrefix}-cae'
var appName = '${namePrefix}-mcp-roadmap'

var effectiveAcrLoginServer = empty(acrLoginServer) ? split(roadmapImage, '/')[0] : acrLoginServer
var acrName = split(effectiveAcrLoginServer, '.')[0]

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

var acrCredentials = listCredentials(acr.id, acr.apiVersion)
var acrUsername = acrCredentials.username
var acrPassword = acrCredentials.passwords[0].value

var acrRegistrySecrets = acrUseManagedIdentity ? [] : [
  {
    name: 'acr-password'
    value: acrPassword
  }
]

var acrRegistries = acrUseManagedIdentity
  ? [
      {
        server: effectiveAcrLoginServer
        identity: 'System'
      }
    ]
  : [
      {
        server: effectiveAcrLoginServer
        username: acrUsername
        passwordSecretRef: 'acr-password'
      }
    ]

var appFqdnComputed = '${appName}.${managedEnv.outputs.defaultDomain}'

// AVM modules
// Note: versions are pinned. Update as needed.

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.14.2' = {
  name: 'logAnalytics'
  params: {
    name: logAnalyticsName
    location: location
    skuName: logAnalyticsSku
  }
}

module appInsights 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'appInsights'
  params: {
    name: appInsightsName
    location: location
    kind: 'web'
    applicationType: 'web'
    workspaceResourceId: logAnalytics.outputs.resourceId
  }
}

module managedEnv 'br/public:avm/res/app/managed-environment:0.11.3' = {
  name: 'managedEnv'
  dependsOn: [
    logAnalytics
  ]
  params: {
    name: acaEnvName
    location: location
    zoneRedundant: zoneRedundant
    publicNetworkAccess: 'Enabled'
    // Wire logs to Log Analytics
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsName), '2025-07-01').customerId
        sharedKey: listKeys(resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsName), '2025-07-01').primarySharedKey
      }
    }
    // App Insights connection string for Dapr/OpenTelemetry destinations
    appInsightsConnectionString: appInsights.outputs.connectionString
  }
}

module app 'br/public:avm/res/app/container-app:0.19.0' = {
  name: 'roadmapApp'
  params: {
    name: appName
    location: location
    environmentResourceId: managedEnv.outputs.resourceId

    managedIdentities: {
      systemAssigned: true
    }

    ingressExternal: true
    ingressAllowInsecure: false
    ingressTargetPort: roadmapTargetPort
    ingressTransport: 'auto'

    secrets: acrRegistrySecrets
    registries: acrRegistries

    containers: [
      {
        name: 'app'
        image: roadmapImage
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
        env: [
          {
            name: 'NODE_ENV'
            value: 'production'
          }
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: appInsights.outputs.connectionString
          }
          {
            name: 'PORT'
            value: string(roadmapTargetPort)
          }
        ]
      }
    ]

    scaleSettings: {
      minReplicas: minReplicas
      maxReplicas: maxReplicas
      rules: [
        {
          name: 'http'
          http: {
            metadata: {
              concurrentRequests: '50'
            }
          }
        }
      ]
    }
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, appName, acrPullRoleDefinitionId)
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: reference(resourceId('Microsoft.App/containerApps', appName), '2025-02-02-preview', 'full').identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    app
  ]
}

output roadmapFqdn string = appFqdnComputed
output logAnalyticsWorkspaceResourceId string = logAnalytics.outputs.resourceId
output appInsightsConnectionString string = appInsights.outputs.connectionString
