const { app, BrowserWindow, shell } = require('electron');
const path = require('path');
const http = require('http');
const fs = require('fs');

let mainWindow = null;
let server = null;
let serverPort = null;

// MIME types for Flutter Web assets
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
};

// Start a lightweight local embedded HTTP server to serve Flutter Web release
function startEmbeddedServer(buildDir, callback) {
  server = http.createServer((req, res) => {
    // Sanitize path to prevent directory traversal
    let safeUrlPath = req.url.split('?')[0];
    if (safeUrlPath === '/' || safeUrlPath === '') {
      safeUrlPath = '/index.html';
    }

    let filePath = path.join(buildDir, decodeURIComponent(safeUrlPath));

    // If request has no extension or file doesn't exist, fallback to index.html (SPA routing)
    if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
      const fallbackPath = path.join(buildDir, 'index.html');
      if (fs.existsSync(fallbackPath)) {
        filePath = fallbackPath;
      }
    }

    fs.stat(filePath, (err, stats) => {
      if (err || !stats.isFile()) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('404 Not Found');
        return;
      }

      const ext = path.extname(filePath).toLowerCase();
      const contentType = MIME_TYPES[ext] || 'application/octet-stream';

      const headers = {
        'Content-Type': contentType,
        'Content-Length': stats.size,
        'Cache-Control': 'no-cache',
        'Cross-Origin-Opener-Policy': 'same-origin',
        'Cross-Origin-Embedder-Policy': 'credentialless',
      };

      res.writeHead(200, headers);
      const readStream = fs.createReadStream(filePath);
      readStream.pipe(res);
    });
  });

  // Listen on loopback interface with an OS-assigned ephemeral free port
  server.listen(0, '127.0.0.1', () => {
    serverPort = server.address().port;
    console.log(`[ZEV Desktop] Embedded server listening on http://127.0.0.1:${serverPort}`);
    callback(serverPort);
  });

  server.on('error', (err) => {
    console.error('[ZEV Desktop] Server error:', err);
  });
}

function createWindow(port) {
  const iconPath = path.join(__dirname, '../web/icons/Icon-512.png');

  mainWindow = new BrowserWindow({
    width: 1300,
    height: 860,
    minWidth: 920,
    minHeight: 640,
    title: 'ZEV App',
    backgroundColor: '#FAF5F7',
    icon: fs.existsSync(iconPath) ? iconPath : undefined,
    show: false, // Show once ready to avoid white flash
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webSecurity: true,
      allowRunningInsecureContent: false,
      hardwareAcceleration: true,
    },
  });

  // Custom user agent
  mainWindow.webContents.setUserAgent(
    `${mainWindow.webContents.getUserAgent()} ZevDesktop/1.0.0`
  );

  // Load Flutter Web
  mainWindow.loadURL(`http://127.0.0.1:${port}`);

  // Show window smoothly
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  // Handle external links safely
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://127.0.0.1:') || url.startsWith('http://localhost:')) {
      return { action: 'allow' };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  // Determine Flutter build directory
  let buildDir = path.join(__dirname, '../build/web');
  if (!fs.existsSync(buildDir)) {
    // Check fallback for production packaged resources
    buildDir = path.join(process.resourcesPath, 'build/web');
  }

  startEmbeddedServer(buildDir, (port) => {
    createWindow(port);
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0 && serverPort) {
      createWindow(serverPort);
    }
  });
});

app.on('window-all-closed', () => {
  if (server) {
    server.close();
  }
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
