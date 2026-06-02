/* ------------------------------------------------------------------ */
/*  rc_chat NUI                                                        */
/* ------------------------------------------------------------------ */

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rc_chat';

// runtime config (overridden by the 'init' message from the client script)
let CONFIG = {
    fadeTimeout: 10000,
    suggestionLimit: 5,
    maxMessageLength: 144,
    maxHistory: 100,
    placeholder: 'Type a /command...',
    typingText: 'is typing...',
};

const DEFAULT_SETTINGS = {
    offsetX: 0,
    offsetY: 0,
    fontSize: 100,
    fontWeight: 300,
};

let settings = { ...DEFAULT_SETTINGS };

/* --- state --------------------------------------------------------- */

let inputOpen = false;
let suggestions = [];          // { name, help, params, hidden }
let templates = {};            // legacy chat:addTemplate templates
let sentHistory = [];          // previously sent messages (newest first)
let historyIndex = -1;
let historyDraft = '';
let activeSuggestion = -1;
let visibleSuggestions = [];
let fadeTimer = null;
let typingDebounce = null;
let typingPlayers = {};        // id -> { name, timeout }

/* --- elements ------------------------------------------------------ */

const elChatWindow = document.getElementById('chat-window');
const elMessages = document.getElementById('messages');
const elTyping = document.getElementById('typing-indicators');
const elInputPanel = document.getElementById('input-panel');
const elInput = document.getElementById('chat-input');
const elSuggestions = document.getElementById('suggestions');
const elSettingsPanel = document.getElementById('settings-panel');

/* ------------------------------------------------------------------ */
/*  Helpers                                                            */
/* ------------------------------------------------------------------ */

