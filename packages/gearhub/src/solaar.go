package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strings"
)

// MouseDevice is one device summarized from "solaar show" output.
type MouseDevice struct {
	Name       string            `json:"name"`
	Battery    string            `json:"battery,omitempty"`
	DPI        string            `json:"dpi,omitempty"`
	ReportRate string            `json:"reportRate,omitempty"`
	Settings   map[string]string `json:"settings,omitempty"`
}

var (
	// "  2: PRO X2 SUPERSTRIKE" on a receiver, or a bare non-indented
	// device name for direct USB connections.
	reNumbered = regexp.MustCompile(`^\s{0,4}(\d+):\s+(.+?)\s*$`)
	// "        report_rate (saved): 8ms" style setting lines.
	reSetting = regexp.MustCompile(`^\s+([a-z][a-z0-9_]*)\s*(?:\([^)]*\))?\s*:\s*(.+?)\s*$`)
	reBattery = regexp.MustCompile(`(?i)^\s*Battery:?\s*(.+?)\s*\.?\s*$`)
)

// parseSolaarShow leniently extracts device names, battery, and interesting
// settings from "solaar show". It must never fail on unexpected output.
func parseSolaarShow(out string) []MouseDevice {
	var devices []MouseDevice
	current := func() *MouseDevice {
		if len(devices) == 0 {
			devices = append(devices, MouseDevice{Name: "?"})
		}
		return &devices[len(devices)-1]
	}
	for _, line := range strings.Split(out, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		if m := reNumbered.FindStringSubmatch(line); m != nil {
			devices = append(devices, MouseDevice{Name: m[2]})
			continue
		}
		// Bare, non-indented line: a directly connected device header,
		// unless it is boilerplate like the version banner.
		if !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") {
			lower := strings.ToLower(trimmed)
			if strings.HasPrefix(lower, "solaar") || strings.Contains(lower, "receiver") {
				continue
			}
			devices = append(devices, MouseDevice{Name: trimmed})
			continue
		}
		if len(devices) == 0 {
			continue
		}
		if m := reBattery.FindStringSubmatch(line); m != nil {
			current().Battery = m[1]
			continue
		}
		if m := reSetting.FindStringSubmatch(line); m != nil {
			key, value := m[1], m[2]
			dev := current()
			switch {
			case strings.Contains(key, "dpi") || key == "sensitivity":
				if dev.DPI == "" {
					dev.DPI = value
				}
			case strings.Contains(key, "report_rate") || strings.Contains(key, "polling"):
				if dev.ReportRate == "" {
					dev.ReportRate = value
				}
			default:
				continue
			}
			if dev.Settings == nil {
				dev.Settings = map[string]string{}
			}
			dev.Settings[key] = value
		}
	}
	return devices
}

func handleMouse(w http.ResponseWriter, r *http.Request) {
	out, err := runCommand(r.Context(), "solaar", "show")
	if err != nil {
		writeUnavailable(w, fmt.Errorf("solaar show: %v", err))
		return
	}
	devices := parseSolaarShow(out)
	if len(devices) == 0 {
		writeJSON(w, map[string]any{"available": false, "error": "nenhum dispositivo encontrado"})
		return
	}
	writeJSON(w, map[string]any{"available": true, "devices": devices})
}

type mouseConfigRequest struct {
	Device  string `json:"device"`
	Setting string `json:"setting"`
	Value   string `json:"value"`
}

func handleMouseConfig(w http.ResponseWriter, r *http.Request) {
	var req mouseConfigRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	for _, field := range []string{req.Device, req.Setting, req.Value} {
		if field == "" || strings.HasPrefix(field, "-") {
			http.Error(w, "device, setting and value are required and must not start with '-'", http.StatusBadRequest)
			return
		}
	}
	out, err := runCommand(r.Context(), "solaar", "config", req.Device, req.Setting, req.Value)
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": strings.TrimSpace(out) + " " + err.Error()})
		return
	}
	writeJSON(w, map[string]any{"ok": true, "output": strings.TrimSpace(out)})
}
