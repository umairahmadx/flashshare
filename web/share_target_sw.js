// Web Share Target handler for Flash Share.
// Intercepts the POST that the OS share sheet makes to /share-target, pulls the
// shared file(s) out of the form data, hands them to the running app via a
// BroadcastChannel, then redirects to the app root.
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.pathname === '/share-target') {
    event.respondWith((async () => {
      const formData = await event.request.formData();
      const files = formData.getAll('file');
      const channel = new BroadcastChannel('flashshare-share');
      files.forEach((f) => channel.postMessage({ name: f.name, size: f.size }));
      channel.close();
      return Response.redirect('/', 303);
    })());
  }
});
