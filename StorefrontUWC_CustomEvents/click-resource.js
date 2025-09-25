//Path=/*Web?

/**
 * Send a custom event to Login Enterprise
 * @param {string} message - The event message to send
 */
async function SendCustomEvent(message) {
    try {
        uwc.log.info(`Sending custom event: ${message}`);
        
        const params = [
            message,
            '${sessionid}',
            '${apikey}',
            '${applianceurl}',
            'v8-preview',
            'not-used'  // Placeholder since combined script doesn't need this
        ];
        
        const result = await chrome.webview.hostObjects.dotnet.RunPowerShellScript('Send-LECustomEvent-UWC.ps1', params);
        const resultLines = JSON.parse(result);
        
        if (resultLines && resultLines[0]) {
            if (resultLines[0] === 'SUCCESS') {
                uwc.log.info(`Custom event sent successfully: ${message}`);
            } else {
                uwc.log.warning(`Custom event send result: ${resultLines[0]}`);
            }
        }
    } catch (err) {
        uwc.log.error(`Failed to send custom event: ${err.message}`);
        // Continue execution even if event sending fails
    }
}

// Rest of your existing click-resource.js code remains the same...

/**
 * Delay execution for a specified number of milliseconds.
 * @param {number} ms
 */
function wait(ms) {
    uwc.log.info(`Waiting for ${ms} milliseconds...`);
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Wait for an element specified by a CSS selector to be available and interactive.
 * @param {string} selector
 * @param {number} timeoutMs
 * @param {number} intervalMs
 */
async function waitForElement(selector, timeoutMs = 5000, intervalMs = 100) {
    if (!timeoutMs || timeoutMs <= 0) {
        timeoutMs = 30000;
    }

    uwc.log.info(`waitForElement: checking for selector "${selector}" (timeout ${timeoutMs}ms)`);
    await SendCustomEvent(`Waiting for element: ${selector}`);

    const start = Date.now();
    return new Promise((resolve, reject) => {
        const check = () => {
            const element = document.querySelector(selector);

            if (element) {
                try {
                    const style = window.getComputedStyle(element);
                    const isVisible = style && style.visibility !== 'hidden' && style.display !== 'none' && element.offsetParent !== null;
                    const isEnabled = !element.disabled;

                    if (isVisible && isEnabled) {
                        SendCustomEvent(`Found element: ${selector}`);
                        return resolve(element);
                    }
                } catch (err) {
                    // Continue trying until timeout
                }
            }

            if (Date.now() - start > timeoutMs) {
                const errorMsg = `Timeout: Element "${selector}" not ready within ${timeoutMs}ms`;
                uwc.log.error(`waitForElement: ${errorMsg}`);
                SendCustomEvent(`ERROR: ${errorMsg}`);
                return reject(new Error(errorMsg));
            }

            setTimeout(check, intervalMs);
        };

        check();
    });
}

/**
 * Set the value of an input element by its HTML ID.
 * @param {string} id
 * @param {string} value
 */
async function setInputValueById(id, value) {
    uwc.log.info(`Setting value for input with id: ${id}`);
    await SendCustomEvent(`Setting input field: ${id}`);
    
    try {
        const input = await waitForElement(`#${id}`);
        if (!input) {
            const errorMsg = `Input with id "${id}" not found`;
            uwc.log.error(errorMsg);
            await SendCustomEvent(`ERROR: ${errorMsg}`);
            chrome.webview.hostObjects.dotnet.ExitWithError(errorMsg);
            return;
        }

        input.focus();
        input.click();
        input.value = value;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        
        uwc.log.info(`Set value on element (id='${id}', name='${input.name || ''}', type='${input.type || ''}')`);
        await SendCustomEvent(`Input field ${id} populated successfully`);
    } catch (err) {
        const errorMsg = `Error setting input #${id} - ${err}`;
        uwc.log.error(errorMsg);
        await SendCustomEvent(`ERROR: ${errorMsg}`);
        chrome.webview.hostObjects.dotnet.ExitWithError(errorMsg);
    }
}

/**
 * Try multiple strategies to find and click the resource.
 * Returns true if clicked, false if not.
 */
async function clickResourceByName(resourceName) {
    uwc.log.info(`clickResourceByName: trying to click resource: "${resourceName}"`);
    await SendCustomEvent(`Searching for resource: ${resourceName}`);

    const needle = (resourceName || '').trim().toLowerCase();

    // Strategy 1: find image with alt containing resource name
    const imgs = Array.from(document.querySelectorAll('img.storeapp-icon'));
    for (const img of imgs) {
        if (img.alt && img.alt.toLowerCase().includes(needle)) {
            uwc.log.info(`Found resource via img.alt: "${img.alt}" – clicking`);
            await SendCustomEvent(`Found resource via image alt text: ${img.alt}`);
            img.scrollIntoView({ behavior: 'auto', block: 'center' });

            const rect = img.getBoundingClientRect();
            const evtInit = { bubbles: true, cancelable: true, view: window, clientX: rect.left + 5, clientY: rect.top + 5 };
            img.dispatchEvent(new MouseEvent('mouseover', evtInit));
            img.dispatchEvent(new MouseEvent('mousedown', evtInit));
            img.dispatchEvent(new MouseEvent('mouseup', evtInit));
            img.dispatchEvent(new MouseEvent('click', evtInit));
            await SendCustomEvent(`Clicked resource: ${resourceName}`);
            return true;
        }
    }

    // Strategy 2: find any clickable element whose visible text contains the resource name
    const textCand = Array.from(document.querySelectorAll('a, button, span, div'));
    for (const el of textCand) {
        try {
            const text = (el.innerText || el.textContent || '').trim().toLowerCase();
            if (text && text.includes(needle)) {
                const style = window.getComputedStyle(el);
                if (style && style.visibility !== 'hidden' && style.display !== 'none') {
                    uwc.log.info(`Found resource via visible text: "${(el.innerText||el.textContent).trim()}" – clicking`);
                    await SendCustomEvent(`Found resource via text: ${(el.innerText||el.textContent).trim()}`);
                    el.scrollIntoView({ behavior: 'auto', block: 'center' });
                    el.click();
                    await SendCustomEvent(`Clicked resource: ${resourceName}`);
                    return true;
                }
            }
        } catch (err) {
            // Continue
        }
    }

    // Strategy 3: aria-label, title, data-* attributes
    const attrCandidates = Array.from(document.querySelectorAll('[aria-label], [title], [data-title], [data-resource]'));
    for (const el of attrCandidates) {
        const attrs = [
            el.getAttribute('aria-label'),
            el.getAttribute('title'),
            el.getAttribute('data-title'),
            el.getAttribute('data-resource')
        ].filter(Boolean).map(s => s.toLowerCase());
        for (const a of attrs) {
            if (a.includes(needle)) {
                uwc.log.info(`Found resource via attribute match "${a}" – clicking`);
                await SendCustomEvent(`Found resource via attribute: ${a}`);
                el.scrollIntoView({ behavior: 'auto', block: 'center' });
                el.click();
                await SendCustomEvent(`Clicked resource: ${resourceName}`);
                return true;
            }
        }
    }

    uwc.log.warn('clickResourceByName: resource not found by image/text/attributes');
    await SendCustomEvent(`WARNING: Resource not found by standard methods: ${resourceName}`);
    return false;
}

/**
 * Login to the Citrix StoreFront and connect to the desktop specified by resource.
 * @param {string} username
 * @param {string} password
 * @param {string} resource
 */
async function ConnectToResource(username, password, resource) {
    uwc.log.info(`ConnectToResource() start – username len=${(username||'').length}, resource='${resource}'`);
    await SendCustomEvent(`Starting connection process for user: ${username}, resource: ${resource}`);
    
    await setInputValueById('username', username);
    await setInputValueById('password', password);

    // Click login
    const loginBtn = await waitForElement('#loginBtn');
    uwc.log.info('Clicking login button via selector "#loginBtn"');
    await SendCustomEvent('Clicking login button');
    loginBtn.click();

    // Wait for desktops tab and click it
    await waitForElement('#desktopsBtn');
    uwc.log.info('Clicking desktops button');
    await SendCustomEvent('Navigating to desktops section');
    (await waitForElement('#desktopsBtn')).click();

    // Give the resources a moment to populate
    await wait(400);
    await SendCustomEvent('Resources loaded, attempting to select resource');

    // Try to click the resource
    const attempted = await clickResourceByName(resource || '');

    if (!attempted) {
        const altTry = resource;
        const fallbackSelector = `a[title*="${altTry}"], button[title*="${altTry}"], div[title*="${altTry}"]`;
        try {
            const fallback = document.querySelector(fallbackSelector);
            if (fallback) {
                uwc.log.info(`Fallback selector ${fallbackSelector} found – clicking`);
                await SendCustomEvent(`Using fallback method to click resource: ${resource}`);
                fallback.scrollIntoView({ behavior: 'auto', block: 'center' });
                fallback.click();
                await SendCustomEvent(`Successfully clicked resource via fallback method`);
            } else {
                const errorMsg = `Resource "${resource}" could not be found or clicked`;
                uwc.log.error('No fallback found to click resource.');
                await SendCustomEvent(`ERROR: ${errorMsg}`);
                chrome.webview.hostObjects.dotnet.ExitWithError(errorMsg);
            }
        } catch (err) {
            const errorMsg = `Resource click failed: ${err.message}`;
            uwc.log.error(`Fallback clicking error: ${err.message}`);
            await SendCustomEvent(`ERROR: ${errorMsg}`);
            chrome.webview.hostObjects.dotnet.ExitWithError(errorMsg);
        }
    } else {
        uwc.log.info('Clicked resource. Expecting download or client launch to begin.');
        await SendCustomEvent('Resource clicked successfully, initiating connection');
    }
}

/**
 * Set necessary cookies to bypass the Citrix StoreFront client detection.
 */
async function SetCookies() {
    await SendCustomEvent('Setting client detection cookies');
    await uwc.cookies.loadCookies('clientcookies.json', true);
    await wait(150);
    await SendCustomEvent('Cookies set, reloading page');
    location.reload();
}

// Main execution section
(async () => {
    const username = '${username}';
    const password = `${password}`;
    const resource = '${resource}';

    uwc.log.info(`Starting UWC script: username len=${(username||'').length}, resource='${resource}'`);
    await SendCustomEvent('StoreFront connector initialized');

    // Check if cookie is present
    if (uwc.cookies.getCookieValue("CtxsClientDetectionDone")) {
        uwc.settings.download.openFileAfterDownload = true;
        uwc.settings.download.exitAfterFileOpen = true;

        await SendCustomEvent('Client detection already complete, proceeding with connection');
        await ConnectToResource(username, password, resource);
        await SendCustomEvent('Connection process completed successfully');
    } else {
        uwc.log.info("Client detection cookie missing -> setting cookies and reloading (one-time).");
        await SetCookies();
    }
})();