package main

import (
	"errors"
	"flag"
	"fmt"
	"log"
	"math"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	owm "github.com/briandowns/openweathermap"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const namespace = "openweathermap"

type exporter struct {
	client   *owm.OneCallData
	coords   *owm.Coordinates
	interval time.Duration
	logger   *log.Logger

	mu          sync.RWMutex
	lastUpdate  time.Time
	lastAttempt time.Time
	lastError   string
	scrapeOK    bool
}

func newExporter(apiKey string, coords *owm.Coordinates, units string, language string, interval time.Duration, client *http.Client, logger *log.Logger) (*exporter, error) {
	oneCall, err := owm.NewOneCall(units, strings.ToUpper(language), apiKey, []string{}, owm.WithHttpClient(client))
	if err != nil {
		return nil, err
	}

	return &exporter{
		client:   oneCall,
		coords:   coords,
		interval: interval,
		logger:   logger,
	}, nil
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

	if err := e.client.OneCallByCoordinates(e.coords); err != nil {
		e.scrapeOK = false
		e.lastError = err.Error()
		e.logger.Printf("refresh failed: %v", err)
		return
	}

	e.lastUpdate = time.Now()
	e.scrapeOK = true
	e.lastError = ""
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
			"Whether the last OpenWeatherMap refresh succeeded.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		boolFloat(e.scrapeOK),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_refresh_timestamp"),
			"Unix timestamp in milliseconds of the last successful OpenWeatherMap refresh.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		float64(e.lastUpdate.UnixMilli()),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", "last_refresh_attempt_timestamp"),
			"Unix timestamp in milliseconds of the last attempted OpenWeatherMap refresh.",
			nil,
			nil,
		),
		prometheus.GaugeValue,
		float64(e.lastAttempt.UnixMilli()),
	)

	if !e.scrapeOK {
		return
	}

	now := time.Now()
	ch <- metric("refresh_timestamp", "Unix timestamp in milliseconds of the current OpenWeatherMap data.", float64(now.UnixMilli()))

	ch <- metric("latitude_degrees", "Latitude of the queried location in degrees.", e.client.Latitude)
	ch <- metric("longitude_degrees", "Longitude of the queried location in degrees.", e.client.Longitude)
	ch <- metric("timezone_offset_seconds", "Timezone offset from UTC in seconds for the queried location.", float64(e.client.TimezoneOffset))

	ch <- metric("current_observation_timestamp", "Unix timestamp in milliseconds for the current observation.", float64(e.client.Current.Dt*1000))
	ch <- metric("current_sunrise_timestamp", "Unix timestamp in milliseconds of sunrise for the current observation.", float64(e.client.Current.Sunrise*1000))
	ch <- metric("current_sunset_timestamp", "Unix timestamp in milliseconds of sunset for the current observation.", float64(e.client.Current.Sunset*1000))
	ch <- metric("current_temperature_celsius", "Current air temperature.", e.client.Current.Temp)
	ch <- metric("current_feels_like_celsius", "Current apparent temperature.", e.client.Current.FeelsLike)
	ch <- metric("current_dew_point_celsius", "Current dew point.", e.client.Current.DewPoint)
	ch <- metric("current_humidity_ratio", "Current relative humidity expressed as a ratio from 0 to 1.", float64(e.client.Current.Humidity)/100.0)
	ch <- metric("current_pressure_pascals", "Current atmospheric pressure.", float64(e.client.Current.Pressure)*100.0)
	ch <- metric("current_visibility_meters", "Current horizontal visibility.", float64(e.client.Current.Visibility))
	ch <- metric("current_cloud_cover_ratio", "Current cloud cover expressed as a ratio from 0 to 1.", float64(e.client.Current.Clouds)/100.0)
	ch <- metric("current_wind_speed_meters_per_second", "Current wind speed.", e.client.Current.WindSpeed)
	ch <- metric("current_wind_direction_degrees", "Current wind direction in degrees.", float64(e.client.Current.WindDeg))
	ch <- metric("current_wind_gust_meters_per_second", "Current wind gust speed.", e.client.Current.WindGust)
	ch <- metric("current_uv_index", "Current UV index.", e.client.Current.UVI)
	ch <- metric("current_rain_depth_meters", "Current one hour rain depth.", e.client.Current.Rain.OneH/1000.0)
	ch <- metric("current_snow_depth_meters", "Current one hour snow depth.", e.client.Current.Snow.OneH/1000.0)

	for _, hourly := range e.client.Hourly {
		ch <- forecastMetric("forecast_temperature_celsius", "Forecasted air temperature.", hourly.Temp, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_feels_like_celsius", "Forecasted apparent temperature.", hourly.FeelsLike, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_dew_point_celsius", "Forecasted dew point.", hourly.DewPoint, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_humidity_ratio", "Forecasted relative humidity expressed as a ratio from 0 to 1.", float64(hourly.Humidity)/100.0, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_pressure_pascals", "Forecasted atmospheric pressure.", float64(hourly.Pressure)*100.0, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_visibility_meters", "Forecasted horizontal visibility.", float64(hourly.Visibility), forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_cloud_cover_ratio", "Forecasted cloud cover expressed as a ratio from 0 to 1.", float64(hourly.Clouds)/100.0, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_wind_speed_meters_per_second", "Forecasted wind speed.", hourly.WindSpeed, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_wind_direction_degrees", "Forecasted wind direction in degrees.", float64(hourly.WindDeg), forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_wind_gust_meters_per_second", "Forecasted wind gust speed.", hourly.WindGust, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_uv_index", "Forecasted UV index.", hourly.UVI, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_rain_depth_meters", "Forecasted one hour rain depth.", hourly.Rain.OneH/1000.0, forecastHourly, hourly.Dt, now)
		ch <- forecastMetric("forecast_snow_depth_meters", "Forecasted one hour snow depth.", hourly.Snow.OneH/1000.0, forecastHourly, hourly.Dt, now)
	}

	for _, daily := range e.client.Daily {
		ch <- forecastMetric("forecast_sunrise_timestamp", "Forecasted sunrise time as a Unix timestamp in milliseconds.", float64(daily.Sunrise*1000), forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_sunset_timestamp", "Forecasted sunset time as a Unix timestamp in milliseconds.", float64(daily.Sunset*1000), forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_moonrise_timestamp", "Forecasted moonrise time as a Unix timestamp in milliseconds.", float64(daily.Moonrise*1000), forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_moonset_timestamp", "Forecasted moonset time as a Unix timestamp in milliseconds.", float64(daily.Moonset*1000), forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_moon_phase", "Forecasted moon phase, from 0 to 1, where 0 and 1 correspond to a new moon and 0.5 corresponds to a full moon.", daily.MoonPhase, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_temperature_morning_celsius", "Forecasted morning air temperature.", daily.Temp.Morn, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_temperature_day_celsius", "Forecasted daytime air temperature.", daily.Temp.Day, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_temperature_evening_celsius", "Forecasted evening air temperature.", daily.Temp.Eve, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_temperature_night_celsius", "Forecasted nighttime air temperature.", daily.Temp.Night, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_feels_like_morning_celsius", "Forecasted morning apparent temperature.", daily.FeelsLike.Morn, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_feels_like_day_celsius", "Forecasted daytime apparent temperature.", daily.FeelsLike.Day, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_feels_like_evening_celsius", "Forecasted evening apparent temperature.", daily.FeelsLike.Eve, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_feels_like_night_celsius", "Forecasted nighttime apparent temperature.", daily.FeelsLike.Night, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_dew_point_celsius", "Forecasted dew point.", daily.DewPoint, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_humidity_ratio", "Forecasted relative humidity expressed as a ratio from 0 to 1.", float64(daily.Humidity)/100.0, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_pressure_pascals", "Forecasted atmospheric pressure.", float64(daily.Pressure)*100.0, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_cloud_cover_ratio", "Forecasted cloud cover expressed as a ratio from 0 to 1.", float64(daily.Clouds)/100.0, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_wind_speed_meters_per_second", "Forecasted wind speed.", daily.WindSpeed, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_wind_direction_degrees", "Forecasted wind direction in degrees.", float64(daily.WindDeg), forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_wind_gust_meters_per_second", "Forecasted wind gust speed.", daily.WindGust, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_uv_index", "Forecasted UV index.", daily.UVI, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_rain_depth_meters", "Forecasted one hour rain depth.", daily.Rain/1000.0, forecastDaily, daily.Dt, now)
		ch <- forecastMetric("forecast_snow_depth_meters", "Forecasted one hour snow depth.", daily.Snow/1000.0, forecastDaily, daily.Dt, now)
	}
}

func metric(name string, help string, value float64) prometheus.Metric {
	return prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", name),
			help,
			nil,
			nil,
		),
		prometheus.GaugeValue,
		value,
	)
}

