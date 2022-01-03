# Dynamic Pod Proxy Service

On its own, this service is an unintelligent proxy layer that forwards any
request to the encoded request uri path.

This has utility in achieving container-specific resolution mainly for external
integration environments, but **should not** be used in production runtimes
without additional [security](#security) considerations/restrictions.

## Use Case

The primary reason for this service within the application is to support
external Unreal Engine control through the use of
[VaRest](https://www.unrealengine.com/marketplace/en-US/product/varest-plugin) or similar plugins.

The following snippet illustrates the use case:

```sh
docker build -t proxy-service .
docker run -d --rm -p 8080:8080 --name proxy proxy-service
curl -X GET http://localhost:8080/<another-container-address>:<port>/<uri>
docker rm -f proxy
```

## Security

In the interest of securing this ingress proxy, a few considerations for
restricting this service are provided here, which depend on the `traefik`
router exposing this service and may be used in tandem:

- Specify [IP Whitelist](https://doc.traefik.io/traefik/middlewares/http/ipwhitelist/) rules
- Create a [Forward Auth](https://doc.traefik.io/traefik/middlewares/http/forwardauth/#forwardauth) service
- Define [Basic Auth](https://doc.traefik.io/traefik/middlewares/http/basicauth/) or [Digest Auth](https://doc.traefik.io/traefik/middlewares/http/digestauth/) credentials for integrated apps

Of the above options, the **Basic Auth** strategy is implemented in the associative
traefik [../router](../router) layer, but others should be considered as needed.
