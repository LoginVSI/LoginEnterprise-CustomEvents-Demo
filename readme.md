# Login Enterprise Custom Events Demo

A practical implementation of the Custom Events feature for Login Enterprise v6.2+ Connectors and Launchers, demonstrating how to send custom events from connector scripts to the Login Enterprise appliance for enhanced visibility and troubleshooting.

## Table of Contents
- [Introduction](#introduction)
- [Repository Structure](#repository-structure)
- [StoreFront UWC Implementation](#storefront-uwc-implementation)
- [Generic PowerShell Event Handler](#generic-powershell-event-handler)
- [Prerequisites](#prerequisites)
- [Usage](#usage)

## Introduction

### What are Custom Events for Launchers and Connectors?

Custom Events is a feature introduced in Login Enterprise v6.2 that allows connectors to emit user-defined messages directly to the Login Enterprise appliance. These events appear alongside standard Launcher events in the Events feed, providing real-time visibility into custom connector behavior without relying on external logs.

### Key Benefits

- **Enhanced Visibility**: Track key steps, decisions, and checkpoints during test execution
- **Faster Troubleshooting**: Immediately identify where failures occur in custom connector logic
- **Centralized Logging**: All events appear in the Login Enterprise UI alongside standard events
- **Session Awareness**: Events are automatically associated with the correct test session
- **Reliability**: Events use the same retry and buffering logic as standard events
- **No Tool Switching**: Debug custom connectors without diving into launcher logs or external tools

### What This Repository Demonstrates

This repository showcases the Custom Events feature using a modified [Universal Web Connector (UWC)](https://docs.loginvsi.com/login-enterprise/6.2/configuring-the-universal-web-connector) StoreFront connector as a practical example. While UWC itself is not the focus, it serves as an ideal demonstration vehicle for how to integrate custom events into any connector workflow.

## Repository Structure

```
LoginEnterprise-CustomEvents-Demo/
│
├── Send-LECustomEvent.ps1              # Generic standalone event handler
│
└── StorefrontUWC_CustomEvents/         # Modified UWC StoreFront connector example
    ├── click-resource.js                # Modified connector script with event emission
    ├── clientcookies.json              # Cookie configuration for StoreFront
    ├── connector.json                  # UWC connector configuration
    └── Send-LECustomEvent-UWC.ps1     # UWC-specific event handler
```

## StoreFront UWC Implementation

### What Was Modified

The standard StoreFront UWC connector was enhanced to demonstrate Custom Events integration. Here's what changed:

#### 1. JavaScript Modifications (`click-resource.js`)

**Added SendCustomEvent Function**: A wrapper function that handles event emission to the Login Enterprise API. This function is designed to be portable and can be easily copied into other UWC connector scripts with minimal modification:

```javascript
async function SendCustomEvent(message) {
    try {
        uwc.log.info(`Sending custom event: ${message}`);
        
        const params = [
            message,
            '${sessionid}',
            '${apikey}',
            '${applianceurl}',
            'v8-preview',
            'not-used'
        ];
        
        const result = await chrome.webview.hostObjects.dotnet.RunPowerShellScript('Send-LECustomEvent-UWC.ps1', params);
        // Process result...
    } catch (err) {
        uwc.log.error(`Failed to send custom event: ${err.message}`);
    }
}
```

Note: This function can be dropped into any UWC JavaScript connector script. Simply copy the function and the accompanying PowerShell script, then call `SendCustomEvent('Your message')` at any point in your connector logic.

**Strategic Event Placement**: Events are emitted at critical points:
- Connector initialization
- Element detection (waiting/found)
- User input actions (username/password fields)
- Login button clicks
- Resource selection attempts
- Success/failure states

Example integration:
```javascript
await SendCustomEvent(`Starting connection process for user: ${username}, resource: ${resource}`);
await setInputValueById('username', username);
await SendCustomEvent('Clicking login button');
loginBtn.click();
```

#### 2. Connector Configuration (`connector.json`)

Added required parameters for Custom Events:

```json
{
  "Key": "--sessionid",
  "IsRequired": true,
  "IsHidden": false
},
{
  "Key": "--apikey",
  "IsRequired": true,
  "IsHidden": true
},
{
  "Key": "--applianceurl",
  "IsRequired": true,
  "IsHidden": false
}
```

These parameters enable:
- `--sessionid`: Associates events with the correct test session
- `--apikey`: Authenticates with the Login Enterprise API
- `--applianceurl`: Specifies the target appliance endpoint

#### 3. PowerShell Event Handler (`Send-LECustomEvent-UWC.ps1`)

This script bridges the gap between UWC's stdin-based parameter passing and the Login Enterprise API:

**Key Features:**
- Dual-mode operation: Accepts parameters via stdin (from UWC) or command-line arguments
- Automatic parameter detection based on invocation method
- Full retry logic with exponential backoff
- Comprehensive error handling and logging
- Returns standardized success/failure markers to JavaScript

**How It Works:**
1. JavaScript calls the PowerShell script via `RunPowerShellScript()`
2. PowerShell reads parameters from stdin (UWC passes them this way)
3. Constructs and sends HTTP POST to the Login Enterprise API
4. Returns success/failure status to JavaScript
5. JavaScript continues execution regardless of event status

### Login Enterprise Configuration

Below is an example connection command line for your test configuration. Your actual implementation will vary based on your environment:

```bash
"C:\Program Files\Login VSI\Universal Web Connector\UniversalWebConnector.exe" --url "{host}" --scripts-path "C:\path\to\StorefrontUWC_CustomEvents" --username "{domain}\\{username}" --password "{password}" --resource "{resource}" --sessionid "{sessionId}" --apikey "{securecustom1}" --applianceurl "https://your-appliance.domain.com" --timeout 300
```

**Parameter Notes:**
- `{sessionId}`: Automatically provided by Login Enterprise v6.2+ when the test runs
- `{securecustom1}`: In this example, we're using the [Secured Custom Fields](https://docs.loginvsi.com/login-enterprise/6.3/managing-virtual-user-accounts#id-(6.3)ManagingVirtualUserAccounts-secured-custom-fields-optionalSecuredCustomFields(Optional)) feature to store the API key. This allows the API token to be passed as a variable through the connection command line.
- Replace paths and URLs with your environment specifics
--First, generate an API token following the Adding a System [Access Token guide](https://docs.loginvsi.com/login-enterprise/6.2/using-the-public-api#id-(6.2)UsingthePublicAPI-adding-a-system-access-tokenAddingaSystemAccessToken)
--Then store it in Secure Field 1 of your test account configuration
--The `{securecustom1}` variable will be replaced with your API key at runtime
- `--applianceurl`: Replace with your actual Login Enterprise appliance URL
- `--scripts-path`: Update to point to your actual script location

## Generic PowerShell Event Handler

### Purpose

`Send-LECustomEvent.ps1` is a standalone PowerShell script that can be used with ANY connector (not just UWC) to send custom events to Login Enterprise. It provides a complete, production-ready solution for event emission.

### Features

- Works with any connector type (Custom, Desktop, or standard connectors)
- Command-line parameter interface
- Comprehensive error handling and retry logic
- Detailed logging capabilities
- API version flexibility
- Rate limiting support

### How It Works

The script accepts standard PowerShell parameters and makes direct REST API calls to the Login Enterprise appliance to post events. It handles authentication, retries, and error conditions automatically.

### Standalone Usage

The standalone script can be integrated into ANY connector type running on Login Enterprise Launchers. The critical requirement is capturing the `{sessionId}` parameter that Login Enterprise v6.2+ passes to connectors at runtime. Once your connector captures this session ID, it can invoke the PowerShell script to send events.

**How to integrate with your connector:**
1. Ensure your connector captures the `{sessionId}` parameter passed by Login Enterprise
2. Pass this session ID to the PowerShell script along with your message
3. The script handles the API communication and event posting

Run directly from PowerShell or integrate into any connector script:

```powershell
.\Send-LECustomEvent.ps1 `
    -ApplianceUrl "https://your-appliance.domain.com" `
    -ApiKey "your-api-key-here" `
    -SessionId "session-id-from-launcher" `
    -Message "Your custom event message" `
    -EnableLogging `
    -LogPath "C:\temp\CustomEvents.log"
```

**Parameters:**
- `-ApplianceUrl`: Your Login Enterprise appliance URL
- `-ApiKey`: API key with appropriate permissions ([see documentation](https://docs.loginvsi.com/login-enterprise/6.2/configuring-connectors-and-connections#id-(6.2)ConfiguringConnectorsandConnections-custom-events-for-connectors-and-launchersCustomEventsforConnectorsandLaunchers))
- `-SessionId`: The test session ID (passed via `{sessionId}` in connector configuration)
- `-Message`: Your event message (max 4096 characters)
- `-ApiVersion`: API version (default: "v8-preview")
- `-EnableLogging`: Enable file logging
- `-LogPath`: Log file location
- `-MaxRetries`: Number of retry attempts (default: 2)
- `-TimeoutSeconds`: API call timeout (default: 10)

### Integration Examples

**In a batch file:**
```batch
powershell.exe -ExecutionPolicy Bypass -File "Send-LECustomEvent.ps1" -ApplianceUrl "%APPLIANCE_URL%" -ApiKey "%API_KEY%" -SessionId "%SESSION_ID%" -Message "Batch script checkpoint reached"
```

**In another PowerShell script:**
```powershell
& ".\Send-LECustomEvent.ps1" -ApplianceUrl $applianceUrl -ApiKey $apiKey -SessionId $sessionId -Message "Custom connector stage: Authentication completed"
```

### Capturing Session ID in Your Connector

For the standalone script to work with your custom connector, you must capture the session ID that Login Enterprise provides:

**In a Custom Connector command line:**
`your-connector.exe --param1 value1 --sessionid {sessionId}`

The `{sessionId}` placeholder is replaced by Login Enterprise at runtime. Your connector must:
1. Accept this parameter
2. Pass it to `Send-LECustomEvent.ps1` when posting events

**Example integration pattern:**
```powershell
# Inside your connector script
param($sessionId)  # Capture the session ID

# Later when you want to send an event
& ".\Send-LECustomEvent.ps1" `
    -SessionId $sessionId `
    -Message "Connector reached checkpoint X" `
    # ... other parameters
```

Without the session ID, events cannot be associated with the correct test run in the Login Enterprise UI.

## Prerequisites

- Login Enterprise v6.2 or later
- Configuration-level API token with appropriate permissions
- For UWC example: Universal Web Connector installed
- PowerShell 5.0 or later

## Usage

### Quick Start

1. Clone this repository
2. Copy the appropriate scripts to your environment
3. Configure your API token in Login Enterprise
4. Update the connection command line with your parameters
5. Run a test and observe custom events in the Events tab

### Best Practices

- Keep event messages concise and descriptive
- Use consistent message prefixes for easy filtering
- Emit events at logical checkpoints
- Include relevant context (user, resource, action)
- Don't over-emit - focus on key decision points

### Troubleshooting

Check these locations for diagnostic information:
- `C:\temp\LECustomEvents.log` - Event handler log
- UWC Console Window - Real-time JavaScript execution
- Login Enterprise UI Events Tab - Successfully posted events
- Launcher Logs - Process-level errors

## Learn More

- [Custom Events Documentation](https://docs.loginvsi.com/login-enterprise/6.2/configuring-connectors-and-connections#id-(6.2)ConfiguringConnectorsandConnections-custom-events-for-connectors-and-launchersCustomEventsforConnectorsandLaunchers)
- [Universal Web Connector Guide](https://docs.loginvsi.com/login-enterprise/6.2/configuring-the-universal-web-connector)

## License

This project is provided as-is for demonstration purposes.