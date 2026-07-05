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

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const namespace = "shelly"

// Health represents the health check response.
type Health struct {
	Ok         bool   `json:"ok"`
	Uptime     int64  `json:"uptime"`
	MQTTBroker string `json:"mqtt_broker,omitempty"`
	MQTTTopic  string `json:"mqtt_topic,omitempty"`
	Error      string `json:"error,omitempty"`
}

// SwitchStatus mirrors the "switch:*" JSON object from a Shelly Gen2 status message.
type SwitchStatus struct {
	Output  bool    `json:"output"`
	Apower  float64 `json:"apower"`
	Voltage float64 `json:"voltage"`
	Current float64 `json:"current"`
	Aenergy struct {
		Total float64 `json:"total"`
	} `json:"aenergy"`
	Temperature struct {
		TC float64 `json:"tC"`
	} `json:"temperature"`
}

// exporter implements prometheus.Collector and holds all runtime state.
type exporter struct {
	debug      bool
	logger     *log.Logger
	started    time.Time
	mqttBroker string
	mqttTopic  string
	clientID   string
	username   string
	password   string

	statusPollInterval time.Duration
	publishOnce        sync.Once
	knownDevices       map[string]struct{}

	mu          sync.RWMutex
	lastUpdate  time.Time
	lastAttempt time.Time
	scrapeOK    bool
	connected   bool
	lastError   string

	devices map[string]*deviceState
}

type deviceState struct {
	DeviceID    string
	SwitchID    string
	Output      float64
	Apower      float64
	Voltage     float64
	Current     float64
	EnergyTotal float64
	TempCelsius float64
	Updated     time.Time
}

func newExporter(logger *log.Logger, mqttBroker, mqttClientID, mqttTopic, mqttUser, mqttPass string, debug bool, pollInterval time.Duration) *exporter {
	return &exporter{
		logger:             logger,
		started:            time.Now(),
		mqttBroker:         mqttBroker,
		mqttTopic:          mqttTopic,
		clientID:           mqttClientID,
		username:           mqttUser,
		password:           mqttPass,
		debug:              debug,
		statusPollInterval: pollInterval,
		knownDevices:       make(map[string]struct{}),
		devices:            make(map[string]*deviceState),
	}
}

// Describe implements prometheus.Collector.
func (e *exporter) Describe(ch chan<- *prometheus.Desc) {
	prometheus.DescribeByCollect(e, ch)
}

// Collect implements prometheus.Collector (unchanged).
func (e *exporter) Collect(ch chan<- prometheus.Metric) {
	e.mu.RLock()
	defer e.mu.RUnlock()

	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "connected"),
			"Whether the exporter is connected to the MQTT broker.",
			nil, nil,
		),
		prometheus.GaugeValue,
		func() float64 {
			if e.connected {
				return 1
			}
			return 0
		}(),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "scrape_ok"),
			"Whether the last scrape was successful.",
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
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_update_timestamp"),
			"Timestamp in milliseconds of the last successful update.",
			nil, nil,
		),
		prometheus.GaugeValue,
		float64(e.lastUpdate.UnixMilli()),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_attempt_timestamp"),
			"Timestamp in milliseconds of the last update attempt.",
			nil, nil,
		),
		prometheus.GaugeValue,
		float64(e.lastAttempt.UnixMilli()),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "uptime_seconds"),
			"Uptime of the exporter in seconds.",
			nil, nil,
		),
		prometheus.GaugeValue,
		time.Since(e.started).Seconds(),
	)

	// Per-device switch metrics.
	for _, ds := range e.devices {
		labels := []string{"device_id", "switch_id"}
		lv := []string{ds.DeviceID, ds.SwitchID}

		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "output"),
				"Relay state (1 = on, 0 = off).",
				labels, nil,
			),
			prometheus.GaugeValue,
			ds.Output,
			lv...,
		)
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "apower_watts"),
				"Active power in watts.",
				labels, nil,
			),
			prometheus.GaugeValue,
			ds.Apower,
			lv...,
		)
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "voltage_volts"),
				"Supply voltage in volts.",
				labels, nil,
			),
			prometheus.GaugeValue,
			ds.Voltage,
			lv...,
		)
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "current_amps"),
				"Current in amperes.",
				labels, nil,
			),
			prometheus.GaugeValue,
			ds.Current,
			lv...,
		)
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "energy_total_watthours"),
				"Total consumed energy in watt-hours (cumulative).",
				labels, nil,
			),
			prometheus.GaugeValue,
			ds.EnergyTotal,
			lv...,
		)
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "temperature_celsius"),
				"Internal temperature in degrees Celsius.",
				labels, nil,
			),
			prometheus.GaugeValue,
			ds.TempCelsius,
			lv...,
		)
		ch <- prometheus.MustNewConstMetric(
			prometheus.NewDesc(
				prometheus.BuildFQName(namespace, "switch", "updated_timestamp"),
				"Timestamp in milliseconds of the last update for this device/switch.",
				labels, nil,
			),
			prometheus.GaugeValue,
			float64(ds.Updated.UnixMilli()),
			lv...,
		)
	}
}

