local g = import 'g.libsonnet';

local dashboard = g.dashboard;
local panel = g.panel;
local query = g.query;

local datasource = 'Prometheus';

// ====== Stat Queries (Row 0: Overview) ======
local totalNodesQuery =
  query.prometheus.new(datasource, 'count(kube_node_info)')
  + query.prometheus.withLegendFormat('Nodes');

local totalPodsRunningQuery =
  query.prometheus.new(datasource, 'sum(kube_pod_status_phase{phase="Running"})')
  + query.prometheus.withLegendFormat('Running');

local totalPodsPendingQuery =
  query.prometheus.new(datasource, 'sum(kube_pod_status_phase{phase="Pending"}) or vector(0)')
  + query.prometheus.withLegendFormat('Pending');

local totalPodsFailedQuery =
  query.prometheus.new(datasource, 'sum(kube_pod_status_phase{phase="Failed"}) or vector(0)')
  + query.prometheus.withLegendFormat('Failed');

local clusterCpuUsageQuery =
  query.prometheus.new(datasource, '1 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval]))')
  + query.prometheus.withLegendFormat('CPU Usage');

local clusterMemUsageQuery =
  query.prometheus.new(datasource, '1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)')
  + query.prometheus.withLegendFormat('Memory Usage');

// ====== Node CPU (Row 1) ======
local nodeCpuQuery =
  query.prometheus.new(
    datasource,
    '1 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])) by (instance)',
  )
  + query.prometheus.withLegendFormat('{{ instance }}');

// ====== Node Memory (Row 1) ======
local nodeMemQuery =
  query.prometheus.new(
    datasource,
    '1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)',
  )
  + query.prometheus.withLegendFormat('{{ instance }}');

// ====== Pod Restarts (Row 2) ======
local podRestartsQuery =
  query.prometheus.new(
    datasource,
    'topk(10, sum(increase(kube_pod_container_status_restarts_total[$__rate_interval])) by (namespace, pod))',
  )
  + query.prometheus.withLegendFormat('{{ namespace }}/{{ pod }}');

// ====== Pods by Namespace (Row 2) ======
local podsByNamespaceQuery =
  query.prometheus.new(
    datasource,
    'sum(kube_pod_status_phase{phase="Running"}) by (namespace)',
  )
  + query.prometheus.withLegendFormat('{{ namespace }}');

// ====== CPU Requests vs Usage (Row 3) ======
local cpuRequestsQuery =
  query.prometheus.new(
    datasource,
    'sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)',
  )
  + query.prometheus.withLegendFormat('{{ namespace }} requests');

local cpuUsageByNsQuery =
  query.prometheus.new(
    datasource,
    'sum(rate(container_cpu_usage_seconds_total{container!="", container!="POD"}[$__rate_interval])) by (namespace)',
  )
  + query.prometheus.withLegendFormat('{{ namespace }} actual');

// ====== Memory Requests vs Usage (Row 3) ======
local memRequestsQuery =
  query.prometheus.new(
    datasource,
    'sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)',
  )
  + query.prometheus.withLegendFormat('{{ namespace }} requests');

local memUsageByNsQuery =
  query.prometheus.new(
    datasource,
    'sum(container_memory_working_set_bytes{container!="", container!="POD"}) by (namespace)',
  )
  + query.prometheus.withLegendFormat('{{ namespace }} actual');

// ====== Node Disk Usage (Row 4) ======
local nodeDiskQuery =
  query.prometheus.new(
    datasource,
    '1 - (node_filesystem_avail_bytes{mountpoint="/", fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/", fstype!="tmpfs"})',
  )
  + query.prometheus.withLegendFormat('{{ instance }}');

// ====== Node Network (Row 4) ======
local nodeNetRxQuery =
  query.prometheus.new(
    datasource,
    'sum(rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|flannel.*|cali.*|cbr.*"}[$__rate_interval])) by (instance)',
  )
  + query.prometheus.withLegendFormat('{{ instance }} rx');

local nodeNetTxQuery =
  query.prometheus.new(
    datasource,
    'sum(rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|flannel.*|cali.*|cbr.*"}[$__rate_interval])) by (instance)',
  )
  + query.prometheus.withLegendFormat('{{ instance }} tx');

