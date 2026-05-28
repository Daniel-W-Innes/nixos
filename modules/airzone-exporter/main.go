package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const (
	defaultBaseURL      = "https://m.airzonecloud.com/api/v1"
	defaultListenHost   = ""
	defaultListenPort   = 9922
	defaultMetricsPath  = "/metrics"
	exporterNamespace   = "airzone"
	deviceConfigType    = "user"
	rootPageContentType = "text/plain; charset=utf-8"
)

type exporterConfig struct {
	email         string
	passwordFile  string
	baseURL       string
	listenHost    string
	listenPort    int
	metricsPath   string
	timeout       time.Duration
}

type airzoneClient struct {
	baseURL      string
	email        string
	passwordFile string
	httpClient   *http.Client
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginResponse struct {
	Token        string          `json:"token"`
	RefreshToken string          `json:"refreshToken"`
	User         json.RawMessage `json:"user,omitempty"`
	Config       json.RawMessage `json:"config,omitempty"`
}

type installation struct {
	InstallationID string   `json:"installation_id"`
	LocationID     string   `json:"location_id"`
	Name           string   `json:"name"`
	AccessType     string   `json:"access_type"`
	WSIDs          []string `json:"ws_ids"`
}

type installationsResponse struct {
	Total                int            `json:"total"`
	PendingInstallations *int           `json:"pendingInstallations"`
	Installations        []installation `json:"installations"`
}

type installationDetail struct {
	ID               string              `json:"_id"`
	UserID           string              `json:"user_id"`
	InstallationID   string              `json:"installation_id"`
	LocationID       string              `json:"location_id"`
	ConfirmationDate *string             `json:"confirmation_date"`
	Groups           []installationGroup `json:"groups"`
	Name             string              `json:"name"`
	AccessType       string              `json:"access_type"`
}

type installationDetailsResponse struct {
	Total                int                  `json:"total"`
	PendingInstallations *int                 `json:"pendingInstallations"`
	Installations        []installationDetail `json:"installations"`
}

type installationGroup struct {
	GroupID string                    `json:"group_id"`
	Name    string                    `json:"name"`
	Icon    *int                      `json:"icon"`
	Devices []installationDeviceEntry `json:"devices"`
}

type installationDeviceEntry struct {
	DeviceID string          `json:"device_id"`
	Name     string          `json:"name"`
	Type     string          `json:"type"`
	Config   json.RawMessage `json:"config,omitempty"`
	WSID     string          `json:"ws_id"`
	Meta     json.RawMessage `json:"meta,omitempty"`
}

type deviceDetail struct {
	InstallationID string          `json:"installation_id"`
	Installation   string          `json:"installation"`
	GroupID        string          `json:"group_id"`
	GroupName      string          `json:"group_name"`
	DeviceID       string          `json:"device_id"`
	Name           string          `json:"name"`
	Type           string          `json:"type"`
	WSID           string          `json:"ws_id"`
	Meta           json.RawMessage `json:"meta,omitempty"`
	Status         json.RawMessage `json:"status"`
	Config         json.RawMessage `json:"config"`
}

type deviceDetailsResponse struct {
	TotalDevices int            `json:"totalDevices"`
	Devices      []deviceDetail `json:"devices"`
}

type apiErrorResponse struct {
	Errors json.RawMessage `json:"errors"`
}

type airzoneCollector struct {
	client                 *airzoneClient
	upDesc                 *prometheus.Desc
	durationDesc           *prometheus.Desc
	devicesDesc            *prometheus.Desc
	infoDesc               *prometheus.Desc
	powerDesc              *prometheus.Desc
	energyLastHourDesc     *prometheus.Desc
	connectedDesc          *prometheus.Desc
	wsConnectedDesc        *prometheus.Desc
	activeDesc             *prometheus.Desc
	airActiveDesc          *prometheus.Desc
	autoOverrideModeDesc   *prometheus.Desc
	ledsActiveDesc         *prometheus.Desc
	localVentDesc          *prometheus.Desc
	antifreezeDesc         *prometheus.Desc
	aqActiveDesc           *prometheus.Desc
	aqVentActiveDesc       *prometheus.Desc
	aqPresentDesc          *prometheus.Desc
	machineReadyDesc       *prometheus.Desc
	blockSetpointDesc      *prometheus.Desc
	blockOnDesc            *prometheus.Desc
	blockOffDesc           *prometheus.Desc
	powerfulModeDesc       *prometheus.Desc
	humidityRatioDesc      *prometheus.Desc
	modeDesc               *prometheus.Desc
	autoModeDesc           *prometheus.Desc
	speedConfDesc          *prometheus.Desc
	percentSpeedDesc       *prometheus.Desc
	sleepMinutesDesc       *prometheus.Desc
	timerMinutesDesc       *prometheus.Desc
	timerCountdownDesc     *prometheus.Desc
	localTempDesc          *prometheus.Desc
	workTempDesc           *prometheus.Desc
	zoneWorkTempDesc       *prometheus.Desc
	taiTempDesc            *prometheus.Desc
	returnTempDesc         *prometheus.Desc
	supplyAirTempDesc      *prometheus.Desc
	extractAirTempDesc     *prometheus.Desc
	outdoorAirTempDesc     *prometheus.Desc
	setpointTempDesc       *prometheus.Desc
	activeSetpointTempDesc *prometheus.Desc
	aqScoreDesc            *prometheus.Desc
	aqTVOCDesc             *prometheus.Desc
	aqCO2Desc              *prometheus.Desc
	aqPressureDesc         *prometheus.Desc
	aqPM10Desc             *prometheus.Desc
	aqPM25Desc             *prometheus.Desc
	aqPM1Desc              *prometheus.Desc
}

func main() {
	cfg := exporterConfig{}
	flag.StringVar(&cfg.email, "email", "", "Airzone account email")
	flag.StringVar(&cfg.passwordFile, "password-file", "", "Path to a file containing the Airzone account password")
	flag.StringVar(&cfg.baseURL, "base-url", defaultBaseURL, "Airzone API base URL")
	flag.StringVar(&cfg.listenHost, "listen-host", defaultListenHost, "Host or IP address to listen on for HTTP requests")
	flag.IntVar(&cfg.listenPort, "listen-port", defaultListenPort, "TCP port to listen on for HTTP requests")
	flag.StringVar(&cfg.metricsPath, "metrics-path", defaultMetricsPath, "HTTP path that serves Prometheus metrics")
	flag.DurationVar(&cfg.timeout, "timeout", 15*time.Second, "HTTP timeout for Airzone API requests")
	flag.Parse()

	if err := validateConfig(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}

	client := &airzoneClient{
		baseURL:      cfg.baseURL,
		email:        cfg.email,
		passwordFile: cfg.passwordFile,
		httpClient:   &http.Client{Timeout: cfg.timeout},
	}

	registry := prometheus.NewRegistry()
	registry.MustRegister(newAirzoneCollector(client))

	mux := http.NewServeMux()
	mux.Handle(cfg.metricsPath, promhttp.HandlerFor(registry, promhttp.HandlerOpts{}))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", rootPageContentType)
		_, _ = fmt.Fprintf(w, "Airzone exporter\nmetrics: %s\n", cfg.metricsPath)
	})

	server := &http.Server{
		Addr:              net.JoinHostPort(cfg.listenHost, fmt.Sprintf("%d", cfg.listenPort)),
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func validateConfig(cfg exporterConfig) error {
	if strings.TrimSpace(cfg.email) == "" {
		return errors.New("email is required")
	}
	if strings.TrimSpace(cfg.passwordFile) == "" {
		return errors.New("password-file is required")
	}
	if strings.TrimSpace(cfg.baseURL) == "" {
		return errors.New("base-url is required")
	}
	if cfg.listenPort < 1 || cfg.listenPort > 65535 {
		return errors.New("listen-port must be between 1 and 65535")
	}
	if strings.TrimSpace(cfg.metricsPath) == "" {
		return errors.New("metrics-path is required")
	}
	return nil
}

func newAirzoneCollector(client *airzoneClient) *airzoneCollector {
	deviceLabels := []string{"installation_id", "installation", "group_id", "group_name", "device_id", "device_name", "device_type", "ws_id"}

	return &airzoneCollector{
		client: client,
		upDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "", "up"),
			"Whether the last Airzone scrape succeeded.",
			nil,
			nil,
		),
		durationDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "", "scrape_duration_seconds"),
			"Duration of the last Airzone scrape.",
			nil,
			nil,
		),
		devicesDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "", "devices"),
			"Number of Airzone devices returned by the last successful scrape.",
			nil,
			nil,
		),
		infoDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "info"),
			"Static metadata about an Airzone device.",
			deviceLabels,
			nil,
		),
		powerDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "power_ratio"),
			"Whether the device power is on as a ratio.",
			deviceLabels,
			nil,
		),
		energyLastHourDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "energy_last_hour_kwh"),
			"Energy consumed during the last hour in kWh, reported by energy clamp devices.",
			deviceLabels,
			nil,
		),
		connectedDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "connected_ratio"),
			"Whether the device is connected as a ratio.",
			deviceLabels,
			nil,
		),
		wsConnectedDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "websocket_connected_ratio"),
			"Whether the device websocket connection is active as a ratio.",
			deviceLabels,
			nil,
		),
		activeDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "active_ratio"),
			"Whether the device is actively running as a ratio.",
			deviceLabels,
			nil,
		),
		airActiveDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_active_ratio"),
			"Whether the air stage of the device is active as a ratio.",
			deviceLabels,
			nil,
		),
		autoOverrideModeDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "auto_override_mode_enabled_ratio"),
			"Whether auto override mode is enabled as a ratio.",
			deviceLabels,
			nil,
		),
		ledsActiveDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "leds_active_ratio"),
			"Whether device LEDs are active as a ratio.",
			deviceLabels,
			nil,
		),
		localVentDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "local_vent_ratio"),
			"Whether local ventilation is active as a ratio.",
			deviceLabels,
			nil,
		),
		antifreezeDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "antifreeze_ratio"),
			"Whether antifreeze mode is enabled as a ratio.",
			deviceLabels,
			nil,
		),
		aqActiveDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_active_ratio"),
			"Whether air quality control is active as a ratio.",
			deviceLabels,
			nil,
		),
		aqVentActiveDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_vent_active_ratio"),
			"Whether the AirQ ventilation fan is active as a ratio.",
			deviceLabels,
			nil,
		),
		aqPresentDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_present_ratio"),
			"Whether air quality sensing hardware is present as a ratio.",
			deviceLabels,
			nil,
		),
		machineReadyDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "machine_ready_ratio"),
			"Whether the underlying HVAC machine is ready as a ratio.",
			deviceLabels,
			nil,
		),
		blockSetpointDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "block_setpoint_ratio"),
			"Whether setpoint changes are blocked as a ratio.",
			deviceLabels,
			nil,
		),
		blockOnDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "block_on_ratio"),
			"Whether power-on commands are blocked as a ratio.",
			deviceLabels,
			nil,
		),
		blockOffDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "block_off_ratio"),
			"Whether power-off commands are blocked as a ratio.",
			deviceLabels,
			nil,
		),
		powerfulModeDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "powerful_mode_ratio"),
			"Whether powerful mode is enabled as a ratio.",
			deviceLabels,
			nil,
		),
		humidityRatioDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "humidity_ratio"),
			"Device humidity expressed as a ratio from 0 to 1.",
			deviceLabels,
			nil,
		),
		modeDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "mode"),
			"Numeric Airzone operating mode reported by the device.",
			deviceLabels,
			nil,
		),
		autoModeDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "auto_mode"),
			"Actual operating mode selected while the device is in automatic mode.",
			deviceLabels,
			nil,
		),
		speedConfDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "fan_speed"),
			"Configured fan speed reported by the device.",
			deviceLabels,
			nil,
		),
		percentSpeedDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "fan_speed_percent"),
			"Configured fan speed percentage reported by the device.",
			deviceLabels,
			nil,
		),
		sleepMinutesDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "sleep_minutes"),
			"Configured sleep timer in minutes.",
			deviceLabels,
			nil,
		),
		timerMinutesDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "timer_minutes"),
			"Configured timer target in minutes.",
			deviceLabels,
			nil,
		),
		timerCountdownDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "timer_countdown_seconds"),
			"Remaining timer countdown in seconds.",
			deviceLabels,
			nil,
		),
		localTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "local_temperature_celsius"),
			"Local device temperature in celsius.",
			deviceLabels,
			nil,
		),
		workTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "work_temperature_celsius"),
			"Device work temperature in celsius.",
			deviceLabels,
			nil,
		),
		zoneWorkTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "zone_work_temperature_celsius"),
			"Zone work temperature in celsius.",
			deviceLabels,
			nil,
		),
		taiTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "tai_temperature_celsius"),
			"TAI temperature in celsius.",
			deviceLabels,
			nil,
		),
		returnTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "return_temperature_celsius"),
			"Return temperature in celsius.",
			deviceLabels,
			nil,
		),
		supplyAirTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "supply_air_temperature_celsius"),
			"Supply air temperature in celsius.",
			deviceLabels,
			nil,
		),
		extractAirTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "extract_air_temperature_celsius"),
			"Extract air temperature in celsius.",
			deviceLabels,
			nil,
		),
		outdoorAirTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "outdoor_air_inlet_temperature_celsius"),
			"Outdoor air inlet temperature in celsius.",
			deviceLabels,
			nil,
		),
		setpointTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "setpoint_temperature_celsius"),
			"Configured device setpoint temperature in celsius.",
			append(deviceLabels, "setpoint_type"),
			nil,
		),
		activeSetpointTempDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "active_setpoint_temperature_celsius"),
			"Active device setpoint temperature in celsius.",
			deviceLabels,
			nil,
		),
		aqScoreDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_score"),
			"Air quality score reported by the device.",
			deviceLabels,
			nil,
		),
		aqTVOCDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_tvoc_ppb"),
			"Total volatile organic compounds in ppb.",
			deviceLabels,
			nil,
		),
		aqCO2Desc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_co2_ppm"),
			"CO2 concentration in ppm.",
			deviceLabels,
			nil,
		),
		aqPressureDesc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_pressure_hpa"),
			"Air pressure reported by the device.",
			deviceLabels,
			nil,
		),
		aqPM10Desc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_pm10"),
			"PM10 reading reported by the device.",
			deviceLabels,
			nil,
		),
		aqPM25Desc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_pm2_5"),
			"PM2.5 reading reported by the device.",
			deviceLabels,
			nil,
		),
		aqPM1Desc: prometheus.NewDesc(
			prometheus.BuildFQName(exporterNamespace, "device", "air_quality_pm1_0"),
			"PM1.0 reading reported by the device.",
			deviceLabels,
			nil,
		),
	}
}

