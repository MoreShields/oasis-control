# Cluster Gateways

Two Gateway resources per cluster, both backed by Cilium's `cilium` GatewayClass:

| Gateway | Exposure | TLS | Default for |
|---|---|---|---|
| `tailnet-gateway` | tailnet only via Tailscale operator | HTTP today (deferred) | almost everything |
| `internet-gateway` | public NLB via AWS CCM | HTTPS-only (uses cert in Secret) | explicitly opt-in apps |

Same Cilium data plane (Envoy embedded in `cilium-agent`) handles both. The split is purely about *which Service fronts the listener* — ClusterIP for tailnet (no AWS LB) vs LoadBalancer for internet (CCM-provisioned NLB).

## How HTTPRoutes pick

```yaml
# Default (private)
spec:
  parentRefs:
    - { name: tailnet-gateway, namespace: gateway-system }
  hostnames: [argocd.oasis-control.internal]

# Public
spec:
  parentRefs:
    - { name: internet-gateway, namespace: gateway-system }
  hostnames: [public-app.example.com]

# Both — usually with different hostnames per surface
spec:
  parentRefs:
    - { name: tailnet-gateway,   namespace: gateway-system }
    - { name: internet-gateway,  namespace: gateway-system }
  hostnames:
    - app.oasis-control.internal
    - app.example.com
```

## Public exposure is opt-in

`internet-gateway` has `allowedRoutes.namespaces.from: Selector` requiring the namespace to carry label `networking.oasis-control/exposure: public`. Forces a deliberate step before any HTTPRoute can attach to the public Gateway. Without that label on the namespace, attachment is rejected — accidents impossible.

```bash
kubectl label namespace <ns> networking.oasis-control/exposure=public
```

## internet-gateway is currently unprovisioned

The HTTPS listener references Secret `internet-gateway-cert`, which doesn't exist yet. Until the Secret is created, Cilium leaves the Gateway in `NotProgrammed` state and the underlying Service is never created — so AWS CCM has nothing to react to and **no public NLB is provisioned**. No cost incurred, no exposed surface.

To activate internet-gateway:

1. **Provide a TLS cert** as Secret `internet-gateway-cert` in `gateway-system`. Options:
   - cert-manager Certificate with ACME-HTTP-01 challenge — needs the public NLB up first, so chicken-and-egg unless you DNS-01.
   - cert-manager Certificate with ACME-DNS-01 — cleanest if/when you wire a DNS provider.
   - Hand-imported cert from any source: `kubectl create secret tls internet-gateway-cert -n gateway-system --cert=fullchain.pem --key=key.pem`
2. Cilium picks up the Secret, programs the Gateway, creates the LoadBalancer Service.
3. AWS CCM provisions the public NLB. Cost: ~$25/mo.
4. Add a public DNS A/CNAME record at your registrar pointing at the NLB DNS.
5. Label the namespace(s) you want to publicly expose: `networking.oasis-control/exposure=public`.
6. Add HTTPRoutes attaching to `internet-gateway`.

## Adding a new app — tailnet-only (the common case)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <app-namespace>
spec:
  parentRefs:
    - { name: tailnet-gateway, namespace: gateway-system }
  hostnames: [<app>.oasis-control.<your-internal-domain>]
  rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs: [{ name: <service>, port: <port> }]
```

Wildcard CNAME `*.oasis-control.<your-internal-domain>` → `gw-oasis-control.tail50d0f2.ts.net` covers the hostname.

## Adding a new app — internet-exposed

```bash
kubectl label namespace <ns> networking.oasis-control/exposure=public
```

```yaml
spec:
  parentRefs:
    - { name: internet-gateway, namespace: gateway-system }
  hostnames: [<app>.<your-public-domain>]
  rules: [...]
```
