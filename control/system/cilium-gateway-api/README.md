# Cilium Gateway API config

A `HelmChartConfig` CR consumed by RKE2's helm-controller to override the bundled `rke2-cilium` chart values. Enables the [Cilium Gateway API implementation](https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/), which registers a `cilium` `GatewayClass`.

When this is applied, RKE2's helm-controller patches the existing Cilium release in `kube-system`. Cilium pods restart with the new config; expect ~30s of network reconvergence.

The `Gateway` resource itself lives at `control/system/gateway/`.

## Bumping Cilium values

Edit `helmchartconfig.yml` and let Argo sync. The helm-controller diffs values and reconciles.

## Why HelmChartConfig vs vendored chart values

RKE2 owns the Cilium chart; the only supported override mechanism is `HelmChartConfig`. Trying to manage Cilium directly (a separate Argo helm Application) would fight RKE2's helm-controller — same anti-pattern documented in `control/system/README.md` for ingress-nginx.
