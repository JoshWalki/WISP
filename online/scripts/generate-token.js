/**
 * WISP Token Generator
 * Generates a cryptographically secure token for API authentication
 */

const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// Generate a 256-bit (32-byte) random token
const token = crypto.randomBytes(32).toString('base64');

console.log('='.repeat(70));
console.log('WISP Companion - Security Token Generated');
console.log('='.repeat(70));
console.log('');
console.log('Your secure token:');
console.log('');
console.log(`  ${token}`);
console.log('');
console.log('='.repeat(70));
console.log('IMPORTANT: Store this token securely!');
console.log('='.repeat(70));
console.log('');
console.log('Setup Instructions:');
console.log('');
console.log('1. Create a .env file in the project root:');
console.log('   ');
console.log(`   WISP_TOKEN=${token}`);
console.log('');
console.log('2. Set as environment variable (Windows):');
console.log('   ');
console.log(`   setx WISP_TOKEN "${token}"`);
console.log('');
console.log('3. OR store in Windows Credential Manager (Recommended):');
console.log('   ');
console.log('   Control Panel > Credential Manager > Windows Credentials > Add');
console.log('   Internet or network address: wisp-companion');
console.log('   User name: token');
console.log(`   Password: ${token}`);
console.log('');
console.log('4. Include in HTML requests:');
console.log('   ');
console.log('   headers: {');
console.log(`     'X-WISP-Token': '${token}'`);
console.log('   }');
console.log('');
console.log('='.repeat(70));
console.log('WARNING: Do not commit this token to version control!');
console.log('='.repeat(70));
console.log('');

// Optionally write to .env file
const envPath = path.join(__dirname, '..', '.env');
const envExists = fs.existsSync(envPath);

if (!envExists) {
  const envContent = `# WISP Companion Environment Configuration
# Generated: ${new Date().toISOString()}

# SECURITY: Authentication token (keep secret!)
WISP_TOKEN=${token}

# Optional: Custom port (default: 8765)
# WISP_PORT=8765

# Optional: Custom PsExec path
# PSEXEC_PATH=C:\\SysinternalsSuite\\PsExec.exe

# Optional: Log level (error, warn, info, debug)
# LOG_LEVEL=info

# Environment
NODE_ENV=production
`;

  fs.writeFileSync(envPath, envContent, 'utf8');
  console.log(`✓ Created .env file at: ${envPath}`);
  console.log('');
} else {
  console.log(`! .env file already exists at: ${envPath}`);
  console.log('! Please update it manually with the token above');
  console.log('');
}
