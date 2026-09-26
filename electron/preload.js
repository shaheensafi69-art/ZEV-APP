// Electron preload script for ZEV App
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('zevDesktop', {
  platform: process.platform,
  version: '1.0.0',
  isDesktop: true,
});
