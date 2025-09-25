#Requires -Version 5.0
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ApplianceUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiKey,
    
    [Parameter(Mandatory=$false)]
    [string]$SessionId,
    
    [Parameter(Mandatory=$false)]
    [string]$Message,
    
    [Parameter(Mandatory=$false)]
    [string]$ApiVersion = "v8-preview",
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableLogging,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\LECustomEvents.log",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 2,
    
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$FromUWC
)

# Script metadata
$ScriptVersion = "1.4.0-UWC"
$ErrorActionPreference = 'Continue'

# Check if we're being called from UWC (stdin) or directly (parameters)
if ($FromUWC -or (!$PSBoundParameters.ContainsKey('Message') -and !$PSBoundParameters.ContainsKey('ApplianceUrl'))) {
    # Read from stdin when called from UWC
    $Message = Read-Host "Enter message"
    $SessionId = Read-Host "Enter sessionId" 
    $ApiKey = Read-Host "Enter apiKey"
    $ApplianceUrl = Read-Host "Enter applianceUrl"
    $ApiVersion = Read-Host "Enter apiVersion"
    $scriptPath = Read-Host "Enter scriptPath" # Not used in combined version
    
    $EnableLogging = $true
    $LogPath = "C:\temp\LECustomEvents.log"
}

# Validate required parameters
if (!$ApplianceUrl -or !$ApiKey -or !$SessionId -or !$Message) {
    Write-Host "###ERROR:Missing required parameters"
    exit 1
}

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Output to console with color coding
    switch ($Level) {
        'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
        'WARNING' { Write-Host $logEntry -ForegroundColor Yellow }
        'DEBUG'   { Write-Host $logEntry -ForegroundColor Gray }
        default   { Write-Host $logEntry -ForegroundColor White }
    }
    
    # Also write to file if logging enabled
    if ($EnableLogging) {
        try {
            Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8
        } catch {
            Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        }
    }
}

# Initialize logging
if ($EnableLogging) {
    try {
        $logDir = Split-Path $LogPath -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        Add-Content -Path $LogPath -Value "`n========================================" -Encoding UTF8
    } catch {
        Write-Host "Warning: Could not initialize log file: $_" -ForegroundColor Yellow
        $EnableLogging = $false
    }
}

Write-Log "Send-LECustomEvent-UWC v$ScriptVersion - Starting execution" -Level INFO
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" -Level DEBUG
Write-Log "Called from UWC: $($FromUWC -or (!$PSBoundParameters.ContainsKey('Message')))" -Level DEBUG

try {
    # Build the full API URL
    $baseUrl = $ApplianceUrl.TrimEnd('/')
    if ($baseUrl -notmatch '^https?://') {
        throw "Invalid URL format. Must start with http:// or https://"
    }
    
    $fullUrl = "$baseUrl/publicApi/$ApiVersion/user-sessions/$SessionId/events"
    Write-Log "Target endpoint: $fullUrl" -Level INFO
    
    # Prepare request
    $headers = @{
        "Authorization" = "Bearer $ApiKey"
        "Content-Type" = "application/json"
        "Accept" = "application/json"
    }
    
    $body = @{
        description = $Message
    } | ConvertTo-Json -Compress
    
    Write-Log "Message: $Message" -Level DEBUG
    Write-Log "Request body: $body" -Level DEBUG
    
    # Execute with retry logic
    $attempt = 0
    $success = $false
    $lastError = $null
    
    while ($attempt -le $MaxRetries -and -not $success) {
        if ($attempt -gt 0) {
            $waitTime = [Math]::Pow(2, $attempt - 1)
            Write-Log "Retry $attempt/$MaxRetries after $waitTime seconds..." -Level WARNING
            Start-Sleep -Seconds $waitTime
        }
        
        $attempt++
        
        try {
            Write-Log "Sending request (attempt $attempt)..." -Level INFO
            
            $response = Invoke-RestMethod -Uri $fullUrl `
                                         -Method Post `
                                         -Headers $headers `
                                         -Body $body `
                                         -TimeoutSec $TimeoutSeconds `
                                         -ErrorAction Stop
            
            $success = $true
            Write-Log "SUCCESS: Custom event posted to session $SessionId" -Level INFO
            
            if ($response) {
                Write-Log "Response: $($response | ConvertTo-Json -Compress)" -Level DEBUG
            }
            
            # If called from UWC, output success marker
            if ($FromUWC -or (!$PSBoundParameters.ContainsKey('Message') -and !$PSBoundParameters.ContainsKey('ApplianceUrl'))) {
                Write-Host "###SUCCESS"
            }
            
        } catch {
            $lastError = $_
            $errorMessage = $_.Exception.Message
            
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                
                if ($statusCode -eq 401) {
                    Write-Log "ERROR: Authentication failed (401) - Check API key" -Level ERROR
                    break
                } elseif ($statusCode -eq 404) {
                    Write-Log "ERROR: Session not found (404) - Session ID: $SessionId" -Level ERROR
                    break
                } elseif ($statusCode -eq 400) {
                    Write-Log "ERROR: Bad request (400) - $errorMessage" -Level ERROR
                    break
                } elseif ($statusCode -eq 429) {
                    Write-Log "WARNING: Rate limited (429) - Will retry" -Level WARNING
                } else {
                    Write-Log "ERROR: HTTP $statusCode - $errorMessage" -Level ERROR
                }
            } else {
                Write-Log "ERROR: $errorMessage" -Level ERROR
            }
        }
    }
    
    if (-not $success) {
        if ($FromUWC -or (!$PSBoundParameters.ContainsKey('Message') -and !$PSBoundParameters.ContainsKey('ApplianceUrl'))) {
            Write-Host "###FAILED"
        }
        throw $lastError
    }
    
    exit 0
    
} catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level ERROR
    
    if ($_.Exception.InnerException) {
        Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level ERROR
    }
    
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level DEBUG
    
    if ($FromUWC -or (!$PSBoundParameters.ContainsKey('Message') -and !$PSBoundParameters.ContainsKey('ApplianceUrl'))) {
        Write-Host "###ERROR:$($_.Exception.Message)"
    }
    
    exit 1
    
} finally {
    Write-Log "Script execution completed" -Level INFO
}