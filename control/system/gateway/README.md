# Cluster Gateway

One Gateway resource per cluster (`cluster-gateway` in `gateway-system`). Every app attaches an `HTTPRoute` with `parentRefs: [{ name: cluster-gateway, namespace: gateway-system }]`.

## Current state: HTTP-only

The Gateway listens on port 80 (HTTP) only. TLS is deferred — the user will provide a cert matching their internal CNAME later. When that happens:

1. Apply the cert as a Secret in `gateway-system` (or another namespace + ReferenceGrant)
2. Add a second listener:
   ```yaml
   - name: https
     protocol: HTTPS
     port: 443
     tls:
       mode: Terminate
       certificateRefs:
         - { kind: Secret, name: <secret-name> }
     allowedRoutes:
       namespaces: { from: All }
   ```
3. Optionally remove the HTTP listener (or keep it for redirect).

HTTPRoutes don't need changes — they attach to the Gateway as a whole, not a specific listener.

## Tailnet exposure

The `infrastructure.annotations` block propagates to the Cilium-created `cilium-gateway-cluster-gateway` Service. The Tailscale operator (in the `tailscale` namespace) sees `tailscale.com/expose: "true"` and stands up a proxy at `gw-oasis-control.<tailnet>.ts.net`.

DNS pattern (you maintain in your internal DNS):
```
*.<your-internal-domain>  CNAME  gw-oasis-control.<tailnet>.ts.net
```

Off-tailnet: NXDOMAIN (private by construction). On-tailnet: MagicDNS resolves, operator proxies TCP to the Gateway, Cilium routes by hostname to the right backend.

## Adding a new app

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <app-namespace>
spec:
  parentRefs:
    - { name: cluster-gateway, namespace: gateway-system }
  hostnames: [<app>.<your-internal-domain>]
  rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs: [{ name: <service>, port: <port> }]
```

That's it — wildcard CNAME already covers the hostname.