// parseAndUpdate processes an incoming MQTT status message.
func (e *exporter) parseAndUpdate(topic string, payload []byte) {
	now := time.Now()

	e.mu.Lock()
	e.lastAttempt = now
	e.mu.Unlock()

	parts := strings.Split(topic, "/")
	var deviceID string
	if len(parts) >= 2 && parts[len(parts)-1] == "status" {
		deviceID = parts[len(parts)-2]
	} else {
		if len(parts) >= 2 {
			deviceID = parts[1]
		} else {
			e.setError(fmt.Sprintf("invalid topic format: %s", topic))
			return
		}
	}

	e.mu.Lock()
	e.knownDevices[deviceID] = struct{}{}
	e.mu.Unlock()

	var raw map[string]json.RawMessage
	if err := json.Unmarshal(payload, &raw); err != nil {
		e.setError(fmt.Sprintf("failed to parse JSON from %s: %v", deviceID, err))
		return
	}

	e.mu.Lock()
	defer e.mu.Unlock()

	updated := false
	for key, value := range raw {
		if !strings.HasPrefix(key, "switch:") {
			continue
		}
		switchID := strings.TrimPrefix(key, "switch:")
		var sw SwitchStatus
		if err := json.Unmarshal(value, &sw); err != nil {
			e.logger.Printf("Failed to parse switch data for %s/%s: %v", deviceID, switchID, err)
			continue
		}

		dsKey := deviceID + "/" + switchID
		outputVal := 0.0
		if sw.Output {
			outputVal = 1.0
		}

		e.devices[dsKey] = &deviceState{
			DeviceID:    deviceID,
			SwitchID:    switchID,
			Output:      outputVal,
			Apower:      sw.Apower,
			Voltage:     sw.Voltage,
			Current:     sw.Current,
			EnergyTotal: sw.Aenergy.Total,
			TempCelsius: sw.Temperature.TC,
			Updated:     now,
		}
		updated = true

		if e.debug {
			e.logger.Printf("Updated %s/%s: output=%.0f apower=%.1fW voltage=%.1fV current=%.2fA energy=%.0fWh temp=%.1f°C",
				deviceID, switchID, outputVal, sw.Apower, sw.Voltage, sw.Current, sw.Aenergy.Total, sw.Temperature.TC)
		}
	}

	if updated {
		e.scrapeOK = true
		e.lastUpdate = now
		e.lastError = ""
	} else {
		e.setError(fmt.Sprintf("no switch data found in message from %s", deviceID))
	}
}

func (e *exporter) setError(msg string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.scrapeOK = false
	e.lastError = msg
	e.logger.Printf("Error: %s", msg)
}

func (e *exporter) publishUpdates(ctx context.Context, client mqtt.Client) {
	ticker := time.NewTicker(e.statusPollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			e.mu.RLock()
			devices := make([]string, 0, len(e.knownDevices))
			for id := range e.knownDevices {
				devices = append(devices, id)
			}
			e.mu.RUnlock()

			for _, deviceID := range devices {
				topic := deviceID + "/command"
				if e.debug {
					e.logger.Printf("Sending status_update to %s", topic)
				}
				tok := client.Publish(topic, 0, false, "status_update")
				tok.Wait()
				if tok.Error() != nil {
					e.logger.Printf("Failed to publish to %s: %v", topic, tok.Error())
				}
			}
		}
	}
}

