<#
.SYNOPSIS
This script creates Azure Subscriptions under an Enterprise Agreement according to Input Values.

.DESCRIPTION
You need a user that you can enable as account owner and be used as the identity for this Runbook. Store Credentials in KeyVault and use it to create Subscribtions.

.PARAMETER purpose
A name declarating the project or generally purpose the subsciption is used for.

.PARAMETER environment
An environment identifier, as in "prod", "dev", "stage".

.PARAMETER email
an Email Address that is used to identify the User that is going to be subscription owner.

.EXAMPLE
.\Create-AzureSubscription.ps1 -purpose webshop -environment sbx -email owner.email@your-company.com
Subscription: sub-webshop-sbx

.NOTES
v1.0 - Script released
Developed by tom.treffke@outlook.com

#>




param(
[parameter(Mandatory=$true)]
[string]$purpose = "defaultpurpose",
[parameter(Mandatory=$true)]
[string]$environment = "stage",
[parameter(Mandatory=$true)]
[string]$email = "owner.email@your-company.com",
[Parameter(Mandatory = $false)]
[String]$TenantId = 'YOUR_TENANT_ID',
[Parameter(Mandatory = $false)]
[String]$KeyVaultName = 'THE_KEYVAULT_KEEPING_TECHNICAL_USER_CREDENTIAL',
[Parameter(Mandatory = $false)]
[String]$TechnicalUserName = 'technical.user001@your-company.com'
)

#region functions
function Get-Logtime {
<#
.SYNOPSIS
Returns current logtime
.DESCRIPTION
Returns the current date in a given format.
.EXAMPLE
Get-Logtime
#>
    $Timeformat = "yyyy-MM-dd HH:mm:ss.fff"
    return $(Get-Date -Format $Timeformat)
}


Function Set-SubscriptionName{
param(
[string]$purpose, 
[string]$env
)
    #quality-check purpose and env variable

    if ($purpose -match '[a-zA-Z0-9]' -and $env -match '[a-zA-Z0-9]') {
        #standardize the environment parameter to 3-digit length string.
        if ($env -eq 'prod' -or $env -eq 'production') {
            $env = 'prod'
        }
        elseif ($env -eq 'stage' -or $env -eq 'staging') {
            $env = 'stg'
        }
        elseif ($env -eq 'dev' -or $env -eq 'development') {
            $env = 'dev'
        }
        $subscriptionname = "got-$($env)-$($purpose)"

        return $subscriptionname

    }
    else {
        Write-Output -InputObject "Exiting because either purpose or environment parameter contain special characters other than A-Z, a-z, 0-9.";
        Write-Output -InputObject "purpose: $purpose Environment: $environment"
        exit 2;
    }
}

#endregion



 try {
        Write-Output -InputObject "[$(Get-Logtime)] Importing Modules"
        Import-Module -Name Az.Billing, Az.Subscription, Az.KeyVault, Az.Resources
    } catch {
        $ErrorMsg = "[$(Get-Logtime)] ERROR while importing modules: $($Error[0].Exception)!"
        Write-Error -Message $ErrorMsg
    }


#region initialize Azure Automation connection
    try {
        Write-Output -InputObject "[$(Get-Logtime)] Getting automation connection for execution."
        $connection = Get-AutomationConnection -Name AzureRunAsConnection
    } catch {
        $ErrorMsg = "[$(Get-Logtime)] ERROR retrieving automation connection: $($Error[0].Exception)!"
        Write-Error -Message $ErrorMsg
    }

 try {
        Write-Output -InputObject "[$(Get-Logtime)] Connecting to Microsoft Azure..."
        $null = Connect-AzAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    } catch {
        $ErrorMsg = "[$(Get-Logtime)] ERROR while connecting to Azure: $($Error[0].Exception)!"
        Write-Error -Message $ErrorMsg
    }
#endregion

#region retrieve connection credentials
try{
    Write-Output -InputObject "[$(Get-Logtime)] Retrieving Technical User credentials from Azure KeyVault"
    Write-Output -InputObject "Key: $($TechnicalUserName.Split('@')[0])"
    $SecurePassword = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $TechnicalUserName.Split('@')[0]
    $Credential = New-Object System.Management.Automation.PSCredential($TechnicalUserName, $SecurePassword.SecretValue)
} catch {
    $ErrorMsg = "[$(Get-Logtime)] ERROR while generating connection credential: $($Error[0].Exception)!" 
    Write-Error -Message $ErrorMsg
}
#endregion

#region Login with Technical User
try{
    Write-Output -InputObject "[$(Get-Logtime)] Connecting to Azure AD with user: $($Credential.UserName)"
    $null = Connect-AzAccount -Credential $Credential #-TenantId $TenantId     
} catch {
    $ErrorMsg = "[$(Get-Logtime)] ERROR while logging in with Technical User: $($Error[0].Exception)!" 
    Write-Error -Message $ErrorMsg
}
#endregion

#region getting the Enterprise Enrollment Account
try {
    Write-Output -InputObject "[$(Get-Logtime)] Getting Azure Enrollment Account"
    # this is tricky: the object id is the OID of the user, that is owning the enrollment account.
    $EnrollmentAccountObjectId = (Get-AzEnrollmentAccount)[0].ObjectId
    Write-Output -InputObject "[$(Get-Logtime)] $EnrollmentAccountObjectId"
    }
    catch {
        $ErrorMsg = "[$(Get-Logtime)] ERROR while getting Enrollment Account $($Error[0].Exception)!"
        Write-Error -Message $ErrorMsg
    }
#endregion


try {
    Write-Output -InputObject "[$(Get-Logtime)] Starting to create Azure Subscription"
    $SubscriptionName = Get-SubscriptionName -purpose $purpose -env $environment
    Write-Output -InputObject "Generated SubName: $($SubscriptionName)"
    $CreatedSub = New-AzSubscription -OfferType "MS-AZR-0017P" -Name $SubscriptionName -EnrollmentAccountObjectId $EnrollmentAccountObjectId -OwnerSignInName $email
     
    } 
    catch {
        $ErrorMsg = "[$(Get-Logtime)] ERROR while creating Subscription: $($Error[0].Exception)!"
        Write-Error -Message $ErrorMsg
    }


