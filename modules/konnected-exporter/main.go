package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	influxdb2 "github.com/influxdata/influxdb-client-go/v2"
	"github.com/influxdata/influxdb-client-go/v2/api"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/r3labs/sse"
)

const namespace = "konnected"

type (
	exporter struct {
		debug          bool
		clientEvents   *sse.Client
		clientDB       influxdb2.Client
		writeAPI       api.WriteAPIBlocking
		logger         *log.Logger
		mu             sync.RWMutex
		lastUpdate     time.Time
		lastAttempt    time.Time
		scrapeOK       bool
		Uptime         int
		DeviceID       string
		ESPHomeVersion string
		ProjectVersion string
		IPAddress      string
		LastState      map[string]point
	}

	point struct {
		value any
		time  time.Time
	}

	Ping struct {
		Uptime int `json:"uptime"`
	}

	State struct {
		NameID         string `json:"name_id"`
		ID             string `json:"id"`
		Domain         string `json:"domain"`
		Name           string `json:"name"`
		Icon           string `json:"icon"`
		EntityCategory int    `json:"entity_category"`
	}
	BinaryState struct {
		State
		Value        bool   `json:"value"`
		CurrentState string `json:"state"`
	}
	LightState struct {
		State
		Value        string   `json:"value"`
		Effect       string   `json:"effect"`
		EffectIndex  int      `json:"effect_index"`
		EffectCount  int      `json:"effect_count"`
		ColorMode    string   `json:"color_mode"`
		CurrentState string   `json:"state"`
		Effects      []string `json:"effects"`
	}
	UptimeState struct {
		State
		Value        float64 `json:"value"`
		CurrentState string  `json:"state"`
		Uom          string  `json:"uom"`
	}
	SwitchState struct {
		State
		Value        bool   `json:"value"`
		CurrentState string `json:"state"`
		AssumedState bool   `json:"assumed_state"`
	}
	TextState struct {
		State
		Value        string `json:"value"`
		CurrentState string `json:"state"`
	}
)

func newExporter(logger *log.Logger, eventsURL, dbURL, token, org, bucket string, debug bool) *exporter {
	db := influxdb2.NewClient(dbURL, token)
	return &exporter{
		logger:       logger,
		clientEvents: sse.NewClient(eventsURL),
		clientDB:     db,
		writeAPI:     db.WriteAPIBlocking(org, bucket),
		debug:        debug,
	}
}

func (e *exporter) Describe(ch chan<- *prometheus.Desc) {
	prometheus.DescribeByCollect(e, ch)
}

func (e *exporter) Collect(ch chan<- prometheus.Metric) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "uptime_seconds"),
			"Uptime of the device in seconds",
			nil, nil,
		),
		prometheus.GaugeValue,
		float64(e.Uptime),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "device_id"),
			"Device ID",
			[]string{"device_id"}, nil,
		),
		prometheus.GaugeValue,
		float64(1), // Dummy value for string metric
		e.DeviceID,
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "esphome_version"),
			"ESPHome Version",
			[]string{"esphome_version"}, nil,
		),
		prometheus.GaugeValue,
		float64(1), // Dummy value for string metric
		e.ESPHomeVersion,
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "projest_version"),
			"Projest Version",
			[]string{"projest_version"}, nil,
		),
		prometheus.GaugeValue,
		float64(1), // Dummy value for string metric
		e.ProjectVersion,
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "ip_address"),
			"IP Address",
			[]string{"ip_address"}, nil,
		),
		prometheus.GaugeValue,
		float64(1), // Dummy value for string metric
		e.IPAddress,
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_update_timestamp"),
			"Timestamp in milliseconds of the last successful update",
			nil, nil,
		),
		prometheus.GaugeValue,
		float64(e.lastUpdate.UnixMilli()),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_attempt_timestamp"),
			"Timestamp in milliseconds of the last update attempt",
			nil, nil,
		),
		prometheus.GaugeValue,
		float64(e.lastAttempt.UnixMilli()),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "scrape_ok"),
			"Whether the last scrape was successful",
			nil, nil,
		),
		prometheus.GaugeValue,
		func() float64 {
			if e.scrapeOK {
				return 1
			}
			return 0
		}(),
	)
	for nameID, state := range e.LastState {
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "", "entity_state_timestamp"),
				"Timestamp in milliseconds of the last state change for the entity",
				[]string{"name_id", "state"}, nil,
			),
			prometheus.GaugeValue,
			float64(state.time.UnixMilli()),
			nameID,
			fmt.Sprintf("%v", state.value),
		)
	}
}