// Run connects to the MQTT broker and processes messages until ctx is cancelled.
func (e *exporter) Run(ctx context.Context) {
	opts := mqtt.NewClientOptions()
	opts.AddBroker(e.mqttBroker)
	opts.SetClientID(e.clientID)
	opts.SetAutoReconnect(true)
	opts.SetConnectRetry(true)
	opts.SetMaxReconnectInterval(30 * time.Second)
	if e.username != "" {
		opts.SetUsername(e.username)
	}
	if e.password != "" {
		opts.SetPassword(e.password)
	}
	opts.SetOnConnectHandler(func(c mqtt.Client) {
		e.mu.Lock()
		e.connected = true
		e.lastError = ""
		e.mu.Unlock()
		e.logger.Printf("Connected to MQTT broker, subscribing to %s", e.mqttTopic)
		if token := c.Subscribe(e.mqttTopic, 0, func(_ mqtt.Client, m mqtt.Message) {
			e.parseAndUpdate(m.Topic(), m.Payload())
		}); token.Wait() && token.Error() != nil {
			e.logger.Printf("Subscribe error: %v", token.Error())
		}
	})
	opts.SetConnectionLostHandler(func(_ mqtt.Client, err error) {
		e.mu.Lock()
		e.connected = false
		e.lastError = err.Error()
		e.mu.Unlock()
		e.logger.Printf("MQTT connection lost: %v", err)
	})

	client := mqtt.NewClient(opts)
	for {
		select {
		case <-ctx.Done():
			e.logger.Println("Shutting down MQTT client")
			client.Disconnect(250)
			return
		default:
			if token := client.Connect(); token.Wait() && token.Error() != nil {
				e.mu.Lock()
				e.connected = false
				e.lastError = token.Error().Error()
				e.mu.Unlock()
				e.logger.Printf("MQTT connection failed: %v (retrying in 5s)", token.Error())
				time.Sleep(5 * time.Second)
				continue
			}
			e.publishOnce.Do(func() {
				go e.publishUpdates(ctx, client)
				e.logger.Printf("Status polling started every %s", e.statusPollInterval)
			})

			<-ctx.Done()
			client.Disconnect(250)
			return
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
		host         = flag.String("web.host", "127.0.0.1", "Host or IP address to listen on for Prometheus scrapes.")
		port         = flag.String("web.port", "9090", "TCP port to listen on for Prometheus scrapes.")
		mqttBroker   = flag.String("mqtt.broker", "tcp://localhost:1883", "MQTT broker address.")
		mqttClientID = flag.String("mqtt.client-id", "shelly-exporter", "MQTT client ID.")
		mqttTopic    = flag.String("mqtt.topic", "+/status", "MQTT topic to subscribe to (use + for device ID).")
		mqttUser     = flag.String("mqtt.user", "", "MQTT username.")
		mqttPassPath = flag.String("mqtt.password-path", "", "Path to file containing MQTT password (takes precedence over --mqtt.password).")
		pollInterval = flag.Duration("status.poll-interval", 10*time.Second, "Interval between status_update commands.")
		debug        = flag.Bool("debug", false, "Enable debug logging.")
	)

	logger := log.New(os.Stdout, "shelly-exporter: ", log.LstdFlags)
	flag.Parse()

	password, err := readToken(*mqttPassPath)
	if err != nil {
		logger.Fatalf("Error reading MQTT password file: %v", err)
	}

	exp := newExporter(logger, *mqttBroker, *mqttClientID, *mqttTopic, *mqttUser, password, *debug, *pollInterval)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go exp.Run(ctx)

	registry := prometheus.NewRegistry()
	registry.MustRegister(exp)

	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.HandlerFor(registry, promhttp.HandlerOpts{
		Registry: registry,
	}))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		exp.mu.RLock()
		defer exp.mu.RUnlock()

		health := Health{
			Ok:         exp.connected && exp.scrapeOK,
			Uptime:     int64(time.Since(exp.started).Seconds()),
			MQTTBroker: exp.mqttBroker,
			MQTTTopic:  exp.mqttTopic,
		}
		if exp.lastError != "" {
			health.Error = exp.lastError
		}

		if !health.Ok {
			w.WriteHeader(http.StatusServiceUnavailable)
		} else {
			w.WriteHeader(http.StatusOK)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(health)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(`<html>
            <head><title>Shelly MQTT Exporter</title></head>
            <body>
                <h1>Shelly MQTT Exporter</h1>
                <p><a href="/metrics">Metrics</a></p>
                <p><a href="/healthz">Health</a></p>
            </body>
        </html>`))
	})

	listenAddress := net.JoinHostPort(*host, *port)
	logger.Printf("Listening on %s", listenAddress)
	logger.Fatal(http.ListenAndServe(listenAddress, mux))
}