func (c *airzoneCollector) Describe(ch chan<- *prometheus.Desc) {
	ch <- c.upDesc
	ch <- c.durationDesc
	ch <- c.devicesDesc
	ch <- c.infoDesc
	ch <- c.powerDesc
	ch <- c.energyLastHourDesc
	ch <- c.connectedDesc
	ch <- c.wsConnectedDesc
	ch <- c.activeDesc
	ch <- c.airActiveDesc
	ch <- c.autoOverrideModeDesc
	ch <- c.ledsActiveDesc
	ch <- c.localVentDesc
	ch <- c.antifreezeDesc
	ch <- c.aqActiveDesc
	ch <- c.aqVentActiveDesc
	ch <- c.aqPresentDesc
	ch <- c.machineReadyDesc
	ch <- c.blockSetpointDesc
	ch <- c.blockOnDesc
	ch <- c.blockOffDesc
	ch <- c.powerfulModeDesc
	ch <- c.humidityRatioDesc
	ch <- c.modeDesc
	ch <- c.autoModeDesc
	ch <- c.speedConfDesc
	ch <- c.percentSpeedDesc
	ch <- c.sleepMinutesDesc
	ch <- c.timerMinutesDesc
	ch <- c.timerCountdownDesc
	ch <- c.localTempDesc
	ch <- c.workTempDesc
	ch <- c.zoneWorkTempDesc
	ch <- c.taiTempDesc
	ch <- c.returnTempDesc
	ch <- c.supplyAirTempDesc
	ch <- c.extractAirTempDesc
	ch <- c.outdoorAirTempDesc
	ch <- c.setpointTempDesc
	ch <- c.activeSetpointTempDesc
	ch <- c.aqScoreDesc
	ch <- c.aqTVOCDesc
	ch <- c.aqCO2Desc
	ch <- c.aqPressureDesc
	ch <- c.aqPM10Desc
	ch <- c.aqPM25Desc
	ch <- c.aqPM1Desc
}

