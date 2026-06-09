.pragma library

// Secure curl command builder for Ephemera.
// Security improvements over DMS AI Assistant:
//   1. Body via stdin (-d @-) — conversation never in /proc/cmdline
//   2. Gemini key as header (x-goog-api-key) — not in URL query param
//   3. No --compressed flag (breaks StdioCollector)

/**
 * Validate a URL for use as a provider base URL.
 *
 * Enforces: http(s) scheme only, valid hostname, max 2048 chars, no control
 * characters or characters unsafe in URLs (angle brackets, quotes, backticks,
 * curly braces, pipes, backslashes, spaces).
 *
 * @param {string} url - URL to validate.
 * @returns {{ valid: boolean, error: string }} error is empty when valid or when URL is absent.
 */
function validateUrl(url) {
    var u = (url || "").trim();
    if (!u) return { valid: false, error: "" }; // empty is not an error, just absent
    if (u.length > 2048)
        return { valid: false, error: "URL is too long (max 2048 characters)." };
    if (!/^https?:\/\//i.test(u))
        return { valid: false, error: "Must start with http:// or https://" };
    if (!/^https?:\/\/[a-zA-Z0-9]/.test(u))
        return { valid: false, error: "Invalid hostname in URL." };
    // Reject control characters and characters unsafe in URLs (prevents injection via path)
    if (/[\x00-\x20\x7f<>"'{}|\\^`]/.test(u))
        return { valid: false, error: "URL contains invalid characters." };
    return { valid: true, error: "" };
}

function normalizeBaseUrl(url) {
    var u = (url || "").trim();
    if (!u) return "";
    if (!validateUrl(u).valid) return "";
    return u.endsWith("/") ? u.slice(0, -1) : u;
}

/**
 * Sanitize an API key by stripping newlines and control characters.
 *
 * Prevents HTTP header injection by removing CR, LF, null bytes, and all
 * C0 control characters (U+0000–U+001F). The result is trimmed.
 *
 * @param {string} key - Raw API key string.
 * @returns {string} Sanitized key, or "" if input is falsy.
 */
function sanitizeApiKey(key) {
    if (!key) return "";
    return key.replace(/[\r\n\x00-\x1f]/g, "").trim();
}

// Shared helper: separates system messages from conversation messages.
// Returns { systemText: string, filtered: Array<{role, content}> }
function extractSystemPrompt(messages) {
    var systemText = "";
    var filtered = [];
    for (var i = 0; i < messages.length; i++) {
        var m = messages[i];
        if (m.role === "system") {
            systemText = m.content;
        } else {
            filtered.push(m);
        }
    }
    return { systemText: systemText, filtered: filtered };
}

function openaiChatCompletionsUrl(baseUrl) {
    var b = normalizeBaseUrl(baseUrl || "https://api.openai.com");
    if (/\/v\d+$/.test(b))
        return b + "/chat/completions";
    return b + "/v1/chat/completions";
}

/**
 * Escape a string for use inside a double-quoted curl config value.
 *
 * Curl config files (-K) use "value" syntax where backslashes, double quotes,
 * and whitespace characters must be escaped. Without this, a JSON body containing
 * quotes would break the config parser.
 *
 * @param {string} str - Raw string to escape.
 * @returns {string} Escaped string safe for curl config double-quoted context.
 */
function escapeCurlConfig(str) {
    if (!str) return "";
    return str
        .replace(/\\/g, "\\\\")
        .replace(/"/g, '\\"')
        .replace(/\n/g, "\\n")
        .replace(/\r/g, "\\r")
        .replace(/\t/g, "\\t");
}

/**
 * Build a curl command array and stdin config body for a streaming API request.
 *
 * All sensitive data (URL, auth headers, request body) is passed through a curl
 * config file on stdin (-K -), ensuring nothing appears in /proc/cmdline or ps output.
 *
 * @param {string} provider - Provider identifier.
 * @param {Object} payload - Request payload (must include baseUrl, model, messages, timeout, etc.).
 * @param {string} apiKey - Resolved API key (may be empty for Ollama).
 * @returns {{ cmd: string[], body: string } | null}
 *   cmd: curl argument array (no secrets). body: curl config string to write to stdin.
 *   Returns null if the provider requires a key but none is provided.
 */
function buildCurlCommand(provider, payload, apiKey) {
    var request = buildRequest(provider, payload, apiKey);
    if (!request || !request.url)
        return null;

    var timeout = payload.timeout || 30;
    // Command has no secrets — URL, headers, and body all go through stdin config
    var cmd = [
        "curl", "-K", "-", "-N", "-sS", "--no-buffer", "--show-error",
        "--connect-timeout", "5",
        "--max-time", String(timeout),
        "-w", "\\nEPH_STATUS:%{http_code}\\n"
    ];

    // Build curl config for stdin — hides URL, auth headers, and body from /proc/cmdline
    var config = 'url = "' + escapeCurlConfig(request.url) + '"\n';
    config += 'request = "POST"\n';
    config += 'header = "Content-Type: application/json"\n';

    var headers = request.headers || [];
    for (var i = 0; i < headers.length; i += 2) {
        if (headers[i] === "-H" && headers[i + 1])
            config += 'header = "' + escapeCurlConfig(headers[i + 1]) + '"\n';
    }

    config += 'data = "' + escapeCurlConfig(request.body || "{}") + '"\n';

    return { cmd: cmd, body: config };
}

function buildRequest(provider, payload, apiKey) {
    switch (provider) {
    case "ollama":
        return ollamaRequest(payload);
    case "anthropic":
        return anthropicRequest(payload, apiKey);
    case "gemini":
        return geminiRequest(payload, apiKey);
    case "custom":
        return customRequest(payload, apiKey);
    default:
        return openaiRequest(payload, apiKey);
    }
}

function ollamaRequest(payload) {
    // Use OpenAI-compatible endpoint for SSE streaming
    var base = normalizeBaseUrl(payload.baseUrl || "http://localhost:11434");
    var url = base + "/v1/chat/completions";
    var temp = clampTemperature("ollama", payload.model, payload.temperature);
    var thinkingMode = normalizeOllamaThinkingMode(payload.ollamaThinkingMode);
    var body = {
        model: payload.model,
        messages: payload.messages,
        stream: true
    };
    if (payload.max_tokens > 0) body.max_tokens = payload.max_tokens;
    if (temp !== undefined) body.temperature = temp;
    if (thinkingMode !== "default") body.reasoning_effort = thinkingMode;
    // No auth header for Ollama
    return { url: url, headers: [], body: JSON.stringify(body) };
}

function normalizeOllamaThinkingMode(mode) {
    var m = String(mode || "default").trim().toLowerCase();
    switch (m) {
    case "none":
    case "low":
    case "medium":
    case "high":
        return m;
    default:
        return "default";
    }
}

function openaiRequest(payload, apiKey) {
    var url = openaiChatCompletionsUrl(payload.baseUrl || "https://api.openai.com");
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = ["-H", "Authorization: Bearer " + safeKey];
    var caps = modelCapabilities("openai", payload.model);
    var body = {
        model: payload.model,
        messages: payload.messages,
        stream: true,
        stream_options: { include_usage: true }
    };
    if (payload.max_tokens > 0) {
        // Reasoning models (gpt-5*, o-series) require max_completion_tokens.
        if (caps.tokensParam === "max_completion_tokens") body.max_completion_tokens = payload.max_tokens;
        else body.max_tokens = payload.max_tokens;
    }
    if (caps.thinkingMode === "openai-reasoning") {
        // Reasoning models reject temperature; control depth via reasoning_effort.
        body.reasoning_effort = effortLevel(payload.thinkingEnabled);
    } else {
        var temp = clampTemperature("openai", payload.model, payload.temperature);
        if (temp !== undefined) body.temperature = temp;
    }
    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function anthropicRequest(payload, apiKey) {
    var base = normalizeBaseUrl(payload.baseUrl || "https://api.anthropic.com");
    var url = base + "/v1/messages";
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = [
        "-H", "x-api-key: " + safeKey,
        "-H", "anthropic-version: 2023-06-01"
    ];
    var caps = modelCapabilities("anthropic", payload.model);

    // Extract system prompt from messages if present
    var extracted = extractSystemPrompt(payload.messages);
    var filteredMessages = [];
    for (var i = 0; i < extracted.filtered.length; i++) {
        var m = extracted.filtered[i];
        filteredMessages.push({
            role: m.role === "assistant" ? "assistant" : "user",
            content: m.content
        });
    }

    // Anthropic requires max_tokens — use 128000 as high cap when unlimited
    var maxTokens = (payload.max_tokens > 0) ? payload.max_tokens : 128000;
    var body = {
        model: payload.model,
        messages: filteredMessages,
        max_tokens: maxTokens,
        stream: true
    };

    if (payload.thinkingEnabled) {
        if (caps.thinkingMode === "adaptive") {
            // Opus 4.5+/Sonnet 4.6+: adaptive thinking (auto-interleaved). "summarized"
            // so reasoning streams (default is omitted on Opus 4.7/4.8).
            body.thinking = { type: "adaptive", display: "summarized" };
            if (caps.effortSupported)
                body.output_config = { effort: effortLevel(true) };
        } else {
            // Legacy models: fixed-budget extended thinking.
            body.thinking = { type: "enabled", budget_tokens: Math.max(1024, Math.floor(maxTokens * 0.8)) };
        }
    }

    // Sampling params (temperature) are rejected on Opus 4.7+ — only send when allowed.
    if (caps.samplingAllowed) {
        // Legacy fixed-budget thinking requires temperature = 1.
        var legacyThinking = payload.thinkingEnabled && caps.thinkingMode === "budget";
        var temp = legacyThinking ? 1 : clampTemperature("anthropic", payload.model, payload.temperature);
        if (temp !== undefined) body.temperature = temp;
    }

    if (extracted.systemText)
        body.system = extracted.systemText;

    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function geminiRequest(payload, apiKey) {
    var base = normalizeBaseUrl(payload.baseUrl || "https://generativelanguage.googleapis.com");
    // Validate model name — prevent path traversal via user-supplied free text
    var model = payload.model || "gemini-2.5-flash";
    if (!/^[a-zA-Z0-9._:\-]+$/.test(model)) return null;
    // Key as header, NOT in URL — security fix
    var url = base + "/v1beta/models/" + model
        + ":streamGenerateContent?alt=sse";
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = ["-H", "x-goog-api-key: " + safeKey];

    // Extract system prompt
    var extracted = extractSystemPrompt(payload.messages);
    var contents = [];
    for (var i = 0; i < extracted.filtered.length; i++) {
        var m = extracted.filtered[i];
        contents.push({
            role: m.role === "user" ? "user" : "model",
            parts: [{ text: m.content }]
        });
    }

    var caps = modelCapabilities("gemini", payload.model);
    var temp = clampTemperature("gemini", payload.model, payload.temperature);
    var genConfig = {};
    if (payload.max_tokens > 0) genConfig.maxOutputTokens = payload.max_tokens;
    if (temp !== undefined) genConfig.temperature = temp;
    if (payload.thinkingEnabled) {
        // Gemini 3.x uses thinkingLevel; 2.5 uses thinkingBudget (-1 = dynamic).
        var tc = { includeThoughts: true };
        if (caps.thinkingMode === "gemini-level") tc.thinkingLevel = "high";
        else tc.thinkingBudget = -1;
        genConfig.thinkingConfig = tc;
    }
    var body = {
        contents: contents,
        generationConfig: genConfig
    };
    if (extracted.systemText)
        body.system_instruction = { parts: [{ text: extracted.systemText }] };

    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function customRequest(payload, apiKey) {
    return openaiRequest(payload, apiKey);
}

// ─── Provider Registry ──────────────────────────────────────────
// Centralized metadata for each provider. Adding a new provider only requires
// adding one entry here and a buildRequest function above.

var registry = {
    "ollama": {
        name: "Ollama",
        envVar: null,
        defaultUrl: "http://localhost:11434",
        needsKey: false,
        hasNativeThinking: false,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 0.8,
        modelPlaceholder: "llama3.2"
    },
    "openai": {
        name: "OpenAI",
        envVar: "OPENAI_API_KEY",
        defaultUrl: "https://api.openai.com",
        needsKey: true,
        hasNativeThinking: false,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 1.0,
        modelPlaceholder: "gpt-5.4",
        // o1/o3 reasoning models don't support temperature
        tempUnsupportedModels: ["o1", "o3"],
        models: [
            "gpt-5.4", "gpt-5.4-pro", "gpt-5", "gpt-5-mini", "gpt-5-nano",
            "gpt-4.1", "o4-mini", "o3", "o3-pro", "gpt-4o", "gpt-4o-mini"
        ]
    },
    "anthropic": {
        name: "Anthropic",
        envVar: "ANTHROPIC_API_KEY",
        defaultUrl: "https://api.anthropic.com",
        needsKey: true,
        hasNativeThinking: true,
        tempMin: 0.0, tempMax: 1.0, tempDefault: 1.0,
        modelPlaceholder: "claude-opus-4-8",
        // Seed list (offline fallback). Live list is fetched from GET /v1/models.
        models: [
            "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
            "claude-sonnet-4-6", "claude-haiku-4-5", "claude-opus-4-5"
        ]
    },
    "gemini": {
        name: "Gemini",
        envVar: "GEMINI_API_KEY",
        defaultUrl: "https://generativelanguage.googleapis.com",
        needsKey: true,
        hasNativeThinking: true,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 1.0,
        modelPlaceholder: "gemini-2.5-flash",
        models: [
            "gemini-3.1-pro-preview", "gemini-3-flash-preview",
            "gemini-3.1-flash-lite-preview", "gemini-2.5-pro",
            "gemini-2.5-flash", "gemini-2.5-flash-lite"
        ]
    },
    "custom": {
        name: "custom provider",
        envVar: "EPHEMERA_API_KEY",
        defaultUrl: "https://api.openai.com",
        needsKey: true,
        hasNativeThinking: false,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 0.7,
        modelPlaceholder: "model-name"
    }
};

function getProviderInfo(provider) {
    return registry[provider] || registry["custom"];
}

function getProviderNames() {
    return Object.keys(registry);
}

/**
 * Get the hardcoded model list for a provider.
 *
 * Returns the models array from the registry entry, or an empty array
 * if the provider has no predefined models (e.g. ollama, custom).
 *
 * @param {string} provider - Provider identifier.
 * @returns {string[]} Array of model name strings.
 */
function getModelList(provider) {
    var info = registry[provider];
    return (info && info.models) ? info.models : [];
}

/**
 * Build a curl argv that lists a provider's live models. The key travels as a
 * header (matching the request builders) — never in the URL.
 * @returns {string[]|null} curl command, or null if a key is required but missing.
 */
function listModelsCommand(provider, baseUrl, apiKey) {
    var key = sanitizeApiKey(apiKey);
    var base;
    if (provider === "anthropic") {
        if (!key) return null;
        base = normalizeBaseUrl(baseUrl || "https://api.anthropic.com");
        return ["curl", "-sS", "--max-time", "15",
            "-H", "x-api-key: " + key,
            "-H", "anthropic-version: 2023-06-01",
            base + "/v1/models?limit=1000"];
    }
    if (provider === "openai" || provider === "custom") {
        if (!key) return null;
        base = normalizeBaseUrl(baseUrl || "https://api.openai.com");
        return ["curl", "-sS", "--max-time", "15",
            "-H", "Authorization: Bearer " + key,
            base + "/v1/models"];
    }
    if (provider === "gemini") {
        if (!key) return null;
        base = normalizeBaseUrl(baseUrl || "https://generativelanguage.googleapis.com");
        return ["curl", "-sS", "--max-time", "15",
            "-H", "x-goog-api-key: " + key,
            base + "/v1beta/models?pageSize=1000"];
    }
    return null;
}

// OpenAI /v1/models lists non-chat models too; drop the obvious ones.
function _openaiIsChatModel(id) {
    var s = (id || "").toLowerCase();
    var skip = ["embedding", "whisper", "tts", "dall-e", "davinci", "babbage",
        "moderation", "audio", "transcribe", "realtime", "image", "search", "computer-use"];
    for (var i = 0; i < skip.length; i++)
        if (s.indexOf(skip[i]) !== -1) return false;
    return true;
}

/**
 * Parse a provider's list-models JSON into an array of model id strings.
 */
function parseModelList(provider, jsonText) {
    var data;
    try {
        data = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    var out = [];
    var i;
    if (provider === "anthropic" && data && Array.isArray(data.data)) {
        for (i = 0; i < data.data.length; i++)
            if (data.data[i] && data.data[i].id) out.push(data.data[i].id);
    } else if ((provider === "openai" || provider === "custom") && data && Array.isArray(data.data)) {
        for (i = 0; i < data.data.length; i++)
            if (data.data[i] && data.data[i].id && _openaiIsChatModel(data.data[i].id))
                out.push(data.data[i].id);
        out.sort();
    } else if (provider === "gemini" && data && Array.isArray(data.models)) {
        for (i = 0; i < data.models.length; i++) {
            var entry = data.models[i] || {};
            var nm = entry.name || "";
            if (nm.indexOf("models/") === 0) nm = nm.substring(7);
            var methods = entry.supportedGenerationMethods || [];
            var ok = methods.length === 0 || methods.indexOf("generateContent") !== -1;
            if (nm && ok) out.push(nm);
        }
    }
    return out;
}

/**
 * Clamp temperature to a provider's valid range, or return undefined if unsupported.
 *
 * Some models (OpenAI o1/o3 reasoning models) do not support temperature at all.
 * Detection uses prefix matching with separator check: "o1-mini" matches but "o100" does not.
 * Falls back to the provider's default temperature when the input is null/undefined.
 *
 * @param {string} provider - Provider identifier.
 * @param {string} model - Model name (checked against tempUnsupportedModels).
 * @param {number} temperature - Requested temperature value.
 * @returns {number|undefined} Clamped temperature, or undefined if the model rejects temperature.
 */
function clampTemperature(provider, model, temperature) {
    var info = registry[provider] || registry["custom"];
    // Check if model doesn't support temperature
    if (info.tempUnsupportedModels) {
        var m = (model || "").toLowerCase();
        for (var i = 0; i < info.tempUnsupportedModels.length; i++) {
            var prefix = info.tempUnsupportedModels[i];
            if (m === prefix) return undefined;
            // Match prefix followed by a separator (e.g. "o1-mini", "o3-preview")
            // but not a continuation like "o1.5" or "o100"
            if (m.indexOf(prefix) === 0) {
                var next = m.charAt(prefix.length);
                if (next === "-" || next === "_") return undefined;
            }
        }
    }
    var t = (temperature !== undefined && temperature !== null) ? temperature : info.tempDefault;
    return Math.max(info.tempMin, Math.min(info.tempMax, t));
}

function getTemperatureRange(provider) {
    var info = registry[provider] || registry["custom"];
    return { min: info.tempMin, max: info.tempMax, defaultValue: info.tempDefault };
}

/**
 * Resolve model-generation-dependent capabilities so request builders adapt to
 * API changes instead of hardcoding one era's request shape. This is the single
 * place to edit when a new model generation ships.
 *
 * Background (June 2026):
 * - Anthropic Opus 4.7+ removed temperature/top_p/top_k AND fixed-budget thinking
 *   (`thinking:{type:"enabled",budget_tokens}`) — both 400. Only adaptive thinking
 *   + output_config.effort. Opus 4.5/4.6 and Sonnet 4.6 accept adaptive+effort and
 *   still allow temperature. Older models use fixed-budget thinking.
 * - OpenAI reasoning models (gpt-5*, o-series) use reasoning_effort, require
 *   max_completion_tokens, and reject temperature. gpt-4* use temperature+max_tokens.
 * - Gemini 3.x uses thinkingConfig.thinkingLevel; 2.5 uses thinkingConfig.thinkingBudget.
 *
 * @returns {{thinkingMode:string, samplingAllowed:boolean, effortSupported:boolean, tokensParam:string}}
 *   thinkingMode: "adaptive"|"budget"|"openai-reasoning"|"gemini-level"|"gemini-budget"|"ollama"|"none"
 */
function modelCapabilities(provider, model) {
    var id = (model || "").toLowerCase();
    if (provider === "anthropic") {
        var m = id.match(/claude-(opus|sonnet|haiku)-(\d+)-(\d+)/);
        var family = m ? m[1] : "";
        var ver = m ? (parseInt(m[2], 10) * 100 + parseInt(m[3], 10)) : 0;
        // Opus 4.7+ (and any future opus 5+): sampling params + fixed-budget thinking removed.
        if (family === "opus" && ver >= 407)
            return { thinkingMode: "adaptive", samplingAllowed: false, effortSupported: true, tokensParam: "max_tokens" };
        // Opus 4.5/4.6 and Sonnet 4.6+: adaptive thinking + effort, temperature still allowed.
        if ((family === "opus" && ver >= 405) || (family === "sonnet" && ver >= 406))
            return { thinkingMode: "adaptive", samplingAllowed: true, effortSupported: true, tokensParam: "max_tokens" };
        // Older (Sonnet 4.5, Haiku 4.5, Opus 4.1/4.0, 3.x): fixed-budget thinking, no effort.
        return { thinkingMode: "budget", samplingAllowed: true, effortSupported: false, tokensParam: "max_tokens" };
    }
    if (provider === "openai" || provider === "custom") {
        // Reasoning families: gpt-5*, o1/o3/o4*.
        if (/^gpt-5/.test(id) || /^o[1345]([._-]|$)/.test(id))
            return { thinkingMode: "openai-reasoning", samplingAllowed: false, effortSupported: true, tokensParam: "max_completion_tokens" };
        return { thinkingMode: "none", samplingAllowed: true, effortSupported: false, tokensParam: "max_tokens" };
    }
    if (provider === "gemini") {
        if (/gemini-3/.test(id))
            return { thinkingMode: "gemini-level", samplingAllowed: true, effortSupported: false, tokensParam: "maxOutputTokens" };
        return { thinkingMode: "gemini-budget", samplingAllowed: true, effortSupported: false, tokensParam: "maxOutputTokens" };
    }
    if (provider === "ollama")
        return { thinkingMode: "ollama", samplingAllowed: true, effortSupported: false, tokensParam: "max_tokens" };
    return { thinkingMode: "none", samplingAllowed: true, effortSupported: false, tokensParam: "max_tokens" };
}

// Map the thinking toggle to an effort level for providers that support effort.
function effortLevel(thinkingEnabled) {
    return thinkingEnabled ? "high" : "medium";
}
