# Pixel streaming player view

This code is a direct copy of the signal server (cirrus) web app files. It is
separated to be decoupled from the services which interact with the streamer
runtime.

```sh
docker build -t pixel/player .
```

## Customizations

- Some minor `css` alterations
- `/ws` default websocket path (on same domain)
- `?_ws=wss://another-server-domain` query param to connect to a specific websocket server other than the same host as the player runs.
- Custom init script in `app.js` to support embedding and `window.postMessage` API
- Adds support for `emitSocketInteraction` in conjunction with `emitUIInteraction` where the streamer exposes a REST API