func (c *airzoneCollector) Collect(ch chan<- prometheus.Metric) {
	start := time.Now()
	devices, err := c.client.FetchDeviceDetails(context.Background())
	duration := time.Since(start).Seconds()

	if err != nil {
		ch <- prometheus.MustNewConstMetric(c.upDesc, prometheus.GaugeValue, 0)
		ch <- prometheus.MustNewConstMetric(c.durationDesc, prometheus.GaugeValue, duration)
		fmt.Fprintf(os.Stderr, "scrape error: %v\n", err)
		return
	}

	ch <- prometheus.MustNewConstMetric(c.upDesc, prometheus.GaugeValue, 1)
	ch <- prometheus.MustNewConstMetric(c.durationDesc, prometheus.GaugeValue, duration)
	ch <- prometheus.MustNewConstMetric(c.devicesDesc, prometheus.GaugeValue, float64(devices.TotalDevices))

	for _, device := range devices.Devices {
		baseLabels := []string{
			device.InstallationID,
			device.Installation,
			device.GroupID,
			device.GroupName,
			device.DeviceID,
			device.Name,
			device.Type,
			device.WSID,
		}

		ch <- prometheus.MustNewConstMetric(c.infoDesc, prometheus.GaugeValue, 1, baseLabels...)
		c.collectFocusedMetrics(ch, baseLabels, device.Type, device.Status, device.Config)
	}
}

