/**
 * Custom .env file loader
 * Replaces dotenv package with lightweight implementation
 */

const fs = require('fs');
const path = require('path');

/**
 * Load environment variables from .env file
 * @param {string} filePath - Path to .env file (default: .env in root)
 * @returns {object} - Parsed environment variables
 */
function loadEnv(filePath = path.join(__dirname, '..', '.env')) {
  const env = {};

  try {
    // Check if .env file exists
    if (!fs.existsSync(filePath)) {
      console.warn(`[ENV] .env file not found at: ${filePath}`);
      return env;
    }

    // Read and parse .env file
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');

    for (let line of lines) {
      // Remove whitespace
      line = line.trim();

      // Skip empty lines and comments
      if (!line || line.startsWith('#')) {
        continue;
      }

      // Parse KEY=VALUE format
      const match = line.match(/^([^=]+)=(.*)$/);
      if (match) {
        const key = match[1].trim();
        let value = match[2].trim();

        // Remove quotes if present
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.slice(1, -1);
        }

        // Set in process.env (for compatibility)
        process.env[key] = value;

        // Also store in return object
        env[key] = value;
      }
    }

    console.log(`[ENV] Loaded ${Object.keys(env).length} environment variables from .env`);
    return env;

  } catch (error) {
    console.error(`[ENV] Error loading .env file:`, error.message);
    return env;
  }
}

/**
 * Get environment variable with optional default
 * @param {string} key - Environment variable key
 * @param {*} defaultValue - Default value if not found
 * @returns {*} - Environment variable value or default
 */
function getEnv(key, defaultValue = undefined) {
  return process.env[key] !== undefined ? process.env[key] : defaultValue;
}

module.exports = {
  loadEnv,
  getEnv
};
