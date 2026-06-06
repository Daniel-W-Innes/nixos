package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
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
		clientEvents   *sse.Client
		clientDB       influxdb2.Client
		writeAPI       api.WriteAPIBlocking
		logger         *log.Logger
		mu             sync.RWMutex
		lastUpdate     time.Time
		lastAttempt    time.Time
		lastError      string
		scrapeOK       bool
		Uptime         int
		DeviceID       string
		ESPHomeVersion string
		ProjestVersion string
		IPAddress      string
		debug          bool
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
		e.ProjestVersion,
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
}

func (e *exporter) Run(ctx context.Context) {
	e.clientEvents.SubscribeWithContext(ctx, "", func(msg *sse.Event) {
		e.refresh(ctx, msg)
	})
}

func (e *exporter) refresh(ctx context.Context, msg *sse.Event) {
	switch string(msg.Event) {
	case "ping":
		var ping Ping
		if err := json.Unmarshal(msg.Data, &ping); err != nil {
			e.logger.Printf("Error unmarshalling JSON: %v\n", err)
			return
		}
		if e.debug {
			e.logger.Printf("Received ping with uptime: %d seconds\n", ping.Uptime)
		}
		e.mu.Lock()
		defer e.mu.Unlock()
		e.Uptime = ping.Uptime
	case "state":
		var state State
		if err := json.Unmarshal(msg.Data, &state); err != nil {
			e.logger.Printf("Error unmarshalling JSON: %v\n", err)
			return
		}
		parts := strings.Split(state.NameID, "/")
		switch parts[0] {
		case "binary_sensor":
			var binaryState BinaryState
			if err := json.Unmarshal(msg.Data, &binaryState); err != nil {
				e.logger.Printf("Error unmarshalling JSON: %v\n", err)
				return
			}
			if e.debug {
				e.logger.Printf("Received binary state update for %s: %s\n", binaryState.Name, binaryState.CurrentState)
			}
			if err := e.writeAPI.WritePoint(ctx, influxdb2.NewPointWithMeasurement(binaryState.Name).AddField("value", binaryState.Value).SetTime(time.Now())); err != nil {
				e.logger.Printf("Error writing point to InfluxDB: %v, name: %s, value: %t\n", err, binaryState.Name, binaryState.Value)
			}
		case "light":
			var lightState LightState
			if err := json.Unmarshal(msg.Data, &lightState); err != nil {
				e.logger.Printf("Error unmarshalling JSON: %v\n", err)
				return
			}
			if e.debug {
				e.logger.Printf("Received light state update for %s: %s\n", lightState.Name, lightState.CurrentState)
			}
			if err := e.writeAPI.WritePoint(ctx, influxdb2.NewPointWithMeasurement(lightState.Name).AddField("value", lightState.Value).AddField("effect", lightState.Effect).AddField("color_mode", lightState.ColorMode).SetTime(time.Now())); err != nil {
				e.logger.Printf("Error writing point to InfluxDB: %v, name: %s, value: %s\n", err, lightState.Name, lightState.Value)
			}
		case "sensor":
			var uptimeState UptimeState
			if err := json.Unmarshal(msg.Data, &uptimeState); err != nil {
				e.logger.Printf("Error unmarshalling JSON: %v\n", err)
				return
			}
			if e.debug {
				e.logger.Printf("Received sensor state update for %s: %f %s\n", uptimeState.Name, uptimeState.Value, uptimeState.Uom)
			}
			if uptimeState.NameID == "sensor.uptime" {
				e.mu.Lock()
				defer e.mu.Unlock()
				e.Uptime = int(uptimeState.Value)
			}
		case "switch":
			var switchState SwitchState
			if err := json.Unmarshal(msg.Data, &switchState); err != nil {
				e.logger.Printf("Error unmarshalling JSON: %v\n", err)
				return
			}
			if e.debug {
				e.logger.Printf("Received switch state update for %s: %s\n", switchState.Name, switchState.CurrentState)
			}
		case "button":
			if e.debug {
				e.logger.Printf("Received button state update for %s\n", state.Name)
			}
		case "text_sensor":
			var textState TextState
			if err := json.Unmarshal(msg.Data, &textState); err != nil {
				e.logger.Printf("Error unmarshalling JSON: %v\n", err)
				return
			}
			if e.debug {
				e.logger.Printf("Received text state update for %s: %s\n", textState.Name, textState.Value)
			}
			e.mu.Lock()
			defer e.mu.Unlock()
			switch parts[1] {
			case "Device ID":
				e.DeviceID = textState.Value
			case "ESPHome Version":
				e.ESPHomeVersion = textState.Value
			case "Projest version":
				e.ProjestVersion = textState.Value
			case "Ethernet IP Address":
				e.IPAddress = textState.Value
			default:
				e.logger.Printf("Received text state update for unknown sensor: %s\n", textState.Name)
			}
		default:
			e.logger.Printf("Received state update for unknown entity type: %s\n", state.NameID)
		}
	}
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