func (c *airzoneCollector) collectFocusedMetrics(ch chan<- prometheus.Metric, baseLabels []string, deviceType string, statusRaw, configRaw json.RawMessage) {
	status := decodeJSONObject(statusRaw)
	config := decodeJSONObject(configRaw)

	if deviceType == "az_energy_clamp" {
		c.emitNumberMetric(ch, c.energyLastHourDesc, baseLabels, status, "power")
	} else {
		c.emitBoolMetric(ch, c.powerDesc, baseLabels, status, "power")
	}
	c.emitBoolMetric(ch, c.connectedDesc, baseLabels, status, "isConnected")
	c.emitBoolMetric(ch, c.wsConnectedDesc, baseLabels, status, "ws_connected")
	c.emitBoolMetric(ch, c.activeDesc, baseLabels, status, "active")
	c.emitBoolMetric(ch, c.airActiveDesc, baseLabels, status, "air_active")
	c.emitBoolMetric(ch, c.autoOverrideModeDesc, baseLabels, status, "auto_ovr_mode_enabled")
	c.emitBoolMetric(ch, c.machineReadyDesc, baseLabels, status, "machineready")
	c.emitBoolMetric(ch, c.blockSetpointDesc, baseLabels, status, "block_setpoint")
	c.emitBoolMetric(ch, c.blockOnDesc, baseLabels, status, "block_on")
	c.emitBoolMetric(ch, c.blockOffDesc, baseLabels, status, "block_off")
	c.emitBoolMetric(ch, c.powerfulModeDesc, baseLabels, status, "powerful_mode")
	c.emitBoolMetric(ch, c.aqActiveDesc, baseLabels, status, "aq_active")
	c.emitBoolMetric(ch, c.aqVentActiveDesc, baseLabels, status, "aq_vent_active")
	c.emitBoolMetric(ch, c.aqPresentDesc, baseLabels, status, "aq_present")
	c.emitBoolMetric(ch, c.ledsActiveDesc, baseLabels, config, "leds_active")
	c.emitBoolMetric(ch, c.localVentDesc, baseLabels, config, "local_vent")
	c.emitBoolMetric(ch, c.antifreezeDesc, baseLabels, config, "antifreeze")

	c.emitNumberMetric(ch, c.modeDesc, baseLabels, status, "mode")
	c.emitNumberMetric(ch, c.autoModeDesc, baseLabels, status, "auto_mode")
	c.emitNumberMetric(ch, c.speedConfDesc, baseLabels, status, "speed_conf")
	c.emitNumberMetric(ch, c.percentSpeedDesc, baseLabels, status, "pspeed")
	c.emitNumberMetric(ch, c.sleepMinutesDesc, baseLabels, config, "sleep")
	c.emitNestedNumberMetric(ch, c.timerMinutesDesc, baseLabels, config, "timer", "value")
	c.emitNestedNumberMetric(ch, c.timerCountdownDesc, baseLabels, config, "timer", "count")
	c.emitHumidityRatioMetric(ch, baseLabels, status, "humidity")
	c.emitTemperatureMetric(ch, c.localTempDesc, baseLabels, status, "local_temp")
	c.emitTemperatureMetric(ch, c.workTempDesc, baseLabels, status, "work_temp")
	c.emitTemperatureMetric(ch, c.zoneWorkTempDesc, baseLabels, status, "zone_work_temp")
	c.emitTemperatureMetric(ch, c.taiTempDesc, baseLabels, status, "tai_temp")
	c.emitTemperatureMetric(ch, c.returnTempDesc, baseLabels, status, "return_temp")
	c.emitTemperatureMetric(ch, c.supplyAirTempDesc, baseLabels, status, "supply_air_temp")
	c.emitTemperatureMetric(ch, c.extractAirTempDesc, baseLabels, status, "extract_air_temp")
	c.emitTemperatureMetric(ch, c.outdoorAirTempDesc, baseLabels, status, "outdoor_air_inlet_temp")
	c.emitTemperatureMetric(ch, c.activeSetpointTempDesc, baseLabels, status, "setpoint")

	c.emitSetpointMetric(ch, baseLabels, status, "heat", "setpoint_air_heat")
	c.emitSetpointMetric(ch, baseLabels, status, "cool", "setpoint_air_cool")
	c.emitSetpointMetric(ch, baseLabels, status, "vent", "setpoint_air_vent")
	c.emitSetpointMetric(ch, baseLabels, status, "dry", "setpoint_air_dry")
	c.emitSetpointMetric(ch, baseLabels, status, "auto", "setpoint_air_auto")
	c.emitSetpointMetric(ch, baseLabels, status, "emerheat", "setpoint_air_emerheat")
	c.emitSetpointMetric(ch, baseLabels, status, "stop", "setpoint_air_stop")
	c.emitSetpointMetric(ch, baseLabels, status, "tank", "tank_temp")
	c.emitNumberMetric(ch, c.aqScoreDesc, baseLabels, status, "aq_score")
	c.emitNumberMetric(ch, c.aqTVOCDesc, baseLabels, status, "aq_tvoc")
	c.emitNumberMetric(ch, c.aqCO2Desc, baseLabels, status, "aq_co2")
	c.emitNumberMetric(ch, c.aqPressureDesc, baseLabels, status, "aq_pressure")
	c.emitNumberMetric(ch, c.aqPM10Desc, baseLabels, status, "aqpm10")
	c.emitNumberMetric(ch, c.aqPM25Desc, baseLabels, status, "aqpm2_5")
	c.emitNumberMetric(ch, c.aqPM1Desc, baseLabels, status, "aqpm1_0")
}

