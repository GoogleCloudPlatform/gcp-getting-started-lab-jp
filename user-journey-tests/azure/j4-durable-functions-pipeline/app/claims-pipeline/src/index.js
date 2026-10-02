// Entry point the Functions host loads — the "main" field in package.json.
// Requiring a module registers whatever functions that module declares, so this
// list is what the app actually runs.

require("./functions/intake-processor");
require("./functions/review-router");
require("./functions/claims-approval");
