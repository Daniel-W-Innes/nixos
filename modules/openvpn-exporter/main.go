// Prometheus exporter for the OpenVPN --status file.
//
// Reads the status file on every scrape and exposes the "Updated" timestamp
// plus the TUN/TAP byte counters. The timestamp is the tunnel-liveness
// signal: openvpn stops rewriting the file when it is dead, which the
// pia-tunnel-stalled alert keys on (Grafana rules in generic/server/visibility.nix).
//
// Stdlib only: the status file format is trivial and stable, so there are no
// dependencies to vendor.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

var (
	statusPath = flag.String("status-path", "/run/openvpn/pia.status", "path to the openvpn --status file")
	listenAddr = flag.String("listen", "127.0.0.1:9176", "listen address for the exporter")
)

// Metrics, refreshed on each scrape.
var (
	updateTime   float64
	tunReadBytes int64
	tunWriteBytes int64
	scraped      bool
)

func scrape() {
	scraped = false
	f, err := os.Open(*statusPath)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "Updated,"):
			value := strings.TrimPrefix(line, "Updated,")
			// OpenVPN 2.6 writes a Unix timestamp; accept the older
			// asctime layout as well.
			if ts, err := strconv.ParseInt(value, 10, 64); err == nil {
				updateTime = float64(ts)
				scraped = true
			} else if ts, err := time.Parse("Mon Jan 2 15:04:05 2006", value); err == nil {
				updateTime = float64(ts.Unix())
				scraped = true
			}
		case strings.HasPrefix(line, "TUN/TAP read bytes,"):
			tunReadBytes, _ = strconv.ParseInt(strings.TrimPrefix(line, "TUN/TAP read bytes,"), 10, 64)
		case strings.HasPrefix(line, "TUN/TAP write bytes,"):
			tunWriteBytes, _ = strconv.ParseInt(strings.TrimPrefix(line, "TUN/TAP write bytes,"), 10, 64)
		}
	}
}

func handler(w http.ResponseWriter, _ *http.Request) {
	scrape()
	if !scraped {
		http.Error(w, "openvpn status file not readable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "openvpn_status_update_time_seconds %d\n", int64(updateTime))
	fmt.Fprintf(w, "openvpn_tun_tap_read_bytes_total %d\n", tunReadBytes)
	fmt.Fprintf(w, "openvpn_tun_tap_write_bytes_total %d\n", tunWriteBytes)
}

func main() {
	flag.Parse()
	http.HandleFunc("/metrics", handler)
	log.Fatal(http.ListenAndServe(*listenAddr, nil))
}