func decodeJSONObject(raw json.RawMessage) map[string]any {
	if len(raw) == 0 {
		return nil
	}

	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		return nil
	}
	return decoded
}

func (c *airzoneCollector) emitBoolMetric(ch chan<- prometheus.Metric, desc *prometheus.Desc, labels []string, payload map[string]any, key string) {
	value, ok := boolFromMap(payload, key)
	if !ok {
		return
	}

	numeric := 0.0
	if value {
		numeric = 1
	}
	ch <- prometheus.MustNewConstMetric(desc, prometheus.GaugeValue, numeric, labels...)
}

func (c *airzoneCollector) emitNumberMetric(ch chan<- prometheus.Metric, desc *prometheus.Desc, labels []string, payload map[string]any, key string) {
	value, ok := floatFromMap(payload, key)
	if !ok {
		return
	}
	ch <- prometheus.MustNewConstMetric(desc, prometheus.GaugeValue, value, labels...)
}

func (c *airzoneCollector) emitNestedNumberMetric(ch chan<- prometheus.Metric, desc *prometheus.Desc, labels []string, payload map[string]any, key, nestedKey string) {
	value, ok := nestedFloatFromMap(payload, key, nestedKey)
	if !ok {
		return
	}
	ch <- prometheus.MustNewConstMetric(desc, prometheus.GaugeValue, value, labels...)
}