func (e *exporter) Run(ctx context.Context) {
	if err := e.clientEvents.SubscribeWithContext(ctx, "", func(msg *sse.Event) {
		err := e.refresh(ctx, msg)
		e.mu.Lock()
		defer e.mu.Unlock()
		e.lastAttempt = time.Now()
		if err != nil {
			e.scrapeOK = false
			e.logger.Printf("Error processing event: %v\n", err)
		} else {
			e.scrapeOK = true
			e.lastUpdate = time.Now()
		}
	}); err != nil {
		e.logger.Printf("Error subscribing to events: %v\n", err)
	}
}

func (e *exporter) refresh(ctx context.Context, msg *sse.Event) error {
	switch string(msg.Event) {
	case "ping":
		if err := e.ping(msg); err != nil {
			return fmt.Errorf("error handling ping event: %w", err)
		}
	case "state":
		var state State
		if err := json.Unmarshal(msg.Data, &state); err != nil {
			return fmt.Errorf("error unmarshalling JSON: %w", err)
		}
		parts := strings.Split(state.NameID, "/")
		name := parts[len(parts)-1]
		switch parts[0] {
		case "binary_sensor":
			if err := e.binary_sensor(ctx, name, msg); err != nil {
				return fmt.Errorf("error handling binary_sensor event: %w", err)
			}
		case "light":
			if err := e.light(ctx, name, msg); err != nil {
				return fmt.Errorf("error handling light event: %w", err)
			}
		case "sensor":
			if err := e.sensor(name, msg); err != nil {
				return fmt.Errorf("error handling sensor event: %w", err)
			}
		case "switch":
			if err := e.switch_(name, msg); err != nil {
				return fmt.Errorf("error handling switch event: %w", err)
			}
		case "button":
			if err := e.button(name); err != nil {
				return fmt.Errorf("error handling button event: %w", err)
			}
		case "text_sensor":
			if err := e.text_sensor(name, msg); err != nil {
				return fmt.Errorf("error handling text_sensor event: %w", err)
			}
		default:
			return fmt.Errorf("unknown event type: %q", parts[0])
		}
	}
	return nil
}

