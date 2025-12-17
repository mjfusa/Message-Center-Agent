$t = (& .\GetMcpAccessToken.ps1).Trim(); & .\GetMessages.ps1 -Top 5 -McpAccessToken $t