func (c *airzoneCollector) emitTemperatureMetric(ch chan<- prometheus.Metric, desc *prometheus.Desc, labels []string, payload map[string]any, key string) {
	value, ok := celsiusValueFromMap(payload, key)
	if !ok {
		return
	}
	ch <- prometheus.MustNewConstMetric(desc, prometheus.GaugeValue, value, labels...)
}

func (c *airzoneCollector) emitHumidityRatioMetric(ch chan<- prometheus.Metric, labels []string, payload map[string]any, key string) {
	value, ok := floatFromMap(payload, key)
	if !ok {
		return
	}
	ch <- prometheus.MustNewConstMetric(c.humidityRatioDesc, prometheus.GaugeValue, value/100.0, labels...)
}

func (c *airzoneCollector) emitSetpointMetric(ch chan<- prometheus.Metric, labels []string, payload map[string]any, setpointType, key string) {
	value, ok := celsiusValueFromMap(payload, key)
	if !ok {
		return
	}
	ch <- prometheus.MustNewConstMetric(c.setpointTempDesc, prometheus.GaugeValue, value, append(labels, setpointType)...)
}

func boolFromMap(payload map[string]any, key string) (bool, bool) {
	if payload == nil {
		return false, false
	}
	raw, ok := payload[key]
	if !ok {
		return false, false
	}
	value, ok := raw.(bool)
	return value, ok
}

func floatFromMap(payload map[string]any, key string) (float64, bool) {
	if payload == nil {
		return 0, false
	}
	raw, ok := payload[key]
	if !ok {
		return 0, false
	}
	value, ok := raw.(float64)
	return value, ok
}

func celsiusValueFromMap(payload map[string]any, key string) (float64, bool) {
	if payload == nil {
		return 0, false
	}

	raw, ok := payload[key]
	if !ok {
		return 0, false
	}

	switch typed := raw.(type) {
	case float64:
		return typed, true
	case map[string]any:
		value, ok := typed["celsius"].(float64)
		return value, ok
	default:
		return 0, false
	}
}