type ftype string

const (
	forecastHourly ftype = "hourly"
	forecastDaily  ftype = "daily"
)

func forecastMetric(name string, help string, value float64, ftype ftype, dt int, now time.Time) prometheus.Metric {
	forecastTime := time.Unix(int64(dt), 0)
	offset := int(math.Max(math.Ceil(forecastTime.Sub(now).Hours()), 0))
	return prometheus.MustNewConstMetric(
		prometheus.NewDesc(
			prometheus.BuildFQName(namespace, "", name),
			help,
			[]string{"absolute_hours", "offset_hours", "forecast_type"},
			nil,
		),
		prometheus.GaugeValue,
		value,
		fmt.Sprintf("%d", int(forecastTime.Hour())),
		fmt.Sprintf("%d", offset),
		string(ftype),
	)
}

func boolFloat(v bool) float64 {
	if v {
		return 1
	}
	return 0
}

func readAPIKey(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}

	key := strings.TrimSpace(string(content))
	if key == "" {
		return "", errors.New("api key file is empty")
	}

	return key, nil
}

func readCoords(path string) (*owm.Coordinates, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	coords := strings.Split(string(content), ":")
	if len(coords) != 2 {
		return nil, errors.New("invalid coords file format, expected 'latitude:longitude'")
	}

	lat, err := strconv.ParseFloat(strings.TrimSpace(coords[0]), 64)
	if err != nil {
		return nil, fmt.Errorf("parsing latitude: %w", err)
	}

	if lat < -90 || lat > 90 {
		return nil, errors.New("latitude must be between -90 and 90")
	}

	lon, err := strconv.ParseFloat(strings.TrimSpace(coords[1]), 64)
	if err != nil {
		return nil, fmt.Errorf("parsing longitude: %w", err)
	}

	if lon < -180 || lon > 180 {
		return nil, errors.New("longitude must be between -180 and 180")
	}

	return &owm.Coordinates{
		Latitude:  lat,
		Longitude: lon,
	}, nil
}

