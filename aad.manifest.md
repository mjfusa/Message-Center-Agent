# Microsoft Entra App Registration Manifest

This file defines the configuration for the Microsoft Entra (Azure AD) app registration that is automatically created during provisioning.

## Configuration Details

### Basic Information
- **Display Name**: MessageCenterAgent-reg
- **Sign-in Audience**: AzureADMyOrg (single tenant)

### OAuth2 Permissions
The app defines a custom `access_as_user` delegated permission scope that allows Teams to access the Message Center Agent API on behalf of the signed-in user.

### Required Resource Access
The app requires the following Microsoft Graph API permission:

- **Permission**: ServiceMessage.Read.All (Delegated)
  - **ID**: f28b68df-6165-41f5-a6c1-213b2a43fc61
  - **Resource App ID**: 00000003-0000-0000-c000-000000000000 (Microsoft Graph)
  - **Type**: Scope (Delegated permission)
  - **Description**: Allows the app to read service health and communications messages for the tenant on behalf of the signed-in user

### Redirect URIs
- https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect

## Environment Variables

The following environment variables are automatically populated during provisioning:

- `AAD_APP_CLIENT_ID`: The Application (client) ID
- `SECRET_AAD_APP_CLIENT_SECRET`: The client secret
- `AAD_APP_OBJECT_ID`: The object ID of the app registration
- `AAD_APP_TENANT_ID`: The tenant ID
- `AAD_APP_OAUTH_AUTHORITY`: The OAuth authority URL
- `AAD_APP_OAUTH_AUTHORITY_HOST`: The OAuth authority host
- `AAD_APP_ACCESS_AS_USER_PERMISSION_ID`: Auto-generated GUID for the access_as_user permission scope

## References
- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [ServiceMessage.Read.All permission](https://learn.microsoft.com/en-us/graph/permissions-reference#servicemessagereadall)