function post(callback, data) {
    fetch(`https://${RESOURCE}/${callback}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

function escapeHtml(text) {
    return String(text)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function hexToRgba(hex, alpha) {
    const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!match) return `rgba(204, 170, 0, ${alpha})`;
    const r = parseInt(match[1], 16);
    const g = parseInt(match[2], 16);
    const b = parseInt(match[3], 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

// lighten a hex color toward white (for the sender name)
function lightenHex(hex, amount) {
    const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!match) return '#E0BE00';
    const mix = (c) => Math.round(parseInt(c, 16) + (255 - parseInt(c, 16)) * amount);
    return `rgb(${mix(match[1])}, ${mix(match[2])}, ${mix(match[3])})`;
}

// convert GTA ^0-^9 color codes into spans (input must already be escaped)
function applyGtaColors(text) {
    if (!/\^[0-9]/.test(text)) return text;
    let result = '';
    let open = false;
    const parts = text.split(/\^([0-9])/);
    for (let i = 0; i < parts.length; i++) {
        if (i % 2 === 0) {
            result += parts[i];
        } else {
            if (open) result += '</span>';
            result += `<span class="gtacolor-${parts[i]}">`;
            open = true;
        }
    }
    if (open) result += '</span>';
    return result;
}

/* ------------------------------------------------------------------ */
/*  Settings                                                           */
/* ------------------------------------------------------------------ */

function applySettings() {
    const root = document.documentElement.style;
    root.setProperty('--chat-offset-x', `${settings.offsetX}vw`);
    root.setProperty('--chat-offset-y', `${settings.offsetY}vh`);
    root.setProperty('--chat-font-size', settings.fontSize / 100);
    root.setProperty('--chat-font-weight', settings.fontWeight);

    // sync panel controls
    document.getElementById('setting-offset-x').value = settings.offsetX;
    document.getElementById('setting-offset-y').value = settings.offsetY;
    document.getElementById('setting-font-size').value = settings.fontSize;
    document.getElementById('setting-font-weight').value = settings.fontWeight;
    document.getElementById('setting-offset-x-value').textContent = settings.offsetX;
    document.getElementById('setting-offset-y-value').textContent = settings.offsetY;
    document.getElementById('setting-font-size-value').textContent = `${settings.fontSize}%`;
}

function bindSettingsControls() {
    const bindRange = (id, key, format) => {
        const input = document.getElementById(id);
        const value = document.getElementById(`${id}-value`);
        input.addEventListener('input', () => {
            settings[key] = Number(input.value);
            value.textContent = format ? format(input.value) : input.value;
            applySettings();
        });
    };

    bindRange('setting-offset-x', 'offsetX');
    bindRange('setting-offset-y', 'offsetY');
    bindRange('setting-font-size', 'fontSize', (v) => `${v}%`);

    document.getElementById('setting-font-weight').addEventListener('change', (e) => {
        settings.fontWeight = Number(e.target.value);
        applySettings();
    });

    document.getElementById('settings-save').addEventListener('click', () => {
        post('saveSettings', { settings });
        closeSettings();
    });

    document.getElementById('settings-reset').addEventListener('click', () => {
        settings = { ...DEFAULT_SETTINGS };
        applySettings();
        post('saveSettings', { settings });
    });

    document.getElementById('settings-button').addEventListener('click', toggleSettings);
}

function toggleSettings() {
    elSettingsPanel.classList.toggle('hidden');
}

function closeSettings() {
    elSettingsPanel.classList.add('hidden');
}

/* ------------------------------------------------------------------ */
/*  Fade                                                               */
/* ------------------------------------------------------------------ */

function wakeFeed() {
    elChatWindow.classList.remove('faded');
    if (fadeTimer) clearTimeout(fadeTimer);
    if (!inputOpen) {
        fadeTimer = setTimeout(() => {
            elChatWindow.classList.add('faded');
        }, CONFIG.fadeTimeout);
    }
}

/* ------------------------------------------------------------------ */
/*  Messages                                                           */
/* ------------------------------------------------------------------ */

function renderTemplateMessage(message) {
    let html = templates[message.template] || message.template;
    const args = message.templateArgs || [];
    args.forEach((arg, i) => {
        html = html.split(`{${i}}`).join(applyGtaColors(escapeHtml(arg)));
    });

    const el = document.createElement('div');
    el.className = 'msg-template';
    el.innerHTML = html;
    return el;
}

function renderBadgeMessage(message) {
    const el = document.createElement('div');
    el.className = 'msg';

    const color = message.color || '#CCAA00';
    el.style.setProperty('--badge', color);
    el.style.setProperty('--badge-dim', hexToRgba(color, 0.16));
    el.style.setProperty('--badge-border', hexToRgba(color, 0.32));
    el.style.setProperty('--badge-text', lightenHex(color, 0.35));

    // text: rc_chat payloads are escaped server-side; legacy ones are flagged
    let text = message.escape ? escapeHtml(message.text || '') : (message.text || '');
    text = applyGtaColors(text);

    let inner = '';
    if (message.badge) {
        inner += `<span class="msg-badge">${escapeHtml(message.badge)}</span>`;
    }
    if (message.id !== undefined && message.id !== null) {
        inner += `<span class="msg-id">${escapeHtml(message.id)}</span>`;
    }
    if (message.name) {
        inner += `<span class="msg-name">${escapeHtml(message.name)}</span>`;
    }
    inner += `<span class="msg-text${message.multiline ? ' multiline' : ''}">${text}</span>`;
    if (message.locationText) {
        inner +=
            '<span class="msg-location">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
            '<path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle>' +
            '</svg>' +
            escapeHtml(message.locationText) +
            '</span>';
    }

    el.innerHTML = inner;
    return el;
}

function addMessage(message) {
    if (!message) return;

    const el = (message.template) ? renderTemplateMessage(message) : renderBadgeMessage(message);
    elMessages.appendChild(el);

    // trim history
    while (elMessages.children.length > CONFIG.maxHistory) {
        elMessages.removeChild(elMessages.firstChild);
    }

    elMessages.scrollTop = elMessages.scrollHeight;
    wakeFeed();
}

function clearMessages() {
    elMessages.innerHTML = '';
}

/* ------------------------------------------------------------------ */
/*  Typing indicators                                                  */
/* ------------------------------------------------------------------ */

function renderTypingIndicators() {
    elTyping.innerHTML = '';
    Object.values(typingPlayers).forEach((entry) => {
        const el = document.createElement('div');
        el.className = 'typing';
        el.innerHTML =
            `<span>${escapeHtml(entry.name)} ${escapeHtml(CONFIG.typingText)}</span>` +
            '<span class="typing-dots"><span></span><span></span><span></span></span>';
        elTyping.appendChild(el);
    });
}

function updateTyping(id, name, typing) {
    if (typingPlayers[id] && typingPlayers[id].timeout) {
        clearTimeout(typingPlayers[id].timeout);
    }

    if (typing) {
        typingPlayers[id] = {
            name,
            // safety: never show a stuck indicator for more than 10s
            timeout: setTimeout(() => {
                delete typingPlayers[id];
                renderTypingIndicators();
            }, 10000),
        };
    } else {
        delete typingPlayers[id];
    }

    renderTypingIndicators();
    if (Object.keys(typingPlayers).length > 0) {
        wakeFeed();
    }
}

/* ------------------------------------------------------------------ */
/*  Suggestions                                                        */
/* ------------------------------------------------------------------ */

function addSuggestion(suggestion) {
    if (!suggestion || !suggestion.name) return;
    // replace if it already exists
    const existing = suggestions.findIndex((s) => s.name === suggestion.name);
    if (existing !== -1) {
        // keep richer entries (with help text) over auto-registered hidden ones
        if (suggestion.hidden && !suggestions[existing].hidden) return;
        suggestions[existing] = suggestion;
    } else {
        suggestions.push(suggestion);
    }
}

function removeSuggestion(name) {
    suggestions = suggestions.filter((s) => s.name !== name);
}

function updateSuggestions() {
    const value = elInput.value;

    if (!value.startsWith('/') || value.includes(' ')) {
        // once a space is typed, show only the matched command's params hint
        const matched = suggestions.find((s) => value.startsWith(s.name + ' '));
        if (matched && matched.params && matched.params.length) {
            visibleSuggestions = [matched];
            renderSuggestions(true);
        } else {
            hideSuggestions();
        }
        return;
    }

    const query = value.toLowerCase();
    visibleSuggestions = suggestions
        .filter((s) => {
            if (!s.name.toLowerCase().startsWith(query)) return false;
            // auto-registered commands (no help text) need at least 2 typed chars
            if (s.hidden && query.length < 3) return false;
            return true;
        })
        .sort((a, b) => {
            // commands with help text first, then alphabetical
            if (!!a.help !== !!b.help) return a.help ? -1 : 1;
            return a.name.localeCompare(b.name);
        })
        .slice(0, CONFIG.suggestionLimit);

    activeSuggestion = -1;
    renderSuggestions(false);
}

function renderSuggestions(paramsOnly) {
    if (visibleSuggestions.length === 0) {
        hideSuggestions();
        return;
    }

    elSuggestions.innerHTML = '';
    visibleSuggestions.forEach((s, index) => {
        const el = document.createElement('div');
        el.className = 'suggestion' + (index === activeSuggestion ? ' active' : '');

        const params = (s.params || [])
            .map((p) => `&lt;${escapeHtml(p.name)}&gt;`)
            .join(' ');

        el.innerHTML =
            `<div><span class="suggestion-name">${escapeHtml(s.name)}</span>` +
            (params ? `<span class="suggestion-params">${params}</span>` : '') +
            '</div>' +
            (s.help ? `<div class="suggestion-help">${escapeHtml(s.help)}</div>` : '');

        if (!paramsOnly) {
            el.addEventListener('mousedown', (e) => {
                e.preventDefault();
                completeSuggestion(index);
            });
        }

        elSuggestions.appendChild(el);
    });

    elSuggestions.classList.remove('hidden');
}

function hideSuggestions() {
    visibleSuggestions = [];
    activeSuggestion = -1;
    elSuggestions.classList.add('hidden');
}

function completeSuggestion(index) {
    const target = visibleSuggestions[index !== undefined ? index : Math.max(activeSuggestion, 0)];
    if (!target) return;
    elInput.value = target.name + ' ';
    elInput.focus();
    updateSuggestions();
}

/* ------------------------------------------------------------------ */
/*  Input                                                              */
/* ------------------------------------------------------------------ */

function openInput() {
    inputOpen = true;
    elInputPanel.classList.remove('hidden');
    elInput.value = '';
    elInput.placeholder = CONFIG.placeholder;
    historyIndex = -1;
    historyDraft = '';
    wakeFeed();
    // focus after the panel is visible
    setTimeout(() => elInput.focus(), 50);
}

function closeInput(canceled, message) {
    inputOpen = false;
    elInputPanel.classList.add('hidden');
    closeSettings();
    hideSuggestions();
    elInput.value = '';
    stopTyping();
    wakeFeed();

    post('chatResult', {
        canceled: canceled === true,
        message: message || '',
    });
}

function sendCurrentMessage() {
    const message = elInput.value.trim();

    if (message === '') {
        closeInput(true);
        return;
    }

    // remember for arrow-up history
    sentHistory.unshift(message);
    if (sentHistory.length > 50) sentHistory.pop();

    closeInput(false, message);
}

let typingActive = false;

function stopTyping() {
    if (typingDebounce) {
        clearTimeout(typingDebounce);
        typingDebounce = null;
    }
    if (typingActive) {
        typingActive = false;
        post('typing', { typing: false });
    }
}

function notifyTyping() {
    // only post the state change, not every keystroke
    if (!typingActive) {
        typingActive = true;
        post('typing', { typing: true });
    }
    if (typingDebounce) clearTimeout(typingDebounce);
    // if no keystroke for 3s, report stopped typing
    typingDebounce = setTimeout(() => stopTyping(), 3000);
}

function bindInput() {
    elInput.addEventListener('input', () => {
        updateSuggestions();
        if (elInput.value.length > 0) {
            notifyTyping();
        }
    });

    elInput.addEventListener('keydown', (e) => {
        switch (e.key) {
            case 'Enter':
                e.preventDefault();
                sendCurrentMessage();
                break;

            case 'Escape':
                e.preventDefault();
                closeInput(true);
                break;

            case 'Tab':
                e.preventDefault();
                if (visibleSuggestions.length > 0) {
                    completeSuggestion();
                }
                break;

            case 'ArrowUp':
                e.preventDefault();
                if (visibleSuggestions.length > 0) {
                    activeSuggestion = activeSuggestion <= 0 ? visibleSuggestions.length - 1 : activeSuggestion - 1;
                    renderSuggestions(false);
                } else if (sentHistory.length > 0) {
                    if (historyIndex === -1) historyDraft = elInput.value;
                    historyIndex = Math.min(historyIndex + 1, sentHistory.length - 1);
                    elInput.value = sentHistory[historyIndex];
                }
                break;

            case 'ArrowDown':
                e.preventDefault();
                if (visibleSuggestions.length > 0) {
                    activeSuggestion = activeSuggestion >= visibleSuggestions.length - 1 ? 0 : activeSuggestion + 1;
                    renderSuggestions(false);
                } else if (historyIndex >= 0) {
                    historyIndex--;
                    elInput.value = historyIndex === -1 ? historyDraft : sentHistory[historyIndex];
                }
                break;
        }
    });

    document.getElementById('send-button').addEventListener('click', sendCurrentMessage);

    // safety net: ESC closes the chat no matter what has focus
    // (e.g. while interacting with the settings panel)
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && inputOpen && document.activeElement !== elInput) {
            e.preventDefault();
            closeInput(true);
        }
    });
}

/* ------------------------------------------------------------------ */
/*  Message handler (from client lua)                                  */
/* ------------------------------------------------------------------ */

window.addEventListener('message', (event) => {
    const data = event.data;

    switch (data.action) {
        case 'init':
            CONFIG = { ...CONFIG, ...data.config };
            settings = { ...DEFAULT_SETTINGS, ...data.settings };
            applySettings();
            wakeFeed();
            break;

        case 'openInput':
            openInput();
            break;

        case 'closeInput':
            // closed from lua (e.g. pause menu) — treat as cancel without re-posting
            inputOpen = false;
            elInputPanel.classList.add('hidden');
            closeSettings();
            hideSuggestions();
            wakeFeed();
            break;

        case 'addMessage':
            addMessage(data.message);
            break;

        case 'clear':
            clearMessages();
            break;

        case 'addSuggestion':
            addSuggestion(data.suggestion);
            break;

        case 'removeSuggestion':
            removeSuggestion(data.name);
            break;

        case 'addTemplate':
            templates[data.id] = data.template;
            break;

        case 'typingUpdate':
            updateTyping(data.id, data.name, data.typing);
            break;
    }
});

/* ------------------------------------------------------------------ */
/*  Boot                                                               */
/* ------------------------------------------------------------------ */

// announce readiness to the client script; retry until the Lua side
// has registered its NUI callbacks (they load in parallel on resource start)
function announceLoaded(attempt) {
    attempt = attempt || 0;
    fetch(`https://${RESOURCE}/loaded`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: '{}',
    }).then((response) => {
        if (!response.ok && attempt < 20) {
            setTimeout(() => announceLoaded(attempt + 1), 500);
        }
    }).catch(() => {
        if (attempt < 20) {
            setTimeout(() => announceLoaded(attempt + 1), 500);
        }
    });
}

document.addEventListener('DOMContentLoaded', () => {
    bindInput();
    bindSettingsControls();
    applySettings();
    announceLoaded();
});
