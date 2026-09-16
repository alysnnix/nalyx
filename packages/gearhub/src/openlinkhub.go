package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

var coolerClient = &http.Client{Timeout: commandTimeout}

// makeCoolerHandler proxies a single JSON snapshot from the OpenLinkHub
// daemon. When the daemon is down the card reports available:false.
func makeCoolerHandler(base *url.URL) http.HandlerFunc {
	endpoint := base.JoinPath("/api/").String()
	return func(w http.ResponseWriter, r *http.Request) {
		req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, endpoint, nil)
		if err != nil {
			writeUnavailable(w, err)
			return
		}
		resp, err := coolerClient.Do(req)
		if err != nil {
			writeUnavailable(w, fmt.Errorf("OpenLinkHub: %v", err))
			return
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			writeUnavailable(w, fmt.Errorf("OpenLinkHub: HTTP %d", resp.StatusCode))
			return
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
		if err != nil {
			writeUnavailable(w, fmt.Errorf("OpenLinkHub: %v", err))
			return
		}
		var data any
		if err := json.Unmarshal(body, &data); err != nil {
			writeUnavailable(w, fmt.Errorf("OpenLinkHub: resposta nao e JSON: %v", err))
			return
		}
		writeJSON(w, map[string]any{
			"available": true,
			"fetchedAt": time.Now().Format(time.RFC3339),
			"data":      data,
		})
	}
}
