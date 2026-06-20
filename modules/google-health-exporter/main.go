package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"math"
	"net"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"google.golang.org/api/health/v4"
	"google.golang.org/api/option"
)

const namespace = "google_health"

var nonMetricChars = regexp.MustCompile(`[^a-zA-Z0-9_]+`)

type rollupMode string

const (
	rollupModePhysical rollupMode = "physical"
	rollupModeDaily    rollupMode = "daily"
)

type dataTypeConfig struct {
	DataType string
	Mode     rollupMode
}

type sample struct {
	DataType  string
	Mode      rollupMode
	Field     string
	StartTime string
	EndTime   string
	Value     float64
}

type exporter struct {
	client           *health.Service
	dataTypes        []dataTypeConfig
	interval         time.Duration
	requestTimeout   time.Duration
	lookback         time.Duration
	physicalWindow   time.Duration
	dailyWindowDays  int64
	dataSourceFamily string
	pageSize         int64
	logger           *log.Logger

	mu          sync.RWMutex
	lastUpdate  time.Time
	lastAttempt time.Time
	lastError   string
	scrapeOK    bool
	samples     []sample
}

func newExporter(client *health.Service, dataTypes []dataTypeConfig, interval time.Duration, requestTimeout time.Duration, lookback time.Duration, physicalWindow time.Duration, dailyWindowDays int64, dataSourceFamily string, pageSize int64, logger *log.Logger) *exporter {
	return &exporter{
		client:           client,
		dataTypes:        dataTypes,
		interval:         interval,
		requestTimeout:   requestTimeout,
		lookback:         lookback,
		physicalWindow:   physicalWindow,
		dailyWindowDays:  dailyWindowDays,
		dataSourceFamily: dataSourceFamily,
		pageSize:         pageSize,
		logger:           logger,
	}
}

func (e *exporter) Run() {
	e.refresh()

	ticker := time.NewTicker(e.interval)
	defer ticker.Stop()

	for range ticker.C {
		e.refresh()
	}
}

func (e *exporter) refresh() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.lastAttempt = time.Now()

	ctx, cancel := context.WithTimeout(context.Background(), e.requestTimeout)
	defer cancel()

	samples, err := e.collectSamples(ctx, e.lastAttempt)
	if err != nil {
		e.scrapeOK = false
		e.lastError = err.Error()
		e.logger.Printf("refresh failed: %v", err)
		return
	}

	e.samples = samples
	e.lastUpdate = time.Now()
	e.scrapeOK = true
	e.lastError = ""
}

func (e *exporter) collectSamples(ctx context.Context, now time.Time) ([]sample, error) {
	var samples []sample

	for _, cfg := range e.dataTypes {
		var (
			points []rollupPoint
			err    error
		)

		switch cfg.Mode {
		case rollupModePhysical:
			points, err = e.physicalRollup(ctx, cfg.DataType, now)
		case rollupModeDaily:
			points, err = e.dailyRollup(ctx, cfg.DataType, now)
		default:
			return nil, fmt.Errorf("unsupported rollup mode %q for data type %q", cfg.Mode, cfg.DataType)
		}
		if err != nil {
			return nil, fmt.Errorf("%s %s rollup: %w", cfg.DataType, cfg.Mode, err)
		}

		for _, point := range points {
			values, err := flattenRollupValues(point.Raw)
			if err != nil {
				return nil, fmt.Errorf("%s %s flatten: %w", cfg.DataType, cfg.Mode, err)
			}
			for _, value := range values {
				samples = append(samples, sample{
					DataType:  cfg.DataType,
					Mode:      cfg.Mode,
					Field:     value.Field,
					StartTime: point.StartTime,
					EndTime:   point.EndTime,
					Value:     value.Value,
				})
			}
		}
	}

	return samples, nil
}

type rollupPoint struct {
	Raw       any
	StartTime string
	EndTime   string
}

