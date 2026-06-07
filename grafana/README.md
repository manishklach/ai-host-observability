# Grafana Dashboard

## Import Instructions

1. Open Grafana 10 or newer.
2. Go to `Dashboards` -> `New` -> `Import`.
3. Upload `grafana/ai-host-overview.json`.
4. Select your Prometheus datasource when Grafana prompts for `${datasource}`.

## Template Variables

The dashboard expects these template variables:

- `datasource`: Prometheus datasource selector
- `job`: `label_values(job)`
- `instance`: `label_values(instance)`
- `gpu_index`: `label_values(nixl_gpu_info, index)`

If your Prometheus setup uses different labels or relabeling rules, adjust the variables after import.

## Screenshot Placeholder

Add a screenshot of a populated dashboard here once you have live metrics:

```text
grafana/screenshot-ai-host-overview.png
```

## Publishing Note

This dashboard is intended to be publishable to [grafana.com/dashboards](https://grafana.com/dashboards) after a live screenshot and a short usage note are added.
