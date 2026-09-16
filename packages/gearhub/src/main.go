// gearhub is a local dashboard that unifies peripheral control by
// fronting existing CLIs and services (ddcutil, solaar, OpenLinkHub).
package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"flag"
	"io/fs"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"time"
)

//go:embed web
var webFS embed.FS

const commandTimeout = 5 * time.Second

func main() {
	listen := flag.String("listen", "127.0.0.1:8686", "address to listen on")
	flag.Parse()

	openLinkHubBase := os.Getenv("GEARHUB_OPENLINKHUB")
	if openLinkHubBase == "" {
		openLinkHubBase = "http://127.0.0.1:27003"
	}
	olhURL, err := url.Parse(openLinkHubBase)
	if err != nil {
		log.Fatalf("invalid GEARHUB_OPENLINKHUB %q: %v", openLinkHubBase, err)
	}

	static, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("embedded assets: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServerFS(static))
	mux.HandleFunc("GET /api/monitors", handleMonitors)
	mux.HandleFunc("POST /api/monitors/{n}/vcp", handleSetVCP)
	mux.HandleFunc("GET /api/mouse", handleMouse)
	mux.HandleFunc("POST /api/mouse/config", handleMouseConfig)
	mux.HandleFunc("GET /api/cooler", makeCoolerHandler(olhURL))
	mux.Handle("/openlinkhub/", makeOpenLinkHubProxy(olhURL))

	log.Printf("gearhub listening on http://%s (OpenLinkHub at %s)", *listen, openLinkHubBase)
	if err := http.ListenAndServe(*listen, mux); err != nil {
		log.Fatal(err)
	}
}

// runCommand executes an external tool with a bounded timeout and returns
// its combined output. Errors carry the output for diagnostics.
func runCommand(ctx context.Context, name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	return buf.String(), err
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("encode response: %v", err)
	}
}

// writeUnavailable reports an absent device or tool as a normal payload,
// never as an HTTP error, so the dashboard cards degrade gracefully.
func writeUnavailable(w http.ResponseWriter, err error) {
	writeJSON(w, map[string]any{"available": false, "error": err.Error()})
}

func makeOpenLinkHubProxy(base *url.URL) http.Handler {
	proxy := httputil.NewSingleHostReverseProxy(base)
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		http.Error(w, "OpenLinkHub indisponivel: "+err.Error(), http.StatusBadGateway)
	}
	return http.StripPrefix("/openlinkhub", proxy)
}
