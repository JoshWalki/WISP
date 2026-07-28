/**
 * WISP Companion Profile Manager
 *
 * Lists and deletes Windows user profiles on a target device, replacing the
 * manual ProfileDeleter tool workflow with the same underlying approach:
 * Win32_UserProfile's own .Delete() method, which is the Microsoft-native
 * way to remove both the profile folder AND its registry key together (and
 * refuses to delete a profile that's currently logged in - a safety check a
 * hand-rolled "reg delete + rmdir" wouldn't get for free).
 *
 * Reuses the admin-share staging/fetch helpers already built in psexec.js
 * for the system-report and screen-capture features, rather than
 * duplicating that logic here.
 */

const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const config = require("./config");
const { logExecution, logError } = require("./logger");
const {
  checkPsExec,
  toAdminShareUncPath,
  withAdminShareAccess,
  getQualifiedUsername,
} = require("./psexec");

const PROFILES_REMOTE_DIR = "C:\\Windows\\Temp\\wisp_profiles";
const LIST_TIMEOUT_MS = 60000;
const DELETE_TIMEOUT_MS = 30000;

const SID_PATTERN = /^S-1-\d+(-\d+)+$/i;

function isValidSid(sid) {
  return typeof sid === "string" && SID_PATTERN.test(sid);
}

function buildBaseArgs(hostname) {
  const args = [`\\\\${hostname}`];

  if (config.psexec.credentials.username) {
    args.push("-u", getQualifiedUsername(hostname));
    if (config.psexec.credentials.password) {
      args.push("-p", config.psexec.credentials.password);
    }
  }

  if (config.psexec.acceptEula) {
    args.push("-accepteula");
  }

  args.push("-nobanner");

  return args;
}

function runPsExecAndWait(args, timeoutMs) {
  return new Promise((resolve, reject) => {
    const proc = spawn(config.psexec.path, args, {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    if (proc.stdout) {
      proc.stdout.on("data", (chunk) => (stdout += chunk.toString()));
    }
    if (proc.stderr) {
      proc.stderr.on("data", (chunk) => (stderr += chunk.toString()));
    }

    const timeout = setTimeout(() => {
      proc.kill();
      reject(new Error("PsExec command timed out"));
    }, timeoutMs);

    proc.on("close", (code) => {
      clearTimeout(timeout);
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(stderr.trim() || stdout.trim() || `PsExec exited with code ${code}`));
      }
    });

    proc.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

/**
 * List user profiles on the target, excluding Windows' own "Special"
 * profiles (SYSTEM, Local Service, Network Service, Default, etc.) - Public
 * isn't a real logon profile at all, so it never appears here, but the
 * frontend and deleteProfile() both defensively guard against it anyway.
 */
async function listProfiles(hostname) {
  checkPsExec();

  const remoteDirUnc = toAdminShareUncPath(hostname, PROFILES_REMOTE_DIR);
  const remoteOutputUnc = path.join(remoteDirUnc, "profiles.json");
  const localScript = path.join(
    __dirname,
    "..",
    "assests",
    "list_profiles.ps1"
  );

  await withAdminShareAccess(hostname, () => {
    fs.mkdirSync(remoteDirUnc, { recursive: true });
    fs.copyFileSync(
      localScript,
      path.join(remoteDirUnc, "list_profiles.ps1")
    );
  });

  try {
    const args = buildBaseArgs(hostname);

    // Runs as SYSTEM - listing profile info (including sizes under other
    // users' folders) needs more than a standard user's own access.
    args.push(
      "-s",
      "powershell.exe",
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      `${PROFILES_REMOTE_DIR}\\list_profiles.ps1`,
      "-OutputPath",
      `${PROFILES_REMOTE_DIR}\\profiles.json`
    );

    await runPsExecAndWait(args, LIST_TIMEOUT_MS);

    let profiles = [];
    await withAdminShareAccess(hostname, () => {
      if (!fs.existsSync(remoteOutputUnc)) {
        throw new Error("Profile list output not found on target");
      }
      let jsonContent = fs.readFileSync(remoteOutputUnc, "utf8");
      // PowerShell 5.1's "Out-File -Encoding UTF8" writes a BOM, which
      // JSON.parse chokes on - same fix already used in server.js's report
      // loader for the exact same reason.
      if (jsonContent.charCodeAt(0) === 0xfeff) {
        jsonContent = jsonContent.slice(1);
      }
      profiles = JSON.parse(jsonContent);
    });

    logExecution("profile-list", hostname, null, null, {
      status: "listed",
      count: profiles.length,
    });

    return profiles;
  } finally {
    try {
      await withAdminShareAccess(hostname, () => {
        fs.rmSync(remoteDirUnc, { recursive: true, force: true });
      });
    } catch (cleanupError) {
      logError(
        new Error(
          `Failed to clean up profile listing dir on ${hostname}: ${cleanupError.message}`
        ),
        { hostname }
      );
    }
  }
}

/**
 * Delete a single user profile by SID via Win32_UserProfile.Delete().
 * Re-validates server-side (not just trusting whatever the frontend sent)
 * that the profile isn't Special, isn't Public/Default by folder name, and
 * isn't currently loaded (logged in) - the same guard rails a human using
 * Windows' own "Delete Account" UI would get.
 */
async function deleteProfile(hostname, sid) {
  checkPsExec();

  if (!isValidSid(sid)) {
    throw new Error("Invalid SID format");
  }

  const args = buildBaseArgs(hostname);

  const script = `
$profile = Get-CimInstance Win32_UserProfile -Filter "SID='${sid}'" -ErrorAction Stop
if (-not $profile) { Write-Error 'Profile not found'; exit 1 }
if ($profile.Special) { Write-Error 'Refusing to delete a special/built-in profile'; exit 1 }
if ($profile.Loaded) { Write-Error 'Refusing to delete a profile that is currently logged in'; exit 1 }
$folderName = if ($profile.LocalPath) { Split-Path $profile.LocalPath -Leaf } else { '' }
if ($folderName -ieq 'Public' -or $folderName -ieq 'Default' -or $folderName -ieq 'Default User') {
    Write-Error 'Refusing to delete Public/Default profile'
    exit 1
}
$profile.Delete()
Write-Host "Deleted profile ${sid}"
`;

  // -EncodedCommand (base64 UTF-16LE) sidesteps any quoting/escaping
  // concerns entirely for a script built from a variable (the SID) -
  // already validated above as a plain S-1-... string with no special
  // characters, but this removes any doubt regardless.
  const encodedCommand = Buffer.from(script, "utf16le").toString("base64");

  args.push(
    "-s",
    "powershell.exe",
    "-NoProfile",
    "-EncodedCommand",
    encodedCommand
  );

  try {
    const result = await runPsExecAndWait(args, DELETE_TIMEOUT_MS);
    logExecution("profile-delete", hostname, null, null, {
      status: "deleted",
      sid,
    });
    return result;
  } catch (error) {
    logError(new Error(`Failed to delete profile ${sid} on ${hostname}: ${error.message}`), {
      hostname,
      sid,
    });
    throw error;
  }
}

module.exports = { listProfiles, deleteProfile };
