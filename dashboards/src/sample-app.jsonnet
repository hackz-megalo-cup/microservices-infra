local g = import 'g.libsonnet';

local dashboard = g.dashboard;
local panel = g.panel;
local query = g.query;

local datasource = 'Prometheus';

// -- Queries --
local requestRateQuery =
  query.prometheus.new(
    datasource,
    'sum(rate(sample_app_requests_total{job="sample-app"}[$__rate_interval])) by (endpoint)',
  )
  + query.prometheus.withLegendFormat('{{ endpoint }}');

local httpDurationP99Query =
  query.prometheus.new(
    datasource,
    'histogram_quantile(0.99, sum(rate(http_server_duration_milliseconds_bucket{job="sample-app"}[$__rate_interval])) by (le))',
  )
  + query.prometheus.withLegendFormat('p99');

local httpDurationP50Query =
  query.prometheus.new(
    datasource,
    'histogram_quantile(0.50, sum(rate(http_server_duration_milliseconds_bucket{job="sample-app"}[$__rate_interval])) by (le))',
  )
  + query.prometheus.withLegendFormat('p50');

local errorRateQuery =
  query.prometheus.new(
    datasource,
    'sum(rate(http_server_duration_milliseconds_count{job="sample-app", http_status_code=~"5.."}[$__rate_interval])) / sum(rate(http_server_duration_milliseconds_count{job="sample-app"}[$__rate_interval]))',
  )
  + query.prometheus.withLegendFormat('Error Rate');

local totalRequestsQuery =
  query.prometheus.new(
    datasource,
    'sum(rate(http_server_duration_milliseconds_count{job="sample-app"}[$__rate_interval]))',
  )
  + query.prometheus.withLegendFormat('Total RPS');

// -- Dashboard --
dashboard.new('Sample App Overview')
+ dashboard.withUid('sample-app-overview')
+ dashboard.withDescription('Observability dashboard for the sample-app (OTel instrumented)')
+ dashboard.withTags(['sample-app', 'otel'])
+ dashboard.graphTooltip.withSharedCrosshair()
+ dashboard.withRefresh('30s')
+ dashboard.withPanels([
  // Row 1: Request Rate + Error Rate
  panel.timeSeries.new('Request Rate')
  + panel.timeSeries.queryOptions.withTargets([requestRateQuery])
  + panel.timeSeries.standardOptions.withUnit('reqps')
  + panel.timeSeries.gridPos.withW(12)
  + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(0)
  + panel.timeSeries.gridPos.withY(0),

  panel.timeSeries.new('Error Rate')
  + panel.timeSeries.queryOptions.withTargets([errorRateQuery])
  + panel.timeSeries.standardOptions.withUnit('percentunit')
  + panel.timeSeries.gridPos.withW(12)
  + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(12)
  + panel.timeSeries.gridPos.withY(0),

  // Row 2: Latency + Total RPS stat
  panel.timeSeries.new('HTTP Request Duration')
  + panel.timeSeries.queryOptions.withTargets([httpDurationP99Query, httpDurationP50Query])
  + panel.timeSeries.standardOptions.withUnit('ms')
  + panel.timeSeries.gridPos.withW(16)
  + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(0)
  + panel.timeSeries.gridPos.withY(8),

  panel.stat.new('Total Request Rate')
  + panel.stat.queryOptions.withTargets([totalRequestsQuery])
  + panel.stat.standardOptions.withUnit('reqps')
  + panel.stat.gridPos.withW(8)
  + panel.stat.gridPos.withH(8)
  + panel.stat.gridPos.withX(16)
  + panel.stat.gridPos.withY(8),
])
