package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

// VCPValue is a continuous VCP feature reading (brightness, contrast).
type VCPValue struct {
	Current int `json:"current"`
	Max     int `json:"max"`
}

// Monitor is one DDC/CI display as reported by ddcutil.
type Monitor struct {
	Display    int       `json:"display"`
	Model      string    `json:"model"`
	Brightness *VCPValue `json:"brightness,omitempty"`
	Contrast   *VCPValue `json:"contrast,omitempty"`
	Input      string    `json:"input,omitempty"`
}

var (
	reDisplay    = regexp.MustCompile(`^Display\s+(\d+)`)
	reMonitor    = regexp.MustCompile(`^\s+Monitor:\s+(.+)$`)
	reContinuous = regexp.MustCompile(`VCP code 0x([0-9a-fA-F]{2})\s+\(([^)]*)\):\s*current value\s*=\s*(\d+),\s*max value\s*=\s*(\d+)`)
	reInputSL    = regexp.MustCompile(`VCP code 0x60\s+\([^)]*\):.*?sl=0x([0-9a-fA-F]+)`)
	reHexCode    = regexp.MustCompile(`^[0-9a-fA-F]{1,2}$`)
)

// parseDetectBrief extracts display numbers and model strings from
// "ddcutil detect --brief" output.
func parseDetectBrief(out string) []Monitor {
	var monitors []Monitor
	for _, line := range strings.Split(out, "\n") {
		if m := reDisplay.FindStringSubmatch(line); m != nil {
			n, _ := strconv.Atoi(m[1])
			monitors = append(monitors, Monitor{Display: n})
			continue
		}
		if len(monitors) == 0 {
			continue
		}
		if m := reMonitor.FindStringSubmatch(line); m != nil {
			monitors[len(monitors)-1].Model = friendlyModel(strings.TrimSpace(m[1]))
		}
	}
	return monitors
}

// friendlyModel turns "AOC:24G2W1G4:GNXM1HA000000" into "AOC 24G2W1G4".
func friendlyModel(raw string) string {
	parts := strings.Split(raw, ":")
	if len(parts) >= 2 && parts[0] != "" && parts[1] != "" {
		return parts[0] + " " + parts[1]
	}
	return raw
}

// fillVCP reads brightness (0x10), contrast (0x12), and input source (0x60)
// for one display. Individual feature failures are tolerated.
func fillVCP(ctx context.Context, mon *Monitor) {
	out, err := runCommand(ctx, "ddcutil", "--display", strconv.Itoa(mon.Display), "getvcp", "10", "12", "60")
	if err != nil && out == "" {
		return
	}
	for _, m := range reContinuous.FindAllStringSubmatch(out, -1) {
		cur, _ := strconv.Atoi(m[3])
		max, _ := strconv.Atoi(m[4])
		switch strings.ToLower(m[1]) {
		case "10":
			mon.Brightness = &VCPValue{Current: cur, Max: max}
		case "12":
			mon.Contrast = &VCPValue{Current: cur, Max: max}
		}
	}
	if m := reInputSL.FindStringSubmatch(out); m != nil {
		mon.Input = "0x" + strings.ToLower(m[1])
	}
}

func handleMonitors(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	out, err := runCommand(ctx, "ddcutil", "detect", "--brief")
	if err != nil {
		writeUnavailable(w, fmt.Errorf("ddcutil detect: %v", err))
		return
	}
	monitors := parseDetectBrief(out)
	for i := range monitors {
		fillVCP(ctx, &monitors[i])
	}
	if monitors == nil {
		monitors = []Monitor{}
	}
	writeJSON(w, map[string]any{"available": len(monitors) > 0, "monitors": monitors})
}

type vcpRequest struct {
	Code  string `json:"code"`
	Value int    `json:"value"`
}

func handleSetVCP(w http.ResponseWriter, r *http.Request) {
	n, err := strconv.Atoi(r.PathValue("n"))
	if err != nil || n < 1 {
		http.Error(w, "invalid display number", http.StatusBadRequest)
		return
	}
	var req vcpRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if !reHexCode.MatchString(req.Code) {
		http.Error(w, "invalid VCP code", http.StatusBadRequest)
		return
	}
	if req.Value < 0 || req.Value > 0xFFFF {
		http.Error(w, "value out of range", http.StatusBadRequest)
		return
	}
	out, err := runCommand(r.Context(), "ddcutil",
		"--display", strconv.Itoa(n), "setvcp", req.Code, strconv.Itoa(req.Value))
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "error": strings.TrimSpace(out) + " " + err.Error()})
		return
	}
	writeJSON(w, map[string]any{"ok": true})
}
