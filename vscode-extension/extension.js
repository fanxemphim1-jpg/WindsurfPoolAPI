// WindsurfPoolAPI — VS Code / Cursor extension.
// Minimal, zero-dependency wrapper around the `windsurfpoolapi` binary.
// Uses only `vscode` + Node builtins so the VSIX stays small (< 30 KB).

const vscode = require('vscode');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const https = require('https');
const { promisify } = require('util');

const REPO = 'guanxiaol/WindsurfPoolAPI';
const VERSION = '2.0.4';

/** @type {import('child_process').ChildProcess | null} */
let proc = null;
let output;          // output channel
let statusBarItem;   // status bar
let ctx;             // extension context

function activate(context) {
  ctx = context;
  output = vscode.window.createOutputChannel('WindsurfPoolAPI');
  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusBarItem.command = 'windsurfpoolapi.openDashboard';
  updateStatusBar('stopped');
  statusBarItem.show();
  context.subscriptions.push(output, statusBarItem);

  const reg = (cmd, fn) =>
    context.subscriptions.push(vscode.commands.registerCommand(cmd, fn));

  reg('windsurfpoolapi.start', startProxy);
  reg('windsurfpoolapi.stop', stopProxy);
  reg('windsurfpoolapi.restart', async () => { await stopProxy(); await startProxy(); });
  reg('windsurfpoolapi.openDashboard', openDashboard);
  reg('windsurfpoolapi.setupLanguageServer', setupLanguageServer);
  reg('windsurfpoolapi.showLogs', () => output.show());
  reg('windsurfpoolapi.copyApiEndpoint', copyApiEndpoint);

  if (cfg().autoStart) startProxy();
}

function deactivate() {
  if (proc) proc.kill();
}

// ───────────────────────── helpers ─────────────────────────

function cfg() {
  return vscode.workspace.getConfiguration('windsurfpoolapi');
}

function updateStatusBar(state) {
  if (state === 'running') {
    statusBarItem.text = `$(broadcast) WindsurfPoolAPI :${cfg().get('port', 3003)}`;
    statusBarItem.tooltip = 'WindsurfPoolAPI is running — click to open dashboard';
    statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.prominentBackground');
  } else if (state === 'starting') {
    statusBarItem.text = `$(sync~spin) WindsurfPoolAPI starting…`;
    statusBarItem.tooltip = 'Starting WindsurfPoolAPI…';
    statusBarItem.backgroundColor = undefined;
  } else {
    statusBarItem.text = `$(circle-outline) WindsurfPoolAPI`;
    statusBarItem.tooltip = 'WindsurfPoolAPI is stopped — click to start';
    statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    statusBarItem.command = 'windsurfpoolapi.start';
  }
  if (state === 'running') statusBarItem.command = 'windsurfpoolapi.openDashboard';
}

function binaryAssetName() {
  const p = process.platform;
  const a = process.arch;
  if (p === 'darwin' && a === 'arm64') return `windsurfpoolapi-v${VERSION}-macos-arm64`;
  if (p === 'darwin' && a === 'x64')   return `windsurfpoolapi-v${VERSION}-macos-x64`;
  if (p === 'linux'  && a === 'x64')   return `windsurfpoolapi-v${VERSION}-linux-x64`;
  if (p === 'win32'  && a === 'x64')   return `windsurfpoolapi-v${VERSION}-win-x64.exe`;
  throw new Error(`Unsupported platform: ${p}-${a}`);
}

function binaryStoragePath() {
  const override = cfg().get('binaryPath', '').trim();
  if (override) return override;
  const dir = ctx.globalStorageUri.fsPath;
  fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, binaryAssetName());
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const request = (u, redirectCount = 0) => {
      https.get(u, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          if (redirectCount > 5) return reject(new Error('Too many redirects'));
          return request(res.headers.location, redirectCount + 1);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} downloading ${u}`));
        }
        res.pipe(file);
        file.on('finish', () => file.close(resolve));
      }).on('error', reject);
    };
    request(url);
  });
}

async function ensureBinary() {
  const binPath = binaryStoragePath();
  if (fs.existsSync(binPath)) return binPath;

  const asset = binaryAssetName();
  const url = `https://github.com/${REPO}/releases/download/v${VERSION}/${asset}`;
  output.appendLine(`Downloading ${url} …`);
  output.show(true);

  await vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: `WindsurfPoolAPI — downloading ${asset}` },
    async () => {
      await download(url, binPath);
      if (process.platform !== 'win32') fs.chmodSync(binPath, 0o755);
    }
  );
  output.appendLine(`Saved binary to ${binPath}`);
  return binPath;
}

// ───────────────────────── commands ─────────────────────────

