function Connect-ToGraph {
    <#
    .SYNOPSIS
    Authenticates to the Graph API via OIDC token or interactive authentication.
    .DESCRIPTION
    The Connect-ToGraph cmdlet authenticates to the Graph API using OIDC token from GitHub Actions
    or falls back to interactive authentication for local development.
    .PARAMETER Tenant
    Specifies the tenant (e.g. contoso.onmicrosoft.com) to which to authenticate.
    .PARAMETER AppId
    Specifies the Azure AD app ID (GUID) for the application that will be used to authenticate.
    .PARAMETER OidcToken
    Specifies the OIDC token for GitHub Actions authentication.
    .PARAMETER Scopes
    Specifies the user scopes for interactive authentication.
    .EXAMPLE
    Connect-ToGraph -TenantId $tenantID -AppId $app -OidcToken $token
    #>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory = $false)] [string]$TenantId,
        [Parameter(Mandatory = $false)] [string]$AppId,
        [Parameter(Mandatory = $false)] [string]$OidcToken,
        [Parameter(Mandatory = $false)] [string]$scopes
    )

    process {
        Import-Module Microsoft.Graph.Authentication

        # Check for OIDC authentication (GitHub Actions)
        if ($OidcToken -and $AppId -and $TenantId) {
            Write-Host "Using OIDC authentication for GitHub Actions"

            try {
                # Request Graph access token using OIDC
                $body = @{
                    client_id             = $AppId
                    client_assertion      = $OidcToken
                    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
                    scope                 = "https://graph.microsoft.com/.default"
                    grant_type            = "client_credentials"
                }

                $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"

                $accessToken = $tokenResponse.access_token

                # Convert to SecureString as required by Connect-MgGraph
                $secureAccessToken = ConvertTo-SecureString $accessToken -AsPlainText -Force

                # Connect to Microsoft Graph using the secure access token
                Connect-MgGraph -AccessToken $secureAccessToken

                Write-Host "Connected to Microsoft Graph using OIDC authentication"
                return $true
            } catch {
                Write-Host "OIDC authentication failed: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
        }
        # Check for environment variables (set by GitHub Actions)
        elseif ($env:OIDC_TOKEN -and $env:AZURE_CLIENT_ID -and $env:AZURE_TENANT_ID) {
            Write-Host "Using OIDC authentication from environment variables"
            return Connect-ToGraph -TenantId $env:AZURE_TENANT_ID -AppId $env:AZURE_CLIENT_ID -OidcToken $env:OIDC_TOKEN
        }
        # Fall back to interactive authentication
        else {
            Write-Host "Using interactive authentication"
            $version = (Get-Module microsoft.graph.authentication | Select-Object -ExpandProperty Version).major

            if ($version -eq 2) {
                Write-Host "Version 2 module detected"
            } else {
                Write-Host "Version 1 Module Detected"
                Select-MgProfile -Name Beta
            }
            $graph = Connect-MgGraph -Scopes $scopes
            Write-Host "Connected to Intune tenant $($graph.TenantId)"
        }
    }
}
