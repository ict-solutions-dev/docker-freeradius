# FreeRADIUS Prometheus Alerting Rules

This directory contains Prometheus alerting rules for monitoring FreeRADIUS server health and performance using the `freeradius_exporter`.

## Overview

The `freeradius_rules.yml` file defines a comprehensive set of alerting rules that monitor various aspects of FreeRADIUS operation, including service availability, request processing, error rates, and authentication performance.

## Alert Categories

### 1. Service Availability
- **FreeRADIUSDown**: Triggers when the FreeRADIUS service becomes unreachable
- **FreeRADIUSRestarted**: Detects when the FreeRADIUS service has been restarted
- **FreeRADIUSStatsError**: Alerts when there are errors in stats collection

### 2. Request Processing & Error Monitoring
- **FreeRADIUSHighAuthDroppedRequests**: Monitors authentication requests being dropped
- **FreeRADIUSHighAcctDroppedRequests**: Monitors accounting requests being dropped
- **FreeRADIUSHighInvalidRequests**: Tracks invalid request rates
- **FreeRADIUSHighMalformedRequests**: Monitors malformed request rates

### 3. Authentication Performance
- **FreeRADIUSHighAuthRejectRate**: Alerts when authentication rejection rate exceeds threshold
- **FreeRADIUSLowAuthSuccessRate**: Triggers when authentication success rate drops below acceptable levels

## Alert Thresholds

| Metric | Threshold | Duration | Severity |
|--------|-----------|----------|----------|
| Service Down | `freeradius_up == 0` | 30s | Critical |
| Auth Dropped Requests | > 1 req/s | 2m | Warning |
| Acct Dropped Requests | > 1 req/s | 2m | Warning |
| Invalid Requests | > 0.5 req/s | 2m | Warning |
| Malformed Requests | > 0.5 req/s | 2m | Warning |
| Auth Reject Rate | > 20% | 5m | Warning |
| Auth Success Rate | < 70% | 5m | Warning |
| Stats Error | Present | 1m | Critical |

## Expected Results

### When Alerts Fire

1. **Critical Alerts** (Immediate Action Required):
   - Service downtime notifications
   - Stats collection failures
   - Enables rapid response to service outages

2. **Warning Alerts** (Investigation Recommended):
   - Performance degradation notifications
   - Error rate increases
   - Authentication issues
   - Helps identify potential problems before they become critical

### Monitoring Benefits

- **Proactive Issue Detection**: Catch problems before users report them
- **Performance Baseline**: Establish normal operating parameters
- **Capacity Planning**: Identify when resources need scaling
- **Security Monitoring**: Detect unusual authentication patterns
- **SLA Compliance**: Monitor service availability and response times

### Integration with Alertmanager

These rules are designed to work with Prometheus Alertmanager for:
- **Notification Routing**: Send alerts to appropriate teams
- **Alert Grouping**: Combine related alerts to reduce noise
- **Silence Management**: Temporarily suppress known issues
- **Escalation**: Route critical alerts through multiple channels

## Usage

1. **Deploy Rules**: Copy `freeradius_rules.yml` to your Prometheus rules directory
2. **Configure Prometheus**: Ensure the rules file is included in your Prometheus configuration
3. **Set Up Alertmanager**: Configure notification channels for different severity levels
4. **Customize Thresholds**: Adjust thresholds based on your environment's baseline performance

## Customization

You may need to adjust thresholds based on your specific environment:

```yaml
# Example: Increase dropped request threshold for high-volume environments
expr: rate(freeradius_total_auth_dropped_requests[5m]) > 5  # Increased from 1
```

## Dependencies

- Prometheus server with FreeRADIUS exporter configured
- `freeradius_exporter` collecting metrics from FreeRADIUS
- Alertmanager for notification delivery (recommended)

## Metrics Monitored

The rules monitor these key FreeRADIUS exporter metrics:
- `freeradius_up`: Service availability
- `freeradius_start_time`: Service restart detection
- `freeradius_stats_error`: Stats collection health
- `freeradius_total_*_dropped_requests`: Request drop rates
- `freeradius_total_*_invalid_requests`: Invalid request rates
- `freeradius_total_*_malformed_requests`: Malformed request rates
- `freeradius_total_access_*`: Authentication performance metrics

## Troubleshooting

If alerts are not firing as expected:
1. Verify the FreeRADIUS exporter is running and accessible
2. Check Prometheus is scraping the exporter successfully
3. Confirm the rules file is loaded in Prometheus configuration
4. Review Prometheus logs for rule evaluation errors