func (e *exporter) physicalRollup(ctx context.Context, dataType string, now time.Time) ([]rollupPoint, error) {
	req := &health.RollUpDataPointsRequest{
		DataSourceFamily: e.dataSourceFamily,
		PageSize:         e.pageSize,
		Range: &health.Interval{
			StartTime: now.Add(-e.lookback).UTC().Format(time.RFC3339Nano),
			EndTime:   now.UTC().Format(time.RFC3339Nano),
		},
		WindowSize: formatGoogleDuration(e.physicalWindow),
	}

	parent := fmt.Sprintf("users/me/dataTypes/%s", dataType)
	var points []rollupPoint
	err := e.client.Users.DataTypes.DataPoints.RollUp(parent, req).Pages(ctx, func(resp *health.RollUpDataPointsResponse) error {
		for _, point := range resp.RollupDataPoints {
			points = append(points, rollupPoint{
				Raw:       point,
				StartTime: point.StartTime,
				EndTime:   point.EndTime,
			})
		}
		return nil
	})
	return points, err
}

func (e *exporter) dailyRollup(ctx context.Context, dataType string, now time.Time) ([]rollupPoint, error) {
	start := now.Add(-e.lookback)
	req := &health.DailyRollUpDataPointsRequest{
		DataSourceFamily: e.dataSourceFamily,
		PageSize:         e.pageSize,
		Range: &health.CivilTimeInterval{
			Start: civilDate(start),
			End:   civilDate(now.AddDate(0, 0, 1)),
		},
		WindowSizeDays: e.dailyWindowDays,
	}

	parent := fmt.Sprintf("users/me/dataTypes/%s", dataType)
	resp, err := e.client.Users.DataTypes.DataPoints.DailyRollUp(parent, req).Context(ctx).Do()
	if err != nil {
		return nil, err
	}

	points := make([]rollupPoint, 0, len(resp.RollupDataPoints))
	for _, point := range resp.RollupDataPoints {
		points = append(points, rollupPoint{
			Raw:       point,
			StartTime: formatCivilDateTime(point.CivilStartTime),
			EndTime:   formatCivilDateTime(point.CivilEndTime),
		})
	}
	return points, nil
}

func civilDate(t time.Time) *health.CivilDateTime {
	t = t.Local()
	return &health.CivilDateTime{
		Date: &health.Date{
			Year:  int64(t.Year()),
			Month: int64(t.Month()),
			Day:   int64(t.Day()),
		},
	}
}

func formatCivilDateTime(dt *health.CivilDateTime) string {
	if dt == nil || dt.Date == nil {
		return ""
	}
	return fmt.Sprintf("%04d-%02d-%02d", dt.Date.Year, dt.Date.Month, dt.Date.Day)
}

func (e *exporter) Describe(ch chan<- *prometheus.Desc) {
	prometheus.DescribeByCollect(e, ch)
}

func (e *exporter) Collect(ch chan<- prometheus.Metric) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "up"),
			"Whether the last Google Health refresh succeeded.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		boolFloat(e.scrapeOK),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_refresh_timestamp"),
			"Unix timestamp in milliseconds of the last successful Google Health refresh.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		float64(e.lastUpdate.UnixMilli()),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_refresh_attempt_timestamp"),
			"Unix timestamp in milliseconds of the last attempted Google Health refresh.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		float64(e.lastAttempt.UnixMilli()),
	)

	if !e.scrapeOK {
		return
	}

	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "rollup_samples"),
			"Number of Google Health rollup samples currently exported.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		float64(len(e.samples)),
	)

	desc := prometheus.NewDesc(
		prometheus.BuildFQName(namespace, "", "rollup_value"),
		"Numeric value returned by a Google Health rollup.",
		[]string{"data_type", "rollup_mode", "field", "start_time", "end_time"},
		nil,
	)
	for _, sample := range e.samples {
		ch <- prometheus.MustNewConstMetric(
			desc,
			prometheus.GaugeValue,
			sample.Value,
			sample.DataType,
			string(sample.Mode),
			sample.Field,
			sample.StartTime,
			sample.EndTime,
		)
	}
}

type metricValue struct {
	Field string
	Value float64
}

func flattenRollupValues(v any) ([]metricValue, error) {
	content, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}

	var decoded map[string]any
	if err := json.Unmarshal(content, &decoded); err != nil {
		return nil, err
	}

	for _, field := range []string{"startTime", "endTime", "civilStartTime", "civilEndTime"} {
		delete(decoded, field)
	}

	var values []metricValue
	flattenJSON("", decoded, &values)
	return values, nil
}

