{{flutter_js}}
{{flutter_build_config}}

function showStartupError(error) {
  console.error('ZcBangumi startup failed', error);
  const statusElement = document.getElementById('loading-status');
  const retryButton = document.getElementById('app-retry');
  if (statusElement) {
    statusElement.textContent = '应用启动失败。请检查网络、刷新页面，或使用完整客户端。';
  }
  if (retryButton) retryButton.hidden = false;
}

document.getElementById('app-retry').addEventListener('click', () => {
  window.location.reload();
});

window.addEventListener('flutter-first-frame', () => {
  document.getElementById('app-loading')?.remove();
});

window.addEventListener('error', (event) => {
  if (document.getElementById('app-loading')) {
    showStartupError(event.error || event.message);
  }
});

try {
  const loading = _flutter.loader.load({
    config: { canvasKitBaseUrl: 'canvaskit/' },
    onEntrypointLoaded: async (engineInitializer) => {
      try {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
      } catch (error) {
        showStartupError(error);
      }
    },
  });
  if (loading?.catch) loading.catch(showStartupError);
} catch (error) {
  showStartupError(error);
}