async function startProxy() {
  if (proc) {
    vscode.window.showInformationMessage('WindsurfPoolAPI is already running.');
    return;
  }
  updateStatusBar('starting');

  let binPath;
  try {
    binPath = await ensureBinary();
  } catch (e) {
    updateStatusBar('stopped');
    vscode.window.showErrorMessage(`Failed to locate binary: ${e.message}`);
    return;
  }

  const c = cfg();
  const env = {
    ...process.env,
    PORT: String(c.get('port', 3003)),
    DEFAULT_MODEL: c.get('defaultModel', 'claude-sonnet-4.6'),
  };
  const ls = c.get('lsBinaryPath', '').trim();
  if (ls) env.LS_BINARY_PATH = ls;
  const apiKey = c.get('apiKey', '').trim();
  if (apiKey) env.API_KEY = apiKey;
  const dashPw = c.get('dashboardPassword', '').trim();
  if (dashPw) env.DASHBOARD_PASSWORD = dashPw;

  output.appendLine(`Starting ${binPath} on port ${env.PORT}`);
  proc = spawn(binPath, [], { env, cwd: path.dirname(binPath) });

  proc.stdout.on('data', (d) => output.append(d.toString()));
  proc.stderr.on('data', (d) => output.append(d.toString()));
  proc.on('exit', (code) => {
    output.appendLine(`[proxy exited with code ${code}]`);
    proc = null;
    updateStatusBar('stopped');
  });

  // Wait ~1s for bind before marking running
  setTimeout(() => {
    if (proc) {
      updateStatusBar('running');
      vscode.window.showInformationMessage(
        `WindsurfPoolAPI running on http://127.0.0.1:${env.PORT}`,
        'Open Dashboard',
        'Copy Endpoint'
      ).then((choice) => {
        if (choice === 'Open Dashboard') openDashboard();
        if (choice === 'Copy Endpoint') copyApiEndpoint();
      });
    }
  }, 1000);
}

async function stopProxy() {
  if (!proc) return;
  output.appendLine('Stopping proxy…');
  return new Promise((resolve) => {
    proc.once('exit', () => resolve());
    proc.kill('SIGTERM');
    setTimeout(() => proc && proc.kill('SIGKILL'), 5000);
  });
}

function openDashboard() {
  if (!proc) {
    vscode.window.showWarningMessage('Proxy is not running. Start it first.');
    return;
  }
  const url = `http://127.0.0.1:${cfg().get('port', 3003)}/dashboard`;
  vscode.env.openExternal(vscode.Uri.parse(url));
}

function copyApiEndpoint() {
  const port = cfg().get('port', 3003);
  const text = `http://127.0.0.1:${port}/v1`;
  vscode.env.clipboard.writeText(text);
  vscode.window.showInformationMessage(`Copied: ${text}`);
}

async function setupLanguageServer() {
  const p = process.platform;
  const a = process.arch;
  let candidates = [];
  let lsName;

  if (p === 'darwin') {
    lsName = a === 'arm64' ? 'language_server_macos_arm' : 'language_server_macos_x64';
    candidates = [
      `/Applications/Windsurf.app/Contents/Resources/app/extensions/windsurf/bin/${lsName}`,
      `/Applications/Windsurf.app/Contents/Resources/${lsName}`,
      `${process.env.HOME}/.codeium/windsurf/${lsName}`,
      `/opt/windsurf/${lsName}`,
    ];
  } else if (p === 'linux') {
    lsName = a === 'arm64' ? 'language_server_linux_arm' : 'language_server_linux_x64';
    candidates = [
      `/opt/windsurf/${lsName}`,
      `/usr/share/windsurf/resources/app/extensions/windsurf/bin/${lsName}`,
      `${process.env.HOME}/.codeium/windsurf/${lsName}`,
    ];
  } else if (p === 'win32') {
    lsName = 'language_server_windows_x64.exe';
    const home = process.env.USERPROFILE || process.env.HOME;
    candidates = [
      `${process.env.LOCALAPPDATA}\\Programs\\Windsurf\\resources\\app\\extensions\\windsurf\\bin\\${lsName}`,
      `${process.env.LOCALAPPDATA}\\Programs\\Windsurf\\resources\\${lsName}`,
      `C:\\Program Files\\Windsurf\\resources\\app\\extensions\\windsurf\\bin\\${lsName}`,
      `${home}\\.codeium\\windsurf\\${lsName}`,
    ];
  }

  const found = candidates.find((f) => fs.existsSync(f));
  if (!found) {
    const pick = await vscode.window.showInformationMessage(
      'Windsurf Language Server not found in standard locations. Please install Windsurf IDE or select the binary manually.',
      'Install Windsurf',
      'Select manually'
    );
    if (pick === 'Install Windsurf') {
      vscode.env.openExternal(vscode.Uri.parse('https://windsurf.com/download'));
    } else if (pick === 'Select manually') {
      const uris = await vscode.window.showOpenDialog({
        canSelectFiles: true,
        canSelectMany: false,
        title: 'Select language_server_* binary',
      });
      if (uris && uris[0]) {
        await cfg().update('lsBinaryPath', uris[0].fsPath, vscode.ConfigurationTarget.Global);
        vscode.window.showInformationMessage(`LS binary set to ${uris[0].fsPath}`);
      }
    }
    return;
  }

  await cfg().update('lsBinaryPath', found, vscode.ConfigurationTarget.Global);
  vscode.window.showInformationMessage(`Found Language Server at ${found}. Setting applied.`);
}

module.exports = { activate, deactivate };