func flattenJSON(prefix string, v any, values *[]metricValue) {
	switch typed := v.(type) {
	case map[string]any:
		for key, value := range typed {
			name := sanitizeMetricPart(key)
			if prefix != "" {
				name = prefix + "_" + name
			}
			flattenJSON(name, value, values)
		}
	case []any:
		for i, value := range typed {
			flattenJSON(fmt.Sprintf("%s_%d", prefix, i), value, values)
		}
	case float64:
		if !math.IsNaN(typed) && !math.IsInf(typed, 0) {
			*values = append(*values, metricValue{Field: prefix, Value: typed})
		}
	case bool:
		*values = append(*values, metricValue{Field: prefix, Value: boolFloat(typed)})
	case string:
		if number, ok := parseNumericString(typed); ok {
			*values = append(*values, metricValue{Field: prefix, Value: number})
		} else if seconds, ok := parseGoogleDuration(typed); ok {
			*values = append(*values, metricValue{Field: prefix + "_seconds", Value: seconds})
		}
	}
}

func sanitizeMetricPart(s string) string {
	s = camelToSnake(s)
	s = nonMetricChars.ReplaceAllString(s, "_")
	return strings.Trim(s, "_")
}

func camelToSnake(s string) string {
	var out strings.Builder
	for i, r := range s {
		if i > 0 && r >= 'A' && r <= 'Z' {
			out.WriteByte('_')
		}
		out.WriteRune(r)
	}
	return strings.ToLower(out.String())
}

func formatGoogleDuration(d time.Duration) string {
	seconds := d.Seconds()
	if seconds == math.Trunc(seconds) {
		return fmt.Sprintf("%.0fs", seconds)
	}
	return fmt.Sprintf("%.9fs", seconds)
}

func parseGoogleDuration(s string) (float64, bool) {
	if !strings.HasSuffix(s, "s") {
		return 0, false
	}
	seconds, err := strconv.ParseFloat(strings.TrimSuffix(s, "s"), 64)
	return seconds, err == nil
}

func parseNumericString(s string) (float64, bool) {
	if strings.TrimSpace(s) != s || s == "" {
		return 0, false
	}
	number, err := strconv.ParseFloat(s, 64)
	if err != nil || math.IsNaN(number) || math.IsInf(number, 0) {
		return 0, false
	}
	return number, true
}

func boolFloat(v bool) float64 {
	if v {
		return 1
	}
	return 0
}

func parseDataTypes(raw string, defaultMode rollupMode) ([]dataTypeConfig, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, errors.New("at least one data type is required")
	}

	var configs []dataTypeConfig
	for _, part := range strings.Split(raw, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		cfg := dataTypeConfig{
			DataType: part,
			Mode:     defaultMode,
		}
		if before, after, ok := strings.Cut(part, ":"); ok {
			cfg.DataType = strings.TrimSpace(before)
			cfg.Mode = rollupMode(strings.TrimSpace(after))
		}
		if cfg.DataType == "" {
			return nil, fmt.Errorf("invalid data type %q", part)
		}
		if cfg.Mode != rollupModePhysical && cfg.Mode != rollupModeDaily {
			return nil, fmt.Errorf("invalid rollup mode %q for data type %q", cfg.Mode, cfg.DataType)
		}
		configs = append(configs, cfg)
	}
	if len(configs) == 0 {
		return nil, errors.New("at least one data type is required")
	}
	return configs, nil
}

func normalizeDataSourceFamily(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if strings.HasPrefix(raw, "users/") {
		return raw
	}
	return "users/me/dataSourceFamilies/" + raw
}

func parseCredentialsType(raw string) (option.CredentialsType, error) {
	switch strings.TrimSpace(raw) {
	case "authorized-user", "authorized_user":
		return option.AuthorizedUser, nil
	case "service-account", "service_account":
		return option.ServiceAccount, nil
	case "impersonated-service-account", "impersonated_service_account":
		return option.ImpersonatedServiceAccount, nil
	case "external-account", "external_account":
		return option.ExternalAccount, nil
	default:
		return "", fmt.Errorf("unsupported credentials type %q", raw)
	}
}