func (e *exporter) ping(msg *sse.Event) error {
	var ping Ping
	if err := json.Unmarshal(msg.Data, &ping); err != nil {
		return fmt.Errorf("error unmarshalling JSON: %w", err)
	}
	if e.debug {
		e.logger.Printf("Received ping with uptime: %d seconds\n", ping.Uptime)
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	e.Uptime = ping.Uptime
	return nil
}

func (e *exporter) binary_sensor(ctx context.Context, name string, msg *sse.Event) error {
	var binaryState BinaryState
	if err := json.Unmarshal(msg.Data, &binaryState); err != nil {
		return fmt.Errorf("error unmarshalling JSON: %w", err)
	}
	if e.debug {
		e.logger.Printf("Received binary state update for %q: %q\n", name, binaryState.CurrentState)
	}
	now := time.Now()
	if err := e.writeAPI.WritePoint(ctx, influxdb2.NewPointWithMeasurement(name).AddField("value", binaryState.Value).SetTime(now)); err != nil {
		return fmt.Errorf("error writing point to InfluxDB for %q: %w", name, err)
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.LastState[binaryState.NameID].value != binaryState.Value {
		e.LastState[binaryState.NameID] = point{value: binaryState.Value, time: now}
	}
	return nil
}

func (e *exporter) light(ctx context.Context, name string, msg *sse.Event) error {
	var lightState LightState
	if err := json.Unmarshal(msg.Data, &lightState); err != nil {
		return fmt.Errorf("error unmarshalling JSON: %w", err)
	}
	if e.debug {
		e.logger.Printf("Received light state update for %q: %q\n", name, lightState.CurrentState)
	}
	now := time.Now()
	if err := e.writeAPI.WritePoint(ctx, influxdb2.NewPointWithMeasurement(name).AddField("value", lightState.Value).AddField("effect", lightState.Effect).AddField("color_mode", lightState.ColorMode).SetTime(now)); err != nil {
		return fmt.Errorf("error writing point to InfluxDB for %q: %w", name, err)
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.LastState[lightState.NameID].value != lightState.Value {
		e.LastState[lightState.NameID] = point{value: lightState.Value, time: now}
	}
	return nil
}

func (e *exporter) sensor(name string, msg *sse.Event) error {
	var uptimeState UptimeState
	if err := json.Unmarshal(msg.Data, &uptimeState); err != nil {
		return fmt.Errorf("error unmarshalling JSON: %w", err)
	}
	if e.debug {
		e.logger.Printf("Received sensor state update for %q: %f %q\n", name, uptimeState.Value, uptimeState.Uom)
	}
	if uptimeState.NameID == "sensor.uptime" {
		e.mu.Lock()
		defer e.mu.Unlock()
		e.Uptime = int(uptimeState.Value)
	}
	return nil
}

func (e *exporter) switch_(name string, msg *sse.Event) error {
	var switchState SwitchState
	if err := json.Unmarshal(msg.Data, &switchState); err != nil {
		return fmt.Errorf("error unmarshalling JSON: %w", err)
	}
	if e.debug {
		e.logger.Printf("Received switch state update for %q: %q\n", name, switchState.CurrentState)
	}
	return nil
}

func (e *exporter) button(name string) error {
	if e.debug {
		e.logger.Printf("Received button state update for %q\n", name)
	}
	return nil
}

func (e *exporter) text_sensor(name string, msg *sse.Event) error {
	var textState TextState
	if err := json.Unmarshal(msg.Data, &textState); err != nil {
		return fmt.Errorf("error unmarshalling JSON: %w", err)
	}
	if e.debug {
		e.logger.Printf("Received text state update for %q: %q\n", name, textState.Value)
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	switch strings.ToLower(name) {
	case "device id":
		e.DeviceID = textState.Value
	case "esphome version":
		e.ESPHomeVersion = textState.Value
	case "project version":
		e.ProjectVersion = textState.Value
	case "ethernet ip address":
		e.IPAddress = textState.Value
	default:
		return fmt.Errorf("unknown text sensor name: %q", name)
	}
	return nil
}

func readToken(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	key := strings.TrimSpace(string(content))
	if key == "" {
		return "", errors.New("token file is empty")
	}

	return key, nil
}

func main() {
	var (
		host        = flag.String("web.host", "127.0.0.1", "Host or IP address to listen on for Prometheus scrapes.")
		port        = flag.String("web.port", "9923", "TCP port to listen on for Prometheus scrapes.")
		eventsURL   = flag.String("events.url", "", "URL to subscribe to for receiving events.")
		dbURL       = flag.String("db.url", "", "InfluxDB URL.")
		dbTokenPath = flag.String("db.token-path", "/run/secrets/influxdb_token", "Path to file containing InfluxDB token.")
		dbOrg       = flag.String("db.org", "my-org", "InfluxDB organization.")
		dbBucket    = flag.String("db.bucket", "my-bucket", "InfluxDB bucket.")
		debug       = flag.Bool("debug", false, "Enable debug logging.")
	)
	logger := log.New(os.Stdout, "konnected-exporter: ", log.LstdFlags)
	flag.Parse()

	if *eventsURL == "" {
		logger.Fatal("events.url is required")
	}
	if *dbURL == "" {
		logger.Fatal("db.url is required")
	}

	token, err := readToken(*dbTokenPath)
	if err != nil {
		logger.Fatalf("Error reading InfluxDB token: %v", err)
	}
	exp := newExporter(logger, *eventsURL, *dbURL, token, *dbOrg, *dbBucket, *debug)

	ctx := context.Background()
	go exp.Run(ctx)

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