func nestedFloatFromMap(payload map[string]any, key, nestedKey string) (float64, bool) {
	if payload == nil {
		return 0, false
	}

	raw, ok := payload[key]
	if !ok {
		return 0, false
	}

	object, ok := raw.(map[string]any)
	if !ok {
		return 0, false
	}

	value, ok := object[nestedKey].(float64)
	return value, ok
}

func (c *airzoneClient) FetchDeviceDetails(ctx context.Context) (deviceDetailsResponse, error) {
	password, err := readSecretFile(c.passwordFile)
	if err != nil {
		return deviceDetailsResponse{}, err
	}

	response, err := login(ctx, c.httpClient, c.baseURL, loginRequest{
		Email:    c.email,
		Password: password,
	})
	if err != nil {
		return deviceDetailsResponse{}, err
	}

	installations, err := getInstallations(ctx, c.httpClient, c.baseURL, response.Token)
	if err != nil {
		return deviceDetailsResponse{}, err
	}

	details, err := getInstallationDetails(ctx, c.httpClient, c.baseURL, response.Token, installations)
	if err != nil {
		return deviceDetailsResponse{}, err
	}

	return getAllDeviceDetails(ctx, c.httpClient, c.baseURL, response.Token, details)
}

func readSecretFile(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read password file: %w", err)
	}

	password := strings.TrimSpace(string(data))
	if password == "" {
		return "", errors.New("password file is empty")
	}

	return password, nil
}

func login(ctx context.Context, client *http.Client, baseURL string, payload loginRequest) (loginResponse, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return loginResponse{}, fmt.Errorf("encode login request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(baseURL, "/")+"/auth/login", bytes.NewReader(body))
	if err != nil {
		return loginResponse{}, fmt.Errorf("build login request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		return loginResponse{}, fmt.Errorf("login request failed: %w", err)
	}
	defer func() {
		_ = resp.Body.Close()
	}()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return loginResponse{}, fmt.Errorf("read login response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return loginResponse{}, formatAPIError("login failed", resp.Status, respBody)
	}

	var parsed loginResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return loginResponse{}, fmt.Errorf("decode login response: %w", err)
	}
	if parsed.Token == "" || parsed.RefreshToken == "" {
		return loginResponse{}, errors.New("login response missing token or refreshToken")
	}

	return parsed, nil
}

func getInstallations(ctx context.Context, client *http.Client, baseURL, token string) (installationsResponse, error) {
	req, err := authorizedRequest(ctx, http.MethodGet, strings.TrimRight(baseURL, "/")+"/installations", token)
	if err != nil {
		return installationsResponse{}, fmt.Errorf("build installations request: %w", err)
	}

	respBody, err := doJSONRequest(client, req, "installations request failed")
	if err != nil {
		return installationsResponse{}, err
	}

	var parsed installationsResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return installationsResponse{}, fmt.Errorf("decode installations response: %w", err)
	}
	if parsed.Installations == nil {
		return installationsResponse{}, errors.New("installations response missing installations")
	}

	return parsed, nil
}

func getInstallationDetails(ctx context.Context, client *http.Client, baseURL, token string, installations installationsResponse) (installationDetailsResponse, error) {
	details := installationDetailsResponse{
		Total:                installations.Total,
		PendingInstallations: installations.PendingInstallations,
		Installations:        make([]installationDetail, 0, len(installations.Installations)),
	}

	for _, inst := range installations.Installations {
		detail, err := getInstallationDetail(ctx, client, baseURL, token, inst.InstallationID)
		if err != nil {
			return installationDetailsResponse{}, err
		}
		details.Installations = append(details.Installations, detail)
	}

	return details, nil
}

func getInstallationDetail(ctx context.Context, client *http.Client, baseURL, token, installationID string) (installationDetail, error) {
	if strings.TrimSpace(installationID) == "" {
		return installationDetail{}, errors.New("installationID is required")
	}

	req, err := authorizedRequest(ctx, http.MethodGet, strings.TrimRight(baseURL, "/")+"/installations/"+url.PathEscape(installationID), token)
	if err != nil {
		return installationDetail{}, fmt.Errorf("build installation detail request: %w", err)
	}

	respBody, err := doJSONRequest(client, req, "installation detail request failed for "+installationID)
	if err != nil {
		return installationDetail{}, err
	}

	var parsed installationDetail
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return installationDetail{}, fmt.Errorf("decode installation detail response for %s: %w", installationID, err)
	}
	if parsed.InstallationID == "" {
		return installationDetail{}, fmt.Errorf("installation detail response missing installation_id for %s", installationID)
	}

	return parsed, nil
}