func main() {
	var (
		host             = flag.String("web.host", "127.0.0.1", "Host or IP address to listen on for Prometheus scrapes.")
		port             = flag.String("web.port", "9878", "TCP port to listen on for Prometheus scrapes.")
		credentialsFile  = flag.String("credentials-file", "", "File containing Google credentials JSON.")
		credentialsType  = flag.String("credentials-type", "authorized-user", "Credential file type. Valid values: authorized-user, service-account, impersonated-service-account, external-account.")
		dataTypesFlag    = flag.String("data-types", "steps:daily,distance:daily,active-energy-burned:daily,total-calories:daily", "Comma-separated Google Health data types to roll up. Append :daily or :physical to override the default rollup mode for an item.")
		defaultModeFlag  = flag.String("default-rollup-mode", string(rollupModeDaily), "Default rollup mode for data types without an explicit suffix. Valid values: daily, physical.")
		refresh          = flag.Duration("refresh-interval", 10*time.Minute, "Refresh interval used to poll Google Health.")
		requestTimeout   = flag.Duration("request-timeout", 30*time.Second, "Timeout for each Google Health refresh.")
		lookback         = flag.Duration("lookback", 24*time.Hour, "How far back each Google Health rollup request should query.")
		physicalWindow   = flag.Duration("physical-window", time.Hour, "Aggregation window for physical rollups.")
		dailyWindowDays  = flag.Int64("daily-window-days", 1, "Aggregation window size in days for daily rollups.")
		dataSourceFamily = flag.String("data-source-family", "all-sources", "Google Health data source family to roll up, or empty for the API default.")
		pageSize         = flag.Int64("page-size", 10000, "Maximum rollup data points to request per page.")
	)

	flag.Parse()

	defaultMode := rollupMode(*defaultModeFlag)
	if defaultMode != rollupModeDaily && defaultMode != rollupModePhysical {
		log.Fatalf("invalid --default-rollup-mode %q", *defaultModeFlag)
	}

	if *dailyWindowDays < 1 {
		log.Fatal("--daily-window-days must be at least 1")
	}

	if *refresh <= 0 {
		log.Fatal("--refresh-interval must be greater than 0")
	}

	if *requestTimeout <= 0 {
		log.Fatal("--request-timeout must be greater than 0")
	}

	if *lookback <= 0 {
		log.Fatal("--lookback must be greater than 0")
	}

	if *physicalWindow <= 0 {
		log.Fatal("--physical-window must be greater than 0")
	}

	if *pageSize < 1 {
		log.Fatal("--page-size must be at least 1")
	}

	dataTypes, err := parseDataTypes(*dataTypesFlag, defaultMode)
	if err != nil {
		log.Fatalf("parsing data types: %v", err)
	}

	ctx := context.Background()
	opts := []option.ClientOption{
		option.WithScopes(
			health.GooglehealthActivityAndFitnessReadonlyScope,
			health.GooglehealthEcgReadonlyScope,
			health.GooglehealthHealthMetricsAndMeasurementsReadonlyScope,
			health.GooglehealthIrnReadonlyScope,
			health.GooglehealthLocationReadonlyScope,
			health.GooglehealthProfileReadonlyScope,
			health.GooglehealthSettingsReadonlyScope,
			health.GooglehealthSleepReadonlyScope,
		),
	}
	if *credentialsFile != "" {
		credType, err := parseCredentialsType(*credentialsType)
		if err != nil {
			log.Fatalf("parsing credentials type: %v", err)
		}
		opts = append(opts, option.WithAuthCredentialsFile(credType, *credentialsFile))
	}

	client, err := health.NewService(ctx, opts...)
	if err != nil {
		log.Fatalf("creating Google Health client: %v", err)
	}

	logger := log.New(os.Stdout, "google-health-exporter: ", log.LstdFlags)
	exp := newExporter(
		client,
		dataTypes,
		*refresh,
		*requestTimeout,
		*lookback,
		*physicalWindow,
		*dailyWindowDays,
		normalizeDataSourceFamily(*dataSourceFamily),
		*pageSize,
		logger,
	)

	go exp.Run()

	registry := prometheus.NewRegistry()
	registry.MustRegister(exp)

	http.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	listenAddress := net.JoinHostPort(*host, *port)
	logger.Printf("listening on %s", listenAddress)
	log.Fatal(http.ListenAndServe(listenAddress, nil))
}
