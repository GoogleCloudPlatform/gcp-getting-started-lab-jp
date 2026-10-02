// Shared Google API auth chain for the migration-to-gcp plugin tools.
// Priority: gcloud ADC -> gcloud user credentials -> API key (failover).
// Zero dependencies; requires Node >= 18.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const GCLOUD_TIMEOUT_MS = 20_000;
// OAuth access tokens last ~60 min; refresh well before expiry.
const TOKEN_TTL_MS = 45 * 60 * 1000;

export const SETUP_HELP = `No Google API credentials available. Set up one of (in priority order):
  1. gcloud ADC (recommended):
       gcloud auth application-default login
  2. gcloud user credentials:
       gcloud auth login
  3. API key failover:
       gcloud services api-keys create --display-name="migration-to-gcp" \\
         --api-target=service=developerknowledge.googleapis.com \\
         --api-target=service=cloudbilling.googleapis.com
     then set it in the plugin config (google_dev_knowledge_api_key) or export it
     as an environment variable (DK_API_KEY / GCP_PRICING_API_KEY / GOOGLE_API_KEY).
For ADC/user-credential calls the target API must be enabled on the quota project
(e.g. gcloud services enable cloudbilling.googleapis.com developerknowledge.googleapis.com).`;

async function runGcloud(args) {
  try {
    // shell:true on Windows so gcloud.cmd resolves; args are static, no user input.
    const { stdout } = await execFileAsync("gcloud", args, {
      timeout: GCLOUD_TIMEOUT_MS,
      encoding: "utf8",
      windowsHide: true,
      shell: process.platform === "win32",
    });
    return stdout.trim();
  } catch {
    return null;
  }
}

function firstEnv(names) {
  for (const name of names) {
    const value = process.env[name]?.trim();
    // Skip empty values and unexpanded ${...} placeholders (unset plugin
    // userConfig expansion behavior is unspecified across CC versions).
    if (value && !/^\$\{.*\}$/.test(value)) return value;
  }
  return null;
}

/**
 * Create an auth provider implementing the ADC -> gcloud -> API key chain.
 *
 * @param {object} [options]
 * @param {string[]} [options.apiKeyEnvVars] env vars checked (in order) for the failover API key
 * @returns provider with:
 *   headers(): Promise<Record<string,string>>  fresh auth headers (throws Error with SETUP_HELP if no method works)
 *   mode(): 'adc' | 'gcloud-user' | 'api-key' | null   method used by the last headers() call
 *   invalidate(): void            drop the cached token (call after a 401/403, then retry)
 *   demoteToApiKey(): boolean     permanently switch to the API key; false if no key is set
 */
export function createAuthProvider({ apiKeyEnvVars = ["DK_API_KEY", "GCP_PRICING_API_KEY", "GOOGLE_API_KEY"] } = {}) {
  let cached = null; // { token, mode, acquiredAt }
  let quotaProject; // undefined = not looked up yet, null = none found
  let apiKeyOnly = false;
  let lastMode = null;

  const apiKey = () => firstEnv(apiKeyEnvVars);

  async function getQuotaProject() {
    if (quotaProject !== undefined) return quotaProject;
    const fromEnv = firstEnv(["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"]);
    if (fromEnv) {
      quotaProject = fromEnv;
      return quotaProject;
    }
    const fromConfig = await runGcloud(["config", "get-value", "core/project"]);
    quotaProject = fromConfig && fromConfig !== "(unset)" ? fromConfig : null;
    return quotaProject;
  }

  async function getToken() {
    if (cached && Date.now() - cached.acquiredAt < TOKEN_TTL_MS) return cached;
    const adcToken = await runGcloud(["auth", "application-default", "print-access-token"]);
    if (adcToken) {
      cached = { token: adcToken, mode: "adc", acquiredAt: Date.now() };
      return cached;
    }
    const userToken = await runGcloud(["auth", "print-access-token"]);
    if (userToken) {
      cached = { token: userToken, mode: "gcloud-user", acquiredAt: Date.now() };
      return cached;
    }
    return null;
  }

  return {
    async headers() {
      if (!apiKeyOnly) {
        const entry = await getToken();
        if (entry) {
          lastMode = entry.mode;
          const headers = { Authorization: `Bearer ${entry.token}` };
          const project = await getQuotaProject();
          if (project) headers["X-goog-user-project"] = project;
          return headers;
        }
      }
      const key = apiKey();
      if (key) {
        lastMode = "api-key";
        return { "X-Goog-Api-Key": key };
      }
      lastMode = null;
      throw new Error(SETUP_HELP);
    },
    mode: () => lastMode,
    invalidate() {
      cached = null;
    },
    demoteToApiKey() {
      if (!apiKey()) return false;
      apiKeyOnly = true;
      cached = null;
      return true;
    },
  };
}