func main() {
	var (
		host           = flag.String("web.host", "127.0.0.1", "Host or IP address to listen on for Prometheus scrapes.")
		port           = flag.String("web.port", "9876", "TCP port to listen on for Prometheus scrapes.")
		apiKeyFile     = flag.String("api-key-file", "", "File containing the OpenWeatherMap API key.")
		coordsFile     = flag.String("coords-file", "", "File containing the coordinates to query.")
		language       = flag.String("language", "EN", "Language passed to the OpenWeatherMap client.")
		refresh        = flag.Duration("refresh-interval", 10*time.Minute, "Refresh interval used to poll OpenWeatherMap.")
		requestTimeout = flag.Duration("request-timeout", 15*time.Second, "HTTP timeout for OpenWeatherMap requests.")
	)

	flag.Parse()

	if *apiKeyFile == "" {
		log.Fatal("--api-key-file is required")
	}

	if *coordsFile == "" {
		log.Fatal("--coords-file is required")
	}

	apiKey, err := readAPIKey(*apiKeyFile)
	if err != nil {
		log.Fatalf("reading api key: %v", err)
	}

	if apiKey == "" {
		log.Fatal("api key is empty")
	}

	coords, err := readCoords(*coordsFile)
	if err != nil {
		log.Fatalf("reading coords file: %v", err)
	}

	logger := log.New(os.Stdout, "openweathermap-exporter: ", log.LstdFlags)
	httpClient := &http.Client{Timeout: *requestTimeout}
	exp, err := newExporter(
		apiKey,
		coords,
		"C",
		*language,
		*refresh,
		httpClient,
		logger,
	)
	if err != nil {
		log.Fatalf("creating exporter: %v", err)
	}

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
