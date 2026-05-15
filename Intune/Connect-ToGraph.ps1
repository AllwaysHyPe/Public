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
        [Parameter(Mandatory = $false)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [string]$AppId,
        [Parameter(Mandatory = $false)]
        [string]$OidcToken,
        [Parameter(Mandatory = $false)]
        [string]$Scopes
    )

    process {
        Import-Module Microsoft.Graph.Authentication

        # Check for OIDC authentication (GitHub Actions)
        if ($OidcToken -and $AppId -and $TenantId) {
            Write-Log -Message "Authenticating with OIDC for GitHub Actions..." -Severity Start

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

                $secureAccessToken = ConvertTo-SecureString $accessToken -AsPlainText -Force

                Connect-MgGraph -AccessToken $secureAccessToken

                Write-Log -Message "Connected to Microsoft Graph using OIDC authentication" -Severity End
                return $true
            } catch {
                Write-Log -Message "OIDC authentication failed" -Severity Error
                throw
            }
            # Check for environment variables (set by GitHub Actions)
        } elseif ($env:OIDC_TOKEN -and $env:AZURE_CLIENT_ID -and $env:AZURE_TENANT_ID) {
            Write-Log -Message "Using OIDC authentication from environment variables" -Severity Info
            return Connect-ToGraph -TenantId $env:AZURE_TENANT_ID -AppId $env:AZURE_CLIENT_ID -OidcToken $env:OIDC_TOKEN

            # Fall back to interactive authentication
        } else {
            Write-Log -Message "Using interactive authentication" -Severity Info
            $version = (Get-Module Microsoft.Graph.Authentication | Select-Object -ExpandProperty Version).Major

            if ($version -ne 2) {
                Select-MgProfile -Name Beta
            }

            $graph = Connect-MgGraph -Scopes $Scopes
            Write-Log -Message "Connected to Intune tenant $($graph.TenantId)" -Severity End
        }
    }
}