func getAllDeviceDetails(ctx context.Context, client *http.Client, baseURL, token string, details installationDetailsResponse) (deviceDetailsResponse, error) {
	seen := make(map[string]struct{})
	devices := make([]deviceDetail, 0)

	for _, installation := range details.Installations {
		for _, group := range installation.Groups {
			for _, device := range group.Devices {
				if _, ok := seen[device.DeviceID]; ok {
					continue
				}
				seen[device.DeviceID] = struct{}{}

				status, err := getDeviceStatus(ctx, client, baseURL, token, installation.InstallationID, device.DeviceID)
				if err != nil {
					return deviceDetailsResponse{}, err
				}
				config, err := getDeviceConfig(ctx, client, baseURL, token, installation.InstallationID, device.DeviceID)
				if err != nil {
					return deviceDetailsResponse{}, err
				}

				devices = append(devices, deviceDetail{
					InstallationID: installation.InstallationID,
					Installation:   installation.Name,
					GroupID:        group.GroupID,
					GroupName:      group.Name,
					DeviceID:       device.DeviceID,
					Name:           device.Name,
					Type:           device.Type,
					WSID:           device.WSID,
					Meta:           device.Meta,
					Status:         status,
					Config:         config,
				})
			}
		}
	}

	return deviceDetailsResponse{
		TotalDevices: len(devices),
		Devices:      devices,
	}, nil
}

func getDeviceStatus(ctx context.Context, client *http.Client, baseURL, token, installationID, deviceID string) (json.RawMessage, error) {
	return getDeviceEndpoint(ctx, client, baseURL, token, installationID, deviceID, "status", url.Values{})
}

func getDeviceConfig(ctx context.Context, client *http.Client, baseURL, token, installationID, deviceID string) (json.RawMessage, error) {
	values := url.Values{}
	values.Set("type", deviceConfigType)
	return getDeviceEndpoint(ctx, client, baseURL, token, installationID, deviceID, "config", values)
}

func getDeviceEndpoint(ctx context.Context, client *http.Client, baseURL, token, installationID, deviceID, endpoint string, values url.Values) (json.RawMessage, error) {
	if strings.TrimSpace(installationID) == "" {
		return nil, errors.New("installationID is required")
	}
	if strings.TrimSpace(deviceID) == "" {
		return nil, errors.New("deviceID is required")
	}

	values = cloneValues(values)
	values.Set("installation_id", installationID)

	endpointURL := strings.TrimRight(baseURL, "/") + "/devices/" + url.PathEscape(deviceID) + "/" + endpoint + "?" + values.Encode()
	req, err := authorizedRequest(ctx, http.MethodGet, endpointURL, token)
	if err != nil {
		return nil, fmt.Errorf("build device %s request for %s: %w", endpoint, deviceID, err)
	}

	respBody, err := doJSONRequest(client, req, fmt.Sprintf("device %s request failed for %s", endpoint, deviceID))
	if err != nil {
		return nil, err
	}
	if !json.Valid(respBody) {
		return nil, fmt.Errorf("device %s response for %s returned invalid JSON", endpoint, deviceID)
	}

	return json.RawMessage(respBody), nil
}

func cloneValues(values url.Values) url.Values {
	cloned := make(url.Values, len(values))
	for key, value := range values {
		copied := make([]string, len(value))
		copy(copied, value)
		cloned[key] = copied
	}
	return cloned
}

func authorizedRequest(ctx context.Context, method, requestURL, token string) (*http.Request, error) {
	if strings.TrimSpace(token) == "" {
		return nil, errors.New("token is required")
	}

	req, err := http.NewRequestWithContext(ctx, method, requestURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	return req, nil
}

func doJSONRequest(client *http.Client, req *http.Request, errorPrefix string) ([]byte, error) {
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", errorPrefix, err)
	}
	defer func() {
		_ = resp.Body.Close()
	}()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, formatAPIError(errorPrefix, resp.Status, respBody)
	}

	return respBody, nil
}

func formatAPIError(prefix, status string, body []byte) error {
	var apiErr apiErrorResponse
	if json.Unmarshal(body, &apiErr) == nil && len(apiErr.Errors) > 0 {
		return fmt.Errorf("%s with status %s: %s", prefix, status, strings.TrimSpace(string(apiErr.Errors)))
	}
	return fmt.Errorf("%s with status %s: %s", prefix, status, strings.TrimSpace(string(body)))
}