// ====== Dashboard ======
dashboard.new('Kubernetes Cluster Overview')
+ dashboard.withUid('k8s-cluster-overview')
+ dashboard.withDescription('Cluster-level monitoring: nodes, pods, resource usage')
+ dashboard.withTags(['kubernetes', 'cluster', 'infrastructure'])
+ dashboard.graphTooltip.withSharedCrosshair()
+ dashboard.withRefresh('30s')
+ dashboard.withPanels([

  // === Row 0: Stat panels ===
  panel.stat.new('Nodes')
  + panel.stat.queryOptions.withTargets([totalNodesQuery])
  + panel.stat.gridPos.withW(4) + panel.stat.gridPos.withH(4)
  + panel.stat.gridPos.withX(0) + panel.stat.gridPos.withY(0),

  panel.stat.new('Running Pods')
  + panel.stat.queryOptions.withTargets([totalPodsRunningQuery])
  + panel.stat.gridPos.withW(4) + panel.stat.gridPos.withH(4)
  + panel.stat.gridPos.withX(4) + panel.stat.gridPos.withY(0),

  panel.stat.new('Pending Pods')
  + panel.stat.queryOptions.withTargets([totalPodsPendingQuery])
  + panel.stat.gridPos.withW(4) + panel.stat.gridPos.withH(4)
  + panel.stat.gridPos.withX(8) + panel.stat.gridPos.withY(0),

  panel.stat.new('Failed Pods')
  + panel.stat.queryOptions.withTargets([totalPodsFailedQuery])
  + panel.stat.gridPos.withW(4) + panel.stat.gridPos.withH(4)
  + panel.stat.gridPos.withX(12) + panel.stat.gridPos.withY(0),

  panel.stat.new('Cluster CPU')
  + panel.stat.queryOptions.withTargets([clusterCpuUsageQuery])
  + panel.stat.standardOptions.withUnit('percentunit')
  + panel.stat.gridPos.withW(4) + panel.stat.gridPos.withH(4)
  + panel.stat.gridPos.withX(16) + panel.stat.gridPos.withY(0),

  panel.stat.new('Cluster Memory')
  + panel.stat.queryOptions.withTargets([clusterMemUsageQuery])
  + panel.stat.standardOptions.withUnit('percentunit')
  + panel.stat.gridPos.withW(4) + panel.stat.gridPos.withH(4)
  + panel.stat.gridPos.withX(20) + panel.stat.gridPos.withY(0),

  // === Row 1: Node CPU + Memory ===
  panel.timeSeries.new('Node CPU Usage')
  + panel.timeSeries.queryOptions.withTargets([nodeCpuQuery])
  + panel.timeSeries.standardOptions.withUnit('percentunit')
  + panel.timeSeries.standardOptions.withMax(1)
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(0) + panel.timeSeries.gridPos.withY(4),

  panel.timeSeries.new('Node Memory Usage')
  + panel.timeSeries.queryOptions.withTargets([nodeMemQuery])
  + panel.timeSeries.standardOptions.withUnit('percentunit')
  + panel.timeSeries.standardOptions.withMax(1)
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(12) + panel.timeSeries.gridPos.withY(4),

  // === Row 2: Pod Restarts + Pods by Namespace ===
  panel.timeSeries.new('Pod Restarts (top 10)')
  + panel.timeSeries.queryOptions.withTargets([podRestartsQuery])
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(0) + panel.timeSeries.gridPos.withY(12),

  panel.timeSeries.new('Running Pods by Namespace')
  + panel.timeSeries.queryOptions.withTargets([podsByNamespaceQuery])
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(12) + panel.timeSeries.gridPos.withY(12),

  // === Row 3: CPU + Memory Requests vs Actual ===
  panel.timeSeries.new('CPU: Requests vs Actual (by namespace)')
  + panel.timeSeries.queryOptions.withTargets([cpuRequestsQuery, cpuUsageByNsQuery])
  + panel.timeSeries.standardOptions.withUnit('short')
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(0) + panel.timeSeries.gridPos.withY(20),

  panel.timeSeries.new('Memory: Requests vs Actual (by namespace)')
  + panel.timeSeries.queryOptions.withTargets([memRequestsQuery, memUsageByNsQuery])
  + panel.timeSeries.standardOptions.withUnit('bytes')
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(12) + panel.timeSeries.gridPos.withY(20),

  // === Row 4: Disk + Network ===
  panel.timeSeries.new('Node Disk Usage')
  + panel.timeSeries.queryOptions.withTargets([nodeDiskQuery])
  + panel.timeSeries.standardOptions.withUnit('percentunit')
  + panel.timeSeries.standardOptions.withMax(1)
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(0) + panel.timeSeries.gridPos.withY(28),

  panel.timeSeries.new('Node Network I/O')
  + panel.timeSeries.queryOptions.withTargets([nodeNetRxQuery, nodeNetTxQuery])
  + panel.timeSeries.standardOptions.withUnit('Bps')
  + panel.timeSeries.gridPos.withW(12) + panel.timeSeries.gridPos.withH(8)
  + panel.timeSeries.gridPos.withX(12) + panel.timeSeries.gridPos.withY(28),
